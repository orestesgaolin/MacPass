#import <Foundation/Foundation.h>

#import "MPAutoFillKeychainStore.h"

@class MPAutoFillVaultIndex;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT const NSUInteger MPAutoFillMaximumEncryptedSecretsBytes;
FOUNDATION_EXPORT const NSUInteger MPAutoFillMaximumRegistryBytes;

@interface MPAutoFillGeneration : NSObject
@property(nonatomic, readonly, copy) NSString *publicationIdentifier;
@property(nonatomic, readonly, copy) NSString *generationIdentifier;
@property(nonatomic, readonly, strong) MPAutoFillVaultIndex *index;
@property(nonatomic, readonly, copy) NSData *indexData;
@property(nonatomic, readonly, copy) NSData *indexDigest;
@property(nonatomic, readonly, copy) NSData *encryptedSecrets;
@end

@interface MPAutoFillGenerationStore : NSObject

- (nullable instancetype)initWithRootURL:(NSURL *)rootURL
                  currentGenerationStore:(id<MPAutoFillCurrentGenerationStore>)currentGenerationStore
                                   error:(NSError **)error NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

+ (nullable NSURL *)appGroupRootURLWithFileManager:(NSFileManager *)fileManager error:(NSError **)error;
+ (nullable NSData *)registryDataAtRootURL:(NSURL *)rootURL error:(NSError **)error;

- (BOOL)publishIndexData:(NSData *)indexData
          validatedIndex:(MPAutoFillVaultIndex *)index
        encryptedSecrets:(NSData *)encryptedSecrets
                   error:(NSError **)error;
- (nullable MPAutoFillGeneration *)currentGenerationForPublicationIdentifier:(NSString *)publicationIdentifier
                                                                         error:(NSError **)error;
- (nullable NSArray<NSString *> *)publicationIdentifiersWithError:(NSError **)error;
- (BOOL)removeOrphanedGenerationsForPublicationIdentifier:(NSString *)publicationIdentifier
                                     retainingGenerations:(NSSet<NSString *> *)retainedGenerationIdentifiers
                                                     limit:(NSUInteger)limit
                                                     error:(NSError **)error;
- (BOOL)removePublicationDataForPublicationIdentifier:(NSString *)publicationIdentifier error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
