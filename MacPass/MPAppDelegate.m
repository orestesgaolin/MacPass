//
//  MPAppDelegate.m
//  MacPass
//
//  Created by Michael Starke on 19.07.12.
//  Copyright (c) 2012 HicknHack Software GmbH. All rights reserved.
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

#import "MPAppDelegate.h"

#import "MPAutotypeDaemon.h"
#import "MPConstants.h"
#import "MPContextMenuHelper.h"
#import "MPDockTileHelper.h"
#import "MPDocument.h"
#import "MPDocumentController.h"
#import "MPDocumentWindowController.h"
#import "MPLockDaemon.h"
#import "MPPasswordCreatorViewController.h"
#import "MPPluginHost.h"
#import "MPSettingsHelper.h"
#import "MPPreferencesWindowController.h"
#import "MPStringLengthValueTransformer.h"
#import "MPPrettyPasswordTransformer.h"
#import "MPTemporaryFileStorageCenter.h"
#import "MPValueTransformerHelper.h"
#import "MPUserNotificationCenterDelegate.h"
#import "MPWelcomeViewController.h"
#import "MPPlugin.h"
#import "MPEntryContextMenuDelegate.h"
#import "MPAutotypeDoctor.h"
#import "AutoFill/MPAutoFillCoordinator.h"

#import "NSApplication+MPAdditions.h"
#import "NSTextView+MPTouchBarExtension.h"

#import "KeePassKit/KeePassKit.h"

#import <Sparkle/Sparkle.h>

NSString *const MPDidChangeStoredKeyFilesSettings = @"com.hicknhack.macpass.MPDidChangeStoredKeyFilesSettings";

static void *MPHideDockIconObservingContext = &MPHideDockIconObservingContext;

typedef NS_OPTIONS(NSInteger, MPAppStartupState) {
  MPAppStartupStateNone = 0,
  MPAppStartupStateRestoredWindows = 1,
  MPAppStartupStateFinishedLaunch = 2
};

@interface MPAppDelegate () {
@private
  MPDockTileHelper *_dockTileHelper;
  MPUserNotificationCenterDelegate *_userNotificationCenterDelegate;
  NSStatusItem *_statusItem; // status bar item shown while the Dock icon is hidden
  BOOL _regularPolicyRequested; // YES if the user explicitly brought MacPass to front, keeps the Dock icon while windows are open
  BOOL _shouldOpenFile; // YES if app was started to open a
}

@property (strong) NSWindow *welcomeWindow;
@property (strong) SPUUpdater *updater;
@property (strong) IBOutlet NSWindow *passwordCreatorWindow;
@property (strong, nonatomic) MPPreferencesWindowController *preferencesController;
@property (strong, nonatomic) MPPasswordCreatorViewController *passwordCreatorController;
@property (assign, nonatomic) MPAppStartupState startupState;

@property (strong) MPEntryContextMenuDelegate *itemActionMenuDelegate;

@end

@implementation MPAppDelegate

+ (void)initialize {
  [MPSettingsHelper setupDefaults];
  [MPSettingsHelper migrateDefaults];
  [MPStringLengthValueTransformer registerTransformer];
  [MPPrettyPasswordTransformer registerTransformer];
  [MPValueTransformerHelper registerValueTransformer];
}

- (instancetype)init {
  self = [super init];
  if(self) {
    _userNotificationCenterDelegate = [[MPUserNotificationCenterDelegate alloc] init];
    self.itemActionMenuDelegate = [[MPEntryContextMenuDelegate alloc] init];
    _shouldOpenFile = NO;
    _regularPolicyRequested = YES; // launching the app counts as explicitly bringing it to front
    _isTerminating = NO;
    self.startupState = MPAppStartupStateNone;
    
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(_applicationDidFinishRestoringWindows:)
                                               name:NSApplicationDidFinishRestoringWindowsNotification
                                             object:nil];
    
    /* We know that we do not use the variable after instantiation */
    MPDocumentController *documentController = [[MPDocumentController alloc] init];
    NSAssert(documentController, @"Custom document controller cannot be nil");    
  }
  return self;
}

- (void)dealloc {
  [self unbind:NSStringFromSelector(@selector(isAllowedToStoreKeyFile))];
  [NSNotificationCenter.defaultCenter removeObserver:self];
  [NSUserDefaults.standardUserDefaults removeObserver:self forKeyPath:kMPSettingsKeyHideDockIcon context:MPHideDockIconObservingContext];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
  if(context == MPHideDockIconObservingContext) {
    [self _updateDockIconVisibility];
  }
  else {
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
  }
}

- (void)_updateDockIconVisibility {
  BOOL hideDockIcon = [NSUserDefaults.standardUserDefaults boolForKey:kMPSettingsKeyHideDockIcon];
  [self _updateStatusItemVisibility:hideDockIcon];
  /* toggling the setting takes effect right away, until the user explicitly brings MacPass back to front */
  _regularPolicyRequested = NO;
  [self _updateActivationPolicy];
}

- (void)_updateActivationPolicy {
  /*
   With the Dock icon hidden MacPass runs as an accessory application. When the user explicitly
   brings it back to front (status bar item, Spotlight, opening a file) it turns into a regular
   application again to get its main menu and Dock icon back and retreats once every window is closed.
   */
  BOOL hideDockIcon = [NSUserDefaults.standardUserDefaults boolForKey:kMPSettingsKeyHideDockIcon];
  NSApplicationActivationPolicy policy = NSApplicationActivationPolicyRegular;
  if(hideDockIcon && !_regularPolicyRequested) {
    policy = NSApplicationActivationPolicyAccessory;
  }
  if(NSApp.activationPolicy == policy) {
    return;
  }
  if(policy == NSApplicationActivationPolicyAccessory) {
    BOOL keepInFront = NSApp.isActive && [self _hasVisibleWindows];
    [NSApp setActivationPolicy:policy];
    if(keepInFront) {
      /* switching to accessory deactivates the application, reactivate to keep open windows in front */
      dispatch_async(dispatch_get_main_queue(), ^{
        [NSApp activateIgnoringOtherApps:YES];
      });
    }
    return;
  }
  BOOL wasActive = NSApp.isActive;
  [NSApp setActivationPolicy:policy];
  if(wasActive) {
    /*
     AppKit does not attach a working main menu when the policy turns regular while the
     application is active. Hand activation to the Dock and re-activate shortly after,
     the app switch makes the freshly attached main menu functional.
     */
    NSRunningApplication *dockApp = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.dock"].firstObject;
    [dockApp activateWithOptions:0];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      [NSApp activateIgnoringOtherApps:YES];
    });
  }
}

- (BOOL)_hasVisibleWindows {
  for(NSWindow *window in NSApp.windows) {
    /* only consider titled windows, skips the status bar item, menu tracking and other utility windows */
    if(!(window.styleMask & NSWindowStyleMaskTitled)) {
      continue;
    }
    /* treat miniaturized windows as visible, otherwise their Dock tiles vanish when the policy changes */
    if(window.isVisible || window.isMiniaturized) {
      return YES;
    }
  }
  return NO;
}

- (void)_updateStatusItemVisibility:(BOOL)showStatusItem {
  if(showStatusItem && !_statusItem) {
    _statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    NSImage *statusImage;
    if(@available(macOS 11.0, *)) {
      statusImage = [NSImage imageWithSystemSymbolName:@"lock.square" accessibilityDescription:@"MacPass"];
    }
    if(!statusImage) {
      statusImage = [NSApp.applicationIconImage copy];
      statusImage.size = NSMakeSize(18, 18);
    }
    _statusItem.button.image = statusImage;
    _statusItem.button.toolTip = @"MacPass";

    NSMenu *statusMenu = [[NSMenu alloc] init];
    NSMenuItem *showItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"STATUS_BAR_MENU_SHOW_MACPASS", "Status bar menu item to show MacPass")
                                                      action:@selector(_showApplication:)
                                               keyEquivalent:@""];
    showItem.target = self;
    [statusMenu addItem:showItem];
    [statusMenu addItem:NSMenuItem.separatorItem];
    NSMenuItem *lockItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"STATUS_BAR_MENU_LOCK_ALL_DATABASES", "Status bar menu item to lock all open databases")
                                                      action:@selector(_lockAllDocuments:)
                                               keyEquivalent:@""];
    lockItem.target = self;
    [statusMenu addItem:lockItem];
    NSMenuItem *preferencesItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"STATUS_BAR_MENU_PREFERENCES", "Status bar menu item to show the preferences")
                                                             action:@selector(showPreferences:)
                                                      keyEquivalent:@""];
    preferencesItem.target = self;
    [statusMenu addItem:preferencesItem];
    [statusMenu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"STATUS_BAR_MENU_QUIT_MACPASS", "Status bar menu item to quit MacPass")
                                                      action:@selector(terminate:)
                                               keyEquivalent:@""];
    quitItem.target = NSApp;
    [statusMenu addItem:quitItem];
    _statusItem.menu = statusMenu;
  }
  else if(!showStatusItem && _statusItem) {
    [NSStatusBar.systemStatusBar removeStatusItem:_statusItem];
    _statusItem = nil;
  }
}

- (void)_showApplication:(id)sender {
  /* turn into a regular application before activating, the policy switch attaches the main menu cleanly while inactive */
  _regularPolicyRequested = YES;
  [self _updateActivationPolicy];
  [NSApp activateIgnoringOtherApps:YES];
  [self applicationShouldHandleReopen:NSApp hasVisibleWindows:[self _hasVisibleWindows]];
}

- (void)_lockAllDocuments:(id)sender {
  [self lockAllDocuments];
}

#pragma mark Properties
- (void)setIsAllowedToStoreKeyFile:(BOOL)isAllowedToStoreKeyFile {
  if(_isAllowedToStoreKeyFile != isAllowedToStoreKeyFile) {
    _isAllowedToStoreKeyFile = isAllowedToStoreKeyFile;
    /* cleanup on disable */
    if(!self.isAllowedToStoreKeyFile) {
      [self clearRememberdKeyFiles:nil];
    }
    /* Inform anyone that might be interested that we can now no longer/ or can use keyfiles */
    [NSNotificationCenter.defaultCenter postNotificationName:MPDidChangeStoredKeyFilesSettings object:self];
  }
}

- (void)setStartupState:(MPAppStartupState)notificationState {
  if(notificationState != self.startupState) {
    _startupState = notificationState;
    BOOL restored = self.startupState & MPAppStartupStateRestoredWindows;
    BOOL launched = self.startupState & MPAppStartupStateFinishedLaunch;
    if(restored && launched ) {
      [self _applicationDidFinishLaunchingAndDidRestoreWindows];
    }
  }
}

- (void)awakeFromNib {
  _isAllowedToStoreKeyFile = NO;
  /* Update the … at the save menu */
  self.saveMenuItem.menu.delegate = self;
  
  /* We want to inform anyone about the changes to keyFile remembering */
  [self bind:NSStringFromSelector(@selector(isAllowedToStoreKeyFile))
    toObject:NSUserDefaultsController.sharedUserDefaultsController
 withKeyPath:[MPSettingsHelper defaultControllerPathForKey:kMPSettingsKeyRememberKeyFilesForDatabases]
     options:nil];
  
  NSMenu *fileMenu = self.fileNewMenuItem.menu;
  NSInteger insertIndex = [fileMenu indexOfItem:self.fileNewMenuItem]+1;
  NSArray *items = [MPContextMenuHelper contextMenuItemsWithItems:MPContextMenuCreate];
  for(NSMenuItem *item in items.reverseObjectEnumerator) {
    [fileMenu insertItem:item atIndex:insertIndex];
  }
  [self.itemMenu removeAllItems];
  for(NSMenuItem *item in [MPContextMenuHelper contextMenuItemsWithItems:MPContextMenuFull|MPContextMenuShowGroupInOutline]) {
    [self.itemMenu addItem:item];
  }
  self.itemMenu.delegate = self.itemActionMenuDelegate;
}

#pragma mark -
#pragma mark NSApplicationDelegate

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
  /* reopening (Dock, Spotlight, status bar item) explicitly brings MacPass to front */
  _regularPolicyRequested = YES;
  [self _updateActivationPolicy];
  if(!flag) {
    /* documents might still be open with their windows hidden, just show them again */
    NSArray<NSDocument *> *documents = NSDocumentController.sharedDocumentController.documents;
    if(documents.count > 0) {
      for(NSDocument *document in documents) {
        [document showWindows];
      }
      return YES;
    }
    BOOL reopen = [NSUserDefaults.standardUserDefaults boolForKey:kMPSettingsKeyReopenLastDatabaseOnLaunch];
    BOOL showWelcomeScreen = YES;
    if(reopen) {
      showWelcomeScreen = ![((MPDocumentController *)NSDocumentController.sharedDocumentController) reopenLastDocument];
    }
    if(showWelcomeScreen) {
      [self showWelcomeWindow];
    }
  }
  return YES;
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender {
  return [NSUserDefaults.standardUserDefaults boolForKey:kMPSettingsKeyOpenEmptyDatabaseOnLaunch];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
  return [NSUserDefaults.standardUserDefaults boolForKey:kMPSettingsKeyQuitOnLastWindowClose];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
  _isTerminating = YES;
  [self hideWelcomeWindow];
  if(MPTemporaryFileStorageCenter.defaultCenter.hasPendingStorages) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [MPTemporaryFileStorageCenter.defaultCenter cleanupStorages];
      [sender replyToApplicationShouldTerminate:YES];
    });
    return NSTerminateLater;
  }
  return NSTerminateNow;
}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename {
  _shouldOpenFile = YES;
  _regularPolicyRequested = YES; // opening a file explicitly brings MacPass to front
  [self _updateActivationPolicy];
  NSURL *fileURL = [NSURL fileURLWithPath:filename];
  [NSDocumentController.sharedDocumentController openDocumentWithContentsOfURL:fileURL
                                                                       display:YES
                                                             completionHandler:^(NSDocument * _Nullable document, BOOL documentWasAlreadyOpen, NSError * _Nullable error){}];
  return YES;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
#if defined(NO_SPARKLE)
  NSLog(@"Sparkle explicitly disabled!!!");
#endif
  /* Initalizes Global Daemons */
  [MPLockDaemon defaultDaemon];
  [MPAutotypeDaemon defaultDaemon];
  [MPPluginHost sharedHost];
  if (@available(macOS 11.0, *)) {
    [MPAutoFillCoordinator.sharedCoordinator reconcilePublishedStateWithCompletion:nil];
  }
#if !defined(DEBUG) && !defined(NO_SPARKLE)
  /* Disable updates if in debug or nosparkle  */
  SPUStandardUserDriver *userDriver = [[SPUStandardUserDriver alloc] initWithHostBundle:NSBundle.mainBundle delegate:nil];
  self.updater = [[SPUUpdater alloc] initWithHostBundle:NSBundle.mainBundle applicationBundle:NSBundle.mainBundle userDriver:userDriver delegate:nil];
  [self.updater startUpdater:nil];
#endif
  self.startupState |= MPAppStartupStateFinishedLaunch;
  // Here we just opt-in for allowing our bar to be customized throughout the app.
  NSApplication.sharedApplication.automaticCustomizeTouchBarMenuItemEnabled = YES;

  /* apply the Dock icon visibility and keep it updated when the setting changes */
  [NSUserDefaults.standardUserDefaults addObserver:self
                                        forKeyPath:kMPSettingsKeyHideDockIcon
                                           options:0
                                           context:MPHideDockIconObservingContext];
  [self _updateStatusItemVisibility:[NSUserDefaults.standardUserDefaults boolForKey:kMPSettingsKeyHideDockIcon]];
  [self _updateActivationPolicy];
  /* retreat to the status bar item once the last window is closed */
  [NSNotificationCenter.defaultCenter addObserver:self
                                         selector:@selector(_windowWillClose:)
                                             name:NSWindowWillCloseNotification
                                           object:nil];
}

- (void)_windowWillClose:(NSNotification *)notification {
  [self retreatToStatusItemIfIdle];
}

- (void)retreatToStatusItemIfIdle {
  /* a closing window is still visible, re-evaluate after it is gone */
  dispatch_async(dispatch_get_main_queue(), ^{
    if(self->_isTerminating) {
      return;
    }
    if(![self _hasVisibleWindows]) {
      self->_regularPolicyRequested = NO;
      [self _updateActivationPolicy];
    }
  });
}

#pragma mark -
#pragma mark NSMenuDelegate
- (void)menuNeedsUpdate:(NSMenu *)menu {
  if(menu == self.saveMenuItem.menu) {
    MPDocument *document = NSDocumentController.sharedDocumentController.currentDocument;
    BOOL displayDots = (document.fileURL == nil || !document.compositeKey.hasKeys);
    NSString *saveTitle =  displayDots ? NSLocalizedString(@"SAVE_WITH_DOTS", "Save file menu item title when save will prompt for a location to save or ask for a password/key") : NSLocalizedString(@"SAVE", "Save file menu item title when save will just save the file");
    self.saveMenuItem.title = saveTitle;
  }
  else if(menu == self.fixAutotypeMenuItem.menu) {
    self.fixAutotypeMenuItem.hidden = !(NSEvent.modifierFlags & NSEventModifierFlagOption);
  }
  else if(menu == self.importMenu) {
    NSMenuItem *exportXML = menu.itemArray.firstObject;
    [menu removeAllItems];
    [menu addItem:exportXML];
    for(MPPlugin<MPImportPlugin> * plugin in MPPluginHost.sharedHost.importPlugins) {
      NSMenuItem *importItem = [[NSMenuItem alloc] init];
      [plugin prepareImportMenuItem:importItem];
      importItem.submenu = nil; // kill any potential submenu!
      importItem.representedObject = plugin.identifier;
      importItem.target = nil;
      importItem.action = @selector(importWithPlugin:);
      [menu addItem:importItem];
    }
  }
  else if(menu == self.exportMenu) {
    NSMenuItem *importXML = menu.itemArray.firstObject;
    [menu removeAllItems];
    [menu addItem:importXML];
    for(MPPlugin<MPExportPlugin> * plugin in MPPluginHost.sharedHost.exportPlugins) {
      NSMenuItem *exportItem = [[NSMenuItem alloc] init];
      [plugin prepareExportMenuItem:exportItem];
      exportItem.submenu = nil; // kill any potential submenu!
      exportItem.representedObject = plugin.identifier;
      exportItem.target = nil;
      exportItem.action = @selector(exportWithPlugin:);
      [menu addItem:exportItem];
    }
  }
}

#pragma mark -
#pragma mark Actions

- (void)showPluginPrefences:(id)sender {
  [self _showPreferencesTab:MPPreferencesTabPlugins];
}

- (void)showPreferences:(id)sender {
  [self _showPreferencesTab:MPPreferencesTabGeneral];
}

- (void)_showPreferencesTab:(MPPreferencesTab)tab {
  if(self.preferencesController == nil) {
    self.preferencesController = [[MPPreferencesWindowController alloc] init];
  }
  [self.preferencesController showPreferencesTab:tab];
}

- (void)showPasswordCreator:(id)sender {
  if(!self.passwordCreatorWindow) {
    self.passwordCreatorWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 100, 100)
                                                             styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable
                                                               backing:NSBackingStoreBuffered
                                                                 defer:NO];
    self.passwordCreatorWindow.releasedWhenClosed = NO;
    self.passwordCreatorWindow.title = NSLocalizedString(@"PASSWORD_CREATOR_WINDOW_TITLE", @"Window title for the stand-alone password creator window");
  }
  if(!self.passwordCreatorController) {
    self.passwordCreatorController = [[MPPasswordCreatorViewController alloc] init];
    self.passwordCreatorWindow.contentViewController = self.passwordCreatorController;
  }
  [self.passwordCreatorController reset];
  [self.passwordCreatorWindow center];
  [self.passwordCreatorWindow makeKeyAndOrderFront:self.passwordCreatorWindow];
}

- (void)createNewDatabase:(id)sender {
  [self.welcomeWindow orderOut:sender];
  [NSDocumentController.sharedDocumentController newDocument:sender];
}

- (void)openDatabase:(id)sender {
  [self.welcomeWindow orderOut:sender];
  [NSDocumentController.sharedDocumentController openDocument:sender];
}

- (void)lockAllDocuments {
  for(NSDocument *document in NSDocumentController.sharedDocumentController.documents) {
    for(id windowController in [document.windowControllers reverseObjectEnumerator]) {
      if([windowController respondsToSelector:@selector(lock:)]) {
        [windowController lock:self];
      }
    }
  }
}

- (void)showWelcomeWindow {
  if(!self.welcomeWindow) {
    self.welcomeWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 100, 100)
                                                     styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable
                                                       backing:NSBackingStoreBuffered
                                                         defer:NO];
    self.welcomeWindow.restorable = NO; // do not restore the welcome window!
    self.welcomeWindow.releasedWhenClosed = NO;
  }
  if(!self.welcomeWindow.contentViewController) {
    self.welcomeWindow.contentViewController = [[MPWelcomeViewController alloc] init];
  }
  
  [self.welcomeWindow center];
  [self.welcomeWindow makeKeyAndOrderFront:nil];
}

- (void)hideWelcomeWindow {
  [self.welcomeWindow orderOut:nil];
}

- (void)clearRememberdKeyFiles:(id)sender {
  [NSUserDefaults.standardUserDefaults removeObjectForKey:kMPSettingsKeyRememeberdKeysForDatabases];
}

- (void)showHelp:(id)sender {
  NSString *urlString = NSBundle.mainBundle.infoDictionary[MPBundleHelpURLKey];
  [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:urlString]];
}

- (void)showAutotypeDoctor:(id)sender {
  [MPAutotypeDoctor.defaultDoctor runChecksAndPresentResults];
}

- (void)checkForUpdates:(id)sender {
#if defined(DEBUG) || defined(NO_SPARKLE)
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = NSLocalizedString(@"ALERT_UPDATES_DISABLED_MESSAGE_TEXT", @"Message text for disabled updates alert!");
  alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"ALERT_UPDATES_DISABLED_INFORMATIVE_TEXT_%@!", @"Informative text of the disabled updates alert!"), NSApp.applicationName];
  [alert addButtonWithTitle:NSLocalizedString(@"OK", @"Ok Button to dismiss disabled updates alert")];
  [alert runModal];
#else
  [self.updater checkForUpdates];
#endif
}

#pragma mark -
#pragma mark Private Helper
- (void)_applicationDidFinishRestoringWindows:(NSNotification *)notification {
  self.startupState |= MPAppStartupStateRestoredWindows;
}

- (void)_applicationDidFinishLaunchingAndDidRestoreWindows {
  NSArray *documents = NSDocumentController.sharedDocumentController.documents;
  BOOL hasOpenDocuments = documents.count > 0;
  
  for(NSDocument *document in documents) {
    for(NSWindowController *windowController in document.windowControllers) {
      [windowController.window.contentView layout];
    }
  }
  
  BOOL reopen = [NSUserDefaults.standardUserDefaults boolForKey:kMPSettingsKeyReopenLastDatabaseOnLaunch];
  BOOL showWelcomeScreen = !hasOpenDocuments && !_shouldOpenFile;
  if(reopen && !hasOpenDocuments && !_shouldOpenFile) {
    showWelcomeScreen = ![((MPDocumentController *)NSDocumentController.sharedDocumentController) reopenLastDocument];
  }
  if(showWelcomeScreen) {
    [self showWelcomeWindow];
  }
}

@end
