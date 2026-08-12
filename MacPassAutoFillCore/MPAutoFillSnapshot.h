#import <Foundation/Foundation.h>

@class MPAutoFillCredentialRecord;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT const NSInteger MPAutoFillSnapshotSchemaVersion;
FOUNDATION_EXPORT const NSUInteger MPAutoFillMaximumSnapshotBytes;
FOUNDATION_EXPORT const NSUInteger MPAutoFillMaximumRecordCount;

@interface MPAutoFillSnapshot : NSObject

@property(nonatomic, readonly) NSInteger schemaVersion;
@property(nonatomic, readonly, copy) NSString *publicationIdentifier;
@property(nonatomic, readonly, copy) NSString *generationIdentifier;
@property(nonatomic, readonly, copy) NSData *indexDigest;
@property(nonatomic, readonly, copy) NSArray<MPAutoFillCredentialRecord *> *records;

- (nullable instancetype)initWithPublicationIdentifier:(NSString *)publicationIdentifier
                                   generationIdentifier:(NSString *)generationIdentifier
                                            indexDigest:(NSData *)indexDigest
                                                records:(NSArray<MPAutoFillCredentialRecord *> *)records
                                                  error:(NSError **)error NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (nullable NSData *)serializedDataWithError:(NSError **)error;
+ (nullable instancetype)snapshotWithSerializedData:(NSData *)data
                      expectedPublicationIdentifier:(NSString *)publicationIdentifier
                       expectedGenerationIdentifier:(NSString *)generationIdentifier
                                expectedIndexDigest:(NSData *)indexDigest
                                              error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
