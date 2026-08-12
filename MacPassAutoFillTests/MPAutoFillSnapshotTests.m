#import <XCTest/XCTest.h>

#import "MPAutoFillCredentialRecord.h"
#import "MPAutoFillErrors.h"
#import "MPAutoFillSnapshot.h"

@interface MPAutoFillSnapshotTests : XCTestCase
@end

@implementation MPAutoFillSnapshotTests

- (MPAutoFillCredentialRecord *)record {
  NSError *error = nil;
  MPAutoFillCredentialRecord *record = [[MPAutoFillCredentialRecord alloc]
      initWithEntryIdentifier:@"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
                       title:@"Example"
                    username:@"user"
                    password:@"secret"
          serviceIdentifiers:@[@"example.com"]
            modificationTime:1234
                        rank:5
                       error:&error];
  XCTAssertNotNil(record);
  XCTAssertNil(error);
  return record;
}

- (MPAutoFillSnapshot *)snapshot {
  NSError *error = nil;
  NSData *digest = [NSMutableData dataWithLength:32];
  MPAutoFillSnapshot *snapshot = [[MPAutoFillSnapshot alloc]
      initWithPublicationIdentifier:@"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
               generationIdentifier:@"cccccccc-cccc-cccc-cccc-cccccccccccc"
                        indexDigest:digest
                            records:@[[self record]]
                              error:&error];
  XCTAssertNotNil(snapshot);
  XCTAssertNil(error);
  return snapshot;
}

- (void)testBinarySnapshotRoundTrip {
  MPAutoFillSnapshot *source = [self snapshot];
  NSError *error = nil;
  NSData *data = [source serializedDataWithError:&error];
  XCTAssertNotNil(data);
  XCTAssertNil(error);

  MPAutoFillSnapshot *decoded = [MPAutoFillSnapshot
      snapshotWithSerializedData:data
      expectedPublicationIdentifier:source.publicationIdentifier
      expectedGenerationIdentifier:source.generationIdentifier
      expectedIndexDigest:source.indexDigest
      error:&error];
  XCTAssertNotNil(decoded);
  XCTAssertNil(error);
  XCTAssertEqual(decoded.schemaVersion, 1);
  XCTAssertEqual(decoded.records.count, 1U);
  XCTAssertEqualObjects(decoded.records.firstObject.password, @"secret");
}

- (void)testRejectsNonCanonicalIdentifierAndDuplicateService {
  NSError *error = nil;
  MPAutoFillCredentialRecord *record = [[MPAutoFillCredentialRecord alloc]
      initWithEntryIdentifier:@"AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
                       title:@"Example"
                    username:@"user"
                    password:@"secret"
          serviceIdentifiers:@[@"example.com", @"example.com"]
            modificationTime:0
                        rank:0
                       error:&error];
  XCTAssertNil(record);
  XCTAssertEqual(error.code, MPAutoFillErrorInvalidArgument);
}

- (void)testRejectsOversizedPassword {
  NSString *password = [@"x" stringByPaddingToLength:MPAutoFillMaximumPasswordBytes + 1
                                          withString:@"x"
                                     startingAtIndex:0];
  NSError *error = nil;
  MPAutoFillCredentialRecord *record = [[MPAutoFillCredentialRecord alloc]
      initWithEntryIdentifier:@"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
                       title:@"Example"
                    username:@"user"
                    password:password
          serviceIdentifiers:@[@"example.com"]
            modificationTime:0
                        rank:0
                       error:&error];
  XCTAssertNil(record);
  XCTAssertEqual(error.code, MPAutoFillErrorInvalidArgument);
}

- (void)testRejectsXMLPropertyList {
  NSDictionary *root = @{};
  NSError *error = nil;
  NSData *data = [NSPropertyListSerialization dataWithPropertyList:root
                                                            format:NSPropertyListXMLFormat_v1_0
                                                           options:0
                                                             error:&error];
  XCTAssertNotNil(data);
  MPAutoFillSnapshot *snapshot = [MPAutoFillSnapshot
      snapshotWithSerializedData:data
      expectedPublicationIdentifier:@"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
      expectedGenerationIdentifier:@"cccccccc-cccc-cccc-cccc-cccccccccccc"
      expectedIndexDigest:[NSMutableData dataWithLength:32]
      error:&error];
  XCTAssertNil(snapshot);
  XCTAssertEqual(error.code, MPAutoFillErrorMalformedSnapshot);
}

- (void)testRejectsUnknownSchemaAndContextMismatch {
  MPAutoFillSnapshot *source = [self snapshot];
  NSError *error = nil;
  NSData *data = [source serializedDataWithError:&error];
  NSMutableDictionary *root = [[NSPropertyListSerialization propertyListWithData:data
                                                                          options:NSPropertyListMutableContainers
                                                                           format:NULL
                                                                            error:&error] mutableCopy];
  root[@"schema"] = @2;
  data = [NSPropertyListSerialization dataWithPropertyList:root
                                                    format:NSPropertyListBinaryFormat_v1_0
                                                   options:0
                                                     error:&error];
  XCTAssertNil([MPAutoFillSnapshot snapshotWithSerializedData:data
                                expectedPublicationIdentifier:source.publicationIdentifier
                                 expectedGenerationIdentifier:source.generationIdentifier
                                          expectedIndexDigest:source.indexDigest
                                                        error:&error]);
  XCTAssertEqual(error.code, MPAutoFillErrorUnsupportedSchema);

  data = [source serializedDataWithError:&error];
  XCTAssertNil([MPAutoFillSnapshot snapshotWithSerializedData:data
                                expectedPublicationIdentifier:@"dddddddd-dddd-dddd-dddd-dddddddddddd"
                                 expectedGenerationIdentifier:source.generationIdentifier
                                          expectedIndexDigest:source.indexDigest
                                                        error:&error]);
  XCTAssertEqual(error.code, MPAutoFillErrorContextMismatch);
}

- (void)testRejectsDuplicateEntryIdentifiers {
  MPAutoFillCredentialRecord *record = [self record];
  NSError *error = nil;
  MPAutoFillSnapshot *snapshot = [[MPAutoFillSnapshot alloc]
      initWithPublicationIdentifier:@"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
               generationIdentifier:@"cccccccc-cccc-cccc-cccc-cccccccccccc"
                        indexDigest:[NSMutableData dataWithLength:32]
                            records:@[record, record]
                              error:&error];
  XCTAssertNil(snapshot);
  XCTAssertEqual(error.code, MPAutoFillErrorInvalidArgument);
}

- (void)testCopiesMutableServiceIdentifiers {
  NSMutableString *service = [@"example.com" mutableCopy];
  NSError *error = nil;
  MPAutoFillCredentialRecord *record = [[MPAutoFillCredentialRecord alloc]
      initWithEntryIdentifier:@"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
                       title:@"Example"
                    username:@"user"
                    password:@"secret"
          serviceIdentifiers:@[service]
            modificationTime:0
                        rank:0
                       error:&error];
  [service setString:@""];
  XCTAssertEqualObjects(record.serviceIdentifiers.firstObject, @"example.com");
}

- (void)testRejectsMalformedExpectedMetadata {
  MPAutoFillSnapshot *source = [self snapshot];
  NSError *error = nil;
  NSData *data = [source serializedDataWithError:&error];
  XCTAssertNil([MPAutoFillSnapshot snapshotWithSerializedData:data
                                expectedPublicationIdentifier:@"not-a-uuid"
                                 expectedGenerationIdentifier:source.generationIdentifier
                                          expectedIndexDigest:source.indexDigest
                                                        error:&error]);
  XCTAssertEqual(error.code, MPAutoFillErrorInvalidArgument);
}

@end
