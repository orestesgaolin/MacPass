//
//  MPInspectorTabViewController.m
//  MacPass
//
//  Created by Michael Starke on 05.03.13.
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

#import "MPInspectorViewController.h"
#import "MPDatePickingViewController.h"
#import "MPDocument.h"
#import "MPEntryInspectorViewController.h"
#import "MPGroupInspectorViewController.h"
#import "MPIconHelper.h"
#import "MPIconSelectViewController.h"
#import "MPIconImageView.h"
#import "MPNotifications.h"
#import "MPPluginDataViewController.h"
#import "MPPasteBoardController.h"
#import "MPReferenceBuilderViewController.h"

#import "KeePassKit/KeePassKit.h"

#import "KPKNode+IconImage.h"

typedef NS_ENUM(NSUInteger, MPContentTab) {
  MPEntryTab,
  MPGroupTab,
  MPEmptyTab,
};

@protocol MPReferenceTextViewDelegate <NSTextViewDelegate>
- (NSMenu *)textView:(NSTextView *)textView menu:(NSMenu *)menu;
@end

@interface MPReferenceTextView : HNHUITextView
@end

@implementation MPReferenceTextView

- (NSMenu *)menuForEvent:(NSEvent *)event {
  NSMenu *menu = [super menuForEvent:event];
  id<MPReferenceTextViewDelegate> delegate = (id)self.delegate;
  if([delegate respondsToSelector:@selector(textView:menu:)]) {
    return [delegate textView:self menu:menu];
  }
  return menu;
}

@end

@interface MPInspectorViewController ()

@property (strong) MPEntryInspectorViewController *entryViewController;
@property (strong) MPGroupInspectorViewController *groupViewController;

@property (copy) NSString *expiryDateText;

@property (nonatomic, assign) NSUInteger activeTab;
@property (weak) IBOutlet NSTabView *tabView;
@property (weak) IBOutlet NSSplitView *splitView;
@property (unsafe_unretained) IBOutlet HNHUITextView *notesTextView;
@property (strong) NSButton *notesReferenceButton;
@property (assign) BOOL showRawNotesReference;

@property BOOL didPushHistory;

@end

@implementation MPInspectorViewController

- (NSString *)nibName {
  return @"InspectorView";
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
  self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
  if (self) {
    self.activeTab = MPEmptyTab;
    self.entryViewController = [[MPEntryInspectorViewController alloc] init];
    self.groupViewController = [[MPGroupInspectorViewController alloc] init];
    self.didPushHistory = NO;
    /* subviewcontrollers will notify us about a change so we can handle the history pushing */
  }
  return self;
}

- (NSResponder *)reconmendedFirstResponder {
  return self.view;
}

- (void)awakeFromNib {
  self.noSelectionInfo.cell.backgroundStyle = NSBackgroundStyleRaised;
  self.itemImageView.cell.backgroundStyle = NSBackgroundStyleRaised;
  [self.tabView bind:NSSelectedIndexBinding toObject:self withKeyPath:NSStringFromSelector(@selector(activeTab)) options:nil];
  [self _setupNotesReferenceButton];
  
  NSView *entryView = self.entryViewController.view;
  NSView *groupView = self.groupViewController.view;
  
  
  NSTabViewItem *entryTabItem = [self.tabView tabViewItemAtIndex:MPEntryTab];
  NSView *entryTabView = entryTabItem.view;
  [entryTabView addSubview:entryView];
  NSDictionary *views = NSDictionaryOfVariableBindings(entryView, groupView);
  [entryTabView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[entryView]|" options:0 metrics:nil views:views]];
  [entryTabView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[entryView]|" options:0 metrics:nil views:views]];
  entryTabItem.initialFirstResponder = entryTabView;
  
  NSTabViewItem *groupTabItem = [self.tabView tabViewItemAtIndex:MPGroupTab];
  NSView *groupTabView = groupTabItem.view;
  [groupTabView addSubview:groupView];
    
  [groupTabView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[groupView]|" options:0 metrics:nil views:views]];
  [groupTabView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[groupView]|" options:0 metrics:nil views:views]];
  groupTabItem.initialFirstResponder = groupView;
  
  [self.view layout];}

- (void)registerNotificationsForDocument:(MPDocument *)document {
  [NSNotificationCenter.defaultCenter addObserver:self
                                         selector:@selector(_didChangeCurrentItem:)
                                             name:MPDocumentCurrentItemChangedNotification
                                           object:document];
  
  [NSNotificationCenter.defaultCenter addObserver:self
                                         selector:@selector(_willChangeModelProperty:)
                                             name:MPDocumentWillChangeModelPropertyNotification
                                           object:document];
  [NSNotificationCenter.defaultCenter addObserver:self
                                         selector:@selector(_didChangeEntryForPresentation:)
                                             name:KPKDidChangeEntryNotification
                                           object:nil];
  [NSNotificationCenter.defaultCenter addObserver:self
                                         selector:@selector(_didChangeEntryForPresentation:)
                                             name:KPKDidChangeAttributeNotification
                                           object:nil];
  
  self.entryViewController.observer = document;
  self.itemImageView.modelChangeObserver = document;
  self.observer = document;
  
  [self.entryViewController registerNotificationsForDocument:document];
  [self.groupViewController registerNotificationsForDocument:document];
}

#pragma mark - Properties
- (void)setActiveTab:(NSUInteger)activeTab {
  if(_activeTab != activeTab) {
    _activeTab = activeTab;
  }
}

#pragma mark - TextViewDelegate
- (NSMenu *)textView:(NSTextView *)textView menu:(NSMenu *)menu {
  if(textView != self.notesTextView) {
    return menu;
  }
  KPKEntry *entry = [self.representedObject asEntry];
  BOOL notesHaveReference = [KPKFieldReference referencesInString:entry.notes ?: @""].count > 0;
  if(entry != nil && !entry.isHistory && (!notesHaveReference || self.showRawNotesReference)) {
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *insertReferenceItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"INSERT_FIELD_REFERENCE", "Menu item to insert a reference to another entry")
                                                                    action:@selector(showNotesReferenceBuilder:)
                                                             keyEquivalent:@""];
    insertReferenceItem.target = self;
    insertReferenceItem.representedObject = @{ @"originalValue": textView.string ?: @"",
                                               @"range": [NSValue valueWithRange:textView.selectedRange] };
    [menu addItem:insertReferenceItem];
  }
  NSArray<NSString *> *referenceDescriptions = [self _referenceDescriptionsForString:entry.notes];
  if(referenceDescriptions.count > 0) {
    NSMenuItem *referencesItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"FIELD_REFERENCES", "Menu containing resolved field references") action:NULL keyEquivalent:@""];
    NSMenu *referencesMenu = [[NSMenu alloc] initWithTitle:referencesItem.title];
    for(NSString *description in referenceDescriptions) {
      NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:description action:NULL keyEquivalent:@""];
      item.enabled = NO;
      [referencesMenu addItem:item];
    }
    referencesItem.submenu = referencesMenu;
    [menu addItem:referencesItem];
  }
  return menu;
}

- (BOOL)textView:(NSTextView *)textView performAction:(SEL)action {
  if(action == @selector(copy:)) {
    MPPasteboardOverlayInfoType info = MPPasteboardOverlayInfoCustom;
    NSMutableString *selectedString = [[NSMutableString alloc] initWithCapacity:MAX(1,textView.string.length)];
    NSString *string = textView.string;
    for(NSValue *rangeValue in textView.selectedRanges) {
      if(rangeValue.rangeValue.length != 0) {
        [selectedString appendString:[string substringWithRange:rangeValue.rangeValue]];
      }
    }
    NSString *name = @"";
    if(selectedString.length == 0) {
      return YES;
    }
    if(textView == self.notesTextView) {
      name = NSLocalizedString(@"NOTES", "Displayed name when notes or part of notes was copied");
    }
    [MPPasteBoardController.defaultController copyObject:selectedString overlayInfo:info name:name atView:self.view];
    return NO;
  }
  return YES;
}

- (void)showNotesReferenceBuilder:(NSMenuItem *)sender {
  NSDictionary *insertionInfo = sender.representedObject;
  NSString *originalValue = insertionInfo[@"originalValue"];
  NSRange insertionRange = [insertionInfo[@"range"] rangeValue];
  KPKEntry *entry = [self.representedObject asEntry];
  if(entry == nil || originalValue == nil || insertionRange.location == NSNotFound || NSMaxRange(insertionRange) > originalValue.length) {
    return;
  }
  [self.view.window makeFirstResponder:nil];
  [self commitEditing];
  if(![entry.notes isEqualToString:originalValue]) {
    [self setValue:originalValue forKeyPath:@"representedObject.notes"];
  }

  MPReferenceBuilderViewController *builder = [[MPReferenceBuilderViewController alloc] init];
  builder.representedObject = entry;
  builder.preferredFieldKey = kKPKReferenceNotesKey;
  builder.valueBeingReplaced = originalValue;
  __weak typeof(self) weakSelf = self;
  builder.completionHandler = ^(NSString *reference) {
    typeof(self) strongSelf = weakSelf;
    KPKEntry *currentEntry = [strongSelf.representedObject asEntry];
    if(strongSelf == nil || currentEntry != entry || ![currentEntry.notes isEqualToString:originalValue]) {
      return;
    }
    [strongSelf.view.window makeFirstResponder:nil];
    [strongSelf commitEditing];
    NSString *newValue = originalValue.length > 0
                         ? reference
                         : [originalValue stringByReplacingCharactersInRange:insertionRange withString:reference];
    [strongSelf setValue:newValue forKeyPath:@"representedObject.notes"];
    [strongSelf _updateNotesReferenceToolTip];
  };
  [self _popupViewController:builder atView:self.notesTextView];
}

- (NSString *)_nameForReferenceField:(KPKReferenceField)field {
  switch(field) {
    case KPKReferenceFieldTitle: return NSLocalizedString(@"TITLE", "Title field");
    case KPKReferenceFieldUsername: return NSLocalizedString(@"USERNAME", "Username field");
    case KPKReferenceFieldPassword: return NSLocalizedString(@"PASSWORD", "Password field");
    case KPKReferenceFieldUrl: return NSLocalizedString(@"URL", "URL field");
    case KPKReferenceFieldNotes: return NSLocalizedString(@"NOTES", "Notes field");
    case KPKReferenceFieldUUID: return NSLocalizedString(@"UUID", "UUID field");
    case KPKReferenceFieldOther: return NSLocalizedString(@"CUSTOM_ATTRIBUTE", "Custom field");
  }
  return @"";
}

- (NSArray<NSString *> *)_referenceDescriptionsForString:(NSString *)string {
  KPKEntry *entry = [self.representedObject asEntry];
  NSMutableArray<NSString *> *descriptions = [[NSMutableArray alloc] init];
  if(entry.tree == nil) {
    return descriptions;
  }
  for(KPKFieldReference *reference in [KPKFieldReference referencesInString:string ?: @""]) {
    KPKFieldReferenceResolution *resolution = [KPKReferenceBuilder resolveReference:reference inTree:entry.tree excludingEntry:entry];
    NSString *fieldName = [self _nameForReferenceField:reference.wantedField];
    if(resolution.selectedEntry == nil) {
      [descriptions addObject:[NSString stringWithFormat:NSLocalizedString(@"FIELD_REFERENCE_MISSING_FORMAT", "Unresolved field reference description"), fieldName]];
      continue;
    }
    NSString *entryTitle = resolution.selectedEntry.title.length > 0 ? resolution.selectedEntry.title : NSLocalizedString(@"UNTITLED", "Fallback title for an entry without a title");
    NSString *description = [NSString stringWithFormat:NSLocalizedString(@"FIELD_REFERENCE_FORMAT", "Resolved field reference description"), fieldName, entryTitle];
    if(resolution.status == KPKFieldReferenceResolutionStatusResolvedAmbiguous) {
      description = [description stringByAppendingFormat:NSLocalizedString(@"FIELD_REFERENCE_AMBIGUOUS_SUFFIX", "Ambiguous reference match count suffix"), resolution.matchingEntries.count];
    }
    [descriptions addObject:description];
  }
  return descriptions;
}

- (void)_updateNotesReferenceToolTip {
  NSArray<NSString *> *descriptions = [self _referenceDescriptionsForString:[self.representedObject asEntry].notes];
  self.notesTextView.toolTip = descriptions.count > 0 ? [descriptions componentsJoinedByString:@"\n"] : nil;
}

- (void)_setupNotesReferenceButton {
  NSScrollView *scrollView = self.notesTextView.enclosingScrollView;
  NSView *container = scrollView.superview;
  NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
  button.translatesAutoresizingMaskIntoConstraints = NO;
  button.bordered = NO;
  button.image = [NSImage imageNamed:NSImageNameRefreshFreestandingTemplate];
  button.imagePosition = NSImageOnly;
  button.target = self;
  button.action = @selector(toggleNotesReferenceSource:);
  button.hidden = YES;
  [container addSubview:button];
  [NSLayoutConstraint activateConstraints:@[
    [button.trailingAnchor constraintEqualToAnchor:scrollView.trailingAnchor],
    [button.bottomAnchor constraintEqualToAnchor:scrollView.topAnchor constant:2],
    [button.widthAnchor constraintEqualToConstant:24],
    [button.heightAnchor constraintEqualToConstant:18]
  ]];
  self.notesReferenceButton = button;
}

- (void)_bindNotesValueIfNeeded {
  if([self.notesTextView infoForBinding:NSValueBinding] == nil) {
    [self.notesTextView bind:NSValueBinding
                    toObject:self
                 withKeyPath:@"representedObject.notes"
                     options:@{ NSConditionallySetsEditableBindingOption: @NO,
                                NSNoSelectionPlaceholderBindingOption: NSLocalizedString(@"NONE", "No selection placeholder"),
                                NSNullPlaceholderBindingOption: NSLocalizedString(@"NONE", "Empty value placeholder") }];
  }
}

- (void)_updateNotesReferencePresentation {
  if(!self.isViewLoaded) {
    return;
  }
  KPKEntry *entry = [self.representedObject asEntry];
  KPKNode *node = self.representedObject;
  NSString *rawNotes = entry.notes ?: @"";
  BOOL hasReference = [KPKFieldReference referencesInString:rawNotes].count > 0;
  if(!hasReference) {
    self.showRawNotesReference = NO;
  }
  BOOL showRaw = hasReference && self.showRawNotesReference;
  self.notesReferenceButton.hidden = !hasReference;
  self.notesReferenceButton.state = showRaw ? NSControlStateValueOn : NSControlStateValueOff;
  self.notesReferenceButton.enabled = entry != nil && !entry.isHistory;
  self.notesReferenceButton.toolTip = showRaw
                                      ? NSLocalizedString(@"SHOW_RESOLVED_FIELD_REFERENCE", "Tooltip to show a resolved field reference")
                                      : NSLocalizedString(@"EDIT_FIELD_REFERENCE_SOURCE", "Tooltip to edit a field reference expression");
  if(hasReference && !showRaw) {
    if([self.notesTextView infoForBinding:NSValueBinding] != nil) {
      [self.notesTextView unbind:NSValueBinding];
    }
    self.notesTextView.string = [rawNotes kpk_finalValueForEntry:entry options:KPKCommandEvaluationOptionSkipUserInteraction|KPKCommandEvaluationOptionReadOnly] ?: @"";
    self.notesTextView.editable = NO;
    self.notesTextView.selectable = YES;
  }
  else {
    [self _bindNotesValueIfNeeded];
    self.notesTextView.editable = node != nil && (entry == nil || !entry.isHistory);
  }
}

- (IBAction)toggleNotesReferenceSource:(NSButton *)sender {
  self.showRawNotesReference = !self.showRawNotesReference;
  [self _updateNotesReferencePresentation];
  [self _updateNotesReferenceToolTip];
}

- (void)_updateTitlePresentation {
  KPKEntry *entry = [self.representedObject asEntry];
  BOOL hasReference = [KPKFieldReference referencesInString:entry.title ?: @""].count > 0;
  if(hasReference) {
    if([self.itemNameTextField infoForBinding:NSValueBinding] != nil) {
      [self.itemNameTextField unbind:NSValueBinding];
    }
    self.itemNameTextField.stringValue = [entry.title kpk_finalValueForEntry:entry options:KPKCommandEvaluationOptionSkipUserInteraction|KPKCommandEvaluationOptionReadOnly] ?: @"";
    self.itemNameTextField.editable = NO;
    self.itemNameTextField.toolTip = NSLocalizedString(@"FIELD_REFERENCE_RESOLVED_TOOLTIP", "Tooltip for a resolved field reference");
  }
  else {
    if([self.itemNameTextField infoForBinding:NSValueBinding] == nil) {
      [self.itemNameTextField bind:NSValueBinding toObject:self withKeyPath:@"representedObject.title" options:nil];
    }
    self.itemNameTextField.editable = entry == nil || !entry.isHistory;
    self.itemNameTextField.toolTip = nil;
  }
}

- (void)_unbindReferencePresentationBindings {
  if([self.itemNameTextField infoForBinding:NSValueBinding] != nil) {
    [self.itemNameTextField unbind:NSValueBinding];
  }
  if([self.notesTextView infoForBinding:NSValueBinding] != nil) {
    [self.notesTextView unbind:NSValueBinding];
  }
}

- (void)_refreshReferencePresentationForChangedObject:(id)changedObject {
  KPKEntry *entry = [self.representedObject asEntry];
  KPKEntry *changedEntry = [changedObject isKindOfClass:KPKEntry.class] ? changedObject : nil;
  if([changedObject isKindOfClass:KPKAttribute.class]) {
    for(KPKEntry *candidate in entry.tree.allEntries) {
      if([candidate.attributes indexOfObjectIdenticalTo:changedObject] != NSNotFound) {
        changedEntry = candidate;
        break;
      }
    }
  }
  if(entry == nil || changedEntry.tree != entry.tree) {
    return;
  }
  [self _updateTitlePresentation];
  [self _updateNotesReferencePresentation];
}

- (void)_didChangeEntryForPresentation:(NSNotification *)notification {
  if(!NSThread.isMainThread) {
    return;
  }
  id changedObject = notification.object;
  if([changedObject isKindOfClass:KPKAttribute.class]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self _refreshReferencePresentationForChangedObject:changedObject];
    });
    return;
  }
  [self _refreshReferencePresentationForChangedObject:changedObject];
}
#pragma mark - Popup
- (IBAction)pickIcon:(id)sender {
  NSAssert([sender isKindOfClass:NSView.class], @"");
  [self _popupViewController:[[MPIconSelectViewController alloc] init] atView:sender];
}

- (IBAction)pickExpiryDate:(id)sender {
  NSAssert([sender isKindOfClass:NSView.class], @"");
  [self _popupViewController:[[MPDatePickingViewController alloc] init] atView:sender];
}

- (IBAction)showPluginData:(id)sender {
  NSAssert([sender isKindOfClass:NSView.class], @"");
  [self _popupViewController:[[MPPluginDataViewController alloc] init] atView:sender];
}

- (void)_popupViewController:(MPViewController *)vc atView:(NSView *)view {
  vc.representedObject = self.representedObject;
  vc.observer = self.windowController.document;
  [self presentViewController:vc asPopoverRelativeToRect:NSZeroRect ofView:view preferredEdge:NSMinYEdge behavior:NSPopoverBehaviorSemitransient];
}

#pragma mark - MPDocument Notifications
- (void)_willChangeModelProperty:(NSNotification *)notification {
  /* TODO use uuids for pushed item? */
  if(self.didPushHistory) {
    return;
  }
  KPKEntry *entry = [self.representedObject asEntry];
  if(entry) {
    [entry pushHistory];
    self.didPushHistory = YES;
  }
}

- (void)_didChangeCurrentItem:(NSNotification *)notification {
  MPDocument *document = notification.object;
  KPKNode *node = document.selectedNodes.count == 1 ? document.selectedNodes.firstObject : nil;
  if(node.asGroup) {
    self.activeTab = MPGroupTab;
  }
  else if(node.asEntry) {
    self.activeTab = MPEntryTab;
  }
  else {
    self.activeTab = MPEmptyTab;
  }
  self.didPushHistory = NO;
  
  /* manually commit editing on any active editors */
  [self commitEditing];
  [self.entryViewController commitEditing];
  [self.groupViewController commitEditing];

  /* Unbind nested key paths before changing representedObject, while Cocoa's
   * binders can still remove their observations from the original node. */
  [self _unbindReferencePresentationBindings];
  self.representedObject = node;
  self.showRawNotesReference = NO;
  self.itemImageView.node = node;
  self.entryViewController.representedObject = node.asEntry;
  self.groupViewController.representedObject = node.asGroup;
  [self _updateTitlePresentation];
  [self _updateNotesReferencePresentation];
  [self _updateNotesReferenceToolTip];
  
}

@end
