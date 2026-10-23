#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint prembly_identity_kyc.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'prembly_identity_kyc'
  s.version          = '0.1.1'
  s.summary          = 'Prembly Identity KYC and Transaction Monitoring device signals for Flutter.'
  s.description      = <<-DESC
Reads the phone's real device ID and device signals for the Prembly Identity KYC widget and
Transaction Monitoring. Never asks for a permission.
                       DESC
  s.homepage         = 'https://github.com/AbdlKabeer/prembly-flutter-sdk'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Prembly' => 'olanrewaju@prembly.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.frameworks = 'UIKit', 'Security', 'SystemConfiguration', 'CFNetwork', 'LocalAuthentication', 'CoreLocation'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
end
