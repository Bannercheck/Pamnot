# Usage: ruby tool/ios/add_widget_target.rb ios/Runner.xcodeproj
# Adds the PamnotWidgetExtension target (bundle id app.pamnot.pamnot.PamnotWidget, iOS 17.0) built
# from ios/PamnotWidget, and embeds it in Runner. Idempotent: if the target already exists, the
# project is saved unchanged. No DEVELOPMENT_TEAM is written (the owner picks a team in Xcode);
# no pod or Swift package is linked into the extension. Checked by tool/ios/check_project.rb.
require 'xcodeproj'

NAME = 'PamnotWidgetExtension'
SOURCES = %w[PamnotWidgetBundle.swift PamnotTodayWidget.swift PamnotListWidget.swift
             PamnotListIntents.swift].freeze

project = Xcodeproj::Project.open(ARGV.fetch(0))
runner  = project.targets.find { |t| t.name == 'Runner' } or abort 'Runner target missing'

unless project.targets.any? { |t| t.name == NAME }
  ext   = project.new_target(:app_extension, NAME, :ios, '17.0', nil, :swift)
  group = project.main_group.new_group('PamnotWidget', 'PamnotWidget')

  # Sources: the four Swift files.
  SOURCES.each { |name| ext.source_build_phase.add_file_reference(group.new_reference(name), true) }

  # Resources: privacy manifest (copied into the .appex) and the en/tr Localizable.strings.
  privacy = group.new_reference('PrivacyInfo.xcprivacy')
  privacy.last_known_file_type = 'text.xml'
  ext.resources_build_phase.add_file_reference(privacy, true)
  variant = group.new_variant_group('Localizable.strings')
  %w[en tr].each do |lang|
    ref = variant.new_reference("#{lang}.lproj/Localizable.strings")
    ref.name = lang
    ref.last_known_file_type = 'text.plist.strings'
  end
  ext.resources_build_phase.add_file_reference(variant, true)

  # References only (not target members): Info.plist, entitlements, base configuration.
  group.new_reference('Info.plist')
  group.new_reference('PamnotWidget.entitlements')
  xc = group.new_reference('PamnotWidget.xcconfig')

  ext.build_configurations.each do |c|
    c.base_configuration_reference = xc
    c.build_settings.replace(
      'PRODUCT_NAME' => '$(TARGET_NAME)', 'PRODUCT_BUNDLE_IDENTIFIER' => 'app.pamnot.pamnot.PamnotWidget',
      'INFOPLIST_FILE' => 'PamnotWidget/Info.plist', 'GENERATE_INFOPLIST_FILE' => 'NO',
      'CODE_SIGN_ENTITLEMENTS' => 'PamnotWidget/PamnotWidget.entitlements', 'CODE_SIGN_STYLE' => 'Automatic',
      'IPHONEOS_DEPLOYMENT_TARGET' => '17.0', 'SWIFT_VERSION' => '5.0', 'TARGETED_DEVICE_FAMILY' => '1,2',
      'SKIP_INSTALL' => 'YES', 'APPLICATION_EXTENSION_API_ONLY' => 'YES', 'SWIFT_EMIT_LOC_STRINGS' => 'YES',
      'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks'])
  end

  # The gem adds a Foundation.framework reference with a fixed SDK path; the SDK folder on another
  # Mac or Xcode may differ, and the extension needs no explicit framework link.
  ext.frameworks_build_phase.files.to_a.each do |f|
    ref = f.file_ref
    f.remove_from_project
    ref&.remove_from_project
  end
  # new_target also leaves an empty Frameworks/iOS group behind; drop it while it holds no file.
  frameworks = project.main_group.children.find { |g| g.isa == 'PBXGroup' && g.display_name == 'Frameworks' }
  if frameworks && frameworks.recursive_children.none? { |c| c.isa == 'PBXFileReference' }
    frameworks.clear
    frameworks.remove_from_project
  end

  runner.add_dependency(ext)
  embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
  embed.symbol_dst_subfolder_spec = :plug_ins
  embed.add_file_reference(ext.product_reference, true).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
  # Before "Run Script" and "Thin Binary", so the build has no "Cycle inside Runner".
  runner.build_phases.move(embed, 0)
  runner.build_configurations.each { |c| c.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements' }
  project.root_object.known_regions |= %w[tr]
end

project.save
puts 'ok'
