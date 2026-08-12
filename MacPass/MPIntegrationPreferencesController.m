//
//  MPServerSettingsController.m
//  MacPass
//
//  Created by Michael Starke on 17.06.13.
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

#import "MPIntegrationPreferencesController.h"
#import "MPSettingsHelper.h"
#import "MPIconHelper.h"
#import "MPAutotypeDoctor.h"
#import "MPConstants.h"
#import "MPDocument.h"

#import <AuthenticationServices/AuthenticationServices.h>

#import "MPAutoFillCoordinator.h"
#import "MPAutoFillIdentityStoreUpdater.h"
#import "MPAutoFillPublicationRegistry.h"

#import "DDHotKeyCenter.h"
#import "DDHotKey+MacPassAdditions.h"
#import "DDHotKeyTextField.h"

@interface MPIntegrationPreferencesController ()

@property (nonatomic, strong) DDHotKey *hotKey;
@property (nonatomic, strong) DDHotKey *touchIdHotKey;
@property(nonatomic, strong) NSBox *autoFillBox;
@property(nonatomic, strong) NSTextField *autoFillProviderLabel;
@property(nonatomic, strong) NSTextField *autoFillStatusLabel;
@property(nonatomic, strong) NSPopUpButton *autoFillPublicationsButton;
@property(nonatomic, strong) NSButton *autoFillEnableButton;
@property(nonatomic, strong) NSButton *autoFillRemoveButton;

@end

@implementation MPIntegrationPreferencesController

- (NSString *)nibName {
  return @"IntegrationPreferences";
}

- (NSString *)identifier {
  return @"Integration";
}

- (NSImage *)image {
  return [NSImage imageNamed:NSImageNameComputer];
}

- (NSString *)label {
  return NSLocalizedString(@"INTEGRATION_SETTINGS", "Label for the integration settings tab");
}

- (void)awakeFromNib {
  NSUserDefaultsController *defaultsController = NSUserDefaultsController.sharedUserDefaultsController;
  NSString *enableGlobalAutotypeKeyPath = [MPSettingsHelper defaultControllerPathForKey:kMPSettingsKeyEnableGlobalAutotype];
  NSString *quicklookKeyPath = [MPSettingsHelper defaultControllerPathForKey:kMPSettingsKeyEnableQuicklookPreview];
  [self.enableGlobalAutotypeCheckBox bind:NSValueBinding toObject:defaultsController withKeyPath:enableGlobalAutotypeKeyPath options:nil];
  [self.enableQuicklookCheckBox bind:NSValueBinding toObject:defaultsController withKeyPath:quicklookKeyPath options:nil];
  [self.hotKeyTextField bind:NSEnabledBinding toObject:defaultsController withKeyPath:enableGlobalAutotypeKeyPath options:nil];
  self.hotKeyTextField.delegate = self;
  
  [self.matchTitleCheckBox bind:NSValueBinding toObject:defaultsController withKeyPath:[MPSettingsHelper defaultControllerPathForKey:kMPSettingsKeyAutotypeMatchTitle ] options:nil];
  [self.matchURLCheckBox bind:NSValueBinding toObject:defaultsController withKeyPath:[MPSettingsHelper defaultControllerPathForKey:kMPSettingsKeyAutotypeMatchURL] options:nil];
  [self.matchHostCheckBox bind:NSValueBinding toObject:defaultsController withKeyPath:[MPSettingsHelper defaultControllerPathForKey:kMPSettingsKeyAutotypeMatchHost] options:nil];
  [self.matchTagsCheckBox bind:NSValueBinding toObject:defaultsController withKeyPath:[MPSettingsHelper defaultControllerPathForKey:kMPSettingsKeyAutotypeMatchTags] options:nil];
  
  [self.sendCommandForControlCheckBox bind:NSValueBinding
                                  toObject:defaultsController
                               withKeyPath:[MPSettingsHelper defaultControllerPathForKey:kMPSettingsKeySendCommandForControlKey]
                                   options:nil];
  
  [self.alwaysShowConfirmationBeforeAutotypeCheckBox bind:NSValueBinding
                                                 toObject:defaultsController
                                              withKeyPath:[MPSettingsHelper defaultControllerPathForKey:kMPSettingsKeyGloablAutotypeAlwaysShowCandidateSelection]
                                                  options:nil];
  
  NSString *enableTouchIdShortcutKeyPath = [MPSettingsHelper defaultControllerPathForKey:kMPSettingsKeyTouchIdUnlockShortcutEnabled];
  [self.enableTouchIdShortcutCheckBox bind:NSValueBinding toObject:defaultsController withKeyPath:enableTouchIdShortcutKeyPath options:nil];
  [self.touchIdHotKeyTextField bind:NSEnabledBinding toObject:defaultsController withKeyPath:enableTouchIdShortcutKeyPath options:nil];
  self.touchIdHotKeyTextField.delegate = self;

  [self _showKeyCodeMissingKeyWarning:NO];
  [self _showTouchIdKeyCodeMissingKeyWarning:NO];
  [self _updateAccessabilityWarning];
  [self _installAutoFillSettings];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(_updateAutoFillSettings)
      name:MPAutoFillPublicationDidSucceedNotification object:nil];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(_autoFillPublicationFailed:)
      name:MPAutoFillPublicationDidFailNotification object:nil];
}

- (void)willShowTab {
  if(!_hotKey) {
    _hotKey = [DDHotKey hotKeyWithKeyData:[NSUserDefaults.standardUserDefaults dataForKey:kMPSettingsKeyGlobalAutotypeKeyDataKey]];
  }
  /* Only call the setter if the hotkeys are different, otherwise the dealloc call will unregister them*/
  if(![self.hotKeyTextField.hotKey isEqual:self.hotKey]) {
    self.hotKeyTextField.hotKey = self.hotKey;
  }

  if(!_touchIdHotKey) {
    NSData *touchIdKeyData = [NSUserDefaults.standardUserDefaults dataForKey:kMPSettingsKeyTouchIdUnlockShortcutKeyDataKey];
    if(touchIdKeyData) {
      _touchIdHotKey = [DDHotKey hotKeyWithKeyData:touchIdKeyData];
    }
  }
  if(_touchIdHotKey && ![self.touchIdHotKeyTextField.hotKey isEqual:self.touchIdHotKey]) {
    self.touchIdHotKeyTextField.hotKey = self.touchIdHotKey;
  }
  [self _updateAutoFillSettings];
  if (@available(macOS 11.0, *)) {
    [MPAutoFillIdentityStoreUpdater.sharedUpdater synchronizeWithCompletion:^(NSError *error) {
      [self _updateAutoFillSettings];
    }];
  }
}

- (void)_installAutoFillSettings {
  if (self.autoFillBox) return;
  NSView *root = self.view;
  NSView *bottomView = nil;
  NSLayoutConstraint *bottomConstraint = nil;
  for (NSLayoutConstraint *constraint in root.constraints) {
    if (constraint.firstItem == root && constraint.firstAttribute == NSLayoutAttributeBottom &&
        constraint.secondItem && constraint.secondAttribute == NSLayoutAttributeBottom) {
      bottomView = constraint.secondItem;
      bottomConstraint = constraint;
      break;
    }
  }
  if (!bottomView || !bottomConstraint) return;
  [root removeConstraint:bottomConstraint];

  self.autoFillBox = [[NSBox alloc] init];
  self.autoFillBox.title = NSLocalizedString(@"AUTOFILL_PREFERENCES_TITLE", @"AutoFill preferences section title");
  self.autoFillBox.translatesAutoresizingMaskIntoConstraints = NO;
  NSStackView *stack = [[NSStackView alloc] init];
  stack.orientation = NSUserInterfaceLayoutOrientationVertical;
  stack.alignment = NSLayoutAttributeLeading;
  stack.spacing = 8;
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  self.autoFillProviderLabel = [NSTextField wrappingLabelWithString:@""];
  self.autoFillStatusLabel = [NSTextField wrappingLabelWithString:@""];
  self.autoFillPublicationsButton = [[NSPopUpButton alloc] init];
  self.autoFillPublicationsButton.accessibilityLabel = NSLocalizedString(@"AUTOFILL_PUBLICATIONS_ACCESSIBILITY_LABEL", @"");
  self.autoFillEnableButton = [NSButton buttonWithTitle:NSLocalizedString(@"AUTOFILL_PUBLISH_CURRENT_DATABASE", @"")
      target:self action:@selector(enableCurrentDatabaseForAutoFill:)];
  self.autoFillEnableButton.accessibilityLabel = NSLocalizedString(@"AUTOFILL_PUBLISH_CURRENT_DATABASE", @"");
  self.autoFillRemoveButton = [NSButton buttonWithTitle:NSLocalizedString(@"AUTOFILL_REMOVE_PUBLICATION", @"")
      target:self action:@selector(removeSelectedAutoFillPublication:)];
  self.autoFillRemoveButton.accessibilityLabel = NSLocalizedString(@"AUTOFILL_REMOVE_PUBLICATION", @"");
  NSButton *settingsButton = [NSButton buttonWithTitle:NSLocalizedString(@"AUTOFILL_OPEN_SETTINGS", @"")
      target:self action:@selector(openAutoFillSettings:)];
  settingsButton.accessibilityLabel = NSLocalizedString(@"AUTOFILL_OPEN_SETTINGS", @"");
  NSStackView *buttons = [NSStackView stackViewWithViews:@[self.autoFillEnableButton, self.autoFillRemoveButton, settingsButton]];
  buttons.orientation = NSUserInterfaceLayoutOrientationVertical;
  buttons.alignment = NSLayoutAttributeLeading;
  buttons.spacing = 8;
  [stack addArrangedSubview:self.autoFillProviderLabel];
  [stack addArrangedSubview:self.autoFillStatusLabel];
  [stack addArrangedSubview:self.autoFillPublicationsButton];
  [stack addArrangedSubview:buttons];
  [self.autoFillBox.contentView addSubview:stack];
  [root addSubview:self.autoFillBox];
  [NSLayoutConstraint activateConstraints:@[
    [self.autoFillBox.topAnchor constraintEqualToAnchor:bottomView.bottomAnchor constant:8],
    [self.autoFillBox.leadingAnchor constraintEqualToAnchor:bottomView.leadingAnchor],
    [self.autoFillBox.trailingAnchor constraintEqualToAnchor:bottomView.trailingAnchor],
    [root.bottomAnchor constraintEqualToAnchor:self.autoFillBox.bottomAnchor constant:20],
    [stack.topAnchor constraintEqualToAnchor:self.autoFillBox.topAnchor constant:25],
    [stack.leadingAnchor constraintEqualToAnchor:self.autoFillBox.leadingAnchor constant:16],
    [stack.trailingAnchor constraintEqualToAnchor:self.autoFillBox.trailingAnchor constant:-16],
    [self.autoFillBox.bottomAnchor constraintEqualToAnchor:stack.bottomAnchor constant:16],
  ]];
  NSRect frame = root.frame;
  frame.size.height += 220;
  root.frame = frame;
}

- (MPDocument *)_currentAutoFillDocument {
  NSDocument *document = NSDocumentController.sharedDocumentController.currentDocument;
  return [document isKindOfClass:MPDocument.class] ? (MPDocument *)document : nil;
}

- (void)_updateAutoFillSettings {
  if (!self.autoFillBox) return;
  if (@available(macOS 11.0, *)) {
    MPAutoFillIdentityStoreUpdater *updater = MPAutoFillIdentityStoreUpdater.sharedUpdater;
    NSString *provider = updater.state == MPAutoFillIdentitySyncStateStoreDisabled ?
        NSLocalizedString(@"AUTOFILL_PROVIDER_DISABLED", @"") : NSLocalizedString(@"AUTOFILL_PROVIDER_AVAILABLE", @"");
    self.autoFillProviderLabel.stringValue = provider;
    if (updater.state == MPAutoFillIdentitySyncStateFailed) {
      self.autoFillStatusLabel.stringValue = NSLocalizedString(@"AUTOFILL_SYNC_FAILED", @"");
    } else if (updater.state == MPAutoFillIdentitySyncStateSynchronizing) {
      self.autoFillStatusLabel.stringValue = NSLocalizedString(@"AUTOFILL_SYNCHRONIZING", @"");
    } else {
      self.autoFillStatusLabel.stringValue = [NSString stringWithFormat:NSLocalizedString(@"AUTOFILL_SYNC_COUNT_%lu", @""),
          (unsigned long)updater.lastIdentityCount];
    }
  } else {
    self.autoFillProviderLabel.stringValue = NSLocalizedString(@"AUTOFILL_REQUIRES_MACOS_11", @"");
    self.autoFillStatusLabel.stringValue = NSLocalizedString(@"AUTOFILL_UPDATE_MACOS", @"");
  }
  NSArray *summaries = MPAutoFillPublicationRegistry.sharedRegistry.publicationSummaries;
  [self.autoFillPublicationsButton removeAllItems];
  NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
  formatter.dateStyle = NSDateFormatterMediumStyle;
  formatter.timeStyle = NSDateFormatterShortStyle;
  for (NSDictionary *summary in summaries) {
    NSString *date = summary[@"published"] ? [formatter stringFromDate:summary[@"published"]] : NSLocalizedString(@"AUTOFILL_PENDING", @"");
    [self.autoFillPublicationsButton addItemWithTitle:[NSString stringWithFormat:@"%@ - %@", summary[@"name"], date]];
    self.autoFillPublicationsButton.lastItem.representedObject = summary[@"publication"];
  }
  self.autoFillPublicationsButton.enabled = summaries.count > 0;
  self.autoFillRemoveButton.enabled = summaries.count > 0;
  MPDocument *document = [self _currentAutoFillDocument];
  if (@available(macOS 11.0, *)) {
    NSString *rootIdentifier = document.root.uuid.UUIDString.lowercaseString;
    BOOL published = document && [MPAutoFillPublicationRegistry.sharedRegistry
        publicationIdentifierForDocument:document sourceURL:document.fileURL rootIdentifier:rootIdentifier] != nil;
    self.autoFillEnableButton.title = published ? NSLocalizedString(@"AUTOFILL_CURRENT_DATABASE_PUBLISHED", @"") :
        NSLocalizedString(@"AUTOFILL_PUBLISH_CURRENT_DATABASE", @"");
    self.autoFillEnableButton.enabled = !published && document.fileURL.isFileURL && document.tree != nil &&
        document.compositeKey.hasKeys && !document.documentEdited;
  } else {
    self.autoFillEnableButton.enabled = NO;
  }
}

- (void)_autoFillPublicationFailed:(NSNotification *)notification {
  self.autoFillStatusLabel.stringValue = NSLocalizedString(@"AUTOFILL_PUBLICATION_FAILED", @"");
}

- (IBAction)enableCurrentDatabaseForAutoFill:(id)sender {
  if (@available(macOS 11.0, *)) {
    MPDocument *document = [self _currentAutoFillDocument];
    if (!document.fileURL.isFileURL || !document.tree || !document.compositeKey.hasKeys || document.documentEdited) {
      self.autoFillStatusLabel.stringValue = NSLocalizedString(@"AUTOFILL_UNLOCK_AND_SAVE", @"");
      return;
    }
    NSString *rootIdentifier = document.root.uuid.UUIDString.lowercaseString;
    MPAutoFillPublicationRegistry *registry = MPAutoFillPublicationRegistry.sharedRegistry;
    if ([registry publicationIdentifierForDocument:document sourceURL:document.fileURL rootIdentifier:rootIdentifier]) return;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = NSLocalizedString(@"AUTOFILL_CONFIRM_TITLE", @"");
    alert.informativeText = NSLocalizedString(@"AUTOFILL_CONFIRM_MESSAGE", @"");
    [alert addButtonWithTitle:NSLocalizedString(@"AUTOFILL_PUBLISH", @"")];
    [alert addButtonWithTitle:NSLocalizedString(@"CANCEL", @"")];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    NSData *savedData = [NSData dataWithContentsOfURL:document.fileURL options:NSDataReadingUncached error:NULL];
    NSString *publication = NSUUID.UUID.UUIDString.lowercaseString;
    NSError *error = nil;
    MPAutoFillCoordinator *coordinator = MPAutoFillCoordinator.sharedCoordinator;
    BOOL prepared = savedData && [coordinator preparePublicationIdentifier:publication registrationBlock:^BOOL(NSError **registrationError) {
      return [registry enablePublicationIdentifier:publication forDocument:document
          sourceURL:document.fileURL rootIdentifier:rootIdentifier error:registrationError];
    } error:&error];
    if (!prepared) {
      self.autoFillStatusLabel.stringValue = NSLocalizedString(@"AUTOFILL_ENABLE_FAILED", @"");
      return;
    }
    uint64_t token = [coordinator beginSaveForPublicationIdentifier:publication];
    [coordinator publishSavedData:savedData key:document.compositeKey publicationIdentifier:publication saveToken:token];
    [self _updateAutoFillSettings];
  }
}

- (IBAction)removeSelectedAutoFillPublication:(id)sender {
  NSString *publication = self.autoFillPublicationsButton.selectedItem.representedObject;
  if (!publication) return;
  self.autoFillRemoveButton.enabled = NO;
  [MPAutoFillCoordinator.sharedCoordinator unpublishPublicationIdentifier:publication completion:^(NSError *error) {
    self.autoFillStatusLabel.stringValue = error ?
        NSLocalizedString(@"AUTOFILL_CLEANUP_RETRY", @"") :
        NSLocalizedString(@"AUTOFILL_PUBLICATION_REMOVED", @"");
    [self _updateAutoFillSettings];
  }];
}

- (IBAction)openAutoFillSettings:(id)sender {
  if (@available(macOS 15.0, *)) {
    [ASSettingsHelper requestToTurnOnCredentialProviderExtensionWithCompletionHandler:^(BOOL enabled) {
      dispatch_async(dispatch_get_main_queue(), ^{ [self _updateAutoFillSettings]; });
    }];
  } else if (@available(macOS 14.0, *)) {
    [ASSettingsHelper openCredentialProviderAppSettingsWithCompletionHandler:nil];
  } else if (@available(macOS 11.0, *)) {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.Passwords-Settings.extension"]];
  }
}

#pragma mark -
#pragma mark Properties
- (void)setHotKey:(DDHotKey *)hotKey {
  if([self.hotKey isEqual:hotKey]) {
    return; // Nothing of interest has changed;
  }
  _hotKey = hotKey;
  [NSUserDefaults.standardUserDefaults setObject:self.hotKey.keyData forKey:kMPSettingsKeyGlobalAutotypeKeyDataKey];
}

- (void)setTouchIdHotKey:(DDHotKey *)touchIdHotKey {
  if([self.touchIdHotKey isEqual:touchIdHotKey]) {
    return;
  }
  _touchIdHotKey = touchIdHotKey;
  [NSUserDefaults.standardUserDefaults setObject:self.touchIdHotKey.keyData forKey:kMPSettingsKeyTouchIdUnlockShortcutKeyDataKey];
}

#pragma mark -
#pragma mark NSTextFieldDelegate

- (void)controlTextDidChange:(NSNotification *)obj {
  if(obj.object == self.hotKeyTextField) {
    BOOL validHotKey = self.hotKeyTextField.hotKey.valid;
    [self _showKeyCodeMissingKeyWarning:!validHotKey];
    if(validHotKey) {
      self.hotKey = self.hotKeyTextField.hotKey;
    }
  }
  else if(obj.object == self.touchIdHotKeyTextField) {
    BOOL validHotKey = self.touchIdHotKeyTextField.hotKey.valid;
    [self _showTouchIdKeyCodeMissingKeyWarning:!validHotKey];
    if(validHotKey) {
      self.touchIdHotKey = self.touchIdHotKeyTextField.hotKey;
    }
  }
}

- (void)_showKeyCodeMissingKeyWarning:(BOOL)show {
  self.hotkeyWarningTextField.hidden = !show;
}

- (void)_showTouchIdKeyCodeMissingKeyWarning:(BOOL)show {
  self.touchIdHotkeyWarningTextField.hidden = !show;
}

- (void)_updateAccessabilityWarning {
  
  BOOL hasAutotypeSupport = MPAutotypeDoctor.defaultDoctor.hasNecessaryAutotypePermissions;
  
  if(hasAutotypeSupport) {
    [self.autotypeStackView setVisibilityPriority:NSStackViewVisibilityPriorityNotVisible forView:self.autotypeWarningTextField];
    [self.autotypeStackView setVisibilityPriority:NSStackViewVisibilityPriorityNotVisible forView:self.openPreferencesButton];
  }
  else {
    [self.autotypeStackView setVisibilityPriority:NSStackViewVisibilityPriorityMustHold forView:self.autotypeWarningTextField];
    [self.autotypeStackView setVisibilityPriority:NSStackViewVisibilityPriorityMustHold forView:self.openPreferencesButton];
  }
}

- (void)runAutotypeDoctor:(id)sender {
  [MPAutotypeDoctor.defaultDoctor runChecksAndPresentResults];
}

#pragma mark -
#pragma mark Keychain Actions
- (IBAction)renewTouchIdKey:(id)sender {
    NSData* publicKeyTag = [MPTouchIdUnlockPublicKeyTag dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *publicKeyQuery = @{
      (id)kSecClass: (id)kSecClassKey,
      (id)kSecAttrApplicationTag: publicKeyTag,
      (id)kSecReturnRef: @YES,
    };
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)publicKeyQuery);
    if (status != errSecSuccess) {
      NSString* description = CFBridgingRelease(SecCopyErrorMessageString(status, NULL));
        NSLog(@"Error while trying to delete public key from Keychain: %@", description);
    }
    
    NSData* privateKeyTag = [MPTouchIdUnlockPrivateKeyTag dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *privateKeyQuery = @{
      (id)kSecClass: (id)kSecClassKey,
      (id)kSecAttrApplicationTag: privateKeyTag,
      (id)kSecReturnRef: @YES,
    };
    status = SecItemDelete((__bridge CFDictionaryRef)privateKeyQuery);
    if (status != errSecSuccess) {
        NSString* description = CFBridgingRelease(SecCopyErrorMessageString(status, NULL));
        NSLog(@"Error while trying to delete private key from Keychain: %@", description);
    }
}
@end
