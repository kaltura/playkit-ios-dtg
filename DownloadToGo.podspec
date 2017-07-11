Pod::Spec.new do |s|
  s.name             = 'DownloadToGo'
  s.version          = '0.1.0'
  s.summary          = 'A short description of DownloadToGo.'
  s.homepage         = 'https://github.com/noamtamim/DownloadToGo'
  s.license          = { :type => 'AGPLv3', :file => 'LICENSE' }
  s.author           = { 'Kaltura' => 'community@kaltura.com' }
  s.source           = { :git => 'https://github.com/kaltura/DownloadToGo.git', :tag => s.version.to_s }

  s.ios.deployment_target = '9.0'

  s.source_files = 'Sources/**/*'
  
  s.dependency 'M3U8Kit', '~> 0.2'
  s.dependency 'GCDWebServer', '~> 3.3.3'
end
