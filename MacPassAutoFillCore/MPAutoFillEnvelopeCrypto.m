#import "MPAutoFillEnvelopeCrypto.h"

#import "MPAutoFillErrors.h"
#import "MPAutoFillSnapshot.h"

static const NSUInteger MPAutoFillMaximumEnvelopeBytes = 4 * 1024 * 1024 + 4096;

@implementation MPAutoFillEnvelopeCrypto

+ (NSData *)encryptSnapshot:(MPAutoFillSnapshot *)snapshot
               withPublicKey:(SecKeyRef)publicKey
                       error:(NSError **)error {
  if (!snapshot || !publicKey) {
    if (error) {
      *error = MPAutoFillError(MPAutoFillErrorInvalidArgument, @"A snapshot and public key are required.", nil);
    }
    return nil;
  }
  if (!SecKeyIsAlgorithmSupported(publicKey, kSecKeyOperationTypeEncrypt,
                                  kSecKeyAlgorithmRSAEncryptionOAEPSHA256AESGCM)) {
    if (error) {
      *error = MPAutoFillError(MPAutoFillErrorCryptoAlgorithmUnsupported, @"The public key cannot encrypt AutoFill snapshots.", nil);
    }
    return nil;
  }
  NSData *plaintext = [snapshot serializedDataWithError:error];
  if (!plaintext) {
    return nil;
  }
  CFErrorRef securityError = NULL;
  NSData *envelope = CFBridgingRelease(SecKeyCreateEncryptedData(publicKey,
      kSecKeyAlgorithmRSAEncryptionOAEPSHA256AESGCM, (__bridge CFDataRef)plaintext, &securityError));
  if (!envelope || envelope.length > MPAutoFillMaximumEnvelopeBytes) {
    NSError *underlyingError = CFBridgingRelease(securityError);
    if (error) {
      *error = MPAutoFillError(MPAutoFillErrorEncryptionFailed, @"The AutoFill snapshot could not be encrypted.", underlyingError);
    }
    return nil;
  }
  return envelope;
}

+ (MPAutoFillSnapshot *)decryptEnvelope:(NSData *)envelope
                          withPrivateKey:(SecKeyRef)privateKey
                  publicationIdentifier:(NSString *)publicationIdentifier
                   generationIdentifier:(NSString *)generationIdentifier
                            indexDigest:(NSData *)indexDigest
                                  error:(NSError **)error {
  if (![envelope isKindOfClass:NSData.class] || envelope.length == 0 ||
      envelope.length > MPAutoFillMaximumEnvelopeBytes || !privateKey) {
    if (error) {
      *error = MPAutoFillError(MPAutoFillErrorInvalidArgument, @"The encrypted AutoFill envelope is invalid.", nil);
    }
    return nil;
  }
  if (!SecKeyIsAlgorithmSupported(privateKey, kSecKeyOperationTypeDecrypt,
                                  kSecKeyAlgorithmRSAEncryptionOAEPSHA256AESGCM)) {
    if (error) {
      *error = MPAutoFillError(MPAutoFillErrorCryptoAlgorithmUnsupported, @"The private key cannot decrypt AutoFill snapshots.", nil);
    }
    return nil;
  }
  CFErrorRef securityError = NULL;
  NSData *plaintext = CFBridgingRelease(SecKeyCreateDecryptedData(privateKey,
      kSecKeyAlgorithmRSAEncryptionOAEPSHA256AESGCM, (__bridge CFDataRef)envelope, &securityError));
  if (!plaintext) {
    NSError *underlyingError = CFBridgingRelease(securityError);
    if (error) {
      *error = MPAutoFillSecurityError(underlyingError, @"The AutoFill snapshot could not be decrypted.");
    }
    return nil;
  }
  return [MPAutoFillSnapshot snapshotWithSerializedData:plaintext
                          expectedPublicationIdentifier:publicationIdentifier
                           expectedGenerationIdentifier:generationIdentifier
                                    expectedIndexDigest:indexDigest
                                                  error:error];
}

@end
