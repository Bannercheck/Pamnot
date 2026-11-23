# Usage: ruby tool/ios/add_voice_files.rb ios/Runner.xcodeproj
# Adds the voice-capture Swift files, the privacy manifest and the en/tr .strings tables to the
# Runner target. Idempotent: running it again changes nothing.
require 'xcodeproj'

project = Xcodeproj::Project.open(ARGV.fetch(0))
target  = project.targets.find { |t| t.name == 'Runner' } or abort 'Runner target missing'
group   = project.main_group.children.find { |g| g.display_name == 'Runner' } or abort 'Runner group missing'

%w[PamnotLaunchBridge.swift VoiceTaskIntent.swift].each do |name|
  next if group.files.any? { |f| f.path == name }
  target.source_build_phase.add_file_reference(group.new_reference(name), true)
end

%w[PrivacyInfo.xcprivacy].each do |name|
  next if group.files.any? { |f| f.path == name }
  ref = group.new_reference(name)
  ref.last_known_file_type = 'text.xml'
  target.resources_build_phase.add_file_reference(ref, true)
end

%w[AppShortcuts Localizable InfoPlist].each do |table|
  name = "#{table}.strings"
  next if group.children.any? { |c| c.isa == 'PBXVariantGroup' && c.name == name }
  variant = group.new_variant_group(name)
  %w[en tr].each do |lang|
    ref = variant.new_reference("#{lang}.lproj/#{name}")
    ref.name = lang
    ref.last_known_file_type = 'text.plist.strings'
  end
  target.resources_build_phase.add_file_reference(variant, true)
end

project.root_object.known_regions |= %w[tr]
project.save
puts 'ok'
