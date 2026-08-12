#import <XCTest/XCTest.h>

#import "MPIntegrationPreferencesController.h"

@interface MPTestAutoFillPreferences : XCTestCase
@end

@implementation MPTestAutoFillPreferences

- (void)testIntegrationPreferencesRenderAutoFillSectionWithoutAmbiguousLayout {
  NSAppearance *appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
  MPIntegrationPreferencesController *controller = [[MPIntegrationPreferencesController alloc] init];
  NSView *view = controller.view;
  view.appearance = appearance;
  view.wantsLayer = YES;
  view.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
  NSWindow *window = [[NSWindow alloc] initWithContentRect:view.bounds
                                                styleMask:NSWindowStyleMaskBorderless
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
  window.appearance = appearance;
  window.backgroundColor = NSColor.windowBackgroundColor;
  window.contentView = view;
  [controller willShowTab];
  [view layoutSubtreeIfNeeded];

  __block NSBox *autoFillBox = nil;
  NSMutableArray<NSButton *> *buttons = [NSMutableArray array];
  __block NSPopUpButton *publicationsButton = nil;
  NSMutableArray<NSView *> *views = [NSMutableArray arrayWithObject:view];
  while (views.count > 0) {
    NSView *candidate = views.lastObject;
    [views removeLastObject];
    if ([candidate isKindOfClass:NSBox.class] &&
        [((NSBox *)candidate).title isEqualToString:NSLocalizedString(@"AUTOFILL_PREFERENCES_TITLE", @"")]) {
      autoFillBox = (NSBox *)candidate;
    }
    if ([candidate isKindOfClass:NSButton.class]) [buttons addObject:(NSButton *)candidate];
    if ([candidate isKindOfClass:NSPopUpButton.class]) publicationsButton = (NSPopUpButton *)candidate;
    [views addObjectsFromArray:candidate.subviews];
  }

  XCTAssertNotNil(autoFillBox);
  XCTAssertFalse(view.hasAmbiguousLayout);
  XCTAssertFalse(autoFillBox.hasAmbiguousLayout);
  XCTAssertGreaterThanOrEqual(view.frame.size.width, 425);
  XCTAssertGreaterThanOrEqual(view.frame.size.height, 850);
  XCTAssertNotNil(publicationsButton.accessibilityLabel);
  for (NSButton *button in buttons) XCTAssertGreaterThan(button.accessibilityLabel.length, 0);

  NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
  [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
  NSData *PNG = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
  XCTAttachment *attachment = [XCTAttachment attachmentWithData:PNG uniformTypeIdentifier:@"public.png"];
  attachment.name = @"Integration Preferences AutoFill";
  attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
  [self addAttachment:attachment];
}

@end
