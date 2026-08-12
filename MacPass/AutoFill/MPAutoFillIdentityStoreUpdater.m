#import "MPAutoFillIdentityStoreUpdater.h"

#import <AuthenticationServices/AuthenticationServices.h>
#import <Security/SecTask.h>

#import "MPAutoFillConstants.h"
#import "MPAutoFillCredentialIdentifier.h"
#import "MPAutoFillErrors.h"
#import "MPAutoFillGenerationStore.h"
#import "MPAutoFillKeychainStore.h"
#import "MPAutoFillPublicationRegistry.h"
#import "MPAutoFillVaultIndex.h"

static const NSUInteger MPAutoFillIdentityMaximumAttempts = 3;

API_AVAILABLE(macos(11.0))
@interface MPAutoFillSystemIdentityStore : NSObject <MPAutoFillIdentityStore>
@end

@implementation MPAutoFillSystemIdentityStore
- (void)getStateWithCompletion:(void (^)(BOOL, BOOL))completion {
  if (@available(macOS 11.0, *)) {
    [ASCredentialIdentityStore.sharedStore getCredentialIdentityStoreStateWithCompletion:^(ASCredentialIdentityStoreState *state) {
      completion(state.enabled, state.supportsIncrementalUpdates);
    }];
  } else {
    completion(NO, NO);
  }
}
- (void)replaceIdentities:(NSArray *)identities completion:(void (^)(BOOL, NSError *))completion {
  if (@available(macOS 11.0, *)) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [ASCredentialIdentityStore.sharedStore replaceCredentialIdentitiesWithIdentities:identities completion:completion];
#pragma clang diagnostic pop
  } else {
    completion(NO, nil);
  }
}
@end

@interface MPAutoFillIdentityStoreUpdater ()
@property(nonatomic, strong) MPAutoFillGenerationStore *generationStore;
@property(nonatomic, strong) id<MPAutoFillIdentityStore> identityStore;
@property(nonatomic, copy) NSArray<NSString *> *(^publicationIdentifiersBlock)(void);
@property(nonatomic) NSTimeInterval retryDelay;
@property(nonatomic, strong) dispatch_queue_t queue;
@property(nonatomic) NSUInteger requestedRevision;
@property(nonatomic, copy) void (^synchronizationCompletion)(NSError *error);
@property(atomic, readwrite) MPAutoFillIdentitySyncState state;
@property(atomic, readwrite) NSUInteger lastIdentityCount;
@property(atomic, readwrite) NSUInteger lastAttemptCount;
@property(atomic, readwrite) NSError *lastError;
@end

@implementation MPAutoFillIdentityStoreUpdater

+ (instancetype)sharedUpdater {
  if (@available(macOS 11.0, *)) {
    static MPAutoFillIdentityStoreUpdater *updater;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      SecTaskRef task = SecTaskCreateFromSelf(NULL);
      NSString *applicationIdentifier = task ? CFBridgingRelease(SecTaskCopyValueForEntitlement(task,
          CFSTR("com.apple.application-identifier"), NULL)) : nil;
      if (task) CFRelease(task);
      NSRange range = [applicationIdentifier rangeOfString:NSBundle.mainBundle.bundleIdentifier options:NSBackwardsSearch];
      NSString *prefix = range.location != NSNotFound ? [applicationIdentifier substringToIndex:range.location] : nil;
      if (!prefix) return;
      MPAutoFillKeychainStore *keychain = [[MPAutoFillKeychainStore alloc]
          initWithAccessGroup:[prefix stringByAppendingString:MPAutoFillSharedKeychainAccessGroupSuffix]];
      NSURL *rootURL = [MPAutoFillGenerationStore appGroupRootURLWithFileManager:NSFileManager.defaultManager error:NULL];
      MPAutoFillGenerationStore *store = rootURL ? [[MPAutoFillGenerationStore alloc]
          initWithRootURL:rootURL currentGenerationStore:keychain error:NULL] : nil;
      if (store) updater = [[self alloc] initWithGenerationStore:store identityStore:[[MPAutoFillSystemIdentityStore alloc] init]
          publicationIdentifiersBlock:^NSArray *{ return MPAutoFillPublicationRegistry.sharedRegistry.publicationIdentifiers; }
          retryDelay:0.25];
    });
    return updater;
  }
  return nil;
}

- (instancetype)initWithGenerationStore:(MPAutoFillGenerationStore *)generationStore
                           identityStore:(id<MPAutoFillIdentityStore>)identityStore
            publicationIdentifiersBlock:(NSArray<NSString *> *(^)(void))publicationIdentifiersBlock
                              retryDelay:(NSTimeInterval)retryDelay {
  self = [super init];
  if (self) {
    _generationStore = generationStore;
    _identityStore = identityStore;
    _publicationIdentifiersBlock = [publicationIdentifiersBlock copy];
    _retryDelay = retryDelay;
    _queue = dispatch_queue_create("dev.roszkowski.macpass.autofill-identities", DISPATCH_QUEUE_SERIAL);
  }
  return self;
}

- (void)synchronize {
  [self synchronizeWithCompletion:nil];
}

- (void)synchronizeWithCompletion:(void (^)(NSError *))completion {
  dispatch_async(self.queue, ^{
    NSUInteger revision = ++self.requestedRevision;
    if (self.synchronizationCompletion) {
      void (^superseded)(NSError *) = self.synchronizationCompletion;
      NSError *error = MPAutoFillError(MPAutoFillErrorStorageUnavailable,
          @"Identity synchronization was superseded.", nil);
      dispatch_async(dispatch_get_main_queue(), ^{ superseded(error); });
    }
    self.synchronizationCompletion = completion;
    self.state = MPAutoFillIdentitySyncStateSynchronizing;
    self.lastError = nil;
    [self synchronizeRevision:revision attempt:1];
  });
}

- (void)finishRevision:(NSUInteger)revision error:(NSError *)error {
  if (revision != self.requestedRevision) return;
  void (^completion)(NSError *) = self.synchronizationCompletion;
  self.synchronizationCompletion = nil;
  if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
}

- (NSArray *)identitiesWithError:(NSError **)error {
  NSMutableArray *identities = [NSMutableArray array];
  for (NSString *publicationIdentifier in self.publicationIdentifiersBlock()) {
    NSError *generationError = nil;
    MPAutoFillGeneration *generation = [self.generationStore currentGenerationForPublicationIdentifier:publicationIdentifier
                                                                                                 error:&generationError];
    if (!generation) {
      if ([generationError.domain isEqualToString:MPAutoFillErrorDomain] &&
          generationError.code == MPAutoFillErrorItemNotFound) continue;
      if (generationError && error) *error = generationError;
      return nil;
    }
    for (MPAutoFillVaultIndexRecord *record in generation.index.records) {
      MPAutoFillCredentialIdentifier *identifier = [MPAutoFillCredentialIdentifier
          identifierWithPublicationIdentifier:publicationIdentifier entryIdentifier:record.entryIdentifier error:error];
      if (!identifier) return nil;
      for (NSString *serviceString in record.serviceIdentifiers) {
        ASCredentialServiceIdentifier *service = [[ASCredentialServiceIdentifier alloc]
            initWithIdentifier:serviceString type:ASCredentialServiceIdentifierTypeURL];
        [identities addObject:[[ASPasswordCredentialIdentity alloc] initWithServiceIdentifier:service
            user:record.username recordIdentifier:identifier.recordIdentifier]];
      }
    }
  }
  return identities;
}

- (void)synchronizeRevision:(NSUInteger)revision attempt:(NSUInteger)attempt {
  [self.identityStore getStateWithCompletion:^(BOOL enabled, BOOL supportsIncrementalUpdates) {
    dispatch_async(self.queue, ^{
      if (revision != self.requestedRevision) return;
      self.lastAttemptCount = attempt;
      if (!enabled) {
        self.state = MPAutoFillIdentitySyncStateStoreDisabled;
        [self finishRevision:revision error:nil];
        return;
      }
      NSError *assemblyError = nil;
      NSArray *identities = [self identitiesWithError:&assemblyError];
      if (!identities) {
        self.lastError = assemblyError;
        self.state = MPAutoFillIdentitySyncStateFailed;
        [self finishRevision:revision error:assemblyError];
        return;
      }
      [self.identityStore replaceIdentities:identities completion:^(BOOL success, NSError *storeError) {
        dispatch_async(self.queue, ^{
          if (revision != self.requestedRevision) return;
          BOOL busy = [storeError.domain isEqualToString:ASCredentialIdentityStoreErrorDomain] &&
              storeError.code == ASCredentialIdentityStoreErrorCodeStoreBusy;
          if (!success && busy && attempt < MPAutoFillIdentityMaximumAttempts) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.retryDelay * NSEC_PER_SEC)), self.queue, ^{
              [self synchronizeRevision:revision attempt:attempt + 1];
            });
            return;
          }
          if (!success && [storeError.domain isEqualToString:ASCredentialIdentityStoreErrorDomain] &&
              storeError.code == ASCredentialIdentityStoreErrorCodeStoreDisabled) {
            self.state = MPAutoFillIdentitySyncStateStoreDisabled;
            self.lastError = nil;
            [self finishRevision:revision error:nil];
            return;
          }
          self.lastIdentityCount = success ? identities.count : 0;
          self.lastError = success ? nil : storeError;
          self.state = success ? MPAutoFillIdentitySyncStateSucceeded : MPAutoFillIdentitySyncStateFailed;
          [self finishRevision:revision error:success ? nil : storeError];
        });
      }];
    });
  }];
}

@end
