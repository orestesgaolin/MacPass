#import <Foundation/Foundation.h>
#import <Security/Security.h>

@class LAContext;

NS_ASSUME_NONNULL_BEGIN

@protocol MPAutoFillCurrentGenerationStore <NSObject>
- (nullable NSString *)currentGenerationForPublicationIdentifier:(NSString *)publicationIdentifier error:(NSError **)error;
- (BOOL)setCurrentGeneration:(NSString *)generationIdentifier
     forPublicationIdentifier:(NSString *)publicationIdentifier
                        error:(NSError **)error;
- (BOOL)deleteCurrentGenerationForPublicationIdentifier:(NSString *)publicationIdentifier error:(NSError **)error;
@end

API_AVAILABLE(macos(11.0))
@interface MPAutoFillKeychainStore : NSObject <MPAutoFillCurrentGenerationStore>

- (instancetype)initWithAccessGroup:(NSString *)accessGroup NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (BOOL)createKeyPairForPublicationIdentifier:(NSString *)publicationIdentifier error:(NSError **)error;
- (nullable SecKeyRef)copyPublicKeyForPublicationIdentifier:(NSString *)publicationIdentifier
                                                       error:(NSError **)error CF_RETURNS_RETAINED;
- (nullable SecKeyRef)copyPrivateKeyForPublicationIdentifier:(NSString *)publicationIdentifier
                                       authenticationContext:(LAContext *)context
                                          interactionAllowed:(BOOL)interactionAllowed
                                                       error:(NSError **)error CF_RETURNS_RETAINED;
- (BOOL)deleteKeyPairForPublicationIdentifier:(NSString *)publicationIdentifier error:(NSError **)error;
- (nullable NSArray<NSString *> *)publicationIdentifiersWithError:(NSError **)error;

- (nullable NSString *)currentGenerationForPublicationIdentifier:(NSString *)publicationIdentifier error:(NSError **)error;
- (BOOL)setCurrentGeneration:(NSString *)generationIdentifier
     forPublicationIdentifier:(NSString *)publicationIdentifier
                        error:(NSError **)error;
- (BOOL)deleteCurrentGenerationForPublicationIdentifier:(NSString *)publicationIdentifier error:(NSError **)error;

+ (nullable NSData *)activationDataForGenerationIdentifier:(NSString *)generationIdentifier error:(NSError **)error;
+ (nullable NSString *)generationIdentifierFromActivationData:(NSData *)activationData
                                                 highWaterData:(nullable NSData *)highWaterData
                                                         error:(NSError **)error;
+ (nullable NSArray<NSString *> *)publicationIdentifiersFromKeyAttributes:(NSArray<NSDictionary *> *)keyAttributes
                                                activationAttributes:(NSArray<NSDictionary *> *)activationAttributes
                                                 highWaterAttributes:(NSArray<NSDictionary *> *)highWaterAttributes
                                                               error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
