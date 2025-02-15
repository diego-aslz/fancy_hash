# frozen_string_literal: true

require_relative 'fancy_hash/version'
require 'active_model'

# FancyHash was born to simplify handling third party JSON payloads. Let's say for example we have the following JSON:
#
#   payload = {
#     'identificador' => 1,
#     'nomeCompleto' => "John Doe",
#     'dtNascimento' => "1990-01-01",
#     'genero' => 1, # Let's say we know this field is going to be 1 for Male, 2 for Female
#   }
#
# It would be very tedius having to remember the field names and handle type conversion everywhere, like this:
#
#   payload['dtNascimento'].to_date
#   payload['dtNascimento'] = Date.new(1990, 1, 2).iso8601
#
#   if payload['genero'] == 1
#     # do something
#   end
#
# Instead, we can do this:
#
#   class Person < FancyHash
#     attribute :id, field: 'identificador', type: :integer
#     attribute :name, field: 'nomeCompleto', type: :string
#     attribute :birth_date, field: 'dtNascimento', type: :date
#     attribute :gender, field: 'genero', type: :enum, of: { male: 1, female: 2 }
#   end
#
#   person = Person.new(payload) # `payload` here is a Hash that we retrieved from an hypothetical API
#   person.id # => 1
#   person.name # => "John Doe"
#   person.name = 'Mary Smith'
#   person.birth_date # => Mon, 01 Jan 1990
#   person.birth_date = Date.new(1990, 1, 2)
#   person.gender # => :male
#   person.male? # => true
#   person.female? # => false
#   person.gender = :female # we can use the symbols here, the FancyHash will convert it to the right value
#
#   person.__getobj__ # => { 'identificador' => 1, 'nomeCompleto' => 'Mary Smith', 'dtNascimento' => '1990-01-02', 'genero' => 2 }
#
# This can be used for inbound payloads that we need to parse and for outbound requests we need to send so we
# don't need to worry about type casting and enum mapping either way.
class FancyHash < SimpleDelegator
  extend ActiveModel::Naming
  extend ActiveModel::Translation
  include ActiveModel::Validations
  include ActiveModel::Conversion

  module Types
    class << self
      def find(type, **config)
        return type if type.is_a?(Class)

        {
          nil => -> { ActiveModel::Type::Value.new },
          array: -> { Types::Array.new(**config) },
          boolean: -> { ActiveModel::Type::Boolean.new },
          binboolean: -> { BinBoolean.new },
          string: -> { ActiveModel::Type::String.new },
          date: -> { Date.new },
          datetime: -> { DateTime.new },
          integer: -> { ActiveModel::Type::Integer.new },
          decimal: -> { ActiveModel::Type::Decimal.new },
          money: -> { Money.new },
          enum: -> { Enum.new(**config) },
        }.fetch(type).call
      end
    end

    class Array < ActiveModel::Type::Value
      attr_reader :of

      def initialize(of: nil)
        super()

        @of = of
      end

      def serialize(value)
        value&.map { |v| Types.find(of).serialize(v) }
      end

      private

      def cast_value(value)
        # Freezing to prevent adding items to it, as that would be misleading and not affect the original array
        value&.map { |v| Types.find(of).cast(v) }&.freeze
      end
    end

    class Enum < ActiveModel::Type::Value
      attr_reader :config

      def initialize(of:)
        super()

        @config = of.stringify_keys
      end

      def serialize(value)
        return value if config.value?(value)

        config[value.to_s]
      end

      private

      def cast_value(value)
        return value.to_sym if config.keys.map(&:to_s).include?(value.to_s)

        config.key(value)
      end
    end

    class BinBoolean < ActiveModel::Type::Boolean
      def serialize(value)
        value ? '1' : '0'
      end
    end

    class Date < ActiveModel::Type::Date
      def serialize(value)
        value&.iso8601
      end
    end

    class DateTime < ActiveModel::Type::DateTime
      def serialize(value)
        value&.iso8601
      end

      def cast_value(value)
        # Facil returns no timezone information, then it defaults to the OS timezone, which may be UTC in production
        value = "#{value}#{Time.zone.formatted_offset}" if value.is_a?(String) && value.size == 19

        super
      end
    end

    class Money < ActiveModel::Type::Decimal
      def serialize(value)
        value&.to_f
      end

      private

      def cast_value(_)
        ::Money.from_amount(super)
      end
    end
  end

  class << self
    def serialize(fancy_hash)
      fancy_hash.is_a?(FancyHash) ? fancy_hash.__getobj__ : fancy_hash
    end

    def wrap_many(array)
      Array.wrap(array).map { |hash| new(hash) }
    end

    # Allows defining attributes coming from a Hash with a different attribute name. For example:
    #
    #   attribute :name, type: :string
    #   attribute :born_on, field: 'birthDate', type: :date
    #   attribute :favorite_color, field: 'favoriteColor', type: :enum, of: { red: 0, green: 1, blue: 2 }
    def attribute(name, field: name.to_s, type: nil, default: nil, **, &block)
      attribute_names << name

      attribute_definitions[name] = { field:, type: }

      field = Array(field)

      defaults[name] = default unless default.nil?

      type_serializer = Types.find(type, **)

      raw_method = :"raw_#{name}"
      define_method(raw_method) { dig(*field) }

      define_method(name) do
        type_serializer.cast(send(raw_method)).tap do |value|
          Array(value).each do |v|
            instance_exec(v, &block) if block
          end
        end
      end

      if type_serializer.is_a?(ActiveModel::Type::Boolean)
        define_method(:"#{name}?") { send(name) }
      elsif type.is_a?(Class)
        define_method(:"#{name}_attributes=") { |attributes| send(:"#{raw_method}=", type.new(**attributes)) }
      end

      define_method(:"#{name}=") do |new_value|
        send(:"#{raw_method}=", type_serializer.serialize(type_serializer.cast(new_value)))
      end

      define_method(:"#{raw_method}=") do |new_raw_value|
        hsh = self

        field[0..-2].each do |key|
          hsh = hsh[key] ||= {}
        end

        hsh[field.last] = new_raw_value
      end

      return unless type == :enum

      define_singleton_method(name.to_s.pluralize) do
        type_serializer.config.symbolize_keys
      end

      type_serializer.config.each_key do |key|
        define_method(:"#{key}?") do
          send(name) == key
        end
      end
    end

    def attribute_definitions
      @attribute_definitions ||= {}
    end

    def cast(raw)
      return raw if raw.nil? || raw.is_a?(self)

      new(raw)
    end

    # This is to support FancyHash instances as ActiveModel attributes
    def assert_valid_value(_value)
      # NOOP
    end

    def attribute_names
      @attribute_names ||= Set.new
    end

    def defaults
      @defaults ||= {}
    end
  end

  def initialize(hash = {}, **attributes)
    raise ArgumentError, "Unexpected object class. Should be a Hash or #{self.class}, got #{hash.class} (#{hash})" unless hash.is_a?(Hash) || hash.is_a?(self.class)

    super(hash)

    defaults = self.class.defaults.transform_values { |v| v.is_a?(Proc) ? instance_exec(&v) : v }
    assign_attributes(defaults.merge(attributes))
  end

  def classes
    (self['_klass'] || []) + [self.class.to_s]
  end

  def merge(other)
    merged = __getobj__.merge(other.__getobj__)
    merged['_klass'] ||= []
    merged['_klass'].push(self.class.to_s)

    other.class.new(self.class.new(merged))
  end

  def attributes
    self.class.attribute_names.index_with { send(_1) }
  end

  def assign_attributes(attributes)
    attributes.each { |k, v| public_send(:"#{k}=", v) }

    self
  end

  # Override this method so it does not get delegated to the underlying Hash,
  # which allows us to override `blank?` in entities
  def present?
    !blank?
  end
end
