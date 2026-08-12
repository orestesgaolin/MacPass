#import <Foundation/Foundation.h>
#import <Security/Security.h>

@class MPAutoFillSnapshot;

NS_ASSUME_NONNULL_BEGIN

@interface MPAutoFillEnvelopeCrypto : NSObject

+ (nullable NSData *)encryptSnapshot:(MPAutoFillSnapshot *)snapshot
                       withPublicKey:(SecKeyRef)publicKey
                               error:(NSError **)error;
+ (nullable MPAutoFillSnapshot *)decryptEnvelope:(NSData *)envelope
                                  withPrivateKey:(SecKeyRef)privateKey
                          publicationIdentifier:(NSString *)publicationIdentifier
                           generationIdentifier:(NSString *)generationIdentifier
                                    indexDigest:(NSData *)indexDigest
                                          error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
