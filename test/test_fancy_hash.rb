require 'minitest/autorun'
require 'fancy_hash'

class Person < FancyHash
  attribute :name, type: :string
  attribute :age, field: 'Idade', type: :integer
  attribute :favorite_color, field: 'favoriteColor', type: :enum, of: { red: 0, green: 1, blue: 2 }
end

class FancyHashTest < Minitest::Test
  def test_string_attribute
    person = Person.new({})
    person.name = 'Diego'

    assert_equal person.__getobj__, { 'name' => 'Diego' }
    assert_equal person.name, 'Diego'
  end

  def test_integer_attribute
    person = Person.new({ 'Idade' => 18 })

    assert_equal person.age, 18

    person.age = 20

    assert_equal person.__getobj__, { 'Idade' => 20 }
  end

  def test_enum_attribute
    person = Person.new({})

    assert_nil person.favorite_color

    person.favorite_color = :green

    assert person.green?
    assert_equal person.favorite_color, 'green'
    assert_equal person.__getobj__, { 'favoriteColor' => 1 }

    person.favorite_color = 2

    assert_equal person.favorite_color, 'blue'
  end
end
