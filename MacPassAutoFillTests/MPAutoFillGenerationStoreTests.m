#import <XCTest/XCTest.h>

#import "MPAutoFillCredentialRecord.h"
#import "MPAutoFillErrors.h"
#import "MPAutoFillGenerationStore.h"
#import "MPAutoFillVaultIndex.h"

@interface MPAutoFillFakeGenerationPointer : NSObject <MPAutoFillCurrentGenerationStore>
@property(nonatomic, copy) NSMutableDictionary<NSString *, NSString *> *generations;
@property(nonatomic) BOOL failActivation;
@end

@implementation MPAutoFillFakeGenerationPointer
- (instancetype)init {
  self = [super init];
  if (self) _generations = [NSMutableDictionary dictionary];
  return self;
}
- (NSString *)currentGenerationForPublicationIdentifier:(NSString *)publicationIdentifier error:(NSError **)error {
  NSString *value = self.generations[publicationIdentifier];
  if (!value && error) *error = MPAutoFillError(MPAutoFillErrorItemNotFound, @"No active generation.", nil);
  return value;
}
- (BOOL)setCurrentGeneration:(NSString *)generationIdentifier forPublicationIdentifier:(NSString *)publicationIdentifier error:(NSError **)error {
  if (self.failActivation) {
    if (error) *error = MPAutoFillError(MPAutoFillErrorKeychainUnavailable, @"Activation failed.", nil);
    return NO;
  }
  self.generations[publicationIdentifier] = generationIdentifier;
  return YES;
}
- (BOOL)deleteCurrentGenerationForPublicationIdentifier:(NSString *)publicationIdentifier error:(NSError **)error {
  [self.generations removeObjectForKey:publicationIdentifier];
  return YES;
}
@end

@interface MPAutoFillGenerationStoreTests : XCTestCase
@property(nonatomic, strong) NSURL *rootURL;
@property(nonatomic, strong) MPAutoFillFakeGenerationPointer *pointer;
@property(nonatomic, strong) MPAutoFillGenerationStore *store;
@end

@implementation MPAutoFillGenerationStoreTests

- (void)setUp {
  [super setUp];
  self.rootURL = [NSFileManager.defaultManager.temporaryDirectory
      URLByAppendingPathComponent:[NSString stringWithFormat:@"MPAutoFillGenerationStoreTests-%@", NSUUID.UUID.UUIDString]
      isDirectory:YES];
  self.pointer = [[MPAutoFillFakeGenerationPointer alloc] init];
  self.store = [[MPAutoFillGenerationStore alloc] initWithRootURL:self.rootURL currentGenerationStore:self.pointer error:NULL];
  XCTAssertNotNil(self.store);
}

- (void)tearDown {
  [NSFileManager.defaultManager removeItemAtURL:self.rootURL error:NULL];
  [super tearDown];
}

- (MPAutoFillVaultIndex *)indexWithGeneration:(NSString *)generation {
  return [self indexWithGeneration:generation publication:@"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"];
}

- (MPAutoFillVaultIndex *)indexWithGeneration:(NSString *)generation publication:(NSString *)publication {
  MPAutoFillCredentialRecord *credential = [[MPAutoFillCredentialRecord alloc]
      initWithEntryIdentifier:@"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" title:@"Example"
      username:@"user" password:@"secret" serviceIdentifiers:@[@"https://example.com"]
      modificationTime:1 rank:0 error:NULL];
  return [[MPAutoFillVaultIndex alloc]
      initWithPublicationIdentifier:publication
      generationIdentifier:generation
      records:@[[MPAutoFillVaultIndexRecord recordWithCredentialRecord:credential]] error:NULL];
}

- (BOOL)publishIndex:(MPAutoFillVaultIndex *)index secrets:(NSData *)secrets error:(NSError **)error {
  NSData *data = [index serializedDataWithError:error];
  return [self.store publishIndexData:data validatedIndex:index encryptedSecrets:secrets error:error];
}

- (void)publishGeneration:(NSString *)generation publication:(NSString *)publication marker:(NSString *)marker {
  NSError *error = nil;
  XCTAssertTrue([self publishIndex:[self indexWithGeneration:generation publication:publication]
      secrets:[marker dataUsingEncoding:NSUTF8StringEncoding] error:&error]);
  XCTAssertNil(error);
}

- (NSURL *)generationURL:(NSString *)generation {
  return [[[[[self.rootURL URLByAppendingPathComponent:@"Vaults" isDirectory:YES]
      URLByAppendingPathComponent:@"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb" isDirectory:YES]
      URLByAppendingPathComponent:@"generations" isDirectory:YES]
      URLByAppendingPathComponent:generation isDirectory:YES] URLByStandardizingPath];
}

- (NSURL *)writeRegistryData:(NSData *)data {
  NSURL *URL = [self.rootURL URLByAppendingPathComponent:@"registry.plist"];
  XCTAssertTrue([data writeToURL:URL options:NSDataWritingAtomic error:NULL]);
  XCTAssertTrue([NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: @0600}
                                                      ofItemAtPath:URL.path error:NULL]);
  return URL;
}

- (void)testRegistryReadValidatesFileAndRootMetadata {
  NSData *expected = [@"registry" dataUsingEncoding:NSUTF8StringEncoding];
  NSURL *registryURL = [self writeRegistryData:expected];
  NSError *error = nil;
  XCTAssertEqualObjects([MPAutoFillGenerationStore registryDataAtRootURL:self.rootURL error:&error], expected);
  XCTAssertNil(error);

  XCTAssertEqual(chmod(registryURL.fileSystemRepresentation, 0644), 0);
  XCTAssertNil([MPAutoFillGenerationStore registryDataAtRootURL:self.rootURL error:&error]);
  XCTAssertEqual(error.code, MPAutoFillErrorUnsafeFile);
  XCTAssertEqual(chmod(registryURL.fileSystemRepresentation, 0600), 0);

  XCTAssertEqual(chmod(self.rootURL.fileSystemRepresentation, 0755), 0);
  XCTAssertNil([MPAutoFillGenerationStore registryDataAtRootURL:self.rootURL error:&error]);
  XCTAssertEqual(error.code, MPAutoFillErrorUnsafeFile);
}

- (void)testRegistryReadRejectsSymlinkAndHardLink {
  NSURL *registryURL = [self writeRegistryData:[@"registry" dataUsingEncoding:NSUTF8StringEncoding]];
  NSURL *targetURL = [self.rootURL URLByAppendingPathComponent:@"target.plist"];
  XCTAssertTrue([NSFileManager.defaultManager moveItemAtURL:registryURL toURL:targetURL error:NULL]);
  XCTAssertTrue([NSFileManager.defaultManager createSymbolicLinkAtURL:registryURL
                                           withDestinationURL:targetURL error:NULL]);
  NSError *error = nil;
  XCTAssertNil([MPAutoFillGenerationStore registryDataAtRootURL:self.rootURL error:&error]);
  XCTAssertNotNil(error);

  XCTAssertTrue([NSFileManager.defaultManager removeItemAtURL:registryURL error:NULL]);
  XCTAssertEqual(link(targetURL.fileSystemRepresentation, registryURL.fileSystemRepresentation), 0);
  XCTAssertNil([MPAutoFillGenerationStore registryDataAtRootURL:self.rootURL error:&error]);
  XCTAssertEqual(error.code, MPAutoFillErrorUnsafeFile);
}

- (void)testMissingRegistryIsReportedWithoutCreatingIt {
  NSError *error = nil;
  XCTAssertNil([MPAutoFillGenerationStore registryDataAtRootURL:self.rootURL error:&error]);
  XCTAssertEqual(error.code, MPAutoFillErrorItemNotFound);
  XCTAssertFalse([NSFileManager.defaultManager fileExistsAtPath:
      [self.rootURL URLByAppendingPathComponent:@"registry.plist"].path]);
}

- (void)testPublishesFilesBeforeActivationAndReadsOneGeneration {
  NSString *generation = @"cccccccc-cccc-cccc-cccc-cccccccccccc";
  NSData *secrets = [@"encrypted-envelope" dataUsingEncoding:NSUTF8StringEncoding];
  NSError *error = nil;
  XCTAssertTrue([self publishIndex:[self indexWithGeneration:generation] secrets:secrets error:&error]);
  XCTAssertEqualObjects(self.pointer.generations[@"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"], generation);
  MPAutoFillGeneration *current = [self.store
      currentGenerationForPublicationIdentifier:@"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb" error:&error];
  XCTAssertEqualObjects(current.generationIdentifier, generation);
  XCTAssertEqualObjects(current.encryptedSecrets, secrets);
  XCTAssertEqual(current.indexDigest.length, 32u);
  XCTAssertNil(error);
}

- (void)testFailedActivationPreservesPreviousCurrentGeneration {
  NSString *oldGeneration = @"cccccccc-cccc-cccc-cccc-cccccccccccc";
  NSString *newGeneration = @"dddddddd-dddd-dddd-dddd-dddddddddddd";
  XCTAssertTrue([self publishIndex:[self indexWithGeneration:oldGeneration]
                           secrets:[@"old" dataUsingEncoding:NSUTF8StringEncoding] error:NULL]);
  self.pointer.failActivation = YES;
  NSError *error = nil;
  XCTAssertFalse([self publishIndex:[self indexWithGeneration:newGeneration]
                            secrets:[@"new" dataUsingEncoding:NSUTF8StringEncoding] error:&error]);
  XCTAssertEqualObjects(self.pointer.generations[@"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"], oldGeneration);
  self.pointer.failActivation = NO;
  MPAutoFillGeneration *current = [self.store
      currentGenerationForPublicationIdentifier:@"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb" error:&error];
  XCTAssertEqualObjects(current.encryptedSecrets, [@"old" dataUsingEncoding:NSUTF8StringEncoding]);
  XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:[self generationURL:newGeneration].path]);
}

- (void)testCorruptCurrentFailsClosedWithoutOlderFallback {
  NSString *oldGeneration = @"cccccccc-cccc-cccc-cccc-cccccccccccc";
  NSString *newGeneration = @"dddddddd-dddd-dddd-dddd-dddddddddddd";
  XCTAssertTrue([self publishIndex:[self indexWithGeneration:oldGeneration]
                           secrets:[@"old" dataUsingEncoding:NSUTF8StringEncoding] error:NULL]);
  XCTAssertTrue([self publishIndex:[self indexWithGeneration:newGeneration]
                           secrets:[@"new" dataUsingEncoding:NSUTF8StringEncoding] error:NULL]);
  NSURL *secretsURL = [[self generationURL:newGeneration] URLByAppendingPathComponent:@"secrets.bin"];
  XCTAssertTrue([NSFileManager.defaultManager removeItemAtURL:secretsURL error:NULL]);
  NSError *error = nil;
  XCTAssertNil([self.store currentGenerationForPublicationIdentifier:@"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb" error:&error]);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(self.pointer.generations[@"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"], newGeneration);
}

- (void)testUnsafePermissionsAndSymlinkFailClosed {
  NSString *generation = @"cccccccc-cccc-cccc-cccc-cccccccccccc";
  XCTAssertTrue([self publishIndex:[self indexWithGeneration:generation]
                           secrets:[@"encrypted" dataUsingEncoding:NSUTF8StringEncoding] error:NULL]);
  NSURL *indexURL = [[self generationURL:generation] URLByAppendingPathComponent:@"index.plist"];
  XCTAssertEqual(chmod(indexURL.fileSystemRepresentation, 0644), 0);
  NSError *error = nil;
  XCTAssertNil([self.store currentGenerationForPublicationIdentifier:@"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb" error:&error]);
  XCTAssertEqual(error.code, MPAutoFillErrorUnsafeFile);
}

- (void)testSymlinkedFileFailsClosed {
  NSString *generation = @"cccccccc-cccc-cccc-cccc-cccccccccccc";
  XCTAssertTrue([self publishIndex:[self indexWithGeneration:generation]
                           secrets:[@"encrypted" dataUsingEncoding:NSUTF8StringEncoding] error:NULL]);
  NSURL *secretsURL = [[self generationURL:generation] URLByAppendingPathComponent:@"secrets.bin"];
  NSURL *outsideURL = [self.rootURL URLByAppendingPathComponent:@"outside.bin"];
  XCTAssertTrue([@"outside" writeToURL:outsideURL atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
  XCTAssertTrue([NSFileManager.defaultManager removeItemAtURL:secretsURL error:NULL]);
  XCTAssertTrue([NSFileManager.defaultManager createSymbolicLinkAtURL:secretsURL
                                                  withDestinationURL:outsideURL error:NULL]);
  NSError *error = nil;
  XCTAssertNil([self.store currentGenerationForPublicationIdentifier:@"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb" error:&error]);
  XCTAssertNotNil(error);
}

- (void)testSwappedIndexFromAnotherGenerationFailsClosed {
  NSString *first = @"cccccccc-cccc-cccc-cccc-cccccccccccc";
  NSString *second = @"dddddddd-dddd-dddd-dddd-dddddddddddd";
  XCTAssertTrue([self publishIndex:[self indexWithGeneration:first]
                           secrets:[@"first" dataUsingEncoding:NSUTF8StringEncoding] error:NULL]);
  XCTAssertTrue([self publishIndex:[self indexWithGeneration:second]
                           secrets:[@"second" dataUsingEncoding:NSUTF8StringEncoding] error:NULL]);
  NSURL *firstIndex = [[self generationURL:first] URLByAppendingPathComponent:@"index.plist"];
  NSURL *secondIndex = [[self generationURL:second] URLByAppendingPathComponent:@"index.plist"];
  NSData *firstData = [NSData dataWithContentsOfURL:firstIndex];
  XCTAssertTrue([NSFileManager.defaultManager removeItemAtURL:secondIndex error:NULL]);
  XCTAssertTrue([firstData writeToURL:secondIndex options:0 error:NULL]);
  XCTAssertEqual(chmod(secondIndex.fileSystemRepresentation, 0600), 0);
  NSError *error = nil;
  XCTAssertNil([self.store currentGenerationForPublicationIdentifier:@"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb" error:&error]);
  XCTAssertEqual(error.code, MPAutoFillErrorContextMismatch);
}

- (void)testConcurrentReadersObserveCompleteOldOrNewGeneration {
  NSString *first = @"cccccccc-cccc-cccc-cccc-cccccccccccc";
  NSString *second = @"dddddddd-dddd-dddd-dddd-dddddddddddd";
  XCTAssertTrue([self publishIndex:[self indexWithGeneration:first]
                           secrets:[@"first" dataUsingEncoding:NSUTF8StringEncoding] error:NULL]);
  dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
  dispatch_group_t group = dispatch_group_create();
  __block BOOL invalidResult = NO;
  for (NSUInteger reader = 0; reader < 8; reader++) {
    dispatch_group_async(group, queue, ^{
      for (NSUInteger attempt = 0; attempt < 50; attempt++) {
        MPAutoFillGeneration *generation = [self.store
            currentGenerationForPublicationIdentifier:@"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb" error:NULL];
        NSString *value = [[NSString alloc] initWithData:generation.encryptedSecrets encoding:NSUTF8StringEncoding];
        if (![value isEqualToString:@"first"] && ![value isEqualToString:@"second"]) invalidResult = YES;
      }
    });
  }
  XCTAssertTrue([self publishIndex:[self indexWithGeneration:second]
                           secrets:[@"second" dataUsingEncoding:NSUTF8StringEncoding] error:NULL]);
  XCTAssertEqual(dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)), 0L);
  XCTAssertFalse(invalidResult);
}

- (void)testCleanupIsBoundedAndRetainsCurrentAndPrevious {
  NSArray *generations = @[
    @"cccccccc-cccc-cccc-cccc-cccccccccccc", @"dddddddd-dddd-dddd-dddd-dddddddddddd",
    @"eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee", @"ffffffff-ffff-ffff-ffff-ffffffffffff",
  ];
  for (NSString *generation in generations) {
    XCTAssertTrue([self publishIndex:[self indexWithGeneration:generation]
                             secrets:[generation dataUsingEncoding:NSUTF8StringEncoding] error:NULL]);
  }
  XCTAssertTrue([self.store removeOrphanedGenerationsForPublicationIdentifier:@"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
      retainingGenerations:[NSSet setWithObject:@"eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"] limit:1 error:NULL]);
  NSUInteger count = [NSFileManager.defaultManager contentsOfDirectoryAtURL:
      [[self generationURL:generations.firstObject] URLByDeletingLastPathComponent]
      includingPropertiesForKeys:nil options:0 error:NULL].count;
  XCTAssertEqual(count, 3u);
  XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:[self generationURL:generations.lastObject].path]);
  XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:[self generationURL:@"eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"].path]);
}

- (void)testRemovingPublicationDataDeletesAllGenerationsAndIsIdempotent {
  NSString *publication = @"99999999-9999-9999-9999-999999999999";
  [self publishGeneration:@"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" publication:publication marker:@"first"];
  [self publishGeneration:@"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb" publication:publication marker:@"second"];

  NSError *error = nil;
  XCTAssertTrue([self.store removePublicationDataForPublicationIdentifier:publication error:&error]);
  XCTAssertNil(error);
  NSURL *publicationURL = [[self.rootURL URLByAppendingPathComponent:@"Vaults"]
      URLByAppendingPathComponent:publication];
  XCTAssertFalse([NSFileManager.defaultManager fileExistsAtPath:publicationURL.path]);
  XCTAssertTrue([self.store removePublicationDataForPublicationIdentifier:publication error:&error]);
}

- (void)testPublicationEnumerationReturnsOnlyValidatedCanonicalDirectories {
  NSString *first = @"99999999-9999-9999-9999-999999999999";
  NSString *second = @"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
  [self publishGeneration:@"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb" publication:first marker:@"first"];
  [self publishGeneration:@"cccccccc-cccc-cccc-cccc-cccccccccccc" publication:second marker:@"second"];

  NSError *error = nil;
  XCTAssertEqualObjects([self.store publicationIdentifiersWithError:&error], (@[first, second]));
  XCTAssertNil(error);

  NSURL *unexpected = [[self.rootURL URLByAppendingPathComponent:@"Vaults"] URLByAppendingPathComponent:@"unexpected"];
  XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtURL:unexpected withIntermediateDirectories:NO
      attributes:@{NSFilePosixPermissions: @0700} error:NULL]);
  XCTAssertNil([self.store publicationIdentifiersWithError:&error]);
  XCTAssertEqual(error.code, MPAutoFillErrorUnsafeFile);
}

@end
