#import <Foundation/Foundation.h>

@class MPAutoFillGenerationStore;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, MPAutoFillIdentitySyncState) {
  MPAutoFillIdentitySyncStateIdle = 0,
  MPAutoFillIdentitySyncStateSynchronizing,
  MPAutoFillIdentitySyncStateSucceeded,
  MPAutoFillIdentitySyncStateStoreDisabled,
  MPAutoFillIdentitySyncStateFailed,
};

@protocol MPAutoFillIdentityStore <NSObject>
- (void)getStateWithCompletion:(void (^)(BOOL enabled, BOOL supportsIncrementalUpdates))completion;
- (void)replaceIdentities:(NSArray *)identities completion:(void (^)(BOOL success, NSError * _Nullable error))completion;
@end

API_AVAILABLE(macos(11.0))
@interface MPAutoFillIdentityStoreUpdater : NSObject

@property(atomic, readonly) MPAutoFillIdentitySyncState state;
@property(atomic, readonly) NSUInteger lastIdentityCount;
@property(atomic, readonly) NSUInteger lastAttemptCount;
@property(atomic, readonly, nullable) NSError *lastError;

+ (nullable instancetype)sharedUpdater;
- (instancetype)initWithGenerationStore:(MPAutoFillGenerationStore *)generationStore
                           identityStore:(id<MPAutoFillIdentityStore>)identityStore
            publicationIdentifiersBlock:(NSArray<NSString *> *(^)(void))publicationIdentifiersBlock
                              retryDelay:(NSTimeInterval)retryDelay NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (void)synchronize;
- (void)synchronizeWithCompletion:(void (^ _Nullable)(NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
