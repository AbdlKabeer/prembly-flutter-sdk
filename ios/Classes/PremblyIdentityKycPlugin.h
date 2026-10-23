#import <Flutter/Flutter.h>

/// The native side only reads the device. Every method answers with JSON text, which keeps the
/// channel contract small and identical on Android and iOS. It never asks for a permission.
@interface PremblyIdentityKycPlugin : NSObject <FlutterPlugin>
@end
