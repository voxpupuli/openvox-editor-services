# frozen_string_literal: true
require_relative 'lib/puppet_editor_services/version'
require 'rake'

Gem::Specification.new do |s|
  s.name           = 'openvox-editor-services'
  s.version        = PuppetEditorServices.version
  s.authors        = ['OpenVox Project contributors']
  s.email          = ['openvox@voxpupuli.org']
  s.summary       = 'OpenVox Puppet DSL Server for editors'
  s.description = <<~EOF
    A ruby based implementation of a Language Server and Debug Server for the
    OpenVox Puppet DSL. Integrate this into your editor to benefit from full OpenVox
    Puppet DSL support, such as syntax hightlighting, linting, hover support and more.
  EOF
  s.homepage    = 'https://github.com/voxpupuli/openvox-editor-services'
  s.required_ruby_version = '>= 3.1.0'
  s.executables = %w[ openvox-debugserver openvox-languageserver openvox-languageserver-sidecar ]
  s.files          = FileList['lib/**/*.rb',
                              'bin/*',
                              '[A-Z]*'].to_a.reject { |file| file.end_with?('.gem') }
  s.license        = 'Apache-2.0'
  s.add_runtime_dependency 'puppet-lint', '~> 4.0'
  s.add_runtime_dependency 'hiera-eyaml', '~> 2.1'
  s.add_runtime_dependency 'puppetfile-resolver', '~> 0.6'
  s.add_runtime_dependency 'molinillo', '~> 0.6'
  s.add_runtime_dependency 'openvox-strings', '~> 7.1'
  s.add_runtime_dependency 'openfact', '>= 5.1', '< 6'
  s.add_runtime_dependency 'yard', '~> 0.9'
end
