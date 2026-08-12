#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MPAutoFillCredentialIdentifier : NSObject

@property(nonatomic, readonly, copy) NSString *publicationIdentifier;
@property(nonatomic, readonly, copy) NSString *entryIdentifier;
@property(nonatomic, readonly, copy) NSString *recordIdentifier;

+ (nullable instancetype)identifierWithPublicationIdentifier:(NSString *)publicationIdentifier
                                              entryIdentifier:(NSString *)entryIdentifier
                                                        error:(NSError **)error;
+ (nullable instancetype)identifierWithRecordIdentifier:(NSString *)recordIdentifier
                                                   error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
