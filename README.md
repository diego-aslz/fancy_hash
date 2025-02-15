# FancyHash

Welcome to FancyHash! This gem provides a way to define attributes within a Hash, including type casting.

## Installation

Install the gem and add to the application's Gemfile by executing:

    bundle add fancy_hash

If bundler is not being used to manage dependencies, install the gem by executing:

    gem install fancy_hash

## Usage

FancyHash was born to simplify handling third party JSON payloads. Let's say for example we have the following JSON:

```ruby
payload = {
  'identificador' => 1,
  'nomeCompleto' => "John Doe",
  'dtNascimento' => "1990-01-01",
  'genero' => 1, # Let's say we know this field is going to be 1 for Male, 2 for Female
}
```

It would be very tedius having to remember the field names and handle type conversion everywhere, like this:

```ruby
payload['dtNascimento'].to_date
payload['dtNascimento'] = Date.new(1990, 1, 2).iso8601

if payload['genero'] == 1
  # do something
end
```

Instead, we can do this:

```ruby
class Person < FancyHash
  attribute :id, field: 'identificador', type: :integer
  attribute :name, field: 'nomeCompleto', type: :string
  attribute :birth_date, field: 'dtNascimento', type: :date
  attribute :gender, field: 'genero', type: :enum, of: { male: 1, female: 2 }
end

person = Person.new(payload) # `payload` here is a Hash that we retrieved from an hypothetical API
person.id # => 1
person.name # => "John Doe"
person.name = 'Mary Smith'
person.birth_date # => Mon, 01 Jan 1990
person.birth_date = Date.new(1990, 1, 2)
person.gender # => :male
person.male? # => true
person.female? # => false
person.gender = :female # we can use the symbols here, the FancyHash will convert it to the right value

person.__getobj__ # => { 'identificador' => 1, 'nomeCompleto' => 'Mary Smith', 'dtNascimento' => '1990-01-02', 'genero' => 2 }
```

This can be used for inbound payloads that we need to parse and for outbound requests we need to send so we
don't need to worry about type casting and enum mapping either way.

It also supports nested FancyHashes, so you can do this:

```ruby
class Address < FancyHash
  attribute :street, field: 'rua', type: :string
  attribute :city, field: 'cidade', type: :string
  attribute :state, field: 'uf', type: :string
end

class Person < FancyHash
  attribute :address, field: 'endereco', type: Address
end

person = Person.new({ 'endereco' => { 'rua' => 'Some Street', 'cidade' => 'São Paulo', 'uf' => 'SP' } })
person.address.street # => "Some Street"
person.address.city # => "São Paulo"
person.address.state # => "SP"

person.__getobj__ # => { 'endereco' => { 'rua' => 'Rua da Casa', 'cidade' => 'São Paulo', 'uf' => 'SP' } }
```

## Development

Run `rake` to run the tests.

To install this gem onto your local machine, run `bundle`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/diego-aslz/fancy_hash.

## License

The gem is available as open source under the terms of the MIT License.
