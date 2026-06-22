# frozen_string_literal: true

# Activates the OpenFact gem while retaining its Facter-compatible Ruby API.
# OpenFact intentionally provides `require 'facter'`, the `Facter` namespace,
# and the `facter` executable.
module OpenFactRuntime
  GEM_NAME = 'openfact'

  def self.activate!
    gem(GEM_NAME)
    require 'facter'
    @runtime_specification = Gem.loaded_specs[GEM_NAME]
    raise Gem::LoadError, "The loaded fact implementation is not the #{GEM_NAME} gem" if @runtime_specification.nil?

    true
  end

  def self.gem_name
    @runtime_specification&.name || 'unknown'
  end

  def self.gem_version
    @runtime_specification&.version&.to_s || 'Unknown'
  end
end
