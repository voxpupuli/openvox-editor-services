# frozen_string_literal: true

require 'openvox_runtime'

describe OpenVoxRuntime do
  describe '.available_versions' do
    it 'lists installed OpenVox gem versions' do
      expect(described_class.available_versions).not_to be_empty
    end
  end

  describe '.activate!' do
    it 'activates OpenVox while exposing the Puppet compatibility API' do
      described_class.activate!

      expect(described_class.gem_name).to eq('openvox')
      expect(described_class.gem_version).not_to eq('Unknown')
      expect(defined?(Puppet)).to eq('constant')
      expect(Puppet.version).to eq(described_class.gem_version)
    end
  end
end
