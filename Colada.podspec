Pod::Spec.new do |s|
  s.name             = 'Colada'
  s.version          = '0.1.1'
  s.summary          = 'Attribution and lifecycle event tracking SDK for iOS.'
  s.description      = <<-DESC
    Colada is a lightweight iOS SDK for attribution resolution, deep link handling,
    and lifecycle event tracking. No IDFA, no ATT prompt, zero third-party dependencies.
  DESC
  s.homepage         = 'https://github.com/3laween/colada-sdk-ios'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { '3laween' => 'waleed@coladaapp.io' }
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.9'

  s.source           = {
    :http => 'https://github.com/3laween/colada-sdk-ios/releases/download/v0.1.1/Colada.xcframework.zip'
  }

  s.vendored_frameworks = 'Colada.xcframework'
end
