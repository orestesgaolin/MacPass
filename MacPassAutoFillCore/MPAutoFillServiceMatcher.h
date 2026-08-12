#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, MPAutoFillServiceIdentifierType) {
  MPAutoFillServiceIdentifierTypeDomain = 0,
  MPAutoFillServiceIdentifierTypeURL = 1,
};

@interface MPAutoFillServiceMatcher : NSObject

+ (BOOL)credentialServiceIdentifier:(NSString *)credentialServiceIdentifier
    matchesRequestedServiceIdentifier:(NSString *)requestedServiceIdentifier
                                 type:(MPAutoFillServiceIdentifierType)type;
+ (nullable NSString *)normalizedCredentialServiceIdentifier:(NSString *)serviceIdentifier;

@end

NS_ASSUME_NONNULL_END
