# Usage: ruby tool/ios/add_v2_files.rb ios/Runner.xcodeproj
# Adds the v2 Swift files to the Runner target's Sources phase. Idempotent: running it again
# changes nothing. Later v2 tasks append their Swift file to V2_SOURCES; tool/ios/add_voice_files.rb
# stays as it is.
require 'xcodeproj'

V2_SOURCES = %w[PamnotAccessibilityBridge.swift PamnotAlarmPlugin.swift PamnotPipPlugin.swift].freeze

project = Xcodeproj::Project.open(ARGV.fetch(0))
target  = project.targets.find { |t| t.name == 'Runner' } or abort 'Runner target missing'
group   = project.main_group.children.find { |g| g.display_name == 'Runner' } or abort 'Runner group missing'

V2_SOURCES.each do |name|
  next if group.files.any? { |f| f.path == name }
  target.source_build_phase.add_file_reference(group.new_reference(name), true)
end

project.save
puts 'ok'
