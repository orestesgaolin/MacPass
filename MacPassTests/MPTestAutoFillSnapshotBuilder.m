#import <XCTest/XCTest.h>
#import <KeePassKit/KeePassKit.h>

#import "MPAutoFillCredentialRecord.h"
#import "MPAutoFillSnapshotBuilder.h"

@interface MPTestAutoFillSnapshotBuilder : XCTestCase
@end


@implementation MPTestAutoFillSnapshotBuilder

- (NSData *)fixtureData:(NSString *)name extension:(NSString *)extension {
  NSURL *URL = [[NSBundle bundleForClass:self.class] URLForResource:name withExtension:extension];
  XCTAssertNotNil(URL);
  NSData *data = [NSData dataWithContentsOfURL:URL];
  XCTAssertNotNil(data);
  return data;
}

- (KPKCompositeKey *)keyWithPassword:(NSString *)password keyFile:(NSString *)keyFile extension:(NSString *)extension {
  NSMutableArray<KPKKey *> *keys = [NSMutableArray array];
  if (password) [keys addObject:[KPKKey keyWithPassword:password]];
  if (keyFile) {
    KPKKey *fileKey = [KPKKey keyWithKeyFileData:[self fixtureData:keyFile extension:extension]];
    XCTAssertNotNil(fileKey);
    if (fileKey) [keys addObject:fileKey];
  }
  return [[KPKCompositeKey alloc] initWithKeys:keys];
}

- (KPKTree *)tree {
  KPKTree *tree = [[KPKTree alloc] init];
  tree.root = [[KPKGroup alloc] init];
  return tree;
}

- (KPKEntry *)entryInTree:(KPKTree *)tree title:(NSString *)title {
  KPKEntry *entry = [tree createEntry:tree.root];
  [entry addToGroup:tree.root];
  entry.title = title;
  entry.username = @"user";
  entry.password = @"secret";
  entry.url = @"https://Example.COM:443/login";
  return entry;
}

- (void)testBuildsLiteralNormalizedRecord {
  KPKTree *tree = [self tree];
  KPKEntry *entry = [self entryInTree:tree title:@"Example"];
  MPAutoFillSnapshotBuildResult *result = [MPAutoFillSnapshotBuilder buildRecordsFromTree:tree atDate:[NSDate date]];

  XCTAssertEqual(result.records.count, 1u);
  XCTAssertEqualObjects(result.records.firstObject.entryIdentifier, entry.uuid.UUIDString.lowercaseString);
  XCTAssertEqualObjects(result.records.firstObject.serviceIdentifiers, (@[@"https://example.com"]));
  XCTAssertEqual(result.excludedEntryReasons.count, 0u);
}

- (void)testEncryptedSourceFormatAndCredentialMatrixReachesAutoFillBuilder {
  NSArray<NSDictionary *> *fixtures = @[
    @{@"name": @"Test_Password_1234", @"extension": @"kdb", @"format": @(KPKDatabaseFormatKdb),
      @"version": @(0x00030002), @"password": @"1234"},
    @{@"name": @"AutoFill_KDB_KeyFile", @"extension": @"kdb", @"format": @(KPKDatabaseFormatKdb),
      @"version": @(0x00030002), @"keyFile": @"AutoFill_Kdb1HexKey", @"keyExtension": @"key"},
    @{@"name": @"AutoFill_KDB_Combined", @"extension": @"kdb", @"format": @(KPKDatabaseFormatKdb),
      @"version": @(0x00030002), @"password": @"test", @"keyFile": @"AutoFill_Kdb1HexKey", @"keyExtension": @"key"},
    @{@"name": @"Test_Password_1234", @"extension": @"kdbx", @"format": @(KPKDatabaseFormatKdbx),
      @"version": @(kKPKKdbxFileVersion3), @"password": @"1234"},
    @{@"name": @"AutoFill_KDBX31_KeyFile", @"extension": @"kdbx", @"format": @(KPKDatabaseFormatKdbx),
      @"version": @(kKPKKdbxFileVersion3), @"keyFile": @"AutoFill_Kdb1HexKey", @"keyExtension": @"key"},
    @{@"name": @"AutoFill_KDBX4_Password", @"extension": @"kdbx", @"format": @(KPKDatabaseFormatKdbx),
      @"version": @(kKPKKdbxFileVersion4), @"password": @"test"},
    @{@"name": @"AutoFill_KDBX4_Combined", @"extension": @"kdbx", @"format": @(KPKDatabaseFormatKdbx),
      @"version": @(kKPKKdbxFileVersion4), @"password": @"test", @"keyFile": @"AutoFill_KeyFileV2", @"keyExtension": @"keyx"},
    @{@"name": @"AutoFill_KDBX41_Password", @"extension": @"kdbx", @"format": @(KPKDatabaseFormatKdbx),
      @"version": @(kKPKKdbxFileVersion4_1), @"password": @"test"},
  ];

  for (NSDictionary *fixture in fixtures) {
    NSData *data = [self fixtureData:fixture[@"name"] extension:fixture[@"extension"]];
    KPKFileVersion version = [KPKFormat.sharedFormat fileVersionForData:data];
    XCTAssertEqual(version.format, [fixture[@"format"] unsignedIntegerValue], @"%@ format", fixture[@"name"]);
    XCTAssertEqual(version.version, [fixture[@"version"] unsignedIntegerValue], @"%@ version", fixture[@"name"]);
    KPKCompositeKey *key = [self keyWithPassword:fixture[@"password"] keyFile:fixture[@"keyFile"]
                                       extension:fixture[@"keyExtension"]];
    NSError *error = nil;
    KPKTree *tree = [[KPKTree alloc] initWithData:data key:key error:&error];
    XCTAssertNotNil(tree, @"%@ should decrypt: %@", fixture[@"name"], error);
    XCTAssertNil(error);
    MPAutoFillSnapshotBuildResult *result = tree ? [MPAutoFillSnapshotBuilder buildRecordsFromTree:tree atDate:NSDate.date] : nil;
    XCTAssertNotNil(result, @"%@ should reach the AutoFill builder", fixture[@"name"]);
    for (MPAutoFillCredentialRecord *record in result.records) {
      XCTAssertGreaterThan(record.password.length, 0u);
      XCTAssertGreaterThan(record.serviceIdentifiers.count, 0u);
    }
  }
}

- (void)testWrongCredentialCombinationsCannotReachAutoFillBuilder {
  NSData *combinedData = [self fixtureData:@"AutoFill_KDBX4_Combined" extension:@"kdbx"];
  NSData *wrongKeyData = [NSData kpk_generateKeyfileDataOfType:KPKKeyFileTypeXMLVersion2];
  NSArray<KPKCompositeKey *> *wrongKeys = @[
    [self keyWithPassword:@"test" keyFile:nil extension:nil],
    [self keyWithPassword:nil keyFile:@"AutoFill_KeyFileV2" extension:@"keyx"],
    [[KPKCompositeKey alloc] initWithKeys:@[[KPKKey keyWithPassword:@"wrong"],
                                             [KPKKey keyWithKeyFileData:[self fixtureData:@"AutoFill_KeyFileV2" extension:@"keyx"]]]],
    [[KPKCompositeKey alloc] initWithKeys:@[[KPKKey keyWithPassword:@"test"],
                                             [KPKKey keyWithKeyFileData:wrongKeyData]]],
  ];
  for (KPKCompositeKey *wrongKey in wrongKeys) {
    NSError *error = nil;
    XCTAssertNil([[KPKTree alloc] initWithData:combinedData key:wrongKey error:&error]);
    XCTAssertNotNil(error);
  }
}

- (void)testExcludesExpiredEmptyPasswordAndMalformedURL {
  KPKTree *tree = [self tree];
  KPKEntry *expired = [self entryInTree:tree title:@"Expired"];
  expired.timeInfo.expires = YES;
  expired.timeInfo.expirationDate = [NSDate dateWithTimeIntervalSince1970:1];
  KPKEntry *empty = [self entryInTree:tree title:@"Empty"];
  empty.password = @"";
  KPKEntry *malformed = [self entryInTree:tree title:@"Malformed"];
  malformed.url = @"example.com/login";

  MPAutoFillSnapshotBuildResult *result = [MPAutoFillSnapshotBuilder
      buildRecordsFromTree:tree atDate:[NSDate dateWithTimeIntervalSince1970:2]];
  XCTAssertEqual(result.records.count, 0u);
  XCTAssertEqualObjects(result.excludedEntryReasons[expired.uuid.UUIDString.lowercaseString], MPAutoFillEligibilityReasonExpired);
  XCTAssertEqualObjects(result.excludedEntryReasons[empty.uuid.UUIDString.lowercaseString], MPAutoFillEligibilityReasonEmptyPassword);
  XCTAssertEqualObjects(result.excludedEntryReasons[malformed.uuid.UUIDString.lowercaseString], MPAutoFillEligibilityReasonMalformedURL);
}

- (void)testEmptyUsernameRemainsEligibleAndExpirationBoundaryIsExcluded {
  KPKTree *tree = [self tree];
  KPKEntry *emptyUsername = [self entryInTree:tree title:@"Empty username"];
  emptyUsername.username = @"";
  KPKEntry *expiresNow = [self entryInTree:tree title:@"Expires now"];
  expiresNow.timeInfo.expires = YES;
  expiresNow.timeInfo.expirationDate = [NSDate dateWithTimeIntervalSince1970:10];

  MPAutoFillSnapshotBuildResult *result = [MPAutoFillSnapshotBuilder
      buildRecordsFromTree:tree atDate:[NSDate dateWithTimeIntervalSince1970:10]];
  XCTAssertEqual(result.records.count, 1u);
  XCTAssertEqualObjects(result.records.firstObject.entryIdentifier,
                        emptyUsername.uuid.UUIDString.lowercaseString);
  XCTAssertEqualObjects(result.records.firstObject.username, @"");
  XCTAssertEqualObjects(result.excludedEntryReasons[expiresNow.uuid.UUIDString.lowercaseString],
                        MPAutoFillEligibilityReasonExpired);
}

- (void)testExcludesHistoryAndMetaEntries {
  KPKTree *tree = [self tree];
  KPKEntry *entry = [self entryInTree:tree title:@"Current"];
  entry.password = @"historical-secret";
  [entry pushHistory];
  entry.password = @"current-secret";
  KPKEntry *meta = [KPKEntry metaEntryWithData:[@"metadata" dataUsingEncoding:NSUTF8StringEncoding]
                                         name:@"AutoFill test metadata"];
  [meta addToGroup:tree.root];

  MPAutoFillSnapshotBuildResult *result = [MPAutoFillSnapshotBuilder buildRecordsFromTree:tree
                                                                                   atDate:NSDate.date];
  XCTAssertEqual(result.records.count, 1u);
  XCTAssertEqualObjects(result.records.firstObject.password, @"current-secret");
  XCTAssertFalse([result.records.firstObject.password isEqualToString:@"historical-secret"]);
  XCTAssertEqualObjects(result.excludedEntryReasons[meta.uuid.UUIDString.lowercaseString],
                        MPAutoFillEligibilityReasonMeta);
}

- (void)testExcludesTrashAndTemplates {
  KPKTree *tree = [self tree];
  KPKGroup *trash = [tree createGroup:tree.root];
  [trash addToGroup:tree.root];
  tree.trash = trash;
  KPKEntry *trashed = [tree createEntry:trash];
  [trashed addToGroup:trash];
  trashed.password = @"secret";
  trashed.url = @"https://example.com";
  KPKGroup *templates = [tree createGroup:tree.root];
  [templates addToGroup:tree.root];
  tree.templates = templates;
  KPKEntry *templateEntry = [tree createEntry:templates];
  [templateEntry addToGroup:templates];
  templateEntry.password = @"secret";
  templateEntry.url = @"https://example.com";

  MPAutoFillSnapshotBuildResult *result = [MPAutoFillSnapshotBuilder buildRecordsFromTree:tree atDate:[NSDate date]];
  XCTAssertEqualObjects(result.excludedEntryReasons[trashed.uuid.UUIDString.lowercaseString], MPAutoFillEligibilityReasonTrash);
  XCTAssertEqualObjects(result.excludedEntryReasons[templateEntry.uuid.UUIDString.lowercaseString], MPAutoFillEligibilityReasonTemplate);
}

- (void)testResolvesUUIDReferenceAndRejectsDynamicPlaceholder {
  KPKTree *tree = [self tree];
  KPKEntry *source = [self entryInTree:tree title:@"Source"];
  source.password = @"resolved-secret";
  KPKEntry *reference = [self entryInTree:tree title:@"Reference"];
  reference.password = [NSString stringWithFormat:@"{REF:P@I:%@}", source.uuid.UUIDString];
  KPKEntry *dynamic = [self entryInTree:tree title:@"Dynamic"];
  dynamic.password = @"{TOTP}";

  MPAutoFillSnapshotBuildResult *result = [MPAutoFillSnapshotBuilder buildRecordsFromTree:tree atDate:[NSDate date]];
  NSPredicate *referencePredicate = [NSPredicate predicateWithFormat:@"entryIdentifier == %@", reference.uuid.UUIDString.lowercaseString];
  MPAutoFillCredentialRecord *record = [result.records filteredArrayUsingPredicate:referencePredicate].firstObject;
  XCTAssertEqualObjects(record.password, @"resolved-secret");
  XCTAssertEqualObjects(result.excludedEntryReasons[dynamic.uuid.UUIDString.lowercaseString],
                        MPAutoFillEligibilityReasonUnsupportedPlaceholder);
}

- (void)testRejectsReferencesToExcludedEntriesAndIntroducedPlaceholders {
  KPKTree *tree = [self tree];
  KPKGroup *trash = [tree createGroup:tree.root];
  [trash addToGroup:tree.root];
  tree.trash = trash;
  KPKEntry *trashed = [tree createEntry:trash];
  [trashed addToGroup:trash];
  trashed.password = @"trashed-secret";
  KPKEntry *excludedReference = [self entryInTree:tree title:@"Excluded reference"];
  excludedReference.password = [NSString stringWithFormat:@"{REF:P@I:%@}", trashed.uuid.UUIDString];

  KPKEntry *dynamicSource = [self entryInTree:tree title:@"Dynamic source"];
  dynamicSource.password = @"{TOTP}";
  KPKEntry *dynamicReference = [self entryInTree:tree title:@"Dynamic reference"];
  dynamicReference.password = [NSString stringWithFormat:@"{REF:P@I:%@}", dynamicSource.uuid.UUIDString];

  MPAutoFillSnapshotBuildResult *result = [MPAutoFillSnapshotBuilder buildRecordsFromTree:tree atDate:[NSDate date]];
  XCTAssertEqualObjects(result.excludedEntryReasons[excludedReference.uuid.UUIDString.lowercaseString],
                        MPAutoFillEligibilityReasonUnresolvedReference);
  XCTAssertEqualObjects(result.excludedEntryReasons[dynamicReference.uuid.UUIDString.lowercaseString],
                        MPAutoFillEligibilityReasonUnsupportedPlaceholder);
}

- (void)testRejectsDirectAndMultiHopReferenceCycles {
  KPKTree *tree = [self tree];
  KPKEntry *direct = [self entryInTree:tree title:@"Direct cycle"];
  direct.password = [NSString stringWithFormat:@"{REF:P@I:%@}", direct.uuid.UUIDString];
  KPKEntry *first = [self entryInTree:tree title:@"First cycle"];
  KPKEntry *second = [self entryInTree:tree title:@"Second cycle"];
  first.password = [NSString stringWithFormat:@"{REF:P@I:%@}", second.uuid.UUIDString];
  second.password = [NSString stringWithFormat:@"{REF:P@I:%@}", first.uuid.UUIDString];

  MPAutoFillSnapshotBuildResult *result = [MPAutoFillSnapshotBuilder buildRecordsFromTree:tree
                                                                                   atDate:NSDate.date];
  XCTAssertEqualObjects(result.excludedEntryReasons[direct.uuid.UUIDString.lowercaseString],
                        MPAutoFillEligibilityReasonUnresolvedReference);
  XCTAssertEqualObjects(result.excludedEntryReasons[first.uuid.UUIDString.lowercaseString],
                        MPAutoFillEligibilityReasonUnresolvedReference);
  XCTAssertEqualObjects(result.excludedEntryReasons[second.uuid.UUIDString.lowercaseString],
                        MPAutoFillEligibilityReasonUnresolvedReference);
}

@end
