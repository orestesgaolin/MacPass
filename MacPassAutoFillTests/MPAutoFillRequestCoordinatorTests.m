#import <AuthenticationServices/AuthenticationServices.h>
#import <CommonCrypto/CommonDigest.h>
#import <mach/mach.h>
#import <sys/stat.h>
#import <XCTest/XCTest.h>

#import "MPAutoFillCredentialIdentifier.h"
#import "MPAutoFillCredentialRecord.h"
#import "MPAutoFillEnvelopeCrypto.h"
#import "MPAutoFillErrors.h"
#import "MPAutoFillGenerationStore.h"
#import "MPAutoFillRequestCoordinator.h"
#import "MPAutoFillSnapshot.h"
#import "MPAutoFillVaultIndex.h"

@interface MPAutoFillRequestTestKeyStore : NSObject <MPAutoFillCurrentGenerationStore, MPAutoFillPrivateKeyStore>
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *generations;
@property(nonatomic) SecKeyRef privateKey;
@end

@implementation MPAutoFillRequestTestKeyStore
- (instancetype)init { self = [super init]; if (self) _generations = [NSMutableDictionary dictionary]; return self; }
- (void)dealloc { if (_privateKey) CFRelease(_privateKey); }
- (NSString *)currentGenerationForPublicationIdentifier:(NSString *)publication error:(NSError **)error {
  NSString *generation = self.generations[publication];
  if (!generation && error) *error = MPAutoFillError(MPAutoFillErrorItemNotFound, @"Missing generation.", nil);
  return generation;
}
- (BOOL)setCurrentGeneration:(NSString *)generation forPublicationIdentifier:(NSString *)publication error:(NSError **)error {
  self.generations[publication] = generation; return YES;
}
- (BOOL)deleteCurrentGenerationForPublicationIdentifier:(NSString *)publication error:(NSError **)error {
  [self.generations removeObjectForKey:publication]; return YES;
}
- (SecKeyRef)copyPrivateKeyForPublicationIdentifier:(NSString *)publication
                              authenticationContext:(LAContext *)context
                                 interactionAllowed:(BOOL)interactionAllowed error:(NSError **)error {
  if (!interactionAllowed) {
    if (error) *error = MPAutoFillError(MPAutoFillErrorUserInteractionRequired, @"Authentication required.", nil);
    return nil;
  }
  return self.privateKey ? (SecKeyRef)CFRetain(self.privateKey) : nil;
}
@end

@interface MPAutoFillRequestCoordinatorTests : XCTestCase
@property(nonatomic, strong) NSURL *rootURL;
@property(nonatomic, strong) MPAutoFillRequestTestKeyStore *keyStore;
@property(nonatomic, strong) MPAutoFillGenerationStore *generationStore;
@property(nonatomic, strong) MPAutoFillRequestCoordinator *coordinator;
@property(nonatomic, copy) NSString *publication;
@property(nonatomic, copy) NSString *generation;
@property(nonatomic, copy) NSString *entry;
@end

@implementation MPAutoFillRequestCoordinatorTests

static uint64_t MPAutoFillPhysicalFootprint(void) {
  task_vm_info_data_t info;
  mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
  kern_return_t result = task_info(mach_task_self(), TASK_VM_INFO,
      (task_info_t)&info, &count);
  return result == KERN_SUCCESS ? info.phys_footprint : 0;
}

- (void)setUp {
  [super setUp];
  self.publication = @"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
  self.generation = @"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
  self.entry = @"cccccccc-cccc-cccc-cccc-cccccccccccc";
  self.rootURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
      [NSString stringWithFormat:@"MPAutoFillRequestTests-%@", NSUUID.UUID.UUIDString]] isDirectory:YES];
  self.keyStore = [[MPAutoFillRequestTestKeyStore alloc] init];
  NSDictionary *attributes = @{(__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeRSA,
                               (__bridge id)kSecAttrKeySizeInBits: @2048};
  self.keyStore.privateKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes, NULL);
  self.generationStore = [[MPAutoFillGenerationStore alloc] initWithRootURL:self.rootURL
      currentGenerationStore:self.keyStore error:NULL];
  self.coordinator = [[MPAutoFillRequestCoordinator alloc] initWithGenerationStore:self.generationStore
      keychainStore:self.keyStore rootURL:self.rootURL];
  [self writeRegistryWithPublications:@[self.publication]];
}

- (void)tearDown {
  [NSFileManager.defaultManager removeItemAtURL:self.rootURL error:NULL];
  [super tearDown];
}

- (MPAutoFillCredentialRecord *)recordWithEntry:(NSString *)entry title:(NSString *)title service:(NSString *)service rank:(int64_t)rank {
  return [[MPAutoFillCredentialRecord alloc] initWithEntryIdentifier:entry title:title username:title.lowercaseString
      password:@"secret" serviceIdentifiers:@[service] modificationTime:1 rank:rank error:NULL];
}

- (void)publishRecords:(NSArray<MPAutoFillCredentialRecord *> *)records {
  [self publishRecords:records publication:self.publication generation:self.generation];
}

- (void)publishRecords:(NSArray<MPAutoFillCredentialRecord *> *)records
           publication:(NSString *)publication
            generation:(NSString *)generation {
  NSMutableArray *indexRecords = [NSMutableArray array];
  for (MPAutoFillCredentialRecord *record in records) [indexRecords addObject:[MPAutoFillVaultIndexRecord recordWithCredentialRecord:record]];
  MPAutoFillVaultIndex *index = [[MPAutoFillVaultIndex alloc] initWithPublicationIdentifier:publication
      generationIdentifier:generation records:indexRecords error:NULL];
  NSData *indexData = [index serializedDataWithError:NULL];
  uint8_t digestBytes[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(indexData.bytes, (CC_LONG)indexData.length, digestBytes);
  NSData *digest = [NSData dataWithBytes:digestBytes length:sizeof(digestBytes)];
  MPAutoFillSnapshot *snapshot = [[MPAutoFillSnapshot alloc] initWithPublicationIdentifier:publication
      generationIdentifier:generation indexDigest:digest records:records error:NULL];
  SecKeyRef publicKey = SecKeyCopyPublicKey(self.keyStore.privateKey);
  NSData *envelope = [MPAutoFillEnvelopeCrypto encryptSnapshot:snapshot withPublicKey:publicKey error:NULL];
  CFRelease(publicKey);
  XCTAssertTrue([self.generationStore publishIndexData:indexData validatedIndex:index encryptedSecrets:envelope error:NULL]);
}

- (void)writeRegistryWithPublications:(NSArray<NSString *> *)publications {
  NSMutableArray *records = [NSMutableArray arrayWithCapacity:publications.count];
  for (NSString *publication in publications) [records addObject:@{
    @"publication": publication,
    @"root": @"ffffffff-ffff-ffff-ffff-ffffffffffff",
    @"bookmark": NSData.data,
    @"path": @"/tmp/Database.kdbx",
  }];
  NSDictionary *registry = @{@"schema": @1, @"publications": records};
  NSData *data = [NSPropertyListSerialization dataWithPropertyList:registry
      format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
  NSURL *registryURL = [self.rootURL URLByAppendingPathComponent:@"registry.plist"];
  XCTAssertTrue([data writeToURL:registryURL options:NSDataWritingAtomic error:NULL]);
  XCTAssertTrue([NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: @0600}
                                                      ofItemAtPath:registryURL.path error:NULL]);
}

- (void)writeRegistryPropertyList:(NSDictionary *)registry {
  NSData *data = [NSPropertyListSerialization dataWithPropertyList:registry
      format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
  NSURL *registryURL = [self.rootURL URLByAppendingPathComponent:@"registry.plist"];
  XCTAssertTrue([data writeToURL:registryURL options:NSDataWritingAtomic error:NULL]);
  XCTAssertTrue([NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: @0600}
      ofItemAtPath:registryURL.path error:NULL]);
}

- (void)forgeCurrentIndexTitle:(NSString *)title {
  NSURL *indexURL = [[self generationURLForPublication:self.publication generation:self.generation]
      URLByAppendingPathComponent:@"index.plist"];
  NSMutableDictionary *root = [[NSPropertyListSerialization propertyListWithData:[NSData dataWithContentsOfURL:indexURL]
      options:NSPropertyListMutableContainers format:NULL error:NULL] mutableCopy];
  NSMutableDictionary *record = [root[@"records"][0] mutableCopy];
  record[@"title"] = title;
  root[@"records"] = @[record];
  NSData *data = [NSPropertyListSerialization dataWithPropertyList:root
      format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
  XCTAssertTrue([data writeToURL:indexURL options:0 error:NULL]);
}

- (ASPasswordCredentialIdentity *)identityForService:(NSString *)service {
  return [self identityForService:service publication:self.publication entry:self.entry];
}

- (ASPasswordCredentialIdentity *)identityForService:(NSString *)service
                                         publication:(NSString *)publication
                                               entry:(NSString *)entry {
  ASCredentialServiceIdentifier *serviceIdentifier = [[ASCredentialServiceIdentifier alloc]
      initWithIdentifier:service type:ASCredentialServiceIdentifierTypeURL];
  MPAutoFillCredentialIdentifier *identifier = [MPAutoFillCredentialIdentifier
      identifierWithPublicationIdentifier:publication entryIdentifier:entry error:NULL];
  return [[ASPasswordCredentialIdentity alloc] initWithServiceIdentifier:serviceIdentifier user:@"example"
                                                         recordIdentifier:identifier.recordIdentifier];
}

- (NSURL *)generationURLForPublication:(NSString *)publication generation:(NSString *)generation {
  return [[[[[self.rootURL URLByAppendingPathComponent:@"Vaults" isDirectory:YES]
      URLByAppendingPathComponent:publication isDirectory:YES]
      URLByAppendingPathComponent:@"generations" isDirectory:YES]
      URLByAppendingPathComponent:generation isDirectory:YES] URLByStandardizingPath];
}

- (void)testNoninteractiveRequestRequiresUserInteraction {
  [self publishRecords:@[[self recordWithEntry:self.entry title:@"Example" service:@"https://example.com" rank:0]]];
  NSError *error = nil;
  XCTAssertNil([self.coordinator credentialForIdentity:[self identityForService:@"https://example.com"]
                                    interactionAllowed:NO error:&error]);
  XCTAssertEqual(error.code, MPAutoFillErrorUserInteractionRequired);
}

- (void)testInteractiveRequestFillsOnlyExactRequestedService {
  [self publishRecords:@[[self recordWithEntry:self.entry title:@"Example" service:@"https://example.com" rank:0]]];
  NSError *error = nil;
  ASPasswordCredential *credential = [self.coordinator credentialForIdentity:[self identityForService:@"https://example.com/login"]
                                                          interactionAllowed:YES error:&error];
  XCTAssertEqualObjects(credential.user, @"example");
  XCTAssertNil(error);
  XCTAssertNil([self.coordinator credentialForIdentity:[self identityForService:@"https://example.com.attacker.test"]
                                    interactionAllowed:YES error:&error]);
  XCTAssertEqual(error.code, MPAutoFillErrorItemNotFound);
}

- (void)testAuthenticatedListRanksExactMatchesBeforeOtherCredentials {
  MPAutoFillCredentialRecord *other = [self recordWithEntry:@"dddddddd-dddd-dddd-dddd-dddddddddddd"
      title:@"Other" service:@"https://other.test" rank:100];
  MPAutoFillCredentialRecord *exact = [self recordWithEntry:self.entry title:@"Exact"
      service:@"https://example.com" rank:0];
  [self publishRecords:@[other, exact]];
  [self writeRegistryWithPublications:@[self.publication]];
  ASCredentialServiceIdentifier *service = [[ASCredentialServiceIdentifier alloc]
      initWithIdentifier:@"https://example.com" type:ASCredentialServiceIdentifierTypeURL];
  NSArray<MPAutoFillCredentialSelection *> *selections = [self.coordinator
      credentialsForServiceIdentifiers:@[service] error:NULL];
  XCTAssertEqual(selections.count, 2u);
  XCTAssertEqualObjects(selections[0].title, @"Exact");
  XCTAssertEqualObjects(selections[1].title, @"Other");
}

- (void)testAuthenticatedListKeepsCollidingEntryIdentifiersSeparateAcrossVaults {
  NSString *secondPublication = @"dddddddd-dddd-dddd-dddd-dddddddddddd";
  NSString *secondGeneration = @"eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee";
  [self publishRecords:@[[self recordWithEntry:self.entry title:@"First" service:@"https://example.com" rank:0]]
            publication:self.publication generation:self.generation];
  [self publishRecords:@[[self recordWithEntry:self.entry title:@"Second" service:@"https://example.com" rank:0]]
            publication:secondPublication generation:secondGeneration];
  [self writeRegistryWithPublications:@[self.publication, secondPublication]];

  ASCredentialServiceIdentifier *service = [[ASCredentialServiceIdentifier alloc]
      initWithIdentifier:@"https://example.com" type:ASCredentialServiceIdentifierTypeURL];
  NSArray<MPAutoFillCredentialSelection *> *selections = [self.coordinator
      credentialsForServiceIdentifiers:@[service] error:NULL];

  XCTAssertEqual(selections.count, 2u);
  XCTAssertEqualObjects(selections[0].title, @"First");
  XCTAssertEqualObjects(selections[1].title, @"Second");
}

- (void)testAuthenticatedListRejectsDuplicateRegistryPublication {
  [self publishRecords:@[[self recordWithEntry:self.entry title:@"Example"
      service:@"https://example.com" rank:0]]];
  [self writeRegistryWithPublications:@[self.publication, self.publication]];
  ASCredentialServiceIdentifier *service = [[ASCredentialServiceIdentifier alloc]
      initWithIdentifier:@"https://example.com" type:ASCredentialServiceIdentifierTypeURL];
  NSError *error = nil;

  XCTAssertNil([self.coordinator credentialsForServiceIdentifiers:@[service] error:&error]);
  XCTAssertEqual(error.code, MPAutoFillErrorMalformedSnapshot);
}

- (void)testRegistryRejectsFutureSchemaAndUnknownFields {
  ASCredentialServiceIdentifier *service = [[ASCredentialServiceIdentifier alloc]
      initWithIdentifier:@"https://example.com" type:ASCredentialServiceIdentifierTypeURL];
  for (NSDictionary *registry in @[
      @{@"schema": @2, @"publications": @[]},
      @{@"schema": @1, @"publications": @[], @"future": @1},
      @{@"schema": @1, @"publications": @[@{@"publication": self.publication, @"future": @1}]},
  ]) {
    [self writeRegistryPropertyList:registry];
    NSError *error = nil;
    XCTAssertNil([self.coordinator credentialsForServiceIdentifiers:@[service] error:&error]);
    XCTAssertEqual(error.code, MPAutoFillErrorMalformedSnapshot);
  }
}

- (void)testMalformedAndStaleIdentitiesFailClosed {
  [self publishRecords:@[[self recordWithEntry:self.entry title:@"Example"
      service:@"https://example.com" rank:0]]];
  ASCredentialServiceIdentifier *service = [[ASCredentialServiceIdentifier alloc]
      initWithIdentifier:@"https://example.com" type:ASCredentialServiceIdentifierTypeURL];
  ASPasswordCredentialIdentity *malformed = [[ASPasswordCredentialIdentity alloc]
      initWithServiceIdentifier:service user:@"example" recordIdentifier:@"v2:invalid"];
  NSError *error = nil;

  XCTAssertNil([self.coordinator credentialForIdentity:malformed interactionAllowed:YES error:&error]);
  XCTAssertEqual(error.code, MPAutoFillErrorInvalidArgument);

  error = nil;
  XCTAssertNil([self.coordinator credentialForIdentity:[self identityForService:@"https://example.com"
      publication:self.publication entry:@"dddddddd-dddd-dddd-dddd-dddddddddddd"]
      interactionAllowed:YES error:&error]);
  XCTAssertEqual(error.code, MPAutoFillErrorItemNotFound);
}

- (void)testMissingPointerAndGenerationFailClosed {
  [self publishRecords:@[[self recordWithEntry:self.entry title:@"Example"
      service:@"https://example.com" rank:0]]];
  ASPasswordCredentialIdentity *identity = [self identityForService:@"https://example.com"];
  [self.keyStore.generations removeObjectForKey:self.publication];
  NSError *error = nil;
  XCTAssertNil([self.coordinator credentialForIdentity:identity interactionAllowed:YES error:&error]);
  XCTAssertEqual(error.code, MPAutoFillErrorItemNotFound);

  self.keyStore.generations[self.publication] = self.generation;
  XCTAssertTrue([NSFileManager.defaultManager removeItemAtURL:
      [self generationURLForPublication:self.publication generation:self.generation] error:NULL]);
  error = nil;
  XCTAssertNil([self.coordinator credentialForIdentity:identity interactionAllowed:YES error:&error]);
  XCTAssertNotNil(error);
}

- (void)testMissingRegistryAndRemovedPublicationFailClosedForDirectIdentity {
  [self publishRecords:@[[self recordWithEntry:self.entry title:@"Example"
      service:@"https://example.com" rank:0]]];
  ASPasswordCredentialIdentity *identity = [self identityForService:@"https://example.com"];
  NSURL *registryURL = [self.rootURL URLByAppendingPathComponent:@"registry.plist"];
  XCTAssertTrue([NSFileManager.defaultManager removeItemAtURL:registryURL error:NULL]);
  NSError *error = nil;
  XCTAssertNil([self.coordinator credentialForIdentity:identity interactionAllowed:YES error:&error]);
  XCTAssertEqual(error.code, MPAutoFillErrorItemNotFound);

  [self writeRegistryWithPublications:@[]];
  error = nil;
  XCTAssertNil([self.coordinator credentialForIdentity:identity interactionAllowed:YES error:&error]);
  XCTAssertEqual(error.code, MPAutoFillErrorItemNotFound);
}

- (void)testTamperedEncryptedSecretsFailClosedAtRequestBoundary {
  [self publishRecords:@[[self recordWithEntry:self.entry title:@"Example"
      service:@"https://example.com" rank:0]]];
  NSURL *secretsURL = [[self generationURLForPublication:self.publication generation:self.generation]
      URLByAppendingPathComponent:@"secrets.bin"];
  NSMutableData *tampered = [[NSData dataWithContentsOfURL:secretsURL] mutableCopy];
  ((uint8_t *)tampered.mutableBytes)[tampered.length - 1] ^= 0x01;
  XCTAssertTrue([tampered writeToURL:secretsURL options:0 error:NULL]);
  NSError *error = nil;

  XCTAssertNil([self.coordinator credentialForIdentity:[self identityForService:@"https://example.com"]
      interactionAllowed:YES error:&error]);
  XCTAssertNotNil(error);
}

- (void)testForgedIndexMetadataFailsClosedAtDirectAndListBoundaries {
  [self publishRecords:@[[self recordWithEntry:self.entry title:@"Example"
      service:@"https://example.com" rank:0]]];
  [self writeRegistryWithPublications:@[self.publication]];
  [self forgeCurrentIndexTitle:@"Forged"];
  NSError *error = nil;
  XCTAssertNil([self.coordinator credentialForIdentity:[self identityForService:@"https://example.com"]
      interactionAllowed:YES error:&error]);
  XCTAssertEqual(error.code, MPAutoFillErrorContextMismatch);

  ASCredentialServiceIdentifier *service = [[ASCredentialServiceIdentifier alloc]
      initWithIdentifier:@"https://example.com" type:ASCredentialServiceIdentifierTypeURL];
  error = nil;
  XCTAssertNil([self.coordinator credentialsForServiceIdentifiers:@[service] error:&error]);
  XCTAssertEqual(error.code, MPAutoFillErrorContextMismatch);
}

- (void)testUnsafeRegistryPermissionsFailClosedAtListBoundary {
  [self publishRecords:@[[self recordWithEntry:self.entry title:@"Example"
      service:@"https://example.com" rank:0]]];
  [self writeRegistryWithPublications:@[self.publication]];
  NSURL *registryURL = [self.rootURL URLByAppendingPathComponent:@"registry.plist"];
  XCTAssertEqual(chmod(registryURL.fileSystemRepresentation, 0644), 0);
  ASCredentialServiceIdentifier *service = [[ASCredentialServiceIdentifier alloc]
      initWithIdentifier:@"https://example.com" type:ASCredentialServiceIdentifierTypeURL];
  NSError *error = nil;

  XCTAssertNil([self.coordinator credentialsForServiceIdentifiers:@[service] error:&error]);
  XCTAssertEqual(error.code, MPAutoFillErrorUnsafeFile);
}

- (void)testTruncatedRegistryFailsClosedAtListBoundary {
  NSURL *registryURL = [self.rootURL URLByAppendingPathComponent:@"registry.plist"];
  NSData *truncated = [@"bplist00" dataUsingEncoding:NSASCIIStringEncoding];
  XCTAssertTrue([truncated writeToURL:registryURL options:NSDataWritingAtomic error:NULL]);
  XCTAssertTrue([NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: @0600}
                                                      ofItemAtPath:registryURL.path error:NULL]);
  ASCredentialServiceIdentifier *service = [[ASCredentialServiceIdentifier alloc]
      initWithIdentifier:@"https://example.com" type:ASCredentialServiceIdentifierTypeURL];
  NSError *error = nil;

  XCTAssertNil([self.coordinator credentialsForServiceIdentifiers:@[service] error:&error]);
  XCTAssertNotNil(error);
}

- (void)testOneCorruptVaultFailsClosedForCompleteList {
  NSString *secondPublication = @"dddddddd-dddd-dddd-dddd-dddddddddddd";
  NSString *secondGeneration = @"eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee";
  [self publishRecords:@[[self recordWithEntry:self.entry title:@"First"
      service:@"https://example.com" rank:0]] publication:self.publication generation:self.generation];
  [self publishRecords:@[[self recordWithEntry:@"ffffffff-ffff-ffff-ffff-ffffffffffff" title:@"Second"
      service:@"https://example.com" rank:0]] publication:secondPublication generation:secondGeneration];
  [self writeRegistryWithPublications:@[self.publication, secondPublication]];
  XCTAssertTrue([NSFileManager.defaultManager removeItemAtURL:[[self generationURLForPublication:secondPublication
      generation:secondGeneration] URLByAppendingPathComponent:@"secrets.bin"] error:NULL]);
  ASCredentialServiceIdentifier *service = [[ASCredentialServiceIdentifier alloc]
      initWithIdentifier:@"https://example.com" type:ASCredentialServiceIdentifierTypeURL];
  NSError *error = nil;

  XCTAssertNil([self.coordinator credentialsForServiceIdentifiers:@[service] error:&error]);
  XCTAssertNotNil(error);
}

- (void)testColdRequestsForMaximumRecordCountStayWithinDebugBudgets {
  NSMutableArray<MPAutoFillCredentialRecord *> *records =
      [NSMutableArray arrayWithCapacity:MPAutoFillMaximumRecordCount];
  for (NSUInteger index = 0; index < MPAutoFillMaximumRecordCount; index++) {
    NSString *entry = [NSString stringWithFormat:@"00000000-0000-0000-0000-%012lx", (unsigned long)index];
    NSString *title = [NSString stringWithFormat:@"Entry %04lu", (unsigned long)index];
    [records addObject:[self recordWithEntry:entry title:title service:@"https://example.com" rank:(int64_t)index]];
  }
  self.entry = records.lastObject.entryIdentifier;
  [self publishRecords:records];
  [self writeRegistryWithPublications:@[self.publication]];
  records = nil;

  MPAutoFillRequestCoordinator *coldCoordinator = [[MPAutoFillRequestCoordinator alloc]
      initWithGenerationStore:[[MPAutoFillGenerationStore alloc] initWithRootURL:self.rootURL
          currentGenerationStore:self.keyStore error:NULL]
      keychainStore:self.keyStore rootURL:self.rootURL];
  uint64_t footprintBefore = MPAutoFillPhysicalFootprint();
  CFAbsoluteTime directStart = CFAbsoluteTimeGetCurrent();
  NSError *error = nil;
  ASPasswordCredential *credential = [coldCoordinator credentialForIdentity:
      [self identityForService:@"https://example.com"] interactionAllowed:YES error:&error];
  NSTimeInterval directDuration = CFAbsoluteTimeGetCurrent() - directStart;
  XCTAssertNotNil(credential);
  XCTAssertNil(error);
  XCTAssertLessThan(directDuration, 5.0, @"Cold direct request took %.3f seconds", directDuration);

  ASCredentialServiceIdentifier *service = [[ASCredentialServiceIdentifier alloc]
      initWithIdentifier:@"https://example.com" type:ASCredentialServiceIdentifierTypeURL];
  CFAbsoluteTime listStart = CFAbsoluteTimeGetCurrent();
  NSArray<MPAutoFillCredentialSelection *> *selections = [coldCoordinator
      credentialsForServiceIdentifiers:@[service] error:&error];
  NSTimeInterval listDuration = CFAbsoluteTimeGetCurrent() - listStart;
  uint64_t footprintAfter = MPAutoFillPhysicalFootprint();
  uint64_t footprintGrowth = footprintAfter > footprintBefore ? footprintAfter - footprintBefore : 0;
  XCTAssertEqual(selections.count, MPAutoFillMaximumRecordCount);
  XCTAssertNil(error);
  XCTAssertLessThan(listDuration, 15.0, @"Cold list request took %.3f seconds", listDuration);
  XCTAssertLessThan(footprintGrowth, 128ull * 1024 * 1024,
      @"Cold requests grew physical footprint by %.1f MiB", footprintGrowth / (1024.0 * 1024.0));
  NSLog(@"AutoFill 5000-record debug budgets: direct %.3fs, list %.3fs, footprint growth %.1f MiB",
      directDuration, listDuration, footprintGrowth / (1024.0 * 1024.0));
}

@end
