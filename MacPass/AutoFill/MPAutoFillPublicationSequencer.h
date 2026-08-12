#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MPAutoFillPublicationSequencer : NSObject
- (uint64_t)beginSaveForPublicationIdentifier:(NSString *)publicationIdentifier;
- (BOOL)registerSuccessfulSaveToken:(uint64_t)saveToken publicationIdentifier:(NSString *)publicationIdentifier;
- (void)invalidatePublicationIdentifier:(NSString *)publicationIdentifier;
- (BOOL)performIfCurrentToken:(uint64_t)saveToken
        publicationIdentifier:(NSString *)publicationIdentifier
                       action:(BOOL (^)(NSError **error))action
                        error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
