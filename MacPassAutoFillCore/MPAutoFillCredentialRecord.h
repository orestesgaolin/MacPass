#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT const NSUInteger MPAutoFillMaximumTitleBytes;
FOUNDATION_EXPORT const NSUInteger MPAutoFillMaximumUsernameBytes;
FOUNDATION_EXPORT const NSUInteger MPAutoFillMaximumPasswordBytes;
FOUNDATION_EXPORT const NSUInteger MPAutoFillMaximumServiceIdentifierBytes;
FOUNDATION_EXPORT const NSUInteger MPAutoFillMaximumServicesPerRecord;

@interface MPAutoFillCredentialRecord : NSObject

@property(nonatomic, readonly, copy) NSString *entryIdentifier;
@property(nonatomic, readonly, copy) NSString *title;
@property(nonatomic, readonly, copy) NSString *username;
@property(nonatomic, readonly, copy) NSString *password;
@property(nonatomic, readonly, copy) NSArray<NSString *> *serviceIdentifiers;
@property(nonatomic, readonly) int64_t modificationTime;
@property(nonatomic, readonly) int64_t rank;

- (nullable instancetype)initWithEntryIdentifier:(NSString *)entryIdentifier
                                            title:(NSString *)title
                                         username:(NSString *)username
                                         password:(NSString *)password
                               serviceIdentifiers:(NSArray<NSString *> *)serviceIdentifiers
                                 modificationTime:(int64_t)modificationTime
                                             rank:(int64_t)rank
                                            error:(NSError **)error NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (NSDictionary<NSString *, id> *)propertyListRepresentation;
+ (nullable instancetype)recordWithPropertyList:(id)propertyList error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
