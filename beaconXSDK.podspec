Pod::Spec.new do |s|
  s.name         = "beaconXSDK"    #存储库名称
  s.version      = "0.0.1"      #版本号，与tag值一致
  s.summary      = "SDK For eddystone"  #简介
  s.description  = "SDK For eddystone"  #描述
  s.homepage     = "https://github.com/MokoBeaconX/mokoBeaconX_iOS"      #项目主页，不是git地址
  s.license      = { :type => "MIT", :file => "LICENSE" }   #开源协议
  s.author             = { "lovexiaoxia" => "aadyx2007@163.com" }  #作者
  s.platform     = :ios, "8.0"                 #支持的平台和版本号
  s.ios.deployment_target = "8.0"
  s.frameworks   = "UIKit", "Foundation" #支持的框架
  s.source       = { :git => "https://github.com/MokoBeaconX/mokoBeaconX_iOS.git ", :tag => "#{s.version}" }         #存储库的git地址，以及tag值
  s.requires_arc = true #是否支持ARC

  s.source_files = "beaconXSDK/*.{h,m}"

  #s.dependency "MQTTClient","~> 0.15.0"     #所依赖的第三方库，没有就不用写

end