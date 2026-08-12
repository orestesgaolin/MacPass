#import <XCTest/XCTest.h>

#import "MPAutoFillCredentialRecord.h"
#import "MPAutoFillEnvelopeCrypto.h"
#import "MPAutoFillErrors.h"
#import "MPAutoFillSnapshot.h"

@interface MPAutoFillEnvelopeCryptoTests : XCTestCase
@end

@implementation MPAutoFillEnvelopeCryptoTests

- (SecKeyRef)newPrivateKey {
  NSDictionary *attributes = @{
    (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeRSA,
    (__bridge id)kSecAttrKeySizeInBits: @2048,
  };
  CFErrorRef error = NULL;
  SecKeyRef key = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes, &error);
  XCTAssertNotNil((__bridge id)key, @"%@", CFBridgingRelease(error));
  return key;
}

- (MPAutoFillSnapshot *)snapshot {
  NSError *error = nil;
  MPAutoFillCredentialRecord *record = [[MPAutoFillCredentialRecord alloc]
      initWithEntryIdentifier:@"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
                       title:@"Example"
                    username:@"user"
                    password:[@"secret" stringByPaddingToLength:4096 withString:@"x" startingAtIndex:0]
          serviceIdentifiers:@[@"example.com"]
            modificationTime:0
                        rank:0
                       error:&error];
  MPAutoFillSnapshot *snapshot = [[MPAutoFillSnapshot alloc]
      initWithPublicationIdentifier:@"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
               generationIdentifier:@"cccccccc-cccc-cccc-cccc-cccccccccccc"
                        indexDigest:[NSMutableData dataWithLength:32]
                            records:@[record]
                              error:&error];
  XCTAssertNotNil(snapshot);
  XCTAssertNil(error);
  return snapshot;
}

- (void)testHybridEnvelopeRoundTripBeyondPlainRSAInputLimit {
  SecKeyRef privateKey = [self newPrivateKey];
  SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);
  MPAutoFillSnapshot *source = [self snapshot];
  NSError *error = nil;
  NSData *envelope = [MPAutoFillEnvelopeCrypto encryptSnapshot:source withPublicKey:publicKey error:&error];
  XCTAssertNotNil(envelope);
  XCTAssertNil(error);

  MPAutoFillSnapshot *decrypted = [MPAutoFillEnvelopeCrypto
      decryptEnvelope:envelope
      withPrivateKey:privateKey
      publicationIdentifier:source.publicationIdentifier
      generationIdentifier:source.generationIdentifier
      indexDigest:source.indexDigest
      error:&error];
  XCTAssertNotNil(decrypted);
  XCTAssertEqualObjects(decrypted.records.firstObject.username, @"user");
  CFRelease(publicKey);
  CFRelease(privateKey);
}

- (void)testTamperAndWrongKeyFailClosed {
  SecKeyRef privateKey = [self newPrivateKey];
  SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);
  SecKeyRef wrongPrivateKey = [self newPrivateKey];
  MPAutoFillSnapshot *source = [self snapshot];
  NSError *error = nil;
  NSData *envelope = [MPAutoFillEnvelopeCrypto encryptSnapshot:source withPublicKey:publicKey error:&error];

  NSMutableData *tampered = [envelope mutableCopy];
  uint8_t *bytes = tampered.mutableBytes;
  bytes[tampered.length / 2] ^= 1;
  XCTAssertNil([MPAutoFillEnvelopeCrypto decryptEnvelope:tampered
                                           withPrivateKey:privateKey
                                   publicationIdentifier:source.publicationIdentifier
                                    generationIdentifier:source.generationIdentifier
                                             indexDigest:source.indexDigest
                                                   error:&error]);
  XCTAssertEqual(error.code, MPAutoFillErrorDecryptionFailed);

  XCTAssertNil([MPAutoFillEnvelopeCrypto decryptEnvelope:envelope
                                           withPrivateKey:wrongPrivateKey
                                   publicationIdentifier:source.publicationIdentifier
                                    generationIdentifier:source.generationIdentifier
                                             indexDigest:source.indexDigest
                                                   error:&error]);
  XCTAssertEqual(error.code, MPAutoFillErrorDecryptionFailed);
  CFRelease(wrongPrivateKey);
  CFRelease(publicKey);
  CFRelease(privateKey);
}

- (void)testExpectedMetadataMismatchFailsClosed {
  SecKeyRef privateKey = [self newPrivateKey];
  SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);
  MPAutoFillSnapshot *source = [self snapshot];
  NSError *error = nil;
  NSData *envelope = [MPAutoFillEnvelopeCrypto encryptSnapshot:source withPublicKey:publicKey error:&error];
  XCTAssertNil([MPAutoFillEnvelopeCrypto decryptEnvelope:envelope
                                           withPrivateKey:privateKey
                                   publicationIdentifier:@"dddddddd-dddd-dddd-dddd-dddddddddddd"
                                    generationIdentifier:source.generationIdentifier
                                             indexDigest:source.indexDigest
                                                   error:&error]);
  XCTAssertEqual(error.code, MPAutoFillErrorContextMismatch);
  CFRelease(publicKey);
  CFRelease(privateKey);
}

- (void)testTruncatedEnvelopeFailsClosed {
  SecKeyRef privateKey = [self newPrivateKey];
  SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);
  MPAutoFillSnapshot *source = [self snapshot];
  NSError *error = nil;
  NSData *envelope = [MPAutoFillEnvelopeCrypto encryptSnapshot:source withPublicKey:publicKey error:&error];
  NSData *truncated = [envelope subdataWithRange:NSMakeRange(0, envelope.length - 1)];

  XCTAssertNil([MPAutoFillEnvelopeCrypto decryptEnvelope:truncated
                                           withPrivateKey:privateKey
                                   publicationIdentifier:source.publicationIdentifier
                                    generationIdentifier:source.generationIdentifier
                                             indexDigest:source.indexDigest
                                                   error:&error]);
  XCTAssertEqual(error.code, MPAutoFillErrorDecryptionFailed);
  CFRelease(publicKey);
  CFRelease(privateKey);
}

- (void)testSecurityErrorMappingPreservesOnlyAuthenticationDecisions {
  NSDictionary<NSNumber *, NSNumber *> *expectedCodes = @{
    @(errSecInteractionNotAllowed): @(MPAutoFillErrorUserInteractionRequired),
    @(errSecUserCanceled): @(MPAutoFillErrorUserCancelled),
    @(errSecAuthFailed): @(MPAutoFillErrorAuthenticationFailed),
    @(errSecParam): @(MPAutoFillErrorDecryptionFailed),
  };

  [expectedCodes enumerateKeysAndObjectsUsingBlock:^(NSNumber *status, NSNumber *expectedCode, BOOL *stop) {
    NSError *securityError = [NSError errorWithDomain:NSOSStatusErrorDomain code:status.integerValue userInfo:nil];
    NSError *mappedError = MPAutoFillSecurityError(securityError, @"The snapshot could not be decrypted.");
    XCTAssertEqual(mappedError.code, expectedCode.integerValue);
    XCTAssertEqualObjects(mappedError.userInfo[NSUnderlyingErrorKey], securityError);
  }];
}

@end
