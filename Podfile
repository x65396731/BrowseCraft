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
    inherit! :search_paths
  end
end

post_install do |installer|
  # The app supports iOS 17 and above. Some pods declare older deployment
  # targets, so we lift generated Pod targets to the app's minimum version.
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
      config.build_settings['LIBRARY_SEARCH_PATHS'] = ['$(inherited)']
    end
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
