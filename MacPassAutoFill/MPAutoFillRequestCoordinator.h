#import <AuthenticationServices/AuthenticationServices.h>
#import <Foundation/Foundation.h>
#import <Security/Security.h>

@class LAContext;
@class MPAutoFillCredentialRecord;
@class MPAutoFillGenerationStore;

NS_ASSUME_NONNULL_BEGIN

@interface MPAutoFillCredentialSelection : NSObject
@property(nonatomic, readonly, copy) NSString *title;
@property(nonatomic, readonly, copy) NSString *username;
@property(nonatomic, readonly, strong) ASPasswordCredential *credential;
@end

@protocol MPAutoFillPrivateKeyStore <NSObject>
- (nullable SecKeyRef)copyPrivateKeyForPublicationIdentifier:(NSString *)publicationIdentifier
                                       authenticationContext:(LAContext *)context
                                          interactionAllowed:(BOOL)interactionAllowed
                                                       error:(NSError **)error CF_RETURNS_RETAINED;
@end

@interface MPAutoFillRequestCoordinator : NSObject

+ (nullable instancetype)sharedCoordinator;
- (instancetype)initWithGenerationStore:(MPAutoFillGenerationStore *)generationStore
                           keychainStore:(id<MPAutoFillPrivateKeyStore>)keychainStore
                                 rootURL:(NSURL *)rootURL NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (nullable ASPasswordCredential *)credentialForIdentity:(ASPasswordCredentialIdentity *)identity
                                       interactionAllowed:(BOOL)interactionAllowed
                                                    error:(NSError **)error;
- (nullable NSArray<MPAutoFillCredentialSelection *> *)credentialsForServiceIdentifiers:
    (NSArray<ASCredentialServiceIdentifier *> *)serviceIdentifiers
                                                               error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
