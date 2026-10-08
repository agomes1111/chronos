#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint chronify.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'chronos'
  s.version          = '1.0.0'
  s.summary          = 'Native system uptime driver and tamper guard for Chronify.'
  s.description      = <<-DESC
A Flutter plugin providing server clock synchronization, monotonic uptime tracking, and tamper detection.
                       DESC
  s.homepage         = 'https://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Imply' => 'agomes@imply.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '12.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version    = '5.0'
end