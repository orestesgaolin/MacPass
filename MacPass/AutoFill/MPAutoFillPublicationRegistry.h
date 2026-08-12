#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface MPAutoFillPublicationRegistry : NSObject

+ (instancetype)sharedRegistry;
- (instancetype)initWithRootURL:(NSURL *)rootURL;

@property(nonatomic, readonly, copy) NSArray<NSString *> *publicationIdentifiers;
@property(nonatomic, readonly, copy) NSArray<NSDictionary<NSString *, id> *> *publicationSummaries;
@property(nonatomic, readonly, getter=isAuthoritative) BOOL authoritative;

- (nullable NSString *)publicationIdentifierForDocument:(NSDocument *)document
                                               sourceURL:(NSURL *)sourceURL
                                          rootIdentifier:(NSString *)rootIdentifier;
- (void)detachDocument:(NSDocument *)document;
- (BOOL)enablePublicationIdentifier:(NSString *)publicationIdentifier
                         forDocument:(NSDocument *)document
                           sourceURL:(NSURL *)sourceURL
                      rootIdentifier:(NSString *)rootIdentifier
                               error:(NSError **)error;
- (BOOL)movePublicationIdentifier:(NSString *)publicationIdentifier
                      forDocument:(NSDocument *)document
                        sourceURL:(NSURL *)sourceURL
                   rootIdentifier:(NSString *)rootIdentifier
                            error:(NSError **)error;
- (BOOL)removePublicationIdentifier:(NSString *)publicationIdentifier error:(NSError **)error;
- (BOOL)markPublicationIdentifierPublished:(NSString *)publicationIdentifier atDate:(NSDate *)date error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
