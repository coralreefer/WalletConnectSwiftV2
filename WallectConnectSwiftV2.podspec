#
#  Be sure to run `pod spec lint WalletConnectSwiftV2.podspec' to ensure this is a
#  valid spec and to remove all comments including this before submitting the spec.
#
#  To learn more about Podspec attributes see https://guides.cocoapods.org/syntax/podspec.html
#  To see working Podspecs in the CocoaPods repo see https://github.com/CocoaPods/Specs/
#

Pod::Spec.new do |spec|

  spec.name         = "WalletConnectSwiftV2"
  spec.version      = "1.0.1"
  spec.summary      = "A delightful way to integrate WalletConnect into your app."
  spec.description  = <<-DESC
  WalletConnect protocol implementation for enabling communication between dapps and
  wallets. This library provides both client and server parts so that you can integrate
  it in your wallet, or in your dapp - whatever you are working on.
                   DESC
  spec.homepage     = "https://github.com/coralreefer/WalletConnectSwiftV2"
  spec.license      = { :type => "MIT", :file => "LICENSE" }
  spec.author             = { "Example" => "example@gmail.com" }
  spec.platform     = :ios, "13.0"
  spec.swift_version = "5.0"
  spec.source       = { :git => "https://github.com/coralreefer/WalletConnectSwiftV2.git", :tag => "#{spec.version}" }
  spec.default_subspec = "WalletConnectSign"
  spec.cocoapods_version = '>= 1.4.0'

  spec.subspec "WalletConnectSign" do |ss|
    ss.source_files = "Sources/WalletConnectSign/**/*.swift"
    ss.dependency "WalletConnectSwiftV2/WalletConnectRelay"
    ss.dependency "WalletConnectSwiftV2/WalletConnectUtils"
    ss.dependency "WalletConnectSwiftV2/WalletConnectKMS"
  end
  
  spec.subspec "Chat" do |ss|
    ss.source_files = "Sources/Chat/**/*.swift"
    ss.dependency "WalletConnectSwiftV2/WalletConnectRelay"
    ss.dependency "WalletConnectSwiftV2/WalletConnectUtils"
    ss.dependency "WalletConnectSwiftV2/WalletConnectKMS"
  end
  
  spec.subspec "WalletConnectRelay" do |ss|
    ss.source_files = "Sources/WalletConnectRelay/**/*.swift"
    ss.dependency "WalletConnectSwiftV2/WalletConnectUtils"
    ss.dependency "WalletConnectSwiftV2/WalletConnectKMS"
  end

  spec.subspec "WalletConnectKMS" do |ss|
    ss.source_files = "Sources/WalletConnectKMS/**/*.swift"
    ss.dependency "WalletConnectSwiftV2/WalletConnectUtils"
  end

  spec.subspec "WalletConnectUtils" do |ss|
    ss.source_files = "Sources/WalletConnectUtils/**/*.swift"
    ss.dependency "WalletConnectSwiftV2/Commons"
  end
  
  spec.subspec "JSONRPC" do |ss|
    ss.source_files = "Sources/JSONRPC/**/*.swift"
    ss.dependency "WalletConnectSwiftV2/Commons"
  end
  
  spec.subspec "Commons" do |ss|
    ss.source_files = "Sources/Commons/**/*.swift"
  end
  
end
