source ENV['GEM_SOURCE'] || "https://rubygems.org"

# -=-=-=-=-=- WARNING -=-=-=-=-=-
# There should be NO runtime gem dependencies here.  In production this code will be running using the Ruby
# runtime provided by Puppet.  That means no native extensions and NO BUNDLER.  All runtime dependences should
# be re-vendored and then the load path modified appropriately.
#
# This gemfile only exists to help when developing the language server and running tests
# -=-=-=-=-=- WARNING -=-=-=-=-=-

group :development do
  gem 'json', "< 2.8.0",                  :require => false
  gem 'openfact', '>= 5.1', '< 6',        :require => false
  gem 'openvox-strings', '~> 7.1',        :require => false
  gem 'puppetfile-resolver', '~> 0.6.2',  :require => false
  gem 'rake', '>= 10.4',                  :require => false
  gem 'rspec', '>= 3.2',                  :require => false
  gem 'rubocop-capybara', '~> 2.22.0',    :require => false
  gem 'rubocop-factory_bot', '~> 2.28.0', :require => false
  gem 'rubocop-rspec_rails', '~> 2.32.0', :require => false
  gem 'simplecov-console',                :require => false
  gem 'simplecov',                        :require => false
  gem 'syslog', '~> 0.4',                 :require => false unless Gem.win_platform?
  gem 'voxpupuli-puppet-lint-plugins', '= 7.0.0', :require => false
  gem 'yard', '~> 0.9.28',                :require => false
  gem "rubocop-performance", '~> 1.24.0', :require => false
  gem "rubocop-rspec", '~> 3.5.0',        :require => false
  gem "rubocop", '~> 1.73.0',             :require => false

  if ENV['OPENVOX_GEM_VERSION']
    gem 'openvox', ENV['OPENVOX_GEM_VERSION'], :require => false
  else
    gem 'openvox', :require => false
  end

  case RUBY_PLATFORM
  when /darwin/
    gem 'CFPropertyList'
  end

  gem "win32-dir", "<= 0.4.9",      :require => false, :platforms => ["mswin", "mingw", "x64_mingw"]
  gem "win32-eventlog", "<= 0.6.7", :require => false, :platforms => ["mswin", "mingw", "x64_mingw"]
  gem "win32-process", "<= 0.10.0",  :require => false, :platforms => ["mswin", "mingw", "x64_mingw"]
  gem "win32-security", "<= 0.2.5", :require => false, :platforms => ["mswin", "mingw", "x64_mingw"]
  gem "win32-service", "<= 2.3.2",  :require => false, :platforms => ["mswin", "mingw", "x64_mingw"]

  # Gems for building release tarballs etc.
  gem "archive-zip", :require => false
  gem "minitar"    , :require => false
end

group :release, optional: true do
  gem 'faraday-retry', '~> 2.1', require: false
  gem 'github_changelog_generator', '~> 1.18', require: false
end
