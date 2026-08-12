#import <Cocoa/Cocoa.h>

@class MPAutoFillCredentialSelection;

NS_ASSUME_NONNULL_BEGIN

@protocol MPAutoFillCredentialListViewControllerDelegate <NSObject>
- (void)credentialListDidSelectCredential:(MPAutoFillCredentialSelection *)selection;
- (void)credentialListDidCancel;
@end

@interface MPAutoFillCredentialListViewController : NSViewController
@property(nonatomic, weak) id<MPAutoFillCredentialListViewControllerDelegate> delegate;
- (instancetype)initWithSelections:(NSArray<MPAutoFillCredentialSelection *> *)selections;
@end

NS_ASSUME_NONNULL_END
