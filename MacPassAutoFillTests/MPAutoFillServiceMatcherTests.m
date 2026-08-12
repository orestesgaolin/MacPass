#import <XCTest/XCTest.h>

#import "MPAutoFillServiceMatcher.h"

@interface MPAutoFillServiceMatcherTests : XCTestCase
@end

@implementation MPAutoFillServiceMatcherTests

- (void)testDomainMatchingUsesExactNormalizedHost {
  XCTAssertTrue([MPAutoFillServiceMatcher credentialServiceIdentifier:@"https://Example.COM./login"
                                     matchesRequestedServiceIdentifier:@"example.com"
                                                                  type:MPAutoFillServiceIdentifierTypeDomain]);
  XCTAssertFalse([MPAutoFillServiceMatcher credentialServiceIdentifier:@"https://example.com/login"
                                      matchesRequestedServiceIdentifier:@"example.com.attacker.test"
                                                                   type:MPAutoFillServiceIdentifierTypeDomain]);
  XCTAssertFalse([MPAutoFillServiceMatcher credentialServiceIdentifier:@"https://sub.example.com/login"
                                      matchesRequestedServiceIdentifier:@"example.com"
                                                                   type:MPAutoFillServiceIdentifierTypeDomain]);
}

- (void)testURLMatchingUsesNormalizedExactOrigin {
  XCTAssertTrue([MPAutoFillServiceMatcher credentialServiceIdentifier:@"HTTPS://EXAMPLE.COM:443/login"
                                     matchesRequestedServiceIdentifier:@"https://example.com/account?next=1"
                                                                  type:MPAutoFillServiceIdentifierTypeURL]);
  XCTAssertFalse([MPAutoFillServiceMatcher credentialServiceIdentifier:@"http://example.com/login"
                                      matchesRequestedServiceIdentifier:@"https://example.com/login"
                                                                   type:MPAutoFillServiceIdentifierTypeURL]);
  XCTAssertFalse([MPAutoFillServiceMatcher credentialServiceIdentifier:@"https://example.com:8443/login"
                                      matchesRequestedServiceIdentifier:@"https://example.com/login"
                                                                   type:MPAutoFillServiceIdentifierTypeURL]);
  XCTAssertTrue([MPAutoFillServiceMatcher credentialServiceIdentifier:@"http://example.com:80/login"
                                     matchesRequestedServiceIdentifier:@"http://example.com/"
                                                                  type:MPAutoFillServiceIdentifierTypeURL]);
}

- (void)testIDNAndIPAddressMatching {
  XCTAssertTrue([MPAutoFillServiceMatcher credentialServiceIdentifier:@"https://bücher.example/login"
                                     matchesRequestedServiceIdentifier:@"https://xn--bcher-kva.example/"
                                                                  type:MPAutoFillServiceIdentifierTypeURL]);
  XCTAssertTrue([MPAutoFillServiceMatcher credentialServiceIdentifier:@"https://127.0.0.1/login"
                                     matchesRequestedServiceIdentifier:@"127.0.0.1"
                                                                  type:MPAutoFillServiceIdentifierTypeDomain]);
  XCTAssertTrue([MPAutoFillServiceMatcher credentialServiceIdentifier:@"https://[2001:db8::1]:443/login"
                                     matchesRequestedServiceIdentifier:@"https://[2001:db8::1]/"
                                                                  type:MPAutoFillServiceIdentifierTypeURL]);
}

- (void)testMalformedAndRelativeValuesFailClosed {
  NSArray<NSString *> *invalidCredentialURLs = @[
    @"example.com/login",
    @"/login",
    @"https:///login",
    @"ftp://example.com/login",
    @"https://user:password@example.com/login",
    @"https://exa mple.com/login",
    @"https://example.com:/login",
    @"https://example.com:0/login",
    @"https://example.com:65536/login",
    @"https://example.com:notaport/login",
    @"https://example.com../login",
  ];
  for (NSString *credentialURL in invalidCredentialURLs) {
    XCTAssertNil([MPAutoFillServiceMatcher normalizedCredentialServiceIdentifier:credentialURL]);
    XCTAssertFalse([MPAutoFillServiceMatcher credentialServiceIdentifier:credentialURL
                                        matchesRequestedServiceIdentifier:@"example.com"
                                                                     type:MPAutoFillServiceIdentifierTypeDomain]);
  }
  XCTAssertFalse([MPAutoFillServiceMatcher credentialServiceIdentifier:@"https://example.com/login"
                                      matchesRequestedServiceIdentifier:@"example.com.."
                                                                   type:MPAutoFillServiceIdentifierTypeDomain]);
}

- (void)testCredentialNormalizationRemovesNonOriginComponents {
  XCTAssertEqualObjects([MPAutoFillServiceMatcher normalizedCredentialServiceIdentifier:@"HTTPS://Example.COM.:443/login?q=1#fragment"],
                        @"https://example.com");
  XCTAssertEqualObjects([MPAutoFillServiceMatcher normalizedCredentialServiceIdentifier:@"https://[2001:db8::1]:443/login"],
                        @"https://[2001:db8::1]");
}

@end
