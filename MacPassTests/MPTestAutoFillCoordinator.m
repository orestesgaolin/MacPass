#import <XCTest/XCTest.h>
#import <KeePassKit/KeePassKit.h>

#import "../MacPass/AutoFill/MPAutoFillPublicationSequencer.h"
#import "../MacPass/AutoFill/MPAutoFillPublicationRegistry.h"
#import "../MacPass/AutoFill/MPAutoFillSavePolicy.h"
#import "../MacPass/AutoFill/MPAutoFillCoordinator.h"
#import "MPAutoFillErrors.h"
#import "MPAutoFillGenerationStore.h"

@interface MPTestAutoFillCurrentStore : NSObject <MPAutoFillCurrentGenerationStore>
@end

@implementation MPTestAutoFillCurrentStore
- (NSString *)currentGenerationForPublicationIdentifier:(NSString *)publication error:(NSError **)error { return nil; }
- (BOOL)setCurrentGeneration:(NSString *)generation forPublicationIdentifier:(NSString *)publication error:(NSError **)error { return YES; }
- (BOOL)deleteCurrentGenerationForPublicationIdentifier:(NSString *)publication error:(NSError **)error { return YES; }
@end

@interface MPTestAutoFillReconciliationStore : MPAutoFillGenerationStore
@property(nonatomic, copy) NSDictionary<NSString *, NSNumber *> *publicationStates;
@property(nonatomic, strong) NSMutableArray<NSString *> *cleanedPublications;
@property(nonatomic) NSUInteger removePublicationCount;
@property(nonatomic) NSUInteger removePublicationFailures;
@property(nonatomic, copy) NSArray<NSString *> *storedPublications;
@property(nonatomic, strong) NSMutableArray<NSString *> *removedPublications;
@end

@implementation MPTestAutoFillReconciliationStore
- (MPAutoFillGeneration *)currentGenerationForPublicationIdentifier:(NSString *)publication error:(NSError **)error {
  NSNumber *state = self.publicationStates[publication];
  if (state.boolValue) return (MPAutoFillGeneration *)[NSObject new];
  if (error) *error = MPAutoFillError(state ? MPAutoFillErrorGenerationIncomplete : MPAutoFillErrorItemNotFound,
      @"Test state is unavailable.", nil);
  return nil;
}
- (BOOL)removeOrphanedGenerationsForPublicationIdentifier:(NSString *)publication
    retainingGenerations:(NSSet<NSString *> *)retained limit:(NSUInteger)limit error:(NSError **)error {
  [self.cleanedPublications addObject:publication];
  return YES;
}
- (BOOL)removePublicationDataForPublicationIdentifier:(NSString *)publication error:(NSError **)error {
  self.removePublicationCount++;
  if (self.removePublicationFailures > 0) {
    self.removePublicationFailures--;
    if (error) *error = MPAutoFillError(MPAutoFillErrorStorageUnavailable, @"Generation cleanup failed.", nil);
    return NO;
  }
  [self.removedPublications addObject:publication];
  return YES;
}
- (NSArray<NSString *> *)publicationIdentifiersWithError:(NSError **)error {
  return self.storedPublications ?: @[];
}
@end

@interface MPTestAutoFillIdentityUpdater : NSObject <MPAutoFillIdentitySynchronizing>
@property(nonatomic, strong) NSError *error;
@property(nonatomic) NSUInteger synchronizationCount;
@property(nonatomic) NSUInteger failures;
@end

@implementation MPTestAutoFillIdentityUpdater
- (void)synchronize {}
- (void)synchronizeWithCompletion:(void (^)(NSError *))completion {
  self.synchronizationCount++;
  if (self.failures > 0) {
    self.failures--;
    completion(self.error ?: MPAutoFillError(MPAutoFillErrorStorageUnavailable, @"Identity failure.", nil));
  } else {
    completion(nil);
  }
}
@end

@interface MPTestAutoFillKeychain : NSObject
@property(nonatomic) NSUInteger keyDeletionCount;
@property(nonatomic) NSUInteger generationDeletionCount;
@property(nonatomic) NSUInteger keyDeletionFailures;
@property(nonatomic) NSUInteger generationDeletionFailures;
@property(nonatomic) NSUInteger keyCreationCount;
@property(nonatomic) NSUInteger keyCreationFailures;
@property(nonatomic, copy) NSArray<NSString *> *storedPublications;
@property(nonatomic, strong) NSError *enumerationError;
@end

@implementation MPTestAutoFillKeychain
- (BOOL)createKeyPairForPublicationIdentifier:(NSString *)publication error:(NSError **)error {
  self.keyCreationCount++;
  if (self.keyCreationFailures > 0) {
    self.keyCreationFailures--;
    if (error) *error = MPAutoFillError(MPAutoFillErrorKeychainUnavailable, @"Key creation failed.", nil);
    return NO;
  }
  return YES;
}
- (BOOL)deleteKeyPairForPublicationIdentifier:(NSString *)publication error:(NSError **)error {
  self.keyDeletionCount++;
  if (self.keyDeletionFailures > 0) {
    self.keyDeletionFailures--;
    if (error) *error = MPAutoFillError(MPAutoFillErrorKeychainUnavailable, @"Key deletion failed.", nil);
    return NO;
  }
  return YES;
}
- (BOOL)deleteCurrentGenerationForPublicationIdentifier:(NSString *)publication error:(NSError **)error {
  self.generationDeletionCount++;
  if (self.generationDeletionFailures > 0) {
    self.generationDeletionFailures--;
    if (error) *error = MPAutoFillError(MPAutoFillErrorKeychainUnavailable, @"Activation deletion failed.", nil);
    return NO;
  }
  return YES;
}
- (NSArray<NSString *> *)publicationIdentifiersWithError:(NSError **)error {
  if (self.enumerationError) {
    if (error) *error = self.enumerationError;
    return nil;
  }
  return self.storedPublications ?: @[];
}
@end

@interface MPTestAutoFillReplacementCoordinator : MPAutoFillCoordinator
@property(nonatomic) NSUInteger publicationCount;
@property(nonatomic, copy) NSData *publishedData;
@end

@implementation MPTestAutoFillReplacementCoordinator
- (void)publishSavedData:(NSData *)savedData key:(KPKCompositeKey *)key
    publicationIdentifier:(NSString *)publication saveToken:(uint64_t)saveToken {
  self.publicationCount++;
  self.publishedData = savedData;
}
@end

@interface MPTestAutoFillRegistry : MPAutoFillPublicationRegistry
@property(nonatomic) NSUInteger removalCount;
@property(nonatomic) NSUInteger removalFailures;
@end

@implementation MPTestAutoFillRegistry
- (BOOL)removePublicationIdentifier:(NSString *)publication error:(NSError **)error {
  self.removalCount++;
  if (self.removalFailures > 0) {
    self.removalFailures--;
    if (error) *error = MPAutoFillError(MPAutoFillErrorStorageUnavailable, @"Registry cleanup failed.", nil);
    return NO;
  }
  return [super removePublicationIdentifier:publication error:error];
}
@end

@interface MPTestAutoFillCoordinator : XCTestCase
@end

@implementation MPTestAutoFillCoordinator

- (NSURL *)temporaryRegistryRoot {
  NSURL *URL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]
                          isDirectory:YES];
  XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtURL:URL withIntermediateDirectories:YES
      attributes:@{NSFilePosixPermissions: @0700} error:NULL]);
  [self addTeardownBlock:^{ [NSFileManager.defaultManager removeItemAtURL:URL error:NULL]; }];
  return URL;
}

- (NSURL *)databaseURLAtRoot:(NSURL *)root name:(NSString *)name {
  NSURL *URL = [root URLByAppendingPathComponent:name];
  XCTAssertTrue([@"fixture" writeToURL:URL atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
  return URL;
}

- (MPAutoFillPublicationSequencer *)sequencer {
  return [[MPAutoFillPublicationSequencer alloc] init];
}

- (NSError *)unpublish:(NSString *)publication coordinator:(MPAutoFillCoordinator *)coordinator {
  XCTestExpectation *completion = [self expectationWithDescription:@"unpublish"];
  __block NSError *result = nil;
  [coordinator unpublishPublicationIdentifier:publication completion:^(NSError *error) {
    result = error;
    [completion fulfill];
  }];
  [self waitForExpectations:@[completion] timeout:2];
  return result;
}

- (NSDictionary *)unpublishFixtureWithRoot:(NSURL *)root {
  NSString *publication = @"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
  MPTestAutoFillRegistry *registry = [[MPTestAutoFillRegistry alloc] initWithRootURL:root];
  XCTAssertTrue([registry enablePublicationIdentifier:publication forDocument:[[NSDocument alloc] init]
      sourceURL:[self databaseURLAtRoot:root name:@"Database.kdbx"]
      rootIdentifier:@"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb" error:NULL]);
  MPTestAutoFillReconciliationStore *store = [[MPTestAutoFillReconciliationStore alloc]
      initWithRootURL:root currentGenerationStore:[[MPTestAutoFillCurrentStore alloc] init] error:NULL];
  MPTestAutoFillKeychain *keychain = [[MPTestAutoFillKeychain alloc] init];
  MPTestAutoFillIdentityUpdater *updater = [[MPTestAutoFillIdentityUpdater alloc] init];
  MPAutoFillCoordinator *coordinator = [[MPAutoFillCoordinator alloc] initWithGenerationStore:store
      keychainStore:keychain identityStoreUpdater:updater publicationRegistry:registry];
  return @{@"publication": publication, @"registry": registry, @"store": store,
           @"keychain": keychain, @"updater": updater, @"coordinator": coordinator};
}

- (NSDictionary *)replacementFixtureWithRoot:(NSURL *)root {
  NSMutableDictionary *fixture = [[self unpublishFixtureWithRoot:root] mutableCopy];
  MPTestAutoFillReplacementCoordinator *coordinator = [[MPTestAutoFillReplacementCoordinator alloc]
      initWithGenerationStore:fixture[@"store"] keychainStore:fixture[@"keychain"]
      identityStoreUpdater:fixture[@"updater"] publicationRegistry:fixture[@"registry"]];
  fixture[@"coordinator"] = coordinator;
  return fixture;
}

- (NSData *)passwordFixtureData {
  NSURL *URL = [[NSBundle bundleForClass:self.class] URLForResource:@"Test_Password_1234" withExtension:@"kdbx"];
  XCTAssertNotNil(URL);
  NSData *data = [NSData dataWithContentsOfURL:URL];
  XCTAssertNotNil(data);
  return data;
}

- (KPKCompositeKey *)passwordFixtureKey {
  return [[KPKCompositeKey alloc] initWithKeys:@[[KPKKey keyWithPassword:@"1234"]]];
}

- (BOOL)replacePublication:(NSString *)publication coordinator:(MPAutoFillCoordinator *)coordinator
    data:(NSData *)data key:(KPKCompositeKey *)key expectedRoot:(NSString *)root {
  XCTestExpectation *completion = [self expectationWithDescription:@"replacement"];
  __block BOOL retained = NO;
  [coordinator replacePublicationIdentifier:publication withSavedData:data key:key
      expectedRootIdentifier:root completion:^(BOOL publicationRetained) {
        retained = publicationRetained;
        [completion fulfill];
      }];
  [self waitForExpectations:@[completion] timeout:2];
  return retained;
}

- (void)testOlderSuccessfulSaveCannotActivateAfterNewerSaveCompletes {
  MPAutoFillPublicationSequencer *sequencer = self.sequencer;
  NSString *publication = @"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
  uint64_t older = [sequencer beginSaveForPublicationIdentifier:publication];
  uint64_t newer = [sequencer beginSaveForPublicationIdentifier:publication];
  XCTAssertTrue([sequencer registerSuccessfulSaveToken:newer publicationIdentifier:publication]);

  __block BOOL activated = NO;
  XCTAssertFalse([sequencer performIfCurrentToken:older publicationIdentifier:publication
      action:^BOOL(NSError **error) { activated = YES; return YES; } error:NULL]);
  XCTAssertFalse(activated);
}

- (void)testOnlyLatestSuccessfulSaveCanActivate {
  MPAutoFillPublicationSequencer *sequencer = self.sequencer;
  NSString *publication = @"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
  uint64_t token = [sequencer beginSaveForPublicationIdentifier:publication];
  XCTAssertTrue([sequencer registerSuccessfulSaveToken:token publicationIdentifier:publication]);

  __block BOOL activated = NO;
  XCTAssertTrue([sequencer performIfCurrentToken:token publicationIdentifier:publication
      action:^BOOL(NSError **error) { activated = YES; return YES; } error:NULL]);
  XCTAssertTrue(activated);
}

- (void)testPublicationPreparationRegistersBeforeReconciliationCanObserveKey {
  NSURL *root = [self temporaryRegistryRoot];
  NSString *publication = @"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
  MPTestAutoFillRegistry *registry = [[MPTestAutoFillRegistry alloc] initWithRootURL:root];
  MPTestAutoFillReconciliationStore *store = [[MPTestAutoFillReconciliationStore alloc]
      initWithRootURL:root currentGenerationStore:[[MPTestAutoFillCurrentStore alloc] init] error:NULL];
  store.storedPublications = @[];
  MPTestAutoFillKeychain *keychain = [[MPTestAutoFillKeychain alloc] init];
  MPAutoFillCoordinator *coordinator = [[MPAutoFillCoordinator alloc] initWithGenerationStore:store
      keychainStore:keychain identityStoreUpdater:[[MPTestAutoFillIdentityUpdater alloc] init]
      publicationRegistry:registry];
  NSURL *databaseURL = [self databaseURLAtRoot:root name:@"Database.kdbx"];

  XCTAssertTrue([coordinator preparePublicationIdentifier:publication registrationBlock:^BOOL(NSError **error) {
    return [registry enablePublicationIdentifier:publication forDocument:[[NSDocument alloc] init]
        sourceURL:databaseURL rootIdentifier:@"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb" error:error];
  } error:NULL]);
  XCTAssertEqual(keychain.keyCreationCount, 1u);
  XCTAssertEqual(keychain.keyDeletionCount, 0u);
  XCTAssertEqualObjects(registry.publicationIdentifiers, (@[publication]));
}

- (void)testFailedPublicationRegistrationDeletesPreparedKeychainState {
  NSURL *root = [self temporaryRegistryRoot];
  MPTestAutoFillReconciliationStore *store = [[MPTestAutoFillReconciliationStore alloc]
      initWithRootURL:root currentGenerationStore:[[MPTestAutoFillCurrentStore alloc] init] error:NULL];
  MPTestAutoFillKeychain *keychain = [[MPTestAutoFillKeychain alloc] init];
  MPAutoFillCoordinator *coordinator = [[MPAutoFillCoordinator alloc] initWithGenerationStore:store
      keychainStore:keychain identityStoreUpdater:[[MPTestAutoFillIdentityUpdater alloc] init]
      publicationRegistry:[[MPTestAutoFillRegistry alloc] initWithRootURL:root]];
  NSError *expected = MPAutoFillError(MPAutoFillErrorStorageUnavailable, @"Registration failed.", nil);
  NSError *error = nil;

  XCTAssertFalse([coordinator preparePublicationIdentifier:@"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
      registrationBlock:^BOOL(NSError **registrationError) {
        if (registrationError) *registrationError = expected;
        return NO;
      } error:&error]);
  XCTAssertEqualObjects(error, expected);
  XCTAssertEqual(keychain.keyCreationCount, 1u);
  XCTAssertEqual(keychain.keyDeletionCount, 1u);
  XCTAssertEqual(keychain.generationDeletionCount, 1u);
}

- (void)testRevertInvalidatesQueuedSave {
  MPAutoFillPublicationSequencer *sequencer = self.sequencer;
  NSString *publication = @"cccccccc-cccc-cccc-cccc-cccccccccccc";
  uint64_t token = [sequencer beginSaveForPublicationIdentifier:publication];
  XCTAssertTrue([sequencer registerSuccessfulSaveToken:token publicationIdentifier:publication]);
  [sequencer invalidatePublicationIdentifier:publication];

  XCTAssertFalse([sequencer performIfCurrentToken:token publicationIdentifier:publication
      action:^BOOL(NSError **error) { return YES; } error:NULL]);
}

- (void)testSuccessfulSaveOperationsPublishOrPromptExplicitly {
  XCTAssertEqual(MPAutoFillSaveActionForResult(NSSaveOperation, YES, YES), MPAutoFillSaveActionPublish);
  XCTAssertEqual(MPAutoFillSaveActionForResult(NSAutosaveInPlaceOperation, YES, YES), MPAutoFillSaveActionPublish);
  XCTAssertEqual(MPAutoFillSaveActionForResult(NSSaveAsOperation, YES, YES), MPAutoFillSaveActionChooseSaveAsPublication);
  XCTAssertEqual(MPAutoFillSaveActionForResult(NSSaveToOperation, YES, YES), MPAutoFillSaveActionNone);
}

- (void)testFailedOrDisabledSaveNeverPublishes {
  XCTAssertEqual(MPAutoFillSaveActionForResult(NSSaveOperation, NO, YES), MPAutoFillSaveActionNone);
  XCTAssertEqual(MPAutoFillSaveActionForResult(NSAutosaveInPlaceOperation, NO, YES), MPAutoFillSaveActionNone);
  XCTAssertEqual(MPAutoFillSaveActionForResult(NSSaveOperation, YES, NO), MPAutoFillSaveActionNone);
}

- (void)testDetachedSaveAsDocumentCannotPublishUnderOriginalBinding {
  NSURL *root = [self temporaryRegistryRoot];
  NSURL *originalURL = [self databaseURLAtRoot:root name:@"Original.kdbx"];
  NSURL *savedAsURL = [self databaseURLAtRoot:root name:@"Saved As.kdbx"];
  MPAutoFillPublicationRegistry *registry = [[MPAutoFillPublicationRegistry alloc] initWithRootURL:root];
  NSDocument *document = [[NSDocument alloc] init];
  NSString *publication = @"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
  NSString *databaseRoot = @"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
  XCTAssertTrue([registry enablePublicationIdentifier:publication forDocument:document sourceURL:originalURL
      rootIdentifier:databaseRoot error:NULL]);

  [registry detachDocument:document];

  XCTAssertNil([registry publicationIdentifierForDocument:document sourceURL:savedAsURL rootIdentifier:databaseRoot]);
  XCTAssertEqualObjects([registry publicationIdentifierForDocument:[[NSDocument alloc] init]
      sourceURL:originalURL rootIdentifier:databaseRoot], publication);
}

- (void)testMoveRebindsDocumentAndPersistsNewLocation {
  NSURL *root = [self temporaryRegistryRoot];
  NSURL *originalURL = [self databaseURLAtRoot:root name:@"Original.kdbx"];
  NSURL *movedURL = [self databaseURLAtRoot:root name:@"Moved.kdbx"];
  NSString *publication = @"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
  NSString *databaseRoot = @"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
  NSDocument *document = [[NSDocument alloc] init];
  MPAutoFillPublicationRegistry *registry = [[MPAutoFillPublicationRegistry alloc] initWithRootURL:root];
  XCTAssertTrue([registry enablePublicationIdentifier:publication forDocument:document sourceURL:originalURL
      rootIdentifier:databaseRoot error:NULL]);
  [registry detachDocument:document];
  XCTAssertTrue([registry movePublicationIdentifier:publication forDocument:document sourceURL:movedURL
      rootIdentifier:databaseRoot error:NULL]);

  MPAutoFillPublicationRegistry *reloaded = [[MPAutoFillPublicationRegistry alloc] initWithRootURL:root];
  XCTAssertEqualObjects([reloaded publicationIdentifierForDocument:[[NSDocument alloc] init]
      sourceURL:movedURL rootIdentifier:databaseRoot], publication);
  XCTAssertNil([reloaded publicationIdentifierForDocument:[[NSDocument alloc] init]
      sourceURL:originalURL rootIdentifier:databaseRoot]);
}

- (void)testFilesystemRenameRetainsPublicationAfterRegistryReload {
  NSURL *root = [self temporaryRegistryRoot];
  NSURL *originalURL = [self databaseURLAtRoot:root name:@"Original.kdbx"];
  NSURL *renamedURL = [root URLByAppendingPathComponent:@"Renamed.kdbx"];
  NSString *publication = @"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
  NSString *databaseRoot = @"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
  MPAutoFillPublicationRegistry *registry = [[MPAutoFillPublicationRegistry alloc] initWithRootURL:root];
  XCTAssertTrue([registry enablePublicationIdentifier:publication forDocument:[[NSDocument alloc] init]
      sourceURL:originalURL rootIdentifier:databaseRoot error:NULL]);
  XCTAssertTrue([NSFileManager.defaultManager moveItemAtURL:originalURL toURL:renamedURL error:NULL]);

  MPAutoFillPublicationRegistry *reloaded = [[MPAutoFillPublicationRegistry alloc] initWithRootURL:root];
  XCTAssertEqualObjects([reloaded publicationIdentifierForDocument:[[NSDocument alloc] init]
      sourceURL:renamedURL rootIdentifier:databaseRoot], publication);
}

- (void)testCopiedDatabaseWithSameRootRequiresSeparateEnablement {
  NSURL *root = [self temporaryRegistryRoot];
  NSURL *originalURL = [self databaseURLAtRoot:root name:@"Original.kdbx"];
  NSURL *copyURL = [root URLByAppendingPathComponent:@"Copy.kdbx"];
  NSString *databaseRoot = @"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
  MPAutoFillPublicationRegistry *registry = [[MPAutoFillPublicationRegistry alloc] initWithRootURL:root];
  XCTAssertTrue([registry enablePublicationIdentifier:@"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
      forDocument:[[NSDocument alloc] init] sourceURL:originalURL rootIdentifier:databaseRoot error:NULL]);
  XCTAssertTrue([NSFileManager.defaultManager copyItemAtURL:originalURL toURL:copyURL error:NULL]);

  MPAutoFillPublicationRegistry *reloaded = [[MPAutoFillPublicationRegistry alloc] initWithRootURL:root];
  XCTAssertNil([reloaded publicationIdentifierForDocument:[[NSDocument alloc] init]
      sourceURL:copyURL rootIdentifier:databaseRoot]);
}

- (void)testReadOnlySourceCanBeRegisteredWithoutModification {
  NSURL *root = [self temporaryRegistryRoot];
  NSURL *databaseURL = [self databaseURLAtRoot:root name:@"Read Only.kdbx"];
  NSData *before = [NSData dataWithContentsOfURL:databaseURL];
  NSDate *dateBefore = [databaseURL resourceValuesForKeys:@[NSURLContentModificationDateKey]
      error:NULL][NSURLContentModificationDateKey];
  XCTAssertTrue([NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: @0444}
      ofItemAtPath:databaseURL.path error:NULL]);
  MPAutoFillPublicationRegistry *registry = [[MPAutoFillPublicationRegistry alloc] initWithRootURL:root];

  XCTAssertTrue([registry enablePublicationIdentifier:@"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
      forDocument:[[NSDocument alloc] init] sourceURL:databaseURL
      rootIdentifier:@"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb" error:NULL]);
  XCTAssertEqualObjects([NSData dataWithContentsOfURL:databaseURL], before);
  XCTAssertEqualObjects([databaseURL resourceValuesForKeys:@[NSURLContentModificationDateKey]
      error:NULL][NSURLContentModificationDateKey], dateBefore);
}

- (void)testMultiplePublicationsWithCollidingRootUUIDRemainFileScoped {
  NSURL *root = [self temporaryRegistryRoot];
  NSURL *firstURL = [self databaseURLAtRoot:root name:@"First.kdbx"];
  NSURL *secondURL = [self databaseURLAtRoot:root name:@"Second.kdbx"];
  NSString *databaseRoot = @"cccccccc-cccc-cccc-cccc-cccccccccccc";
  NSString *firstPublication = @"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
  NSString *secondPublication = @"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
  MPAutoFillPublicationRegistry *registry = [[MPAutoFillPublicationRegistry alloc] initWithRootURL:root];
  XCTAssertTrue([registry enablePublicationIdentifier:firstPublication forDocument:[[NSDocument alloc] init]
      sourceURL:firstURL rootIdentifier:databaseRoot error:NULL]);
  XCTAssertTrue([registry enablePublicationIdentifier:secondPublication forDocument:[[NSDocument alloc] init]
      sourceURL:secondURL rootIdentifier:databaseRoot error:NULL]);

  MPAutoFillPublicationRegistry *reloaded = [[MPAutoFillPublicationRegistry alloc] initWithRootURL:root];
  XCTAssertEqualObjects(reloaded.publicationIdentifiers, (@[firstPublication, secondPublication]));
  XCTAssertEqualObjects([reloaded publicationIdentifierForDocument:[[NSDocument alloc] init]
      sourceURL:firstURL rootIdentifier:databaseRoot], firstPublication);
  XCTAssertEqualObjects([reloaded publicationIdentifierForDocument:[[NSDocument alloc] init]
      sourceURL:secondURL rootIdentifier:databaseRoot], secondPublication);
}

- (void)testUnsupportedRegistrySchemaIsPreservedAndCannotBeOverwritten {
  NSURL *root = [self temporaryRegistryRoot];
  NSURL *registryURL = [root URLByAppendingPathComponent:@"registry.plist"];
  NSData *futureData = [NSPropertyListSerialization dataWithPropertyList:@{@"schema": @2, @"publications": @[]}
      format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
  XCTAssertTrue([futureData writeToURL:registryURL options:NSDataWritingAtomic error:NULL]);
  XCTAssertTrue([NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: @0600}
      ofItemAtPath:registryURL.path error:NULL]);
  MPAutoFillPublicationRegistry *registry = [[MPAutoFillPublicationRegistry alloc] initWithRootURL:root];
  NSURL *databaseURL = [self databaseURLAtRoot:root name:@"Database.kdbx"];

  XCTAssertFalse([registry enablePublicationIdentifier:@"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
      forDocument:[[NSDocument alloc] init] sourceURL:databaseURL
      rootIdentifier:@"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb" error:NULL]);
  XCTAssertEqualObjects([NSData dataWithContentsOfURL:registryURL], futureData);
}

- (void)testStartupReconciliationCleansEveryHealthyPublicationAndSkipsInvalidState {
  NSURL *root = [self temporaryRegistryRoot];
  MPAutoFillPublicationRegistry *registry = [[MPAutoFillPublicationRegistry alloc] initWithRootURL:root];
  NSArray *publications = @[
    @"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
    @"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
    @"cccccccc-cccc-cccc-cccc-cccccccccccc",
  ];
  for (NSUInteger index = 0; index < publications.count; index++) {
    NSURL *databaseURL = [self databaseURLAtRoot:root name:[NSString stringWithFormat:@"%lu.kdbx", index]];
    XCTAssertTrue([registry enablePublicationIdentifier:publications[index] forDocument:[[NSDocument alloc] init]
        sourceURL:databaseURL rootIdentifier:@"dddddddd-dddd-dddd-dddd-dddddddddddd" error:NULL]);
  }
  MPTestAutoFillReconciliationStore *store = [[MPTestAutoFillReconciliationStore alloc]
      initWithRootURL:root currentGenerationStore:[[MPTestAutoFillCurrentStore alloc] init] error:NULL];
  store.publicationStates = @{publications[0]: @YES, publications[1]: @NO};
  store.cleanedPublications = [NSMutableArray array];
  MPTestAutoFillIdentityUpdater *updater = [[MPTestAutoFillIdentityUpdater alloc] init];
  MPAutoFillCoordinator *coordinator = [[MPAutoFillCoordinator alloc] initWithGenerationStore:store
      keychainStore:[[MPTestAutoFillKeychain alloc] init] identityStoreUpdater:updater publicationRegistry:registry];
  XCTestExpectation *completion = [self expectationWithDescription:@"reconciliation"];

  [coordinator reconcilePublishedStateWithCompletion:^(NSError *error) {
    XCTAssertEqual(error.code, MPAutoFillErrorGenerationIncomplete);
    [completion fulfill];
  }];
  [self waitForExpectations:@[completion] timeout:2];
  XCTAssertEqual(updater.synchronizationCount, 1u);
  XCTAssertEqualObjects(store.cleanedPublications, (@[publications[0]]));
}

- (void)testStartupReconciliationStillCleansHealthyStateWhenIdentitySyncFails {
  NSURL *root = [self temporaryRegistryRoot];
  MPAutoFillPublicationRegistry *registry = [[MPAutoFillPublicationRegistry alloc] initWithRootURL:root];
  NSString *publication = @"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
  XCTAssertTrue([registry enablePublicationIdentifier:publication forDocument:[[NSDocument alloc] init]
      sourceURL:[self databaseURLAtRoot:root name:@"Database.kdbx"]
      rootIdentifier:@"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb" error:NULL]);
  MPTestAutoFillReconciliationStore *store = [[MPTestAutoFillReconciliationStore alloc]
      initWithRootURL:root currentGenerationStore:[[MPTestAutoFillCurrentStore alloc] init] error:NULL];
  store.publicationStates = @{publication: @YES};
  store.cleanedPublications = [NSMutableArray array];
  MPTestAutoFillIdentityUpdater *updater = [[MPTestAutoFillIdentityUpdater alloc] init];
  updater.error = MPAutoFillError(MPAutoFillErrorStorageUnavailable, @"Identity failure.", nil);
  updater.failures = 1;
  MPAutoFillCoordinator *coordinator = [[MPAutoFillCoordinator alloc] initWithGenerationStore:store
      keychainStore:[[MPTestAutoFillKeychain alloc] init] identityStoreUpdater:updater publicationRegistry:registry];
  XCTestExpectation *completion = [self expectationWithDescription:@"reconciliation"];

  [coordinator reconcilePublishedStateWithCompletion:^(NSError *error) {
    XCTAssertEqualObjects(error, updater.error);
    [completion fulfill];
  }];
  [self waitForExpectations:@[completion] timeout:2];
  XCTAssertEqualObjects(store.cleanedPublications, (@[publication]));
}

- (void)testColdStartupRetainsRegisteredStateAndRevokesStorageOrphan {
  NSURL *root = [self temporaryRegistryRoot];
  NSString *registered = @"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
  NSString *orphan = @"cccccccc-cccc-cccc-cccc-cccccccccccc";
  MPAutoFillPublicationRegistry *initialRegistry = [[MPAutoFillPublicationRegistry alloc] initWithRootURL:root];
  XCTAssertTrue([initialRegistry enablePublicationIdentifier:registered forDocument:[[NSDocument alloc] init]
      sourceURL:[self databaseURLAtRoot:root name:@"Database.kdbx"]
      rootIdentifier:@"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb" error:NULL]);

  MPAutoFillPublicationRegistry *reloadedRegistry = [[MPAutoFillPublicationRegistry alloc] initWithRootURL:root];
  MPTestAutoFillReconciliationStore *store = [[MPTestAutoFillReconciliationStore alloc]
      initWithRootURL:root currentGenerationStore:[[MPTestAutoFillCurrentStore alloc] init] error:NULL];
  store.publicationStates = @{registered: @YES};
  store.cleanedPublications = [NSMutableArray array];
  store.storedPublications = @[registered, orphan];
  store.removedPublications = [NSMutableArray array];
  MPTestAutoFillKeychain *keychain = [[MPTestAutoFillKeychain alloc] init];
  keychain.storedPublications = @[registered, orphan];
  MPTestAutoFillIdentityUpdater *updater = [[MPTestAutoFillIdentityUpdater alloc] init];
  MPAutoFillCoordinator *coordinator = [[MPAutoFillCoordinator alloc] initWithGenerationStore:store
      keychainStore:keychain identityStoreUpdater:updater publicationRegistry:reloadedRegistry];
  XCTestExpectation *completion = [self expectationWithDescription:@"cold reconciliation"];

  [coordinator reconcilePublishedStateWithCompletion:^(NSError *error) {
    XCTAssertNil(error);
    [completion fulfill];
  }];
  [self waitForExpectations:@[completion] timeout:2];
  XCTAssertEqualObjects(store.cleanedPublications, (@[registered]));
  XCTAssertEqualObjects(store.removedPublications, (@[orphan]));
  XCTAssertEqual(keychain.keyDeletionCount, 1u);
  XCTAssertEqual(keychain.generationDeletionCount, 1u);
  XCTAssertEqualObjects(reloadedRegistry.publicationIdentifiers, (@[registered]));
}

- (void)testColdStartupRevokesKeychainOnlyOrphanAfterAppGroupLoss {
  NSURL *root = [self temporaryRegistryRoot];
  NSString *orphan = @"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
  MPAutoFillPublicationRegistry *registry = [[MPAutoFillPublicationRegistry alloc] initWithRootURL:root];
  MPTestAutoFillReconciliationStore *store = [[MPTestAutoFillReconciliationStore alloc]
      initWithRootURL:root currentGenerationStore:[[MPTestAutoFillCurrentStore alloc] init] error:NULL];
  store.storedPublications = @[];
  store.removedPublications = [NSMutableArray array];
  MPTestAutoFillKeychain *keychain = [[MPTestAutoFillKeychain alloc] init];
  keychain.storedPublications = @[orphan];
  MPAutoFillCoordinator *coordinator = [[MPAutoFillCoordinator alloc] initWithGenerationStore:store
      keychainStore:keychain identityStoreUpdater:[[MPTestAutoFillIdentityUpdater alloc] init]
      publicationRegistry:registry];
  XCTestExpectation *completion = [self expectationWithDescription:@"Keychain orphan reconciliation"];

  [coordinator reconcilePublishedStateWithCompletion:^(NSError *error) {
    XCTAssertNil(error);
    [completion fulfill];
  }];
  [self waitForExpectations:@[completion] timeout:2];
  XCTAssertEqual(keychain.keyDeletionCount, 1u);
  XCTAssertEqual(keychain.generationDeletionCount, 1u);
  XCTAssertEqualObjects(store.removedPublications, (@[orphan]));
}

- (void)testKeychainEnumerationFailurePreventsDestructiveOrphanCleanup {
  NSURL *root = [self temporaryRegistryRoot];
  NSString *orphan = @"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
  MPAutoFillPublicationRegistry *registry = [[MPAutoFillPublicationRegistry alloc] initWithRootURL:root];
  MPTestAutoFillReconciliationStore *store = [[MPTestAutoFillReconciliationStore alloc]
      initWithRootURL:root currentGenerationStore:[[MPTestAutoFillCurrentStore alloc] init] error:NULL];
  store.storedPublications = @[orphan];
  store.removedPublications = [NSMutableArray array];
  MPTestAutoFillKeychain *keychain = [[MPTestAutoFillKeychain alloc] init];
  keychain.enumerationError = MPAutoFillError(MPAutoFillErrorKeychainUnavailable, @"Enumeration failed.", nil);
  MPAutoFillCoordinator *coordinator = [[MPAutoFillCoordinator alloc] initWithGenerationStore:store
      keychainStore:keychain identityStoreUpdater:[[MPTestAutoFillIdentityUpdater alloc] init]
      publicationRegistry:registry];
  XCTestExpectation *completion = [self expectationWithDescription:@"failed Keychain enumeration"];

  [coordinator reconcilePublishedStateWithCompletion:^(NSError *error) {
    XCTAssertEqualObjects(error, keychain.enumerationError);
    [completion fulfill];
  }];
  [self waitForExpectations:@[completion] timeout:2];
  XCTAssertEqual(keychain.keyDeletionCount, 0u);
  XCTAssertEqual(keychain.generationDeletionCount, 0u);
  XCTAssertEqual(store.removePublicationCount, 0u);
}

- (void)testUnsupportedRegistryDoesNotDeleteStorageOrKeychainState {
  NSURL *root = [self temporaryRegistryRoot];
  NSData *futureData = [NSPropertyListSerialization dataWithPropertyList:@{@"schema": @2, @"publications": @[]}
      format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
  NSURL *registryURL = [root URLByAppendingPathComponent:@"registry.plist"];
  XCTAssertTrue([futureData writeToURL:registryURL options:NSDataWritingAtomic error:NULL]);
  XCTAssertTrue([NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: @0600}
      ofItemAtPath:registryURL.path error:NULL]);
  MPAutoFillPublicationRegistry *registry = [[MPAutoFillPublicationRegistry alloc] initWithRootURL:root];
  MPTestAutoFillReconciliationStore *store = [[MPTestAutoFillReconciliationStore alloc]
      initWithRootURL:root currentGenerationStore:[[MPTestAutoFillCurrentStore alloc] init] error:NULL];
  store.storedPublications = @[@"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"];
  store.removedPublications = [NSMutableArray array];
  MPTestAutoFillKeychain *keychain = [[MPTestAutoFillKeychain alloc] init];
  MPAutoFillCoordinator *coordinator = [[MPAutoFillCoordinator alloc] initWithGenerationStore:store
      keychainStore:keychain identityStoreUpdater:[[MPTestAutoFillIdentityUpdater alloc] init]
      publicationRegistry:registry];
  XCTestExpectation *completion = [self expectationWithDescription:@"future registry reconciliation"];

  [coordinator reconcilePublishedStateWithCompletion:^(NSError *error) {
    XCTAssertNil(error);
    [completion fulfill];
  }];
  [self waitForExpectations:@[completion] timeout:2];
  XCTAssertFalse(registry.isAuthoritative);
  XCTAssertEqual(store.removePublicationCount, 0u);
  XCTAssertEqual(keychain.keyDeletionCount, 0u);
  XCTAssertEqual(keychain.generationDeletionCount, 0u);
}

- (void)testUnpublishRetriesEachFailureBoundaryAndRemovesRegistryLast {
  for (NSString *failure in @[@"key", @"activation", @"identity", @"generation", @"registry"]) {
    NSDictionary *fixture = [self unpublishFixtureWithRoot:[self temporaryRegistryRoot]];
    NSString *publication = fixture[@"publication"];
    MPTestAutoFillKeychain *keychain = fixture[@"keychain"];
    MPTestAutoFillIdentityUpdater *updater = fixture[@"updater"];
    MPTestAutoFillReconciliationStore *store = fixture[@"store"];
    MPTestAutoFillRegistry *registry = fixture[@"registry"];
    if ([failure isEqualToString:@"key"]) keychain.keyDeletionFailures = 1;
    if ([failure isEqualToString:@"activation"]) keychain.generationDeletionFailures = 1;
    if ([failure isEqualToString:@"identity"]) updater.failures = 1;
    if ([failure isEqualToString:@"generation"]) store.removePublicationFailures = 1;
    if ([failure isEqualToString:@"registry"]) registry.removalFailures = 1;

    XCTAssertNotNil([self unpublish:publication coordinator:fixture[@"coordinator"]], @"%@ should fail once", failure);
    XCTAssertTrue([registry.publicationIdentifiers containsObject:publication], @"%@ must retain registry for retry", failure);
    if ([failure isEqualToString:@"key"]) {
      XCTAssertEqual(keychain.generationDeletionCount, 0u);
      XCTAssertEqual(updater.synchronizationCount, 0u);
    } else if ([failure isEqualToString:@"activation"]) {
      XCTAssertEqual(updater.synchronizationCount, 0u);
    } else if ([failure isEqualToString:@"identity"]) {
      XCTAssertEqual(store.removePublicationCount, 0u);
    } else if ([failure isEqualToString:@"generation"]) {
      XCTAssertEqual(registry.removalCount, 0u);
    }

    XCTAssertNil([self unpublish:publication coordinator:fixture[@"coordinator"]], @"%@ should succeed on retry", failure);
    XCTAssertFalse([registry.publicationIdentifiers containsObject:publication]);
    XCTAssertGreaterThanOrEqual(keychain.keyDeletionCount, 2u);
    XCTAssertGreaterThanOrEqual(keychain.generationDeletionCount, 1u);
    XCTAssertGreaterThanOrEqual(updater.synchronizationCount, 1u);
    XCTAssertGreaterThanOrEqual(store.removePublicationCount, 1u);
    XCTAssertGreaterThanOrEqual(registry.removalCount, 1u);
  }
}

- (void)testRepeatedUnpublishIsIdempotent {
  NSDictionary *fixture = [self unpublishFixtureWithRoot:[self temporaryRegistryRoot]];
  NSString *publication = fixture[@"publication"];

  XCTAssertNil([self unpublish:publication coordinator:fixture[@"coordinator"]]);
  XCTAssertNil([self unpublish:publication coordinator:fixture[@"coordinator"]]);
  XCTAssertFalse([fixture[@"registry"] publicationIdentifiers].count > 0);
}

- (void)testReplacementWithMatchingRootRecreatesKeyAndRepublishes {
  NSDictionary *fixture = [self replacementFixtureWithRoot:[self temporaryRegistryRoot]];
  NSData *data = [self passwordFixtureData];
  KPKCompositeKey *key = [self passwordFixtureKey];
  KPKTree *tree = [[KPKTree alloc] initWithData:data key:key error:NULL];
  MPTestAutoFillReplacementCoordinator *coordinator = fixture[@"coordinator"];

  XCTAssertTrue([self replacePublication:fixture[@"publication"] coordinator:coordinator data:data key:key
      expectedRoot:tree.root.uuid.UUIDString.lowercaseString]);
  XCTAssertEqual([fixture[@"keychain"] keyDeletionCount], 1u);
  XCTAssertEqual([fixture[@"keychain"] generationDeletionCount], 1u);
  XCTAssertEqual([fixture[@"keychain"] keyCreationCount], 1u);
  XCTAssertEqual(coordinator.publicationCount, 1u);
  XCTAssertEqualObjects(coordinator.publishedData, data);
  XCTAssertTrue([fixture[@"registry"] publicationIdentifiers].count > 0);
  XCTAssertEqual([fixture[@"store"] removePublicationCount], 0u);
}

- (void)testReplacementMismatchMalformedDataAndKeyCreationFailureFullyUnpublish {
  NSArray<NSString *> *cases = @[@"root", @"data", @"keyCreation"];
  for (NSString *testCase in cases) {
    NSDictionary *fixture = [self replacementFixtureWithRoot:[self temporaryRegistryRoot]];
    NSData *data = [self passwordFixtureData];
    KPKCompositeKey *key = [self passwordFixtureKey];
    KPKTree *tree = [[KPKTree alloc] initWithData:data key:key error:NULL];
    NSString *expectedRoot = tree.root.uuid.UUIDString.lowercaseString;
    if ([testCase isEqualToString:@"root"]) expectedRoot = @"ffffffff-ffff-ffff-ffff-ffffffffffff";
    if ([testCase isEqualToString:@"data"]) data = [@"invalid" dataUsingEncoding:NSUTF8StringEncoding];
    if ([testCase isEqualToString:@"keyCreation"]) [fixture[@"keychain"] setKeyCreationFailures:1];

    XCTAssertFalse([self replacePublication:fixture[@"publication"] coordinator:fixture[@"coordinator"]
        data:data key:key expectedRoot:expectedRoot], @"%@ replacement must not be retained", testCase);
    XCTAssertFalse([fixture[@"registry"] publicationIdentifiers].count > 0, @"%@ must remove registry", testCase);
    XCTAssertGreaterThanOrEqual([fixture[@"keychain"] keyDeletionCount], 2u);
    XCTAssertGreaterThanOrEqual([fixture[@"keychain"] generationDeletionCount], 2u);
    XCTAssertEqual([fixture[@"store"] removePublicationCount], 1u);
    XCTAssertEqual([fixture[@"registry"] removalCount], 1u);
    XCTAssertEqual([fixture[@"coordinator"] publicationCount], 0u);
  }
}

@end
