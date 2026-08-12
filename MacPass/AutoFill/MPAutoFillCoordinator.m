#import "MPAutoFillCoordinator.h"

#import <CommonCrypto/CommonDigest.h>
#import <KeePassKit/KeePassKit.h>
#import <Security/SecTask.h>

#import "MPAutoFillConstants.h"
#import "MPAutoFillEnvelopeCrypto.h"
#import "MPAutoFillErrors.h"
#import "MPAutoFillGenerationStore.h"
#import "MPAutoFillKeychainStore.h"
#import "MPAutoFillIdentityStoreUpdater.h"
#import "MPAutoFillPublicationRegistry.h"
#import "MPAutoFillPublicationSequencer.h"
#import "MPAutoFillSnapshot.h"
#import "MPAutoFillSnapshotBuilder.h"
#import "MPAutoFillVaultIndex.h"

NSNotificationName const MPAutoFillPublicationDidFailNotification = @"MPAutoFillPublicationDidFailNotification";
NSNotificationName const MPAutoFillPublicationDidSucceedNotification = @"MPAutoFillPublicationDidSucceedNotification";
NSString *const MPAutoFillPublicationErrorKey = @"MPAutoFillPublicationErrorKey";
NSString *const MPAutoFillPublicationIdentifierKey = @"MPAutoFillPublicationIdentifierKey";

@interface MPAutoFillCoordinator ()
@property(nonatomic, strong) MPAutoFillGenerationStore *generationStore;
@property(nonatomic, strong) id keychainStore;
@property(nonatomic, strong) dispatch_queue_t publicationQueue;
@property(nonatomic, strong) MPAutoFillPublicationSequencer *sequencer;
@property(nonatomic, strong) id<MPAutoFillIdentitySynchronizing> identityStoreUpdater;
@property(nonatomic, strong) MPAutoFillPublicationRegistry *publicationRegistry;
@end

@implementation MPAutoFillCoordinator

+ (instancetype)sharedCoordinator {
  if (@available(macOS 11.0, *)) {
    static MPAutoFillCoordinator *coordinator;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      SecTaskRef task = SecTaskCreateFromSelf(NULL);
      NSString *applicationIdentifier = task ? CFBridgingRelease(SecTaskCopyValueForEntitlement(task,
          CFSTR("com.apple.application-identifier"), NULL)) : nil;
      if (task) CFRelease(task);
      NSRange bundleRange = [applicationIdentifier rangeOfString:NSBundle.mainBundle.bundleIdentifier options:NSBackwardsSearch];
      NSString *prefix = bundleRange.location != NSNotFound ? [applicationIdentifier substringToIndex:bundleRange.location] : nil;
      if (!prefix) return;
      MPAutoFillKeychainStore *keychain = [[MPAutoFillKeychainStore alloc]
          initWithAccessGroup:[prefix stringByAppendingString:MPAutoFillSharedKeychainAccessGroupSuffix]];
      NSError *error = nil;
      NSURL *rootURL = [MPAutoFillGenerationStore appGroupRootURLWithFileManager:NSFileManager.defaultManager error:&error];
      MPAutoFillGenerationStore *store = rootURL ? [[MPAutoFillGenerationStore alloc]
          initWithRootURL:rootURL currentGenerationStore:keychain error:&error] : nil;
      if (store) coordinator = [[self alloc] initWithGenerationStore:store keychainStore:keychain];
    });
    return coordinator;
  }
  return nil;
}

- (instancetype)initWithGenerationStore:(MPAutoFillGenerationStore *)generationStore
                           keychainStore:(id)keychainStore {
  id updater = nil;
  if (@available(macOS 11.0, *)) updater = MPAutoFillIdentityStoreUpdater.sharedUpdater;
  return [self initWithGenerationStore:generationStore keychainStore:keychainStore
                   identityStoreUpdater:updater publicationRegistry:MPAutoFillPublicationRegistry.sharedRegistry];
}

- (instancetype)initWithGenerationStore:(MPAutoFillGenerationStore *)generationStore
                           keychainStore:(id)keychainStore
                    identityStoreUpdater:(id<MPAutoFillIdentitySynchronizing>)identityStoreUpdater
                     publicationRegistry:(MPAutoFillPublicationRegistry *)publicationRegistry {
  self = [super init];
  if (self) {
    _generationStore = generationStore;
    _keychainStore = keychainStore;
    _publicationQueue = dispatch_queue_create("dev.roszkowski.macpass.autofill-publication", DISPATCH_QUEUE_SERIAL);
    _sequencer = [[MPAutoFillPublicationSequencer alloc] init];
    _identityStoreUpdater = identityStoreUpdater;
    _publicationRegistry = publicationRegistry;
  }
  return self;
}

- (uint64_t)beginSaveForPublicationIdentifier:(NSString *)publicationIdentifier {
  return [self.sequencer beginSaveForPublicationIdentifier:publicationIdentifier];
}

- (void)invalidatePublicationIdentifier:(NSString *)publicationIdentifier {
  [self.sequencer invalidatePublicationIdentifier:publicationIdentifier];
}

- (void)synchronizeIdentities {
  if (@available(macOS 11.0, *)) [self.identityStoreUpdater synchronize];
}

- (void)reconcilePublishedStateWithCompletion:(void (^)(NSError *))completion {
  if (!self.identityStoreUpdater) {
    if (completion) completion(MPAutoFillError(MPAutoFillErrorStorageUnavailable,
        @"The AutoFill identity store is unavailable.", nil));
    return;
  }
  [self.identityStoreUpdater synchronizeWithCompletion:^(NSError *synchronizationError) {
    dispatch_async(self.publicationQueue, ^{
      NSError *firstError = synchronizationError;
      for (NSString *publicationIdentifier in self.publicationRegistry.publicationIdentifiers) {
        NSError *validationError = nil;
        if (![self.generationStore currentGenerationForPublicationIdentifier:publicationIdentifier error:&validationError]) {
          if (validationError.code != MPAutoFillErrorItemNotFound && !firstError) firstError = validationError;
          continue;
        }
        NSError *cleanupError = nil;
        if (![self.generationStore removeOrphanedGenerationsForPublicationIdentifier:publicationIdentifier
            retainingGenerations:[NSSet set] limit:32 error:&cleanupError] && !firstError) firstError = cleanupError;
      }
      if (self.publicationRegistry.isAuthoritative) {
        NSError *enumerationError = nil;
        NSArray<NSString *> *storedPublications = [self.generationStore publicationIdentifiersWithError:&enumerationError];
        NSArray<NSString *> *keychainPublications = storedPublications ?
            [self.keychainStore publicationIdentifiersWithError:&enumerationError] : nil;
        if (!storedPublications || !keychainPublications) {
          if (!firstError) firstError = enumerationError;
        } else {
          NSSet<NSString *> *registered = [NSSet setWithArray:self.publicationRegistry.publicationIdentifiers];
          NSMutableSet<NSString *> *orphans = [NSMutableSet setWithArray:storedPublications];
          [orphans addObjectsFromArray:keychainPublications];
          [orphans minusSet:registered];
          NSUInteger attempted = 0;
          for (NSString *publicationIdentifier in [orphans.allObjects sortedArrayUsingSelector:@selector(compare:)]) {
            if (attempted >= 32) break;
            attempted++;
            NSError *cleanupError = nil;
            BOOL cleaned = [self.keychainStore deleteKeyPairForPublicationIdentifier:publicationIdentifier error:&cleanupError];
            if (cleaned) cleaned = [self.keychainStore
                deleteCurrentGenerationForPublicationIdentifier:publicationIdentifier error:&cleanupError];
            if (cleaned) cleaned = [self.generationStore
                removePublicationDataForPublicationIdentifier:publicationIdentifier error:&cleanupError];
            if (!cleaned && !firstError) firstError = cleanupError;
          }
        }
      }
      dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(firstError); });
    });
  }];
}

- (BOOL)preparePublicationIdentifier:(NSString *)publicationIdentifier error:(NSError **)error {
  return [self.keychainStore createKeyPairForPublicationIdentifier:publicationIdentifier error:error];
}

- (BOOL)preparePublicationIdentifier:(NSString *)publicationIdentifier
                    registrationBlock:(BOOL (^)(NSError **))registrationBlock
                                error:(NSError **)error {
  if (!registrationBlock) {
    if (error) *error = MPAutoFillError(MPAutoFillErrorInvalidArgument,
        @"The publication registration block is missing.", nil);
    return NO;
  }
  __block BOOL prepared = NO;
  __block NSError *transactionError = nil;
  dispatch_sync(self.publicationQueue, ^{
    prepared = [self preparePublicationIdentifier:publicationIdentifier error:&transactionError];
    if (prepared) prepared = registrationBlock(&transactionError);
    if (!prepared) {
      [self.keychainStore deleteKeyPairForPublicationIdentifier:publicationIdentifier error:NULL];
      [self.keychainStore deleteCurrentGenerationForPublicationIdentifier:publicationIdentifier error:NULL];
    }
  });
  if (!prepared && error) *error = transactionError;
  return prepared;
}

- (void)discardPublicationIdentifier:(NSString *)publicationIdentifier {
  [self invalidatePublicationIdentifier:publicationIdentifier];
  [self.keychainStore deleteKeyPairForPublicationIdentifier:publicationIdentifier error:NULL];
  [self.keychainStore deleteCurrentGenerationForPublicationIdentifier:publicationIdentifier error:NULL];
  [self synchronizeIdentities];
}

- (void)unpublishPublicationIdentifier:(NSString *)publicationIdentifier
                            completion:(void (^)(NSError *))completion {
  [self invalidatePublicationIdentifier:publicationIdentifier];
  NSError *error = nil;
  if (![self.keychainStore deleteKeyPairForPublicationIdentifier:publicationIdentifier error:&error] ||
      ![self.keychainStore deleteCurrentGenerationForPublicationIdentifier:publicationIdentifier error:&error]) {
    if (completion) completion(error);
    return;
  }
  if (@available(macOS 11.0, *)) {
    id<MPAutoFillIdentitySynchronizing> updater = self.identityStoreUpdater;
    if (!updater) {
      if (completion) completion(MPAutoFillError(MPAutoFillErrorStorageUnavailable,
          @"The AutoFill identity store is unavailable.", nil));
      return;
    }
    [updater synchronizeWithCompletion:^(NSError *synchronizationError) {
      if (synchronizationError) {
        if (completion) completion(synchronizationError);
        return;
      }
      dispatch_async(self.publicationQueue, ^{
        NSError *cleanupError = nil;
        BOOL removed = [self.generationStore removePublicationDataForPublicationIdentifier:publicationIdentifier
                                                                                     error:&cleanupError];
        if (removed) removed = [self.publicationRegistry
            removePublicationIdentifier:publicationIdentifier error:&cleanupError];
        dispatch_async(dispatch_get_main_queue(), ^{
          if (completion) completion(removed ? nil : cleanupError);
        });
      });
    }];
  } else if (completion) {
    completion(MPAutoFillError(MPAutoFillErrorStorageUnavailable, @"Password AutoFill requires macOS 11 or later.", nil));
  }
}

- (void)replacePublicationIdentifier:(NSString *)publicationIdentifier
                       withSavedData:(NSData *)savedData
                                 key:(KPKCompositeKey *)key
              expectedRootIdentifier:(NSString *)rootIdentifier
                          completion:(void (^)(BOOL publicationRetained))completion {
  NSError *error = nil;
  // Revoke usable secret material before removing the active pointer or attempting reconstruction.
  [self invalidatePublicationIdentifier:publicationIdentifier];
  BOOL revoked = [self.keychainStore deleteKeyPairForPublicationIdentifier:publicationIdentifier error:&error];
  if (revoked) revoked = [self.keychainStore deleteCurrentGenerationForPublicationIdentifier:publicationIdentifier error:&error];
  if (revoked) [self synchronizeIdentities];
  dispatch_async(self.publicationQueue, ^{
    NSError *replacementError = error;
    KPKTree *tree = revoked ? [[KPKTree alloc] initWithData:savedData key:key error:&replacementError] : nil;
    BOOL sameDatabase = revoked && [tree.root.uuid.UUIDString.lowercaseString isEqualToString:rootIdentifier];
    BOOL publicationRetained = sameDatabase && [self preparePublicationIdentifier:publicationIdentifier error:&replacementError];
    if (publicationRetained) {
      uint64_t token = [self beginSaveForPublicationIdentifier:publicationIdentifier];
      [self publishSavedData:savedData key:key publicationIdentifier:publicationIdentifier saveToken:token];
      dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(YES); });
      return;
    }
    [self unpublishPublicationIdentifier:publicationIdentifier completion:^(NSError *cleanupError) {
      NSError *reportedError = replacementError ?: cleanupError;
      if (completion) completion(NO);
      if (reportedError) {
        [NSNotificationCenter.defaultCenter postNotificationName:MPAutoFillPublicationDidFailNotification
            object:self userInfo:@{MPAutoFillPublicationErrorKey: reportedError}];
      }
    }];
  });
}

- (BOOL)isCurrentToken:(uint64_t)token publicationIdentifier:(NSString *)publicationIdentifier {
  return [self.sequencer performIfCurrentToken:token publicationIdentifier:publicationIdentifier
                                         action:^BOOL(NSError **error) { return YES; } error:NULL];
}

- (BOOL)registerSuccessfulSaveToken:(uint64_t)saveToken publicationIdentifier:(NSString *)publicationIdentifier {
  return [self.sequencer registerSuccessfulSaveToken:saveToken publicationIdentifier:publicationIdentifier];
}

- (BOOL)activateGenerationForPublicationIdentifier:(NSString *)publicationIdentifier
                                         saveToken:(uint64_t)saveToken
                                        activation:(BOOL (^)(NSError **error))activation
                                             error:(NSError **)error {
  return [self.sequencer performIfCurrentToken:saveToken publicationIdentifier:publicationIdentifier
                                         action:activation error:error];
}

- (void)publishSavedData:(NSData *)savedData
                     key:(KPKCompositeKey *)key
   publicationIdentifier:(NSString *)publicationIdentifier
               saveToken:(uint64_t)saveToken {
  if (![self registerSuccessfulSaveToken:saveToken publicationIdentifier:publicationIdentifier]) return;
  dispatch_async(self.publicationQueue, ^{
    if (![self isCurrentToken:saveToken publicationIdentifier:publicationIdentifier]) return;
    NSError *error = nil;
    KPKTree *tree = [[KPKTree alloc] initWithData:savedData key:key error:&error];
    MPAutoFillSnapshotBuildResult *result = tree ? [MPAutoFillSnapshotBuilder buildRecordsFromTree:tree atDate:NSDate.date] : nil;
    NSString *generationIdentifier = NSUUID.UUID.UUIDString.lowercaseString;
    NSMutableArray *indexRecords = [NSMutableArray arrayWithCapacity:result.records.count];
    for (id record in result.records) [indexRecords addObject:[MPAutoFillVaultIndexRecord recordWithCredentialRecord:record]];
    MPAutoFillVaultIndex *index = result ? [[MPAutoFillVaultIndex alloc]
        initWithPublicationIdentifier:publicationIdentifier generationIdentifier:generationIdentifier records:indexRecords error:&error] : nil;
    NSData *indexData = index ? [index serializedDataWithError:&error] : nil;
    uint8_t digestBytes[CC_SHA256_DIGEST_LENGTH];
    NSData *indexDigest = nil;
    if (indexData) {
      CC_SHA256(indexData.bytes, (CC_LONG)indexData.length, digestBytes);
      indexDigest = [NSData dataWithBytes:digestBytes length:sizeof(digestBytes)];
    }
    MPAutoFillSnapshot *snapshot = indexDigest ? [[MPAutoFillSnapshot alloc]
        initWithPublicationIdentifier:publicationIdentifier generationIdentifier:generationIdentifier
        indexDigest:indexDigest records:result.records error:&error] : nil;
    SecKeyRef publicKey = snapshot ? [self.keychainStore copyPublicKeyForPublicationIdentifier:publicationIdentifier error:&error] : nil;
    NSData *encrypted = publicKey ? [MPAutoFillEnvelopeCrypto encryptSnapshot:snapshot withPublicKey:publicKey error:&error] : nil;
    if (publicKey) CFRelease(publicKey);
    if (encrypted) {
      BOOL activated = [self activateGenerationForPublicationIdentifier:publicationIdentifier saveToken:saveToken
          activation:^BOOL(NSError **activationError) {
            return [self.generationStore publishIndexData:indexData validatedIndex:index
                                          encryptedSecrets:encrypted error:activationError];
          } error:&error];
      if (activated) {
        [self.publicationRegistry markPublicationIdentifierPublished:publicationIdentifier
                                                                                  atDate:NSDate.date error:NULL];
        [self synchronizeIdentities];
        dispatch_async(dispatch_get_main_queue(), ^{
          [NSNotificationCenter.defaultCenter postNotificationName:MPAutoFillPublicationDidSucceedNotification
              object:self userInfo:@{MPAutoFillPublicationIdentifierKey: publicationIdentifier}];
        });
      }
    }
    if (error && [self isCurrentToken:saveToken publicationIdentifier:publicationIdentifier]) {
      dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:MPAutoFillPublicationDidFailNotification
            object:self userInfo:@{MPAutoFillPublicationErrorKey: error}];
      });
    }
  });
}

@end
