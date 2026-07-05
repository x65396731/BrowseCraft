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
    end
  end
end
