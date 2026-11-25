# Usage: ruby tool/ios/check_project.rb ios/Runner.xcodeproj
# Local check (not a CI step) that tool/ios/add_voice_files.rb and tool/ios/add_v2_files.rb wired
# their files into the Runner target: build phases, en/tr variant groups, knownRegions,
# objectVersion 54, and every file they add exists on disk. Also checks the PamnotWidgetExtension
# target that tool/ios/add_widget_target.rb adds: its build settings, phases and files, and how
# Runner depends on and embeds it. Generated files the project also references
# (Generated.xcconfig, GeneratedPluginRegistrant.*, Runner.app) are not checked.
# Prints every failure and exits 1; prints `project ok` on success.
require 'xcodeproj'

SOURCES = %w[PamnotLaunchBridge.swift VoiceTaskIntent.swift PamnotAccessibilityBridge.swift
             PamnotAlarmPlugin.swift].freeze
PLAIN_RESOURCES = %w[PrivacyInfo.xcprivacy].freeze
STRINGS_TABLES = %w[AppShortcuts.strings Localizable.strings InfoPlist.strings].freeze
LANGS = %w[en tr].freeze

failures = []
project = Xcodeproj::Project.open(ARGV.fetch(0))
target = project.targets.find { |t| t.name == 'Runner' }
abort 'FAIL Runner target missing' unless target

failures << "objectVersion must be 54, found #{project.object_version}" unless project.object_version == '54'
failures << "knownRegions must include tr, found #{project.root_object.known_regions}" \
  unless project.root_object.known_regions.include?('tr')

# Each name must appear exactly once in its phase: a second copy means a non-idempotent run.
def phase_refs(phase, name)
  phase.files.map(&:file_ref).compact.select { |ref| ref.display_name == name }
end

on_disk = []

SOURCES.each do |name|
  refs = phase_refs(target.source_build_phase, name)
  failures << "#{name}: in the Sources phase #{refs.size} times, expected once" unless refs.size == 1
  on_disk.concat(refs)
end

PLAIN_RESOURCES.each do |name|
  refs = phase_refs(target.resources_build_phase, name)
  failures << "#{name}: in the Resources phase #{refs.size} times, expected once" unless refs.size == 1
  on_disk.concat(refs)
end

STRINGS_TABLES.each do |name|
  refs = phase_refs(target.resources_build_phase, name)
  failures << "#{name}: in the Resources phase #{refs.size} times, expected once" unless refs.size == 1
  variant = refs.first
  next unless variant
  unless variant.isa == 'PBXVariantGroup'
    failures << "#{name}: expected a variant group, found #{variant.isa}"
    next
  end
  langs = variant.children.map(&:display_name).sort
  failures << "#{name}: variant group must hold en and tr once each, found #{langs}" unless langs == LANGS
  on_disk.concat(variant.children)
end

on_disk.each do |ref|
  path = ref.real_path
  failures << "#{ref.display_name}: #{path} is referenced but missing on disk" unless File.file?(path)
end
expected_files = SOURCES.size + PLAIN_RESOURCES.size + STRINGS_TABLES.size * LANGS.size
failures << "expected #{expected_files} files, found #{on_disk.size}" unless on_disk.size == expected_files

# --- PamnotWidgetExtension (tool/ios/add_widget_target.rb) ---
WIDGET_NAME = 'PamnotWidgetExtension'
WIDGET_SOURCES = %w[PamnotWidgetBundle.swift PamnotTodayWidget.swift PamnotListWidget.swift
                    PamnotListIntents.swift].freeze
WIDGET_SETTINGS = {
  'PRODUCT_BUNDLE_IDENTIFIER' => 'app.pamnot.pamnot.PamnotWidget',
  'INFOPLIST_FILE' => 'PamnotWidget/Info.plist',
  'CODE_SIGN_ENTITLEMENTS' => 'PamnotWidget/PamnotWidget.entitlements',
  'IPHONEOS_DEPLOYMENT_TARGET' => '17.0'
}.freeze
CONFIGS = %w[Debug Release Profile].freeze

widget = project.targets.find { |t| t.name == WIDGET_NAME }
if widget.nil?
  failures << "#{WIDGET_NAME} target missing"
else
  unless widget.product_type == 'com.apple.product-type.app-extension'
    failures << "#{WIDGET_NAME}: product type must be com.apple.product-type.app-extension, found #{widget.product_type}"
  end
  CONFIGS.each do |config_name|
    config = widget.build_configurations.find { |c| c.name == config_name }
    unless config
      failures << "#{WIDGET_NAME}: #{config_name} configuration missing"
      next
    end
    WIDGET_SETTINGS.each do |key, value|
      found = config.build_settings[key]
      failures << "#{WIDGET_NAME} #{config_name}: #{key} must be #{value}, found #{found.inspect}" unless found == value
    end
    base = config.base_configuration_reference
    unless base && base.display_name == 'PamnotWidget.xcconfig'
      failures << "#{WIDGET_NAME} #{config_name}: base configuration must be PamnotWidget.xcconfig, " \
                  "found #{base&.display_name.inspect}"
    end
  end

  widget_files = []
  WIDGET_SOURCES.each do |name|
    refs = phase_refs(widget.source_build_phase, name)
    failures << "#{WIDGET_NAME} #{name}: in the Sources phase #{refs.size} times, expected once" unless refs.size == 1
    widget_files.concat(refs)
  end
  source_count = widget.source_build_phase.files.size
  unless source_count == WIDGET_SOURCES.size
    failures << "#{WIDGET_NAME}: Sources phase must hold #{WIDGET_SOURCES.size} files, found #{source_count}"
  end
  privacy = phase_refs(widget.resources_build_phase, 'PrivacyInfo.xcprivacy')
  failures << "#{WIDGET_NAME} PrivacyInfo.xcprivacy: in the Resources phase #{privacy.size} times, expected once" \
    unless privacy.size == 1
  widget_files.concat(privacy)
  strings = phase_refs(widget.resources_build_phase, 'Localizable.strings')
  if strings.size != 1
    failures << "#{WIDGET_NAME} Localizable.strings: in the Resources phase #{strings.size} times, expected once"
  elsif strings.first.isa != 'PBXVariantGroup'
    failures << "#{WIDGET_NAME} Localizable.strings: expected a variant group, found #{strings.first.isa}"
  else
    langs = strings.first.children.map(&:display_name).sort
    failures << "#{WIDGET_NAME} Localizable.strings: variant group must hold en and tr, found #{langs}" \
      unless langs == LANGS
    widget_files.concat(strings.first.children)
  end
  widget_files.each do |ref|
    path = ref.real_path
    failures << "#{WIDGET_NAME} #{ref.display_name}: #{path} is referenced but missing on disk" unless File.file?(path)
  end
  base_refs = widget.build_configurations.map(&:base_configuration_reference).compact.uniq
  base_refs.each do |ref|
    failures << "#{WIDGET_NAME}: #{ref.real_path} is referenced but missing on disk" unless File.file?(ref.real_path)
  end

  frameworks = widget.frameworks_build_phase.files.size
  failures << "#{WIDGET_NAME}: Frameworks phase must be empty, found #{frameworks} files" unless frameworks.zero?

  first = target.build_phases.first
  if first.nil? || first.display_name != 'Embed Foundation Extensions'
    failures << "Runner: first build phase must be Embed Foundation Extensions, found #{first&.display_name.inspect}"
  else
    unless first.respond_to?(:dst_subfolder_spec) && first.dst_subfolder_spec.to_s == '13'
      failures << 'Runner Embed Foundation Extensions: dstSubfolderSpec must be 13'
    end
    embedded = first.files.map(&:file_ref).compact.map(&:display_name)
    failures << "Runner Embed Foundation Extensions: must hold #{WIDGET_NAME}.appex, found #{embedded}" \
      unless embedded == ["#{WIDGET_NAME}.appex"]
  end
  unless target.dependencies.any? { |d| d.target == widget }
    failures << "Runner: target dependency on #{WIDGET_NAME} missing"
  end
end

project.objects.select { |o| o.respond_to?(:path) && o.path.to_s.include?('iPhoneOS26') }.each do |o|
  failures << "#{o.display_name}: path #{o.path} points into a fixed iPhoneOS26 SDK folder"
end

CONFIGS.each do |config_name|
  config = target.build_configurations.find { |c| c.name == config_name }
  found = config&.build_settings&.fetch('CODE_SIGN_ENTITLEMENTS', nil)
  failures << "Runner #{config_name}: CODE_SIGN_ENTITLEMENTS must be Runner/Runner.entitlements, found #{found.inspect}" \
    unless found == 'Runner/Runner.entitlements'
end

if failures.empty?
  puts 'project ok'
else
  failures.each { |message| puts "FAIL #{message}" }
  exit 1
end
