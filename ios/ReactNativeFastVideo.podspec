require 'json'

package = JSON.parse(File.read(File.join(__dir__, '..', 'package.json')))

Pod::Spec.new do |s|
  s.name           = 'ReactNativeFastVideo'
  s.version        = package['version']
  s.summary        = package['description']
  s.description    = package['description']
  s.license        = package['license']
  s.author         = package['author']
  s.homepage       = package['homepage']
  s.source         = { git: package['repository']['url'], tag: s.version.to_s }
  s.platforms      = { ios: '15.1', tvos: '15.1' }
  s.swift_version  = '5.9'
  s.static_framework = true

  s.dependency 'ExpoModulesCore'

  s.source_files = [
    'ios/**/*.{h,m,mm,swift}',
    'cpp/include/**/*.{h,hpp}',
    'cpp/src/**/*.{cpp}'
  ]
  s.exclude_files = 'cpp/tests/**/*'
  s.public_header_files = 'ios/RNFVFastCoreBridge.h'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++20',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/cpp/include"'
  }
end
