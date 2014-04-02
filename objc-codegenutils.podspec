#
#  Be sure to run `pod spec lint objc-codegenutils.podspec' to ensure this is a
#  valid spec and to remove all comments including this before submitting the spec.
#
#  To learn more about Podspec attributes see http://docs.cocoapods.org/specification.html
#  To see working Podspecs in the CocoaPods repo see https://github.com/CocoaPods/Specs/
#

Pod::Spec.new do |s|

  s.name         = "objc-codegenutils"
  s.version      = "0.0.1"
  s.summary      = "A short description of objc-codegenutils."

  s.osx.deployment_target = '10.9'

  s.source       = { :git => "https://github.com/rocket0423/objc-codegenutils.git" }

  s.source_files  = 'colordump/*.{h,m}', 'assetgen/*.{h,m}', 'customfontlist/*.{h,m}', 'identifierconstants/*.{h,m}', 'Shared/*.{h,m}'

  s.preserve_paths = 'codegenutils.xcodeproj'

end
