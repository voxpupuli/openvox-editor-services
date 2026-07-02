# frozen_string_literal: true

require 'puppet-lint'

# puppet-lint discovers installed plugin gems through RubyGems metadata. The
# packaged language server uses vendored source trees instead, so load their
# checks explicitly.
vendored_plugins = File.expand_path('../../vendor/puppet-lint-*/lib/puppet-lint/plugins/**/*.rb', __dir__)
Dir[vendored_plugins].sort.each { |plugin| require plugin }
