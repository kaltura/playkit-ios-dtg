suffix = '.0000'   # Dev mode
# suffix = ''       # Release

Pod::Spec.new do |s|
  s.name             = 'DownloadToGo'
  s.version          = '3.12.1' + suffix
  s.summary          = 'DownloadToGo -- download manager for HLS'
  s.homepage         = 'https://github.com/kaltura/playkit-ios-dtg'
  s.license          = { :type => 'AGPLv3', :file => 'LICENSE' }
  s.author           = { 'Kaltura' => 'community@kaltura.com' }
  s.source           = { :git => 'https://github.com/kaltura/playkit-ios-dtg.git', :tag => s.version.to_s }
  s.swift_version    = '5.0'

  s.ios.deployment_target = '10.0'

  s.source_files = 'Sources/**/*'

  s.dependency 'M3U8Kit', '1.0.0'
  s.dependency 'GCDWebServer', '~> 3.5.4'
  s.dependency 'RealmSwift', '~> 10.1.0'
  s.dependency 'XCGLogger', '~> 7.0.0'
  s.dependency 'PlayKitUtils', '~> 0.5'
end
