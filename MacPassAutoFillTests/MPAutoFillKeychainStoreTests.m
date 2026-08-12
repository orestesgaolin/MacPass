#import <XCTest/XCTest.h>

#import "MPAutoFillErrors.h"
#import "MPAutoFillKeychainStore.h"

@interface MPAutoFillKeychainStoreTests : XCTestCase
@end

@implementation MPAutoFillKeychainStoreTests

- (void)testRejectsMalformedIdentifiersBeforeKeychainAccess {
  MPAutoFillKeychainStore *store = [[MPAutoFillKeychainStore alloc] initWithAccessGroup:@"invalid.test.group"];
  NSError *error = nil;
  XCTAssertFalse([store createKeyPairForPublicationIdentifier:@"invalid" error:&error]);
  XCTAssertEqual(error.code, MPAutoFillErrorInvalidArgument);

  error = nil;
  XCTAssertFalse([store setCurrentGeneration:@"invalid"
                    forPublicationIdentifier:@"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
                                       error:&error]);
  XCTAssertEqual(error.code, MPAutoFillErrorInvalidArgument);
}

- (void)testActivationStateRoundTripAndRollbackDetection {
  NSString *oldGeneration = @"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
  NSString *newGeneration = @"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
  NSData *oldData = [MPAutoFillKeychainStore activationDataForGenerationIdentifier:oldGeneration error:NULL];
  NSData *newData = [MPAutoFillKeychainStore activationDataForGenerationIdentifier:newGeneration error:NULL];
  NSError *error = nil;

  XCTAssertEqualObjects([MPAutoFillKeychainStore generationIdentifierFromActivationData:newData
      highWaterData:newData error:&error], newGeneration);
  XCTAssertNil(error);

  error = nil;
  XCTAssertNil([MPAutoFillKeychainStore generationIdentifierFromActivationData:oldData
      highWaterData:newData error:&error]);
  XCTAssertEqual(error.code, MPAutoFillErrorContextMismatch);

  error = nil;
  XCTAssertNil([MPAutoFillKeychainStore generationIdentifierFromActivationData:newData
      highWaterData:nil error:&error]);
  XCTAssertEqual(error.code, MPAutoFillErrorContextMismatch);
}

- (void)testLegacyActivationIsAcceptedOnlyWithoutHighWaterMarker {
  NSString *generation = @"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
  NSData *legacy = [generation dataUsingEncoding:NSUTF8StringEncoding];
  NSData *modern = [MPAutoFillKeychainStore activationDataForGenerationIdentifier:generation error:NULL];
  NSError *error = nil;

  XCTAssertEqualObjects([MPAutoFillKeychainStore generationIdentifierFromActivationData:legacy
      highWaterData:nil error:&error], generation);
  XCTAssertNil(error);

  XCTAssertNil([MPAutoFillKeychainStore generationIdentifierFromActivationData:legacy
      highWaterData:modern error:&error]);
  XCTAssertEqual(error.code, MPAutoFillErrorContextMismatch);
}

- (void)testMalformedActivationFailsClosed {
  NSData *malformed = [@"not-an-activation" dataUsingEncoding:NSUTF8StringEncoding];
  NSError *error = nil;
  XCTAssertNil([MPAutoFillKeychainStore generationIdentifierFromActivationData:malformed
      highWaterData:malformed error:&error]);
  XCTAssertEqual(error.code, MPAutoFillErrorContextMismatch);
}

- (void)testPublicationEnumerationParsesAllNamespacedItemKinds {
  NSString *first = @"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
  NSString *second = @"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
  NSData *privateTag = [[@"dev.roszkowski.macpass.autofill.private.v1:" stringByAppendingString:first]
      dataUsingEncoding:NSUTF8StringEncoding];
  NSData *unrelatedTag = [@"other.application.key" dataUsingEncoding:NSUTF8StringEncoding];
  NSArray *identifiers = [MPAutoFillKeychainStore publicationIdentifiersFromKeyAttributes:@[
      @{(__bridge id)kSecAttrApplicationTag: privateTag},
      @{(__bridge id)kSecAttrApplicationTag: unrelatedTag},
    ] activationAttributes:@[@{(__bridge id)kSecAttrAccount: second}]
      highWaterAttributes:@[@{(__bridge id)kSecAttrAccount: first}] error:NULL];

  XCTAssertEqualObjects(identifiers, (@[first, second]));
}

- (void)testPublicationEnumerationRejectsMalformedNamespacedState {
  NSData *tag = [@"dev.roszkowski.macpass.autofill.public.v1:not-a-uuid"
      dataUsingEncoding:NSUTF8StringEncoding];
  NSError *error = nil;

  XCTAssertNil([MPAutoFillKeychainStore publicationIdentifiersFromKeyAttributes:@[
      @{(__bridge id)kSecAttrApplicationTag: tag}
    ] activationAttributes:@[] highWaterAttributes:@[] error:&error]);
  XCTAssertEqual(error.code, MPAutoFillErrorContextMismatch);

  error = nil;
  XCTAssertNil([MPAutoFillKeychainStore publicationIdentifiersFromKeyAttributes:@[]
      activationAttributes:@[@{(__bridge id)kSecAttrAccount: @"not-a-uuid"}]
      highWaterAttributes:@[] error:&error]);
  XCTAssertEqual(error.code, MPAutoFillErrorContextMismatch);
}

- (void)testPublicationEnumerationAllowsDuplicateRowsAtUniqueLimit {
  NSMutableArray<NSDictionary *> *activation = [NSMutableArray array];
  for (NSUInteger index = 0; index < 1024; index++) {
    NSString *identifier = [NSString stringWithFormat:@"00000000-0000-0000-0000-%012lu", (unsigned long)index];
    [activation addObject:@{(__bridge id)kSecAttrAccount: identifier}];
  }
  NSDictionary *duplicate = activation.lastObject;

  NSArray *identifiers = [MPAutoFillKeychainStore publicationIdentifiersFromKeyAttributes:@[]
      activationAttributes:activation highWaterAttributes:@[duplicate] error:NULL];
  XCTAssertEqual(identifiers.count, 1024u);
}

@end
