platform :ios, '17.0'

use_frameworks!

target 'BrowseCraft' do
  # Core MVP pipeline: fetch -> parse -> publish current snapshot -> display.
  pod 'GRDB.swift', '6.24.1'
  pod 'Alamofire', '5.11.2'
  pod 'Nuke', '10.7.1'
  pod 'NukeUI', '0.8.0'
  pod 'SwiftSoup', '2.11.3'

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
      # TEST BrowseCraft archives with the Debug configuration. Dynamic pod
      # frameworks still need standalone dSYMs when that archive is uploaded.
      config.build_settings['DEBUG_INFORMATION_FORMAT'] = 'dwarf-with-dsym'
    end
  end

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
    cleaned = content.gsub(
      'LIBRARY_SEARCH_PATHS = $(inherited) "${TOOLCHAIN_DIR}/usr/lib/swift/${PLATFORM_NAME}" /usr/lib/swift',
      'LIBRARY_SEARCH_PATHS = $(inherited)'
    )
    File.write(xcconfig, cleaned) if cleaned != content
  end
end
