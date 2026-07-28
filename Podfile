platform :ios, '17.0'

use_frameworks!

target 'BrowseCraft' do
  # Core MVP pipeline: fetch -> parse -> publish current snapshot -> display.
  pod 'GRDB.swift', '6.24.1'
  pod 'Alamofire', '5.11.2'
  pod 'Nuke', '10.7.1'
  pod 'NukeUI', '0.8.0'

  target 'BrowseCraftTests' do
    inherit! :search_paths
  end

  target 'BrowseCraftUITests' do
    # UI tests launch the app bundle and do not import app Pods directly.
  end
end

post_install do |installer|
  # CocoaPods 1.16 still stamps its generated project as Xcode 16. Mark the
  # generated project with the active Xcode version so Xcode does not offer
  # project-wide recommended-setting edits for disposable Pods metadata.
  installer.pods_project.root_object.attributes['LastUpgradeCheck'] = '2660'

  # The app supports iOS 17 and above. Some pods declare older deployment
  # targets, so we lift generated Pod targets to the app's minimum version.
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
      config.build_settings['LIBRARY_SEARCH_PATHS'] = ['$(inherited)']
      config.build_settings.delete('ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES')
      config.build_settings.delete('EMBEDDED_CONTENT_CONTAINS_SWIFT')
      config.build_settings['CODE_SIGN_IDENTITY'] = ''
      config.build_settings['ENABLE_MODULE_VERIFIER'] = 'YES'
      config.build_settings['MODULE_VERIFIER_SUPPORTED_LANGUAGES'] = 'objective-c objective-c++'
      config.build_settings['MODULE_VERIFIER_SUPPORTED_LANGUAGE_STANDARDS'] = 'gnu17 gnu++20'
      # TEST BrowseCraft archives with the Debug configuration. Dynamic pod
      # frameworks still need standalone dSYMs when that archive is uploaded.
      config.build_settings['DEBUG_INFORMATION_FORMAT'] = 'dwarf-with-dsym'
    end
  end

  installer.pods_project.build_configurations.each do |config|
    config.build_settings['ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS'] = 'YES'
    config.build_settings['DEAD_CODE_STRIPPING'] = 'YES'
    config.build_settings['STRING_CATALOG_GENERATE_SYMBOLS'] = 'YES'
    config.build_settings.delete('STRIP_INSTALLED_PRODUCT')
    config.build_settings.delete('STRIP_STYLE')
    config.build_settings.delete('STRIP_SWIFT_SYMBOLS')
  end
  installer.pods_project.root_object.attributes['BuildIndependentTargetsInParallel'] = 'YES'

  # NukeUI 0.8 resolves Gifu 3.x, whose GIF helper still uses the
  # MobileCoreServices UTI API deprecated in iOS 15. Keep the compatibility
  # dependency while compiling it against UniformTypeIdentifiers instead.
  gifu_image_source_helper = File.join(
    installer.sandbox.root,
    'Gifu/Sources/Gifu/Helpers/ImageSourceHelpers.swift'
  )
  if File.exist?(gifu_image_source_helper)
    content = File.read(gifu_image_source_helper)
    patched = content
      .sub('import MobileCoreServices', 'import UniformTypeIdentifiers')
      .sub(
        'let isTypeGIF = UTTypeConformsTo(CGImageSourceGetType(self) ?? "" as CFString, kUTTypeGIF)',
        <<~'SWIFT'.strip
          let isTypeGIF = CGImageSourceGetType(self)
            .flatMap { UTType($0 as String) }?
            .conforms(to: .gif) == true
        SWIFT
      )
      .sub(
        'return isTypeGIF != false && imageCount > 1',
        'return isTypeGIF && imageCount > 1'
      )
    File.write(gifu_image_source_helper, patched) if patched != content
  end

  # Xcode 26 expands the old CocoaPods Swift runtime search path into a
  # cryptexd Metal toolchain path and reports it as a missing search path.
  Dir.glob(File.join(installer.sandbox.root, 'Target Support Files/**/*.xcconfig')).each do |xcconfig|
    content = File.read(xcconfig)
    cleaned = content
      .gsub(
        'LIBRARY_SEARCH_PATHS = $(inherited) "${TOOLCHAIN_DIR}/usr/lib/swift/${PLATFORM_NAME}" /usr/lib/swift',
        'LIBRARY_SEARCH_PATHS = $(inherited)'
      )
      # Modern Xcode determines Swift runtime embedding automatically. These
      # legacy CocoaPods settings trigger duplicate recommended-setting issues.
      .gsub(/^ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES = YES\r?\n/, '')
      .gsub(/^EMBEDDED_CONTENT_CONTAINS_SWIFT = YES\r?\n/, '')
    File.write(xcconfig, cleaned) if cleaned != content
  end
end
