# frozen_string_literal: true

require 'rbconfig'

module OpenVoxAgentRubygems
  def self.activate!
    return false unless packaged_agent_ruby?

    unless ENV.key?('GEM_HOME') || ENV.key?('GEM_PATH')
      restore_paths!
      return !@gem_paths.nil?
    end

    original_paths = Gem.path
    ENV.delete('GEM_HOME')
    ENV.delete('GEM_PATH')
    Gem.clear_paths

    agent_paths = Gem.path.reject { |path| user_ruby_path?(path) }
    preserved_paths = original_paths.reject { |path| user_ruby_path?(path) }
    combined_paths = (preserved_paths + agent_paths).uniq
    @gem_home = combined_paths.first
    @gem_paths = combined_paths
    restore_paths!
    add_gem_require_paths!(preserved_paths)
    true
  end

  def self.restore_paths!
    return false unless packaged_agent_ruby?
    return false if @gem_paths.nil?

    Gem.use_paths(@gem_home, @gem_paths) unless Gem.path == @gem_paths
    true
  end

  def self.add_gem_require_paths!(gem_paths)
    gem_paths.each do |gem_path|
      specification_dir = File.join(gem_path, 'specifications')
      next unless Dir.exist?(specification_dir)

      Dir[File.join(specification_dir, '*.gemspec')].sort.each do |specification_path|
        specification = Gem::Specification.load(specification_path)
        next if specification.nil?
        next if specification.name == 'openvox-editor-services'

        specification.full_require_paths.reverse_each do |require_path|
          $LOAD_PATH.unshift(require_path) unless $LOAD_PATH.include?(require_path)
        end
      end
    end
  end
  private_class_method :add_gem_require_paths!

  def self.packaged_agent_ruby?
    [RbConfig::CONFIG['prefix'], Gem.default_dir].compact.any? do |path|
      normalized_path(path).include?('/puppetlabs/puppet')
    end
  end
  private_class_method :packaged_agent_ruby?

  def self.normalized_path(path)
    File.expand_path(path.to_s).tr('\\', '/').downcase
  end
  private_class_method :normalized_path

  def self.user_ruby_path?(path)
    normalized = normalized_path(path)
    home = begin
      Dir.home
    rescue StandardError
      nil
    end

    return false if home.nil? || home.empty?

    normalized_home = normalized_path(home)
    normalized.start_with?(File.join(normalized_home, '.rvm')) ||
      normalized.start_with?(File.join(normalized_home, '.gem'))
  end
  private_class_method :user_ruby_path?
end
