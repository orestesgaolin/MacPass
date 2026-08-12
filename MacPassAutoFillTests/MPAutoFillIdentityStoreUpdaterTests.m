#import <AuthenticationServices/AuthenticationServices.h>
#import <XCTest/XCTest.h>

#import "MPAutoFillCredentialRecord.h"
#import "MPAutoFillErrors.h"
#import "MPAutoFillGenerationStore.h"
#import "MPAutoFillIdentityStoreUpdater.h"
#import "MPAutoFillVaultIndex.h"

@interface MPAutoFillIdentityTestPointer : NSObject <MPAutoFillCurrentGenerationStore>
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *values;
@end

@implementation MPAutoFillIdentityTestPointer
- (instancetype)init { self = [super init]; if (self) _values = [NSMutableDictionary dictionary]; return self; }
- (NSString *)currentGenerationForPublicationIdentifier:(NSString *)publication error:(NSError **)error {
  NSString *value = self.values[publication];
  if (!value && error) *error = MPAutoFillError(MPAutoFillErrorItemNotFound, @"No active test generation.", nil);
  return value;
}
- (BOOL)setCurrentGeneration:(NSString *)generation forPublicationIdentifier:(NSString *)publication error:(NSError **)error {
  self.values[publication] = generation; return YES;
}
- (BOOL)deleteCurrentGenerationForPublicationIdentifier:(NSString *)publication error:(NSError **)error {
  [self.values removeObjectForKey:publication]; return YES;
}
@end

@interface MPAutoFillIdentityTestStore : NSObject <MPAutoFillIdentityStore>
@property(nonatomic) BOOL enabled;
@property(nonatomic) NSUInteger busyFailuresRemaining;
@property(nonatomic) NSUInteger replaceCount;
@property(nonatomic, copy) NSArray *lastIdentities;
@property(nonatomic, copy) void (^replacementObserver)(void);
@end

@implementation MPAutoFillIdentityTestStore
- (void)getStateWithCompletion:(void (^)(BOOL, BOOL))completion { completion(self.enabled, NO); }
- (void)replaceIdentities:(NSArray *)identities completion:(void (^)(BOOL, NSError *))completion {
  self.replaceCount++;
  self.lastIdentities = identities;
  if (self.busyFailuresRemaining > 0) {
    self.busyFailuresRemaining--;
    completion(NO, [NSError errorWithDomain:ASCredentialIdentityStoreErrorDomain
        code:ASCredentialIdentityStoreErrorCodeStoreBusy userInfo:nil]);
  } else {
    completion(YES, nil);
  }
  if (self.replacementObserver) self.replacementObserver();
}
@end

@interface MPAutoFillIdentityStoreUpdaterTests : XCTestCase
@property(nonatomic, strong) NSURL *rootURL;
@property(nonatomic, strong) MPAutoFillGenerationStore *generationStore;
@property(nonatomic, strong) MPAutoFillIdentityTestStore *identityStore;
@property(nonatomic, strong) NSMutableArray<NSString *> *publications;
@end

@implementation MPAutoFillIdentityStoreUpdaterTests

- (void)setUp {
  [super setUp];
  self.rootURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
      [NSString stringWithFormat:@"MPAutoFillIdentityTests-%@", NSUUID.UUID.UUIDString]] isDirectory:YES];
  self.generationStore = [[MPAutoFillGenerationStore alloc] initWithRootURL:self.rootURL
      currentGenerationStore:[[MPAutoFillIdentityTestPointer alloc] init] error:NULL];
  self.identityStore = [[MPAutoFillIdentityTestStore alloc] init];
  self.identityStore.enabled = YES;
  self.publications = [NSMutableArray array];
}

- (void)tearDown {
  [NSFileManager.defaultManager removeItemAtURL:self.rootURL error:NULL];
  [super tearDown];
}

- (void)publishEntry:(NSString *)entry publication:(NSString *)publication generation:(NSString *)generation {
  [self publishEntries:@[entry] publication:publication generation:generation];
}

- (void)publishEntries:(NSArray<NSString *> *)entries publication:(NSString *)publication
             generation:(NSString *)generation {
  NSMutableArray<MPAutoFillVaultIndexRecord *> *records = [NSMutableArray array];
  for (NSString *entry in entries) {
    MPAutoFillCredentialRecord *credential = [[MPAutoFillCredentialRecord alloc]
        initWithEntryIdentifier:entry title:@"Title" username:@"user" password:@"secret"
        serviceIdentifiers:@[@"https://example.com"] modificationTime:1 rank:records.count error:NULL];
    [records addObject:[MPAutoFillVaultIndexRecord recordWithCredentialRecord:credential]];
  }
  MPAutoFillVaultIndex *index = [[MPAutoFillVaultIndex alloc]
      initWithPublicationIdentifier:publication generationIdentifier:generation
      records:records error:NULL];
  NSData *data = [index serializedDataWithError:NULL];
  XCTAssertTrue([self.generationStore publishIndexData:data validatedIndex:index
                                      encryptedSecrets:[@"encrypted" dataUsingEncoding:NSUTF8StringEncoding] error:NULL]);
}

- (void)testNewGenerationRemovesDeletedEntryIdentityAndRetainsSurvivor {
  NSString *publication = @"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
  NSString *deleted = @"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
  NSString *survivor = @"cccccccc-cccc-cccc-cccc-cccccccccccc";
  [self publishEntries:@[deleted, survivor] publication:publication
            generation:@"dddddddd-dddd-dddd-dddd-dddddddddddd"];
  [self.publications addObject:publication];
  MPAutoFillIdentityStoreUpdater *updater = self.updater;
  XCTestExpectation *firstSync = [self expectationWithDescription:@"initial replacement"];
  self.identityStore.replacementObserver = ^{ [firstSync fulfill]; };
  [updater synchronize];
  [self waitForExpectations:@[firstSync] timeout:2];
  XCTAssertEqual(self.identityStore.lastIdentities.count, 2u);

  [self publishEntries:@[survivor] publication:publication
            generation:@"eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"];
  XCTestExpectation *secondSync = [self expectationWithDescription:@"replacement after deletion"];
  self.identityStore.replacementObserver = ^{ [secondSync fulfill]; };
  [updater synchronize];
  [self waitForExpectations:@[secondSync] timeout:2];

  XCTAssertEqual(self.identityStore.lastIdentities.count, 1u);
  NSString *identifier = [self.identityStore.lastIdentities.firstObject recordIdentifier];
  XCTAssertTrue([identifier containsString:survivor]);
  XCTAssertFalse([identifier containsString:deleted]);
}

- (MPAutoFillIdentityStoreUpdater *)updater {
  return [[MPAutoFillIdentityStoreUpdater alloc] initWithGenerationStore:self.generationStore
      identityStore:self.identityStore publicationIdentifiersBlock:^NSArray *{ return [self.publications copy]; }
      retryDelay:0];
}

- (void)testCompleteReplacementIncludesAllPublicationsAndQualifiesCollidingEntries {
  NSString *entry = @"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
  NSString *first = @"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
  NSString *second = @"cccccccc-cccc-cccc-cccc-cccccccccccc";
  [self publishEntry:entry publication:first generation:@"dddddddd-dddd-dddd-dddd-dddddddddddd"];
  [self publishEntry:entry publication:second generation:@"eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"];
  [self.publications addObjectsFromArray:@[first, second]];
  XCTestExpectation *replacement = [self expectationWithDescription:@"replacement"];
  self.identityStore.replacementObserver = ^{ [replacement fulfill]; };
  MPAutoFillIdentityStoreUpdater *updater = self.updater;
  [updater synchronize];
  [self waitForExpectations:@[replacement] timeout:2];

  XCTAssertEqual(self.identityStore.lastIdentities.count, 2u);
  NSSet *identifiers = [NSSet setWithArray:[self.identityStore.lastIdentities valueForKey:@"recordIdentifier"]];
  NSString *firstIdentifier = [NSString stringWithFormat:@"v1:%@:%@", first, entry];
  NSString *secondIdentifier = [NSString stringWithFormat:@"v1:%@:%@", second, entry];
  XCTAssertEqual(identifiers.count, 2u);
  XCTAssertTrue([identifiers containsObject:firstIdentifier]);
  XCTAssertTrue([identifiers containsObject:secondIdentifier]);
}

- (void)testDisabledStorePreservesPublicationAndDoesNotReplace {
  self.identityStore.enabled = NO;
  [self.publications addObject:@"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"];
  MPAutoFillIdentityStoreUpdater *updater = self.updater;
  [updater synchronize];
  XCTestExpectation *settled = [self expectationWithDescription:@"settled"];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_MSEC * 50), dispatch_get_main_queue(), ^{ [settled fulfill]; });
  [self waitForExpectations:@[settled] timeout:1];
  XCTAssertEqual(updater.state, MPAutoFillIdentitySyncStateStoreDisabled);
  XCTAssertEqual(self.identityStore.replaceCount, 0u);
  XCTAssertEqual(self.publications.count, 1u);
}

- (void)testBusyRetryIsBoundedAtThreeAttempts {
  self.identityStore.busyFailuresRemaining = 3;
  XCTestExpectation *third = [self expectationWithDescription:@"third attempt"];
  self.identityStore.replacementObserver = ^{ if (self.identityStore.replaceCount == 3) [third fulfill]; };
  MPAutoFillIdentityStoreUpdater *updater = self.updater;
  [updater synchronize];
  [self waitForExpectations:@[third] timeout:2];
  XCTAssertEqual(self.identityStore.replaceCount, 3u);
  XCTAssertEqual(updater.lastAttemptCount, 3u);
  XCTAssertEqual(updater.state, MPAutoFillIdentitySyncStateFailed);
}

- (void)testRemovingPublicationProducesReplacementWithoutItsIdentity {
  NSString *first = @"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
  NSString *second = @"cccccccc-cccc-cccc-cccc-cccccccccccc";
  [self publishEntry:@"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" publication:first generation:@"dddddddd-dddd-dddd-dddd-dddddddddddd"];
  [self publishEntry:@"ffffffff-ffff-ffff-ffff-ffffffffffff" publication:second generation:@"eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"];
  [self.publications addObjectsFromArray:@[first, second]];
  MPAutoFillIdentityStoreUpdater *updater = self.updater;
  XCTestExpectation *firstSync = [self expectationWithDescription:@"first"];
  self.identityStore.replacementObserver = ^{ [firstSync fulfill]; };
  [updater synchronize];
  [self waitForExpectations:@[firstSync] timeout:2];
  [self.publications removeObject:second];
  XCTestExpectation *secondSync = [self expectationWithDescription:@"second"];
  self.identityStore.replacementObserver = ^{ [secondSync fulfill]; };
  [updater synchronize];
  [self waitForExpectations:@[secondSync] timeout:2];
  XCTAssertEqual(self.identityStore.lastIdentities.count, 1u);
  XCTAssertTrue([[[self.identityStore.lastIdentities firstObject] recordIdentifier] containsString:first]);
}

- (void)testPublicationWithoutActiveGenerationIsOmittedFromCompleteReplacement {
  NSString *active = @"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
  NSString *revoked = @"cccccccc-cccc-cccc-cccc-cccccccccccc";
  [self publishEntry:@"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" publication:active
      generation:@"dddddddd-dddd-dddd-dddd-dddddddddddd"];
  [self.publications addObjectsFromArray:@[active, revoked]];
  XCTestExpectation *replacement = [self expectationWithDescription:@"replacement"];
  self.identityStore.replacementObserver = ^{ [replacement fulfill]; };
  [self.updater synchronize];
  [self waitForExpectations:@[replacement] timeout:2];
  XCTAssertEqual(self.identityStore.lastIdentities.count, 1u);
}

- (void)testSynchronizationCompletionRunsAfterIdentityReplacement {
  NSString *publication = @"eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee";
  [self publishEntry:@"ffffffff-ffff-ffff-ffff-ffffffffffff" publication:publication
      generation:@"11111111-1111-1111-1111-111111111111"];
  [self.publications addObject:publication];
  XCTestExpectation *completion = [self expectationWithDescription:@"synchronization completion"];
  MPAutoFillIdentityStoreUpdater *updater = self.updater;
  [updater synchronizeWithCompletion:^(NSError *error) {
    XCTAssertNil(error);
    XCTAssertEqual(self.identityStore.replaceCount, 1u);
    XCTAssertEqual(updater.state, MPAutoFillIdentitySyncStateSucceeded);
    [completion fulfill];
  }];
  [self waitForExpectationsWithTimeout:1 handler:nil];
}

@end
