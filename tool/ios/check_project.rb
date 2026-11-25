# Usage: ruby tool/ios/check_project.rb ios/Runner.xcodeproj
# Local check (not a CI step) that tool/ios/add_voice_files.rb and tool/ios/add_v2_files.rb wired
# their files into the Runner target: build phases, en/tr variant groups, knownRegions,
# objectVersion 54, and every file they add exists on disk. Generated files the project also references
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

if failures.empty?
  puts 'project ok'
else
  failures.each { |message| puts "FAIL #{message}" }
  exit 1
end
