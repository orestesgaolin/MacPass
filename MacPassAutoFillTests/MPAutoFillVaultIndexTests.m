#import <XCTest/XCTest.h>

#import "MPAutoFillCredentialRecord.h"
#import "MPAutoFillErrors.h"
#import "MPAutoFillVaultIndex.h"

@interface MPAutoFillVaultIndexTests : XCTestCase
@end

@implementation MPAutoFillVaultIndexTests

- (MPAutoFillCredentialRecord *)credentialRecord {
  return [[MPAutoFillCredentialRecord alloc]
      initWithEntryIdentifier:@"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" title:@"Example"
      username:@"user" password:@"secret" serviceIdentifiers:@[@"https://example.com"]
      modificationTime:1 rank:2 error:NULL];
}

- (void)testRoundTripContainsNoPassword {
  MPAutoFillVaultIndexRecord *record = [MPAutoFillVaultIndexRecord recordWithCredentialRecord:self.credentialRecord];
  MPAutoFillVaultIndex *source = [[MPAutoFillVaultIndex alloc]
      initWithPublicationIdentifier:@"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
      generationIdentifier:@"cccccccc-cccc-cccc-cccc-cccccccccccc" records:@[record] error:NULL];
  NSError *error = nil;
  NSData *data = [source serializedDataWithError:&error];
  XCTAssertFalse([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].length > 0);
  XCTAssertEqual([data rangeOfData:[@"secret" dataUsingEncoding:NSUTF8StringEncoding] options:0 range:NSMakeRange(0, data.length)].location,
                 NSNotFound);
  MPAutoFillVaultIndex *parsed = [MPAutoFillVaultIndex indexWithSerializedData:data
      expectedPublicationIdentifier:source.publicationIdentifier
      expectedGenerationIdentifier:source.generationIdentifier error:&error];
  XCTAssertEqualObjects(parsed.records.firstObject.username, @"user");
  XCTAssertNil(error);
}

- (void)testRejectsContextMismatchAndXML {
  MPAutoFillVaultIndexRecord *record = [MPAutoFillVaultIndexRecord recordWithCredentialRecord:self.credentialRecord];
  MPAutoFillVaultIndex *source = [[MPAutoFillVaultIndex alloc]
      initWithPublicationIdentifier:@"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
      generationIdentifier:@"cccccccc-cccc-cccc-cccc-cccccccccccc" records:@[record] error:NULL];
  NSError *error = nil;
  NSData *data = [source serializedDataWithError:&error];
  XCTAssertNil([MPAutoFillVaultIndex indexWithSerializedData:data
      expectedPublicationIdentifier:@"dddddddd-dddd-dddd-dddd-dddddddddddd"
      expectedGenerationIdentifier:source.generationIdentifier error:&error]);
  XCTAssertEqual(error.code, MPAutoFillErrorContextMismatch);
  NSData *xml = [NSPropertyListSerialization dataWithPropertyList:@{} format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
  XCTAssertNil([MPAutoFillVaultIndex indexWithSerializedData:xml
      expectedPublicationIdentifier:source.publicationIdentifier
      expectedGenerationIdentifier:source.generationIdentifier error:&error]);
}

- (void)testRejectsScalarServicesWithoutException {
  NSDictionary *root = @{
    @"schema": @1,
    @"publication": @"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
    @"generation": @"cccccccc-cccc-cccc-cccc-cccccccccccc",
    @"records": @[@{
      @"entry": @"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", @"title": @"Example",
      @"username": @"user", @"services": @1, @"modified": @0, @"rank": @0,
    }],
  };
  NSData *data = [NSPropertyListSerialization dataWithPropertyList:root format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
  NSError *error = nil;
  XCTAssertNil([MPAutoFillVaultIndex indexWithSerializedData:data
      expectedPublicationIdentifier:root[@"publication"] expectedGenerationIdentifier:root[@"generation"] error:&error]);
  XCTAssertEqual(error.code, MPAutoFillErrorMalformedSnapshot);
}

- (void)testRejectsOlderAndNewerSchemas {
  NSDictionary *base = @{
    @"publication": @"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
    @"generation": @"cccccccc-cccc-cccc-cccc-cccccccccccc",
    @"records": @[],
  };
  for (NSNumber *schema in @[@0, @2]) {
    NSMutableDictionary *root = [base mutableCopy];
    root[@"schema"] = schema;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:root
        format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
    NSError *error = nil;
    XCTAssertNil([MPAutoFillVaultIndex indexWithSerializedData:data
        expectedPublicationIdentifier:base[@"publication"] expectedGenerationIdentifier:base[@"generation"] error:&error]);
    XCTAssertEqual(error.code, MPAutoFillErrorUnsupportedSchema);
  }
}

@end
