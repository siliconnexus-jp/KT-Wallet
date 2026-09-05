Pod::Spec.new do |s|
  s.name = 'native_wallet_tabs'
  s.version = '0.2.0'
  s.summary = 'Locally maintained UIKit tab bar bridge for KT Wallet.'
  s.description = 'Native UITabBarController with synchronized Flutter state and scoped lifecycle.'
  s.homepage = 'https://github.com/siliconnexus-jp/KT-Wallet'
  s.license = { :file => '../LICENSE' }
  s.author = { 'SiliconNexus' => 'https://github.com/siliconnexus-jp' }
  s.source = { :path => '.' }
  s.source_files = 'native_wallet_tabs/Sources/native_wallet_tabs/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.swift_version = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
end
