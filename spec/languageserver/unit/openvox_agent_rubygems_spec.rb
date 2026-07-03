# frozen_string_literal: true

require 'openvox_agent_rubygems'

describe OpenVoxAgentRubygems do
  around do |example|
    original_gem_home = ENV.fetch('GEM_HOME', nil)
    original_gem_path = ENV.fetch('GEM_PATH', nil)
    original_home = ENV.fetch('HOME', nil)

    example.run
  ensure
    original_gem_home.nil? ? ENV.delete('GEM_HOME') : ENV['GEM_HOME'] = original_gem_home
    original_gem_path.nil? ? ENV.delete('GEM_PATH') : ENV['GEM_PATH'] = original_gem_path
    original_home.nil? ? ENV.delete('HOME') : ENV['HOME'] = original_home
  end

  describe '.activate!' do
    it 'removes inherited user gem paths when running under the packaged OpenVox Agent Ruby' do
      ENV['GEM_HOME'] = '/Users/example/.rvm/gems/ruby-3.4.4'
      ENV['GEM_PATH'] = '/Users/example/.rvm/rubies/ruby-3.4.4/lib/ruby/gems/3.4.0'
      ENV['HOME'] = '/Users/example'

      allow(RbConfig::CONFIG).to receive(:[]).with('prefix').and_return('/opt/puppetlabs/puppet')
      allow(Gem).to receive(:default_dir).and_return('/opt/puppetlabs/puppet/lib/ruby/gems/3.2.0').at_least(:once)
      allow(Gem).to receive(:path).and_return(
        ['/Users/example/.rvm/gems/ruby-3.4.4'],
        ['/opt/puppetlabs/puppet/lib/ruby/gems/3.2.0'],
        [],
      )
      expect(Gem).to receive(:clear_paths)
      expect(Gem).to receive(:use_paths).with(
        '/opt/puppetlabs/puppet/lib/ruby/gems/3.2.0',
        ['/opt/puppetlabs/puppet/lib/ruby/gems/3.2.0'],
      )

      expect(described_class.activate!).to be(true)
      expect(ENV).not_to include('GEM_HOME')
      expect(ENV).not_to include('GEM_PATH')
    end

    it 'keeps bundled extension gems while adding the packaged OpenVox Agent gem paths' do
      ENV['GEM_HOME'] = '/extension/vendor/languageserver/gems'
      ENV['GEM_PATH'] = '/extension/vendor/languageserver/gems'

      allow(RbConfig::CONFIG).to receive(:[]).with('prefix').and_return('/opt/puppetlabs/puppet')
      allow(Gem).to receive(:default_dir).and_return('/opt/puppetlabs/puppet/lib/ruby/gems/3.2.0').at_least(:once)
      allow(Gem).to receive(:path).and_return(
        ['/extension/vendor/languageserver/gems'],
        ['/opt/puppetlabs/puppet/lib/ruby/gems/3.2.0', '/opt/puppetlabs/puppet/lib/ruby/vendor_gems'],
        [],
      )
      expect(Gem).to receive(:clear_paths)
      expect(Gem).to receive(:use_paths).with(
        '/extension/vendor/languageserver/gems',
        [
          '/extension/vendor/languageserver/gems',
          '/opt/puppetlabs/puppet/lib/ruby/gems/3.2.0',
          '/opt/puppetlabs/puppet/lib/ruby/vendor_gems',
        ],
      )

      expect(described_class.activate!).to be(true)
    end

    it 'restores remembered gem paths after RubyGems activation changes them' do
      ENV['GEM_HOME'] = '/extension/vendor/languageserver/gems'
      ENV['GEM_PATH'] = '/extension/vendor/languageserver/gems'

      allow(RbConfig::CONFIG).to receive(:[]).with('prefix').and_return('/opt/puppetlabs/puppet')
      allow(Gem).to receive(:default_dir).and_return('/opt/puppetlabs/puppet/lib/ruby/gems/3.2.0').at_least(:once)
      allow(Gem).to receive(:path).and_return(
        ['/extension/vendor/languageserver/gems'],
        ['/opt/puppetlabs/puppet/lib/ruby/gems/3.2.0'],
        [],
        ['/opt/puppetlabs/puppet/lib/ruby/gems/3.2.0'],
      )
      expect(Gem).to receive(:clear_paths)
      expect(Gem).to receive(:use_paths).twice.with(
        '/extension/vendor/languageserver/gems',
        ['/extension/vendor/languageserver/gems', '/opt/puppetlabs/puppet/lib/ruby/gems/3.2.0'],
      )

      expect(described_class.activate!).to be(true)
      expect(described_class.restore_paths!).to be(true)
    end

    it 'leaves user gem paths alone outside the packaged OpenVox Agent Ruby' do
      ENV['GEM_HOME'] = '/Users/example/.rvm/gems/ruby-3.4.4'
      ENV['GEM_PATH'] = '/Users/example/.rvm/rubies/ruby-3.4.4/lib/ruby/gems/3.4.0'
      ENV['HOME'] = '/Users/example'

      allow(RbConfig::CONFIG).to receive(:[]).with('prefix').and_return('/Users/example/.rvm/rubies/ruby-3.4.4')
      allow(Gem).to receive(:default_dir).and_return('/Users/example/.rvm/rubies/ruby-3.4.4/lib/ruby/gems/3.4.0')
      expect(Gem).not_to receive(:clear_paths)

      expect(described_class.activate!).to be(false)
      expect(ENV['GEM_HOME']).to eq('/Users/example/.rvm/gems/ruby-3.4.4')
      expect(ENV['GEM_PATH']).to eq('/Users/example/.rvm/rubies/ruby-3.4.4/lib/ruby/gems/3.4.0')
    end
  end
end
