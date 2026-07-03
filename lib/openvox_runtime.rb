# frozen_string_literal: true

require 'openvox_agent_rubygems'

module OpenVoxRuntime
  GEM_NAME = 'openvox'

  def self.activate!(version = nil)
    OpenVoxAgentRubygems.activate!
    specification = select_specification(version)
    raise Gem::LoadError, "Unable to find the #{GEM_NAME} gem#{version.nil? ? '' : " version #{version}"}" if specification.nil?

    if Gem::Specification.find_all_by_name(GEM_NAME).include?(specification)
      version.nil? || version.empty? ? gem(GEM_NAME) : gem(GEM_NAME, version)
      OpenVoxAgentRubygems.restore_paths!
    else
      # OpenVox agent packages may retain a puppet-<version>.gemspec filename.
      # RubyGems ignores that file for lookup by the declared `openvox` name,
      # so add its require paths directly after verifying the specification.
      specification.full_require_paths.reverse_each do |require_path|
        $LOAD_PATH.unshift(require_path) unless $LOAD_PATH.include?(require_path)
      end
    end

    require 'puppet'
    @runtime_specification = specification
  end

  def self.gem_name
    @runtime_specification&.name || (Gem.loaded_specs.key?(GEM_NAME) ? GEM_NAME : 'unknown')
  end

  def self.gem_version
    (@runtime_specification || Gem.loaded_specs[GEM_NAME])&.version&.to_s || 'Unknown'
  end

  def self.available_versions
    available_specifications.map { |spec| spec.version.to_s }.uniq
  end

  def self.available_specifications
    specifications = Gem::Specification.find_all_by_name(GEM_NAME)
    legacy_specification_paths.each do |specification_path|
      specification = Gem::Specification.load(specification_path)
      specifications << specification if specification&.name == GEM_NAME
    end
    specifications.uniq { |specification| [specification.name, specification.version, specification.full_gem_path] }
  end
  private_class_method :available_specifications

  def self.select_specification(version)
    specifications = available_specifications
    specifications = specifications.select { |specification| specification.version.to_s == version } unless version.nil? || version.empty?
    specifications.max_by(&:version)
  end
  private_class_method :select_specification

  def self.legacy_specification_paths
    Gem.path.flat_map do |gem_path|
      specification_dir = File.join(gem_path, 'specifications')
      [File.join(specification_dir, 'openvox-*.gemspec'), File.join(specification_dir, 'puppet-*.gemspec')]
    end.flat_map { |pattern| Dir.glob(pattern) }
  end
  private_class_method :legacy_specification_paths
end
