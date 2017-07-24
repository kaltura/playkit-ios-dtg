Pod::Spec.new do |s|
  
  s.name             = 'DownloadToGo'
  s.version          = '3.0.0.rc4'
  s.summary          = 'DownloadToGo -- download manager for HLS'
  s.homepage         = 'https://github.com/kaltura/DownloadToGo'
  s.license          = { :type => 'AGPLv3', :file => 'LICENSE' }
  s.author           = { 'Kaltura' => 'community@kaltura.com' }
  s.source           = { :git => 'https://github.com/kaltura/DownloadToGo.git', :tag => s.version.to_s }

  s.ios.deployment_target = '9.0'

  s.source_files = 'Sources/**/*'
  
  s.dependency 'M3U8Kit', '0.2.1'
  s.dependency 'GCDWebServer', '~> 3.3.3'
  s.dependency 'RealmSwift', '2.8.3'
  s.dependency 'XCGLogger', '5.0.1'

end
