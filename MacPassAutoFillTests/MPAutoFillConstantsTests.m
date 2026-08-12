#import <XCTest/XCTest.h>

#import "MPAutoFillConstants.h"

@interface MPAutoFillConstantsTests : XCTestCase
@end

@implementation MPAutoFillConstantsTests

- (void)testSharedIdentifiersAreStable {
  XCTAssertEqualObjects(MPAutoFillAppGroupIdentifier, @"group.dev.roszkowski.macpass");
  XCTAssertEqualObjects(MPAutoFillSharedKeychainAccessGroupSuffix, @"dev.roszkowski.macpass.shared");
}

- (void)testSliceZeroCredentialIsExplicitlyDevelopmentOnly {
  XCTAssertEqualObjects(MPAutoFillDevelopmentServiceIdentifier, @"example.com");
  XCTAssertTrue([MPAutoFillDevelopmentUsername containsString:@"spike"]);
  XCTAssertTrue([MPAutoFillDevelopmentPassword containsString:@"development"]);
}

@end
