#import "LadybirdPlugin.h"
#if __has_include(<ladybird/ladybird-Swift.h>)
#import <ladybird/ladybird-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-and-objective-c-in-the-same-project/39292
#import "ladybird-Swift.h"
#endif

@implementation LadybirdPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [LadybirdPluginSwift registerWithRegistrar:registrar];
}
@end
