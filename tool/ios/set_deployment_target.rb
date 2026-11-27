# Usage: ruby tool/ios/set_deployment_target.rb ios/Runner.xcodeproj 17.0
# Sets IPHONEOS_DEPLOYMENT_TARGET in the project's build configurations and, where the Runner
# target sets it itself, in Runner's configurations. Other targets (PamnotWidgetExtension,
# RunnerTests) are left as they are. Idempotent: when nothing changes the project is not saved.
require 'xcodeproj'

KEY = 'IPHONEOS_DEPLOYMENT_TARGET'

path    = ARGV.fetch(0)
version = ARGV.fetch(1)
abort "version must look like 17.0, found #{version.inspect}" unless version.match?(/\A\d+\.\d+\z/)

project = Xcodeproj::Project.open(path)
target  = project.targets.find { |t| t.name == 'Runner' } or abort 'Runner target missing'

changed = false
project.build_configurations.each do |config|
  next if config.build_settings[KEY] == version
  config.build_settings[KEY] = version
  changed = true
end
target.build_configurations.each do |config|
  next unless config.build_settings.key?(KEY)
  next if config.build_settings[KEY] == version
  config.build_settings[KEY] = version
  changed = true
end

project.save if changed
puts changed ? 'ok' : 'ok (unchanged)'
