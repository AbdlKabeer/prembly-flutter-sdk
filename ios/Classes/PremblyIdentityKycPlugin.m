#import "PremblyIdentityKycPlugin.h"

#import "TMDeviceIdStore.h"
#import "TMSignalCollector.h"

static NSString *const kChannelName = @"com.prembly.identity_kyc/device";

static NSString *JSONString(id object) {
  NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
  return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{}";
}

@implementation PremblyIdentityKycPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FlutterMethodChannel *channel =
      [FlutterMethodChannel methodChannelWithName:kChannelName
                                  binaryMessenger:[registrar messenger]];
  PremblyIdentityKycPlugin *instance = [[PremblyIdentityKycPlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  // Off the main thread: the checks touch the file system. The collector hops to the main thread
  // itself for the few UIKit and CoreLocation reads, so this must not run on it.
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    id value = nil;
    @try {
      if ([call.method isEqualToString:@"getAppInfo"]) {
        value = JSONString([TMSignalCollector appInfo]);
      } else if ([call.method isEqualToString:@"getDeviceId"]) {
        value = [TMDeviceIdStore deviceId];
      } else if ([call.method isEqualToString:@"collectSignals"]) {
        BOOL includeLocation = [call.arguments[@"includeLocation"] boolValue];
        value = JSONString([TMSignalCollector collectIncludingLocation:includeLocation]);
      } else if ([call.method isEqualToString:@"checkScreenCapture"]) {
        value = JSONString([TMSignalCollector screenCapture]);
      } else {
        dispatch_async(dispatch_get_main_queue(), ^{ result(FlutterMethodNotImplemented); });
        return;
      }
    } @catch (NSException *exception) {
      NSString *reason = exception.reason ?: @"native read failed";
      dispatch_async(dispatch_get_main_queue(), ^{
        result([FlutterError errorWithCode:@"native_failed" message:reason details:nil]);
      });
      return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{ result(value); });
  });
}

@end
