#import <Foundation/Foundation.h>

@class KPKCompositeKey;
@class MPAutoFillGenerationStore;
@class MPAutoFillPublicationRegistry;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const MPAutoFillPublicationDidFailNotification;
FOUNDATION_EXPORT NSNotificationName const MPAutoFillPublicationDidSucceedNotification;
FOUNDATION_EXPORT NSString *const MPAutoFillPublicationErrorKey;
FOUNDATION_EXPORT NSString *const MPAutoFillPublicationIdentifierKey;

@protocol MPAutoFillIdentitySynchronizing <NSObject>
- (void)synchronize;
- (void)synchronizeWithCompletion:(void (^ _Nullable)(NSError * _Nullable error))completion;
@end

@interface MPAutoFillCoordinator : NSObject

+ (nullable instancetype)sharedCoordinator;

- (instancetype)initWithGenerationStore:(MPAutoFillGenerationStore *)generationStore
                           keychainStore:(id)keychainStore;
- (instancetype)initWithGenerationStore:(MPAutoFillGenerationStore *)generationStore
                           keychainStore:(id)keychainStore
                    identityStoreUpdater:(nullable id<MPAutoFillIdentitySynchronizing>)identityStoreUpdater
                     publicationRegistry:(MPAutoFillPublicationRegistry *)publicationRegistry NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (uint64_t)beginSaveForPublicationIdentifier:(NSString *)publicationIdentifier;
- (void)invalidatePublicationIdentifier:(NSString *)publicationIdentifier;
- (BOOL)preparePublicationIdentifier:(NSString *)publicationIdentifier error:(NSError **)error;
- (BOOL)preparePublicationIdentifier:(NSString *)publicationIdentifier
                    registrationBlock:(BOOL (^)(NSError **error))registrationBlock
                                error:(NSError **)error;
- (void)discardPublicationIdentifier:(NSString *)publicationIdentifier;
- (void)reconcilePublishedStateWithCompletion:(void (^ _Nullable)(NSError * _Nullable error))completion;
- (void)unpublishPublicationIdentifier:(NSString *)publicationIdentifier
                            completion:(void (^ _Nullable)(NSError * _Nullable error))completion;
- (void)replacePublicationIdentifier:(NSString *)publicationIdentifier
                       withSavedData:(NSData *)savedData
                                 key:(KPKCompositeKey *)key
              expectedRootIdentifier:(NSString *)rootIdentifier
                          completion:(void (^ _Nullable)(BOOL publicationRetained))completion;
- (void)publishSavedData:(NSData *)savedData
                     key:(KPKCompositeKey *)key
   publicationIdentifier:(NSString *)publicationIdentifier
               saveToken:(uint64_t)saveToken;

@end

NS_ASSUME_NONNULL_END
