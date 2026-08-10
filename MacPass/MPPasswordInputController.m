//
//  MPPasswordInputController.m
//  MacPass
//
//  Created by Michael Starke on 17.02.13.
//  Copyright (c) 2013 HicknHack Software GmbH. All rights reserved.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

#import "MPPasswordInputController.h"
#import "MPAppDelegate.h"
#import "MPDocumentWindowController.h"
#import "MPDocument.h"
#import "MPDocument+BiometricEncryptionSupport.h"
#import "MPSettingsHelper.h"
#import "MPPathControl.h"
#import "MPTouchBarButtonCreator.h"
#import "MPSettingsHelper.h"
#import "MPConstants.h"
#import "MPTouchIdCompositeKeyStore.h"

#import "DDHotKey+MacPassAdditions.h"
#import "DDHotKeyUtilities.h"

#import "HNHUi/HNHUi.h"

#import "NSError+Messages.h"

#import <Carbon/Carbon.h>

@interface MPPasswordInputController ()

@property (strong) NSButton *showPasswordButton;
@property (weak) IBOutlet HNHUISecureTextField *passwordTextField;
@property (weak) IBOutlet MPPathControl *keyPathControl;
@property (weak) IBOutlet NSButton *resetKeyFileButton;
@property (weak) IBOutlet NSImageView *messageImageView;
@property (weak) IBOutlet NSTextField *messageInfoTextField;
@property (strong) IBOutlet NSTextField *keyFileWarningTextField;
@property (weak) IBOutlet NSButton *togglePasswordButton;
@property (weak) IBOutlet NSButton *enablePasswordCheckBox;
@property (weak) IBOutlet NSButton *unlockButton;
@property (weak) IBOutlet NSButton *cancelButton;
@property (weak) IBOutlet NSButton *touchIdButton;
@property (strong) IBOutlet NSPopUpButton *touchIdModeButton;
@property (weak) IBOutlet NSTextField *touchIdModeLabel;
@property (weak) IBOutlet NSSegmentedControl *unlockMethodControl;
@property (weak) IBOutlet NSView *touchIdCard;
@property (weak) IBOutlet NSView *manualCard;
@property (weak) IBOutlet NSView *touchIdFooter;
@property (weak) IBOutlet NSTextField *touchIdShortcutLabel;
@property (weak) IBOutlet NSTextField *touchIdProvisioningLabel;

@property (copy) NSString *message;
@property (copy) NSString *cancelLabel;

@property (assign) BOOL showPassword;
@property (nonatomic, assign) BOOL enablePassword;
@property (copy) passwordInputCompletionBlock completionHandler;

@property (strong) id touchIdShortcutMonitor;
@property (assign) BOOL touchIdFailedForPresentation;

@end

@implementation MPPasswordInputController

+ (MPPasswordInputPresentationState)presentationStateForTouchIDMode:(NSInteger)touchIDMode
                                                        keyAvailable:(BOOL)keyAvailable
                                                     shortcutEnabled:(BOOL)shortcutEnabled
                                                       shortcutValid:(BOOL)shortcutValid
                                                            supported:(BOOL)supported {
  BOOL enabledMode = (touchIDMode == MPTouchIDKeyStorageTransient || touchIDMode == MPTouchIDKeyStoragePersistent);
  if(!supported || !enabledMode) {
    return MPPasswordInputPresentationManualOnly;
  }
  if(!keyAvailable) {
    return MPPasswordInputPresentationProvisioningNeeded;
  }
  MPPasswordInputPresentationState state = MPPasswordInputPresentationTouchIDAvailable;
  if(shortcutEnabled && shortcutValid) {
    state |= MPPasswordInputPresentationShortcutAvailable;
  }
  return state;
}

+ (NSString *)touchIDShortcutHintForKeyData:(NSData *)keyData enabled:(BOOL)enabled {
  if(!enabled) {
    return nil;
  }
  DDHotKey *shortcut = [DDHotKey hotKeyWithKeyData:keyData];
  if(!shortcut.valid) {
    return nil;
  }
  NSString *shortcutString = DDStringFromKeyCode(shortcut.keyCode, shortcut.modifierFlags).uppercaseString;
  return [NSString stringWithFormat:NSLocalizedString(@"PASSWORD_INPUT_TOUCH_ID_SHORTCUT", @"Hint for the Touch ID unlock shortcut"), shortcutString];
}

- (NSString *)nibName {
  return @"PasswordInputView";
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
  self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
  if(self) {
    _enablePassword = YES;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(_selectKeyURL) name:MPDidChangeStoredKeyFilesSettings object:nil];
  }
  return self;
}

- (void)dealloc {
  [NSNotificationCenter.defaultCenter removeObserver:self];
  [self _unregisterTouchIdShortcutMonitor];
}

- (void)viewDidLoad {
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(_didSetKeyURL:) name:MPPathControlDidSetURLNotification object:self.keyPathControl];
  self.messageImageView.image = [NSImage imageNamed:NSImageNameCaution];
  [self.passwordTextField bind:NSStringFromSelector(@selector(showPassword)) toObject:self withKeyPath:NSStringFromSelector(@selector(showPassword)) options:nil];
  [self.togglePasswordButton bind:NSValueBinding toObject:self withKeyPath:NSStringFromSelector(@selector(showPassword)) options:nil];
  [self.enablePasswordCheckBox bind:NSValueBinding toObject:self withKeyPath:NSStringFromSelector(@selector(enablePassword)) options:nil];
  [self.togglePasswordButton bind:NSEnabledBinding toObject:self withKeyPath:NSStringFromSelector(@selector(enablePassword)) options:nil];
  [self.passwordTextField bind:NSEnabledBinding toObject:self withKeyPath:NSStringFromSelector(@selector(enablePassword)) options:nil];

  NSString *touchIdUnlockTitle = NSLocalizedString(@"PASSWORD_INPUT_UNLOCK_WITH_TOUCH_ID", @"Button to unlock a database with Touch ID");
  self.touchIdButton.title = touchIdUnlockTitle;
  self.touchIdButton.accessibilityLabel = touchIdUnlockTitle;
  self.togglePasswordButton.accessibilityLabel = NSLocalizedString(@"TOUCHBAR_SHOW_PASSWORD", @"Accessibility label for the show-password button");
  self.resetKeyFileButton.accessibilityLabel = NSLocalizedString(@"PASSWORD_INPUT_REMOVE_KEY_FILE", @"Accessibility label for the remove-key-file button");
  self.unlockMethodControl.accessibilityLabel = NSLocalizedString(@"PASSWORD_INPUT_UNLOCK_METHOD", @"Accessibility label for the unlock-method switcher");
  self.touchIdModeButton.accessibilityLabel = self.touchIdModeLabel.stringValue;
  
  NSMenu* touchIDMenu = [[NSMenu alloc] init];
  NSMenuItem *disabledItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"TOUCHID_DISABLED", @"menu item to disable touchid key storage")
                             action:NULL
                      keyEquivalent:@""];
  NSMenuItem *transitentItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"TOUCHID_TRANSIENT_KEY_STORAGE", @"menu item to enable transient touchid key storage")
                             action:NULL
                      keyEquivalent:@""];
  NSMenuItem *persistentItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"TOUCHID_PERSISTENT_KEY_STORAGE", @"menu item to enable persisntent touchid key storage")
                             action:NULL
                      keyEquivalent:@""];
  
  disabledItem.tag = MPTouchIDKeyStorageDisabled;
  transitentItem.tag = MPTouchIDKeyStorageTransient;
  persistentItem.tag = MPTouchIDKeyStoragePersistent;
  
  touchIDMenu.itemArray = @[disabledItem, transitentItem, persistentItem];
  self.touchIdModeButton.menu = touchIDMenu;
  [self.touchIdModeButton bind:NSSelectedTagBinding
                         toObject:NSUserDefaultsController.sharedUserDefaultsController
                      withKeyPath:[MPSettingsHelper defaultControllerPathForKey:kMPSettingsKeyTouchIdEnabled]
                          options:nil];
  [self _reset];
}

- (NSResponder *)reconmendedFirstResponder {
  return self.manualCard.hidden ? self.touchIdButton : self.passwordTextField;
}

- (void)requestPasswordWithMessage:(NSString *)message cancelLabel:(NSString *)cancelLabel completionHandler:(passwordInputCompletionBlock)completionHandler {
  [self requestPasswordWithMessage:message cancelLabel:cancelLabel attemptTouchID:NO completionHandler:completionHandler];
}

- (void)requestPasswordWithMessage:(NSString *)message cancelLabel:(NSString *)cancelLabel attemptTouchID:(BOOL)attemptTouchID completionHandler:(passwordInputCompletionBlock)completionHandler {
  self.completionHandler = completionHandler;
  self.message = message;
  self.cancelLabel = cancelLabel;
  [self _reset];
  [self _registerTouchIdShortcutMonitor];
  if(attemptTouchID && [self _touchIdIsUnlockAvailable]) {
    /* Dispatch async to ensure the UI is fully laid out before presenting the Touch ID prompt */
    dispatch_async(dispatch_get_main_queue(), ^{
      [self unlockWithTouchID:nil];
    });
  }
}

#pragma mark Properties
- (void)setEnablePassword:(BOOL)enablePassword {
  if(_enablePassword != enablePassword) {
    _enablePassword = enablePassword;
    if(!_enablePassword) {
      self.passwordTextField.stringValue = @"";
    }
  }
  if(_enablePassword) {
    self.passwordTextField.placeholderString = NSLocalizedString(@"PASSWORD_INPUT_ENTER_PASSWORD", "Placeholder in the unlock-password input field if password is enabled");
  }
  else {
    self.passwordTextField.placeholderString = NSLocalizedString(@"PASSWORD_INPUT_NO_PASSWORD", "Placeholder in the unlock-password input field if password is disabled");
  }
}

#pragma mark -
#pragma mark Touch ID Shortcut
- (void)_registerTouchIdShortcutMonitor {
  [self _unregisterTouchIdShortcutMonitor];
  if(![NSUserDefaults.standardUserDefaults boolForKey:kMPSettingsKeyTouchIdUnlockShortcutEnabled]) {
    return;
  }
  NSData *keyData = [NSUserDefaults.standardUserDefaults dataForKey:kMPSettingsKeyTouchIdUnlockShortcutKeyDataKey];
  DDHotKey *shortcutKey = [DDHotKey hotKeyWithKeyData:keyData];
  if(!shortcutKey.valid) {
    return;
  }
  __weak typeof(self) weakSelf = self;
  self.touchIdShortcutMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
    MPPasswordInputController *strongSelf = weakSelf;
    if(!strongSelf || !strongSelf.view.window) {
      return event;
    }
    if([strongSelf _event:event matchesHotKey:shortcutKey] && [strongSelf _touchIdIsUnlockAvailable]) {
      [strongSelf unlockWithTouchID:nil];
      return nil;
    }
    return event;
  }];
}

- (void)_unregisterTouchIdShortcutMonitor {
  if(self.touchIdShortcutMonitor) {
    [NSEvent removeMonitor:self.touchIdShortcutMonitor];
    self.touchIdShortcutMonitor = nil;
  }
}

- (BOOL)_event:(NSEvent *)event matchesHotKey:(DDHotKey *)hotKey {
  if(event.keyCode != hotKey.keyCode) {
    return NO;
  }
  NSEventModifierFlags eventFlags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
  NSEventModifierFlags hotKeyFlags = 0;
  if(hotKey.modifierFlags & kCGEventFlagMaskCommand)   hotKeyFlags |= NSEventModifierFlagCommand;
  if(hotKey.modifierFlags & kCGEventFlagMaskShift)     hotKeyFlags |= NSEventModifierFlagShift;
  if(hotKey.modifierFlags & kCGEventFlagMaskAlternate) hotKeyFlags |= NSEventModifierFlagOption;
  if(hotKey.modifierFlags & kCGEventFlagMaskControl)   hotKeyFlags |= NSEventModifierFlagControl;
  return eventFlags == hotKeyFlags;
}

- (BOOL)_touchIdControlsSupported {
  if (@available(macOS 10.13.4, *)) {
    return YES;
  }
  return NO;
}

- (DDHotKey *)_validTouchIdShortcut {
  if(![NSUserDefaults.standardUserDefaults boolForKey:kMPSettingsKeyTouchIdUnlockShortcutEnabled]) {
    return nil;
  }
  NSData *keyData = [NSUserDefaults.standardUserDefaults dataForKey:kMPSettingsKeyTouchIdUnlockShortcutKeyDataKey];
  DDHotKey *hotKey = [DDHotKey hotKeyWithKeyData:keyData];
  return hotKey.valid ? hotKey : nil;
}

- (void)_showManualCard:(BOOL)showManual moveFocus:(BOOL)moveFocus {
  self.manualCard.hidden = !showManual;
  self.touchIdCard.hidden = showManual;
  self.unlockMethodControl.selectedSegment = showManual ? 1 : 0;
  self.unlockButton.keyEquivalent = showManual ? @"\r" : @"";
  if(moveFocus && self.view.window) {
    [self.view.window makeFirstResponder:(showManual ? self.passwordTextField : self.touchIdButton)];
  }
}

- (IBAction)unlockMethodChanged:(NSSegmentedControl *)sender {
  [self _showManualCard:(sender.selectedSegment == 1) moveFocus:YES];
}

- (IBAction)touchIdModeChanged:(NSPopUpButton *)sender {
  [NSUserDefaultsController.sharedUserDefaultsController setValue:@(sender.selectedTag)
                                                        forKeyPath:[MPSettingsHelper defaultControllerPathForKey:kMPSettingsKeyTouchIdEnabled]];
  self.touchIdFailedForPresentation = NO;
  [self _updateUnlockPresentation];
  if(self.view.window) {
    [self.view.window makeFirstResponder:self.reconmendedFirstResponder];
  }
}

- (void)_updateUnlockPresentation {
  BOOL supported = [self _touchIdControlsSupported];
  NSInteger mode = self.touchIdModeButton.selectedTag;
  BOOL keyAvailable = [self _storedTouchIdKeyIsAvailable];
  DDHotKey *shortcut = [self _validTouchIdShortcut];
  MPPasswordInputPresentationState state = [self.class presentationStateForTouchIDMode:mode
                                                                          keyAvailable:keyAvailable
                                                                       shortcutEnabled:(shortcut != nil)
                                                                         shortcutValid:shortcut.valid
                                                                              supported:supported];
  BOOL touchIdAvailable = (state & MPPasswordInputPresentationTouchIDAvailable) != 0;

  self.touchIdFooter.hidden = !supported;
  self.unlockMethodControl.hidden = !touchIdAvailable;
  self.touchIdProvisioningLabel.hidden = (state & MPPasswordInputPresentationProvisioningNeeded) == 0;
  self.touchIdShortcutLabel.hidden = (state & MPPasswordInputPresentationShortcutAvailable) == 0;
  if(shortcut) {
    self.touchIdShortcutLabel.stringValue = [self.class touchIDShortcutHintForKeyData:shortcut.keyData enabled:YES];
  }
  self.touchIdProvisioningLabel.stringValue = NSLocalizedString(@"PASSWORD_INPUT_TOUCH_ID_PROVISIONING", @"Instructions for enabling Touch ID for a database");
  self.touchIdButton.enabled = touchIdAvailable && !self.touchIdFailedForPresentation;
  [self _showManualCard:!touchIdAvailable moveFocus:NO];
}

#pragma mark -
#pragma mark Private
- (IBAction)_submit:(id)sender {
  if(!self.completionHandler) {
    return;
  }
  
  /* No password is different than an empty password */
  NSError *error = nil;
  NSString *password = self.enablePassword ? self.passwordTextField.stringValue : nil;
  
  BOOL cancel = (sender == self.cancelButton);
  NSURL* keyURL = self.keyPathControl.URL;
  NSData *keyFileData = keyURL ? [NSData dataWithContentsOfURL:keyURL] : nil;
  KPKKey* passwordKey = [KPKKey keyWithPassword:password];
  KPKKey* fileKey = [KPKKey keyWithKeyFileData:keyFileData];
  KPKCompositeKey* compositeKey = [[KPKCompositeKey alloc] init];
  [compositeKey addKey:passwordKey];
  [compositeKey addKey:fileKey];
  /* After the completion handler finished we no longer have a windowController set */
  NSString* documentKey = [self biometricKeyForCurrentDocument];
  BOOL result = self.completionHandler(compositeKey, keyURL, cancel, &error);
  if(result) {
    [self _unregisterTouchIdShortcutMonitor];
    if(nil != documentKey) {
      [MPTouchIdCompositeKeyStore.defaultStore saveCompositeKey:compositeKey forDocumentKey:documentKey];
    }
    return;
  }
  if(cancel) {
    return;
  }
  [self _showError:error];
  /* do not shake if we are a sheet */
  if(!self.view.window.isSheet) {
    [self.view.window shakeWindow:nil];
  }
}
/*
- (KPKCompositeKey*)_touchIdDecryptCompositeKey:(NSData*)encryptedKey {
  NSError *error;
  return [MPTouchIdCompositeKeyStore.defaultStore compositeKeyForEncryptedKeyData:encryptedKey error:&error];
}*/

- (NSString *)biometricKeyForCurrentDocument {
  MPDocument* currentDocument = (MPDocument *)self.windowController.document;
  return currentDocument.biometricKey;
}

- (BOOL)_storedTouchIdKeyIsAvailable {
  MPDocument *currentDocument = (MPDocument *)self.windowController.document;
  return (nil != currentDocument.encryptedKeyData);
}

- (BOOL)_touchIdIsUnlockAvailable {
  NSInteger mode = self.touchIdModeButton.selectedTag;
  return [self _touchIdControlsSupported]
      && (mode == MPTouchIDKeyStorageTransient || mode == MPTouchIDKeyStoragePersistent)
      && !self.touchIdFailedForPresentation
      && [self _storedTouchIdKeyIsAvailable];
}

- (IBAction)unlockWithTouchID:(id)sender {
  NSString* documentKey = [self biometricKeyForCurrentDocument];
  if(nil == documentKey) {
    return;
  }
  NSData* encryptedKey = [MPTouchIdCompositeKeyStore.defaultStore loadEncryptedCompositeKeyForDocumentKey:documentKey];
  if(!encryptedKey) {
    self.touchIdFailedForPresentation = YES;
    self.touchIdButton.enabled = NO;
    return;
  }
  NSError *error;
  KPKCompositeKey* compositeKey = [MPTouchIdCompositeKeyStore.defaultStore compositeKeyForEncryptedKeyData:encryptedKey error:&error];
  if(!compositeKey) {
    self.touchIdFailedForPresentation = YES;
    self.touchIdButton.enabled = NO;
    [self _showError:error];
    return;
  }
  bool success = self.completionHandler(compositeKey, NULL, false, &error);
  if(success) {
    [self _unregisterTouchIdShortcutMonitor];
    return;
  }
  // TODO: clear encryptedKey if password was wrong? Show user feedback? 
  self.touchIdFailedForPresentation = YES;
  self.touchIdButton.enabled = NO;
  [self _showError:error];
}

- (IBAction)resetKeyFile:(id)sender {
  /* If the reset was triggered by ourselves we want to preselect the keyfile */
  if(sender == self) {
    [self _selectKeyURL];
  }
  else {
    self.keyPathControl.URL = nil;
  }
}

- (void)_reset {
  self.showPassword = NO;
  self.enablePassword = YES;
  self.passwordTextField.stringValue = @"";
  self.messageInfoTextField.hidden = (nil == self.message);
  self.touchIdFailedForPresentation = NO;

  if(self.message) {
    self.messageInfoTextField.stringValue = self.message;
    self.messageImageView.image = [NSImage imageNamed:NSImageNameInfo];
  }
  else {
    self.messageImageView.image = [NSImage imageNamed:NSImageNameCaution];
  }
  self.messageImageView.hidden = (nil == self.message);
  self.cancelButton.hidden = (nil == self.cancelLabel);
  if(self.cancelLabel) {
    self.cancelButton.stringValue = self.cancelLabel;
  }
  [self resetKeyFile:self];
  [self _updateUnlockPresentation];
}

- (void)_selectKeyURL {
  MPDocument *document = self.windowController.document;
  self.keyPathControl.URL = document.suggestedKeyURL;
}

- (void)_showError:(NSError *)error {
  if(error) {
    self.messageInfoTextField.stringValue = error.descriptionForErrorCode;
  }
  self.messageImageView.hidden = NO;
  self.messageImageView.image = [NSImage imageNamed:NSImageNameCaution];
  self.messageInfoTextField.hidden = NO;
}


- (NSTouchBar *)makeTouchBar {
  NSTouchBar *touchBar = [[NSTouchBar alloc] init];
  touchBar.delegate = self;
  touchBar.customizationIdentifier = MPTouchBarCustomizationIdentifierPasswordInput;
  NSArray<NSTouchBarItemIdentifier> *defaultItemIdentifiers = @[MPTouchBarItemIdentifierShowPassword, MPTouchBarItemIdentifierChooseKeyfile, NSTouchBarItemIdentifierFlexibleSpace,MPTouchBarItemIdentifierUnlock];
  touchBar.defaultItemIdentifiers = defaultItemIdentifiers;
  touchBar.customizationAllowedItemIdentifiers = defaultItemIdentifiers;
  return touchBar;
}

- (NSTouchBarItem *)touchBar:(NSTouchBar *)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier  API_AVAILABLE(macos(10.12.2)) {
  if (identifier == MPTouchBarItemIdentifierChooseKeyfile) {
    return [MPTouchBarButtonCreator touchBarButtonWithTitleAndImage:NSLocalizedString(@"TOUCHBAR_CHOOSE_KEYFILE","Touchbar button label for choosing the keyfile") identifier:MPTouchBarItemIdentifierChooseKeyfile image:[NSImage imageNamed:NSImageNameTouchBarFolderTemplate] target:self.keyPathControl selector:@selector(showOpenPanel:) customizationLabel:NSLocalizedString(@"TOUCHBAR_CHOOSE_KEYFILE","Touchbar button label for choosing the keyfile")];
  } else if (identifier == MPTouchBarItemIdentifierShowPassword) {
    NSTouchBarItem *item = [MPTouchBarButtonCreator touchBarButtonWithTitleAndImage:NSLocalizedString(@"TOUCHBAR_SHOW_PASSWORD","Touchbar button label for showing the password") identifier:MPTouchBarItemIdentifierShowPassword image:[NSImage imageNamed:NSImageNameTouchBarQuickLookTemplate] target:self selector:@selector(toggleShowPassword) customizationLabel:NSLocalizedString(@"TOUCHBAR_SHOW_PASSWORD","Touchbar button label for showing the password")];
    _showPasswordButton = (NSButton *) item.view;
    return item;
  } else if (identifier == MPTouchBarItemIdentifierUnlock) {
    return [MPTouchBarButtonCreator touchBarButtonWithImage:[NSImage imageNamed:NSImageNameLockUnlockedTemplate] identifier:MPTouchBarItemIdentifierUnlock target:self selector:@selector(_submit:) customizationLabel:NSLocalizedString(@"TOUCHBAR_UNLOCK_DATABASE","Touchbar button label for unlocking the database")];
  } else {
    return nil;
  }
}

- (void)toggleShowPassword {
  self.showPassword = !self.showPassword;
  self.showPasswordButton.bezelColor = self.showPassword ? [NSColor selectedControlColor] : [NSColor controlColor];
}

- (void)_didSetKeyURL:(NSNotification *)notification {
  if(notification.object != self.keyPathControl) {
    return; // wrong sender
  }
  NSDocument *document = (NSDocument *)self.windowController.document;
  NSData *keyFileData = [NSData dataWithContentsOfURL:self.keyPathControl.URL];
  KPKFileVersion keyFileVersion = [KPKFormat.sharedFormat fileVersionForData:keyFileData];
  BOOL isKdbDatabaseFile = (keyFileVersion.format != KPKDatabaseFormatUnknown);
  if(isKdbDatabaseFile) {
    if([document.fileURL isEqual:self.keyPathControl.URL]) {
      self.keyFileWarningTextField.stringValue = NSLocalizedString(@"WARNING_CURRENT_DATABASE_FILE_SELECTED_AS_KEY_FILE", "Error message displayed when the current database file is also set as the key file");
      self.keyFileWarningTextField.hidden = NO;
    }
    else {
      self.keyFileWarningTextField.stringValue = NSLocalizedString(@"WARNING_DATABASE_FILE_SELECTED_AS_KEY_FILE", "Error message displayed when a keepass database file is set as the key file");
      self.keyFileWarningTextField.hidden = NO;
    }
  }
  else {
    self.keyFileWarningTextField.stringValue = @"";
    self.keyFileWarningTextField.hidden = YES;
  }
}

@end
