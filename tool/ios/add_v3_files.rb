# Usage: ruby tool/ios/add_v3_files.rb ios/Runner.xcodeproj
# Adds the v3 Swift files to the Runner target's Sources phase. Idempotent: running it again
# changes nothing. Later v3 tasks append their Swift file to the V3_SOURCES line below (keep it on
# one line: tool/ios/check_project.rb reads it with a regular expression);
# tool/ios/add_voice_files.rb and tool/ios/add_v2_files.rb stay as they are.
require 'xcodeproj'

V3_SOURCES = %w[].freeze

project = Xcodeproj::Project.open(ARGV.fetch(0))
target  = project.targets.find { |t| t.name == 'Runner' } or abort 'Runner target missing'
group   = project.main_group.children.find { |g| g.display_name == 'Runner' } or abort 'Runner group missing'

V3_SOURCES.each do |name|
  next if group.files.any? { |f| f.path == name }
  target.source_build_phase.add_file_reference(group.new_reference(name), true)
end

project.save
puts 'ok'
