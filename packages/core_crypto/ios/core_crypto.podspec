#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint core_crypto.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'core_crypto'
  s.version          = '0.0.1'
  s.summary          = 'Native key custody and Wallet Core signing for KT Wallet.'
  s.description      = <<-DESC
Device-bound wallet storage, public derivation, authenticated transaction
signing, and encrypted backup support for the KT Wallet Flutter applications.
                       DESC
  s.homepage         = 'https://github.com/siliconnexus-jp/KT-Wallet'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'SiliconNexus' => 'https://github.com/siliconnexus-jp' }
  s.source           = { :path => '.' }
  # Keep the privacy manifest out of Compile Sources. It is packaged as a
  # resource bundle below; a broad `/**/*` glob makes Xcode emit "no rule to
  # process PrivacyInfo.xcprivacy" and can silently omit the SDK declaration.
  s.source_files = 'core_crypto/Sources/core_crypto/**/*.swift'
  s.dependency 'Flutter'
  # Trust Wallet Core: audited C++ crypto (mnemonic, derivation, signing).
  s.dependency 'TrustWalletCore', '4.7.0'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # AuthGate persists non-sensitive retry/lockout counters in app-scoped
  # UserDefaults, so this SDK declares the CA92.1 required-reason category in
  # its own bundle instead of relying on the host application's declaration.
  s.resource_bundles = {
    'core_crypto_privacy' => ['core_crypto/Sources/core_crypto/PrivacyInfo.xcprivacy']
  }
end
