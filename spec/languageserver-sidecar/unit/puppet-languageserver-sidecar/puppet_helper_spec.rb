require 'spec_helper'
require 'tmpdir'
require 'fileutils'

describe 'PuppetLanguageServerSidecar::PuppetHelper', :if => Gem::Version.new(Puppet.version) >= Gem::Version.new('5.0.0') do
  let(:subject) { PuppetLanguageServerSidecar::PuppetHelper }
  let(:cache) { PuppetLanguageServerSidecar::Cache::Null.new }

  describe '#retrieve_classes' do
    # Note this is a private method, so this test can be a little brittle

    it 'should not error when the Puppet.setting[environmentpath] does not exist' do
      mocked_puppet_settings = Puppet.settings
      mocked_puppet_settings[:environmentpath] = 'dir/does/not/exist'

      expect(Puppet).to receive(:settings).and_return(mocked_puppet_settings).at_least(:once)

      result = subject.send(:retrieve_via_puppet_strings, cache, { object_types: [:class] })
    end
  end

  describe 'PuppetPathFinder' do
    let(:root) { Dir.mktmpdir('puppet-path-finder') }
    let(:puppet_lib_path) { File.join(root, 'lib', 'ruby', 'vendor_ruby') }
    let(:system_loader) { double('system_loader', path: puppet_lib_path, lib_root?: true) }
    let(:loaders) { double('loaders', puppet_system_loader: system_loader) }
    let(:configuration) { double('configuration', path_to_env: nil) }
    let(:puppet_env) { double('puppet_env', modules: [], configuration: configuration, loaders: loaders) }

    before do
      FileUtils.mkdir_p(File.join(puppet_lib_path, 'puppet', 'type', 'file'))
      File.write(File.join(puppet_lib_path, 'puppet', 'type', 'file.rb'), "# core file type\n")
      File.write(File.join(puppet_lib_path, 'puppet', 'type', 'file', 'owner.rb'), "# core file owner property\n")
      allow(Puppet).to receive(:settings).and_return(vardir: nil)
    end

    after do
      FileUtils.remove_entry(root)
    end

    it 'finds core resource types in a Puppet agent vendor_ruby layout' do
      finder = PuppetLanguageServerSidecar::PuppetHelper::PuppetPathFinder.new(puppet_env, [:type])

      result = finder.find

      expect(result.length).to eq(1)
      expect(File.read(result.first)).to include('# core file type', '# core file owner property')
    end
  end
end
