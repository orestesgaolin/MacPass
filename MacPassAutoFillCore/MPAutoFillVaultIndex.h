#import <Foundation/Foundation.h>

@class MPAutoFillCredentialRecord;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT const NSInteger MPAutoFillVaultIndexSchemaVersion;
FOUNDATION_EXPORT const NSUInteger MPAutoFillMaximumVaultIndexBytes;

@interface MPAutoFillVaultIndexRecord : NSObject

@property(nonatomic, readonly, copy) NSString *entryIdentifier;
@property(nonatomic, readonly, copy) NSString *title;
@property(nonatomic, readonly, copy) NSString *username;
@property(nonatomic, readonly, copy) NSArray<NSString *> *serviceIdentifiers;
@property(nonatomic, readonly) int64_t modificationTime;
@property(nonatomic, readonly) int64_t rank;

+ (instancetype)recordWithCredentialRecord:(MPAutoFillCredentialRecord *)record;

@end

@interface MPAutoFillVaultIndex : NSObject

@property(nonatomic, readonly) NSInteger schemaVersion;
@property(nonatomic, readonly, copy) NSString *publicationIdentifier;
@property(nonatomic, readonly, copy) NSString *generationIdentifier;
@property(nonatomic, readonly, copy) NSArray<MPAutoFillVaultIndexRecord *> *records;

- (nullable instancetype)initWithPublicationIdentifier:(NSString *)publicationIdentifier
                                  generationIdentifier:(NSString *)generationIdentifier
                                               records:(NSArray<MPAutoFillVaultIndexRecord *> *)records
                                                 error:(NSError **)error NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (nullable NSData *)serializedDataWithError:(NSError **)error;
+ (nullable instancetype)indexWithSerializedData:(NSData *)data
                   expectedPublicationIdentifier:(NSString *)publicationIdentifier
                    expectedGenerationIdentifier:(NSString *)generationIdentifier
                                           error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
