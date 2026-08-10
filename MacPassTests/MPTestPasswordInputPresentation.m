#import <XCTest/XCTest.h>
#import <Carbon/Carbon.h>

#import "MPPasswordInputController.h"
#import "MPSettingsHelper.h"
#import "DDHotKey+MacPassAdditions.h"

@interface MPPasswordInputController (PresentationTests)
- (IBAction)unlockMethodChanged:(NSSegmentedControl *)sender;
@end

@interface MPTestPasswordInputPresentation : XCTestCase
@end

@implementation MPTestPasswordInputPresentation

- (MPPasswordInputPresentationState)stateForMode:(MPTouchIDKeyStorage)mode
                                             key:(BOOL)key
                                         enabled:(BOOL)enabled
                                           valid:(BOOL)valid
                                       supported:(BOOL)supported {
  return [MPPasswordInputController presentationStateForTouchIDMode:mode
                                                       keyAvailable:key
                                                    shortcutEnabled:enabled
                                                      shortcutValid:valid
                                                           supported:supported];
}

- (void)testDisabledModeAlwaysUsesManualPresentation {
  XCTAssertEqual([self stateForMode:MPTouchIDKeyStorageDisabled key:YES enabled:YES valid:YES supported:YES],
                 MPPasswordInputPresentationManualOnly);
}

- (void)testEnabledModesWithoutKeyRequireProvisioning {
  XCTAssertEqual([self stateForMode:MPTouchIDKeyStorageTransient key:NO enabled:NO valid:NO supported:YES],
                 MPPasswordInputPresentationProvisioningNeeded);
  XCTAssertEqual([self stateForMode:MPTouchIDKeyStoragePersistent key:NO enabled:NO valid:NO supported:YES],
                 MPPasswordInputPresentationProvisioningNeeded);
}

- (void)testEnabledModesWithKeyOfferTouchID {
  XCTAssertEqual([self stateForMode:MPTouchIDKeyStorageTransient key:YES enabled:NO valid:NO supported:YES],
                 MPPasswordInputPresentationTouchIDAvailable);
  XCTAssertEqual([self stateForMode:MPTouchIDKeyStoragePersistent key:YES enabled:NO valid:NO supported:YES],
                 MPPasswordInputPresentationTouchIDAvailable);
}

- (void)testShortcutRequiresEnabledAndValidHotKey {
  MPPasswordInputPresentationState validState = [self stateForMode:MPTouchIDKeyStoragePersistent key:YES enabled:YES valid:YES supported:YES];
  XCTAssertTrue((validState & MPPasswordInputPresentationShortcutAvailable) != 0);

  MPPasswordInputPresentationState disabledState = [self stateForMode:MPTouchIDKeyStoragePersistent key:YES enabled:NO valid:YES supported:YES];
  XCTAssertFalse((disabledState & MPPasswordInputPresentationShortcutAvailable) != 0);
  MPPasswordInputPresentationState invalidState = [self stateForMode:MPTouchIDKeyStoragePersistent key:YES enabled:YES valid:NO supported:YES];
  XCTAssertFalse((invalidState & MPPasswordInputPresentationShortcutAvailable) != 0);
}

- (void)testUnsupportedSystemsAlwaysUseManualPresentation {
  XCTAssertEqual([self stateForMode:MPTouchIDKeyStoragePersistent key:YES enabled:YES valid:YES supported:NO],
                 MPPasswordInputPresentationManualOnly);
}

- (void)testShortcutHintUsesDDHotKeyGlyphFormatting {
  NSData *keyData = [DDHotKey hotKeyDataWithKeyCode:kVK_ANSI_M modifierFlags:kCGEventFlagMaskControl|kCGEventFlagMaskAlternate];
  NSString *hint = [MPPasswordInputController touchIDShortcutHintForKeyData:keyData enabled:YES];
  XCTAssertTrue([hint containsString:@"⌃⌥M"]);
  XCTAssertNil([MPPasswordInputController touchIDShortcutHintForKeyData:keyData enabled:NO]);
  XCTAssertNil([MPPasswordInputController touchIDShortcutHintForKeyData:[NSData data] enabled:YES]);
}

- (void)testCardSelectionUpdatesVisibilityAndFocus {
  MPPasswordInputController *controller = [[MPPasswordInputController alloc] initWithNibName:nil bundle:nil];
  NSView *view = controller.view;
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 508, 489)
                                                 styleMask:NSWindowStyleMaskTitled
                                                   backing:NSBackingStoreBuffered
                                                     defer:NO];
  window.contentView = view;
  NSSegmentedControl *control = [controller valueForKey:@"unlockMethodControl"];
  NSView *touchCard = [controller valueForKey:@"touchIdCard"];
  NSView *manualCard = [controller valueForKey:@"manualCard"];
  NSButton *touchButton = [controller valueForKey:@"touchIdButton"];
  NSTextField *passwordField = [controller valueForKey:@"passwordTextField"];

  control.selectedSegment = 1;
  [controller unlockMethodChanged:control];
  XCTAssertFalse(manualCard.hidden);
  XCTAssertTrue(touchCard.hidden);
  XCTAssertEqual(window.firstResponder, passwordField.currentEditor);

  control.selectedSegment = 0;
  [controller unlockMethodChanged:control];
  XCTAssertTrue(manualCard.hidden);
  XCTAssertFalse(touchCard.hidden);
  XCTAssertEqual(window.firstResponder, touchButton);
}

- (void)testUnlockPanelUsesSharedAlignmentAndAccessibleTouchIDAction {
  MPPasswordInputController *controller = [[MPPasswordInputController alloc] initWithNibName:nil bundle:nil];
  NSView *view = controller.view;
  [view layoutSubtreeIfNeeded];

  NSView *manualCard = [controller valueForKey:@"manualCard"];
  NSView *touchCard = [controller valueForKey:@"touchIdCard"];
  NSView *panel = manualCard.superview;
  NSTextField *passwordField = [controller valueForKey:@"passwordTextField"];
  NSView *keyPathControl = [controller valueForKey:@"keyPathControl"];
  NSButton *showPasswordButton = [controller valueForKey:@"togglePasswordButton"];
  NSButton *resetKeyFileButton = [controller valueForKey:@"resetKeyFileButton"];
  NSButton *unlockButton = [controller valueForKey:@"unlockButton"];
  NSButton *touchIdButton = [controller valueForKey:@"touchIdButton"];
  NSView *touchIdFooter = [controller valueForKey:@"touchIdFooter"];

  XCTAssertEqualWithAccuracy(NSMidX(panel.frame), NSMidX(view.bounds), 0.5);
  XCTAssertTrue(NSEqualRects(manualCard.frame, touchCard.frame));
  NSRect passwordAlignmentRect = [passwordField alignmentRectForFrame:passwordField.frame];
  NSRect keyPathAlignmentRect = [keyPathControl alignmentRectForFrame:keyPathControl.frame];
  NSRect unlockAlignmentRect = [unlockButton alignmentRectForFrame:unlockButton.frame];
  XCTAssertEqualWithAccuracy(NSMinX(passwordAlignmentRect), NSMinX(keyPathAlignmentRect), 0.5);
  XCTAssertEqualWithAccuracy(NSMaxX(showPasswordButton.frame), NSMaxX(resetKeyFileButton.frame), 0.5);
  XCTAssertEqualWithAccuracy(NSMaxX(unlockAlignmentRect), NSMaxX(keyPathAlignmentRect), 0.5);
  XCTAssertEqualWithAccuracy(NSMidX(touchIdFooter.frame), NSMidX(panel.bounds), 0.5);
  XCTAssertEqualObjects(touchIdButton.accessibilityLabel, touchIdButton.title);
  XCTAssertTrue([touchIdButton.title containsString:@"Touch ID"]);
}

@end
