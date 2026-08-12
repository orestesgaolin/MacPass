#import "CredentialProviderViewController.h"

#import "MPAutoFillCredentialListViewController.h"
#import "MPAutoFillErrors.h"
#import "MPAutoFillRequestCoordinator.h"

@interface CredentialProviderViewController () <MPAutoFillCredentialListViewControllerDelegate>
@property(nonatomic, strong) MPAutoFillRequestCoordinator *requestCoordinator;
@property(nonatomic, strong) MPAutoFillCredentialListViewController *listViewController;
@end

@implementation CredentialProviderViewController

- (void)loadView {
  NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 420, 180)];
  NSTextField *label = [NSTextField wrappingLabelWithString:
      NSLocalizedString(@"AUTOFILL_PROVIDER_CONFIGURATION_MESSAGE", nil)];
  label.alignment = NSTextAlignmentCenter;
  label.translatesAutoresizingMaskIntoConstraints = NO;
  NSButton *button = [NSButton buttonWithTitle:NSLocalizedString(@"AUTOFILL_PROVIDER_FINISH_SETUP", nil)
                                         target:self action:@selector(finishSetup:)];
  button.keyEquivalent = @"\r";
  button.translatesAutoresizingMaskIntoConstraints = NO;
  [view addSubview:label];
  [view addSubview:button];
  [NSLayoutConstraint activateConstraints:@[
    [label.topAnchor constraintEqualToAnchor:view.topAnchor constant:36],
    [label.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:32],
    [label.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-32],
    [button.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:24],
    [button.centerXAnchor constraintEqualToAnchor:view.centerXAnchor],
  ]];
  self.view = view;
}

- (MPAutoFillRequestCoordinator *)requestCoordinator {
  if (!_requestCoordinator) _requestCoordinator = MPAutoFillRequestCoordinator.sharedCoordinator;
  return _requestCoordinator;
}

- (void)prepareInterfaceForExtensionConfiguration {}

- (void)prepareCredentialListForServiceIdentifiers:(NSArray<ASCredentialServiceIdentifier *> *)serviceIdentifiers {
  NSError *error = nil;
  NSArray *selections = [self.requestCoordinator credentialsForServiceIdentifiers:serviceIdentifiers error:&error];
  if (!selections) { [self cancelForError:error]; return; }
  self.listViewController = [[MPAutoFillCredentialListViewController alloc] initWithSelections:selections];
  self.listViewController.delegate = self;
  self.view = self.listViewController.view;
}

- (void)provideCredentialWithoutUserInteractionForIdentity:(ASPasswordCredentialIdentity *)identity {
  [self provideCredentialForIdentity:identity interactionAllowed:NO];
}

- (void)prepareInterfaceToProvideCredentialForIdentity:(ASPasswordCredentialIdentity *)identity {
  [self provideCredentialForIdentity:identity interactionAllowed:YES];
}

- (void)provideCredentialWithoutUserInteractionForRequest:(id<ASCredentialRequest>)request API_AVAILABLE(macos(14.0)) {
  [self provideCredentialForRequest:request interactionAllowed:NO];
}

- (void)prepareInterfaceToProvideCredentialForRequest:(id<ASCredentialRequest>)request API_AVAILABLE(macos(14.0)) {
  [self provideCredentialForRequest:request interactionAllowed:YES];
}

- (void)provideCredentialForRequest:(id<ASCredentialRequest>)request interactionAllowed:(BOOL)interactionAllowed
    API_AVAILABLE(macos(14.0)) {
  id identity = request.credentialIdentity;
  if (request.type != ASCredentialRequestTypePassword || ![identity isKindOfClass:ASPasswordCredentialIdentity.class]) {
    [self cancelWithCode:ASExtensionErrorCodeCredentialIdentityNotFound];
    return;
  }
  [self provideCredentialForIdentity:identity interactionAllowed:interactionAllowed];
}

- (void)provideCredentialForIdentity:(ASPasswordCredentialIdentity *)identity
                  interactionAllowed:(BOOL)interactionAllowed {
  NSError *error = nil;
  ASPasswordCredential *credential = [self.requestCoordinator credentialForIdentity:identity
                                                                 interactionAllowed:interactionAllowed error:&error];
  if (!credential) { [self cancelForError:error]; return; }
  [self.extensionContext completeRequestWithSelectedCredential:credential completionHandler:nil];
}

- (void)cancelForError:(NSError *)error {
  ASExtensionErrorCode code = ASExtensionErrorCodeFailed;
  if ([error.domain isEqualToString:MPAutoFillErrorDomain]) {
    if (error.code == MPAutoFillErrorUserInteractionRequired) code = ASExtensionErrorCodeUserInteractionRequired;
    else if (error.code == MPAutoFillErrorUserCancelled) code = ASExtensionErrorCodeUserCanceled;
    else if (error.code == MPAutoFillErrorItemNotFound || error.code == MPAutoFillErrorInvalidArgument) {
      code = ASExtensionErrorCodeCredentialIdentityNotFound;
    }
  }
  [self cancelWithCode:code];
}

- (void)cancelWithCode:(ASExtensionErrorCode)code {
  [self.extensionContext cancelRequestWithError:[NSError errorWithDomain:ASExtensionErrorDomain code:code userInfo:nil]];
}

- (void)credentialListDidSelectCredential:(MPAutoFillCredentialSelection *)selection {
  [self.extensionContext completeRequestWithSelectedCredential:selection.credential completionHandler:nil];
  self.listViewController = nil;
}

- (void)credentialListDidCancel {
  [self cancelWithCode:ASExtensionErrorCodeUserCanceled];
  self.listViewController = nil;
}

- (void)finishSetup:(id)sender { [self.extensionContext completeExtensionConfigurationRequest]; }

@end
