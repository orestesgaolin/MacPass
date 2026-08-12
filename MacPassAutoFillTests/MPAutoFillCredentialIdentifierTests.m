#import <XCTest/XCTest.h>

#import "MPAutoFillCredentialIdentifier.h"
#import "MPAutoFillErrors.h"

@interface MPAutoFillCredentialIdentifierTests : XCTestCase
@end

@implementation MPAutoFillCredentialIdentifierTests

- (void)testRoundTrip {
  NSError *error = nil;
  MPAutoFillCredentialIdentifier *identifier = [MPAutoFillCredentialIdentifier
      identifierWithPublicationIdentifier:@"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
      entryIdentifier:@"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
      error:&error];
  XCTAssertEqualObjects(identifier.recordIdentifier,
                        @"v1:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa:bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");

  MPAutoFillCredentialIdentifier *parsed = [MPAutoFillCredentialIdentifier
      identifierWithRecordIdentifier:identifier.recordIdentifier error:&error];
  XCTAssertEqualObjects(parsed.publicationIdentifier, identifier.publicationIdentifier);
  XCTAssertEqualObjects(parsed.entryIdentifier, identifier.entryIdentifier);
  XCTAssertNil(error);
}

- (void)testRejectsMalformedUnknownAndNoncanonicalIdentifiers {
  NSArray<NSString *> *invalidIdentifiers = @[
    @"v2:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa:bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
    @"v1:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
    @"v1:AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA:bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
    @"v1:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa:not-a-uuid",
    @"v1:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa:bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb:extra",
  ];
  for (NSString *recordIdentifier in invalidIdentifiers) {
    NSError *error = nil;
    XCTAssertNil([MPAutoFillCredentialIdentifier identifierWithRecordIdentifier:recordIdentifier error:&error]);
    XCTAssertEqual(error.code, MPAutoFillErrorInvalidArgument);
  }
}

@end
