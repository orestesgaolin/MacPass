//
//  MPDiaAddressBarResolver.h
//  MacPass
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface MPDiaAddressBarResolver : NSObject

+ (nullable NSString *)addressBarValueForRunningApplication:(NSRunningApplication *)runningApplication;
+ (nullable NSString *)normalizedHostForAddressBarValue:(NSString *)addressBarValue;
+ (nullable NSString *)normalizedHostForEntryURL:(NSString *)entryURL;

/* Exposed to keep accessibility element recognition independently testable. */
+ (nullable NSString *)addressBarValueForAccessibilityAttributes:(NSDictionary<NSString *, id> *)attributes
                                                    insideToolbar:(BOOL)insideToolbar;

@end

NS_ASSUME_NONNULL_END
