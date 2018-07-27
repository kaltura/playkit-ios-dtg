Pod::Spec.new do |s|
  s.name             = 'DownloadToGo'
  s.version          = '3.4.0-dev'
  s.summary          = 'DownloadToGo -- download manager for HLS'
  s.homepage         = 'https://github.com/kaltura/playkit-ios-dtg'
  s.license          = { :type => 'AGPLv3', :file => 'LICENSE' }
  s.author           = { 'Kaltura' => 'community@kaltura.com' }
  s.source           = { :git => 'https://github.com/kaltura/playkit-ios-dtg.git', :tag => s.version.to_s }

  s.ios.deployment_target = '8.0'

  s.source_files = 'Sources/**/*'

  s.dependency 'M3U8Kit', '0.2.3'
  s.dependency 'GCDWebServer', '~> 3.4.2'
  s.dependency 'RealmSwift', '~> 3.7.5'
  s.dependency 'XCGLogger', '~> 6.0.1'
  s.dependency 'PlayKitUtils', '~> 0.1.4'
end
