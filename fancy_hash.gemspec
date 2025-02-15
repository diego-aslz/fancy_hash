# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = 'fancy_hash'
  spec.version = '0.1.0'
  spec.summary = 'A gem for working with enhanced Ruby hashes'
  spec.description = 'FancyHash provides additional functionality and convenience methods for working with Ruby hashes'
  spec.authors = ['Diego Selzlein']
  spec.homepage = 'https://github.com/diego-aslz/fancy_hash'
  spec.metadata['source_code_uri'] = spec.homepage
  spec.required_ruby_version = '>= 2.7.0'

  spec.add_dependency 'activemodel', '>= 6.0.0'

  spec.license = 'MIT'

  spec.files = Dir['lib/**/*.rb']
  spec.require_paths = ['lib']
end
