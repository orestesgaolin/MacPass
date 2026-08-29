//
//  MPReferenceBuilderViewController.m
//  MacPass
//
//  Created by Michael Starke on 05/12/14.
//  Copyright (c) 2014 HicknHack Software GmbH. All rights reserved.
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

#import "MPReferenceBuilderViewController.h"

#import "KeePassKit/KeePassKit.h"

@interface MPReferenceBuilderViewController ()

@property (nonatomic, copy) NSString *searchString;
@property (nonatomic, copy) NSString *referenceString;
@property (nonatomic, copy) NSString *previewValue;
@property (nonatomic, strong) NSButton *revealPreviewButton;
@property (nonatomic, assign) BOOL previewPasswordRevealed;

- (void)_completeReferenceSelection;
@end

@implementation MPReferenceBuilderViewController

- (NSString *)nibName {
  return @"ReferenceBuilderView";
}

- (void)viewDidLoad {
  self.valuePopUpButton.menu = [self _allocateAttributeItemMenu];
  NSUInteger preferredIndex = [self.valuePopUpButton.menu.itemArray indexOfObjectPassingTest:^BOOL(NSMenuItem *item, NSUInteger idx, BOOL *stop) {
    return [item.representedObject isEqualToString:self.preferredFieldKey];
  }];
  [self.valuePopUpButton selectItemAtIndex:preferredIndex == NSNotFound ? 3 : (NSInteger)preferredIndex];
  [self.searchStringTextField bind:NSValueBinding toObject:self withKeyPath:NSStringFromSelector(@selector(searchString)) options:nil];
  self.referenceStringTextField.editable = NO;
  self.referenceStringTextField.selectable = YES;
  NSButton *revealButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  revealButton.translatesAutoresizingMaskIntoConstraints = NO;
  revealButton.bordered = NO;
  revealButton.image = [NSImage imageNamed:NSImageNameQuickLookTemplate];
  revealButton.imagePosition = NSImageOnly;
  revealButton.target = self;
  revealButton.action = @selector(togglePreviewPassword:);
  revealButton.toolTip = NSLocalizedString(@"TOUCHBAR_SHOW_PASSWORD", "Tooltip to reveal a password preview");
  revealButton.hidden = YES;
  [self.referenceStringTextField.superview addSubview:revealButton];
  [NSLayoutConstraint activateConstraints:@[
    [revealButton.trailingAnchor constraintEqualToAnchor:self.referenceStringTextField.trailingAnchor constant:-3],
    [revealButton.centerYAnchor constraintEqualToAnchor:self.referenceStringTextField.centerYAnchor],
    [revealButton.widthAnchor constraintEqualToConstant:22],
    [revealButton.heightAnchor constraintEqualToConstant:18]
  ]];
  self.revealPreviewButton = revealButton;
  [self _updateEntryMenu];
  [self _updateReferenceString];
}

- (NSMenu *)_allocateAttributeItemMenu {
  NSMenu *menu = [[NSMenu alloc] init];
  [menu addItemWithTitle:NSLocalizedString(@"UUID","UUID reference item") action:NULL keyEquivalent:@""];
  [menu addItemWithTitle:NSLocalizedString(@"TITLE","Title reference item") action:NULL keyEquivalent:@""];
  [menu addItemWithTitle:NSLocalizedString(@"USERNAME","Username reference item") action:NULL keyEquivalent:@""];
  [menu addItemWithTitle:NSLocalizedString(@"PASSWORD","Password reference item") action:NULL keyEquivalent:@""];
  [menu addItemWithTitle:NSLocalizedString(@"URL","URL reference item") action:NULL keyEquivalent:@""];
  [menu addItemWithTitle:NSLocalizedString(@"NOTES","Notes reference item") action:NULL keyEquivalent:@""];
  NSArray *keys = @[ kKPKReferenceUUIDKey, kKPKReferenceTitleKey, kKPKReferenceUsernameKey, kKPKReferencePasswordKey, kKPKReferenceURLKey, kKPKReferenceNotesKey ];
  [menu.itemArray enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
    NSMenuItem *item = (NSMenuItem *)obj;
    NSAssert(keys.count > idx, @"");
    item.representedObject = keys[idx];
  }];
  return menu;
}

- (NSString *)_displayNameForEntry:(KPKEntry *)entry {
  NSString *resolvedTitle = [entry.title kpk_finalValueForEntry:entry options:KPKCommandEvaluationOptionSkipUserInteraction|KPKCommandEvaluationOptionReadOnly];
  NSString *title = resolvedTitle.length > 0 ? resolvedTitle : NSLocalizedString(@"UNTITLED", "Fallback title for an entry without a title");
  NSMutableArray<NSString *> *groups = [[NSMutableArray alloc] init];
  for(KPKGroup *group = entry.parent; group != nil && group.parent != nil; group = group.parent) {
    if(group.title.length > 0) {
      [groups insertObject:group.title atIndex:0];
    }
  }
  [groups addObject:title];
  return [groups componentsJoinedByString:@" / "];
}

- (void)_updateEntryMenu {
  KPKEntry *destinationEntry = [self.representedObject isKindOfClass:KPKEntry.class] ? self.representedObject : nil;
  NSString *filter = self.searchString ?: @"";
  NSMutableArray<KPKEntry *> *entries = [[NSMutableArray alloc] init];
  for(KPKEntry *entry in destinationEntry.tree.allEntries) {
    if(entry == destinationEntry || entry.isTrash || entry.isTrashed) {
      continue;
    }
    NSString *displayName = [self _displayNameForEntry:entry];
    if(filter.length == 0 || [displayName rangeOfString:filter options:NSCaseInsensitiveSearch].location != NSNotFound) {
      [entries addObject:entry];
    }
  }
  KPKEntry *previousSelection = self.searchKeyPopUpButton.selectedItem.representedObject;
  NSMenu *menu = [[NSMenu alloc] init];
  for(KPKEntry *entry in entries) {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[self _displayNameForEntry:entry] action:NULL keyEquivalent:@""];
    item.representedObject = entry;
    [menu addItem:item];
  }
  if(menu.numberOfItems == 0) {
    [menu addItemWithTitle:NSLocalizedString(@"NO_MATCHING_ENTRIES", "Reference builder has no matching source entries") action:NULL keyEquivalent:@""];
  }
  self.searchKeyPopUpButton.menu = menu;
  NSInteger previousIndex = [entries indexOfObjectIdenticalTo:previousSelection];
  if(previousIndex != NSNotFound) {
    [self.searchKeyPopUpButton selectItemAtIndex:previousIndex];
  }
  self.searchKeyPopUpButton.enabled = entries.count > 0;
}

- (void)setSearchString:(NSString *)searchString {
  if(![searchString isEqualToString:_searchString]) {
    _searchString = [searchString copy];
    self.previewPasswordRevealed = NO;
    [self _updateEntryMenu];
    [self _updateReferenceString];
  }
}

- (IBAction)updateReference:(id)sender {
  self.previewPasswordRevealed = NO;
  [self _updateReferenceString];
}

- (IBAction)updateKey:(id)sender {
  self.previewPasswordRevealed = NO;
  [self _updateReferenceString];
}

- (IBAction)togglePreviewPassword:(NSButton *)sender {
  self.previewPasswordRevealed = !self.previewPasswordRevealed;
  [self _updatePreviewField];
}

- (IBAction)cancelReference:(id)sender {
  [self dismissController:nil];
}

- (IBAction)useReference:(id)sender {
  if(self.referenceString.length == 0 || self.completionHandler == nil) {
    return;
  }
  if(self.valueBeingReplaced.length > 0) {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = NSLocalizedString(@"FIELD_REFERENCE_REPLACE_TITLE", "Title of the confirmation shown before replacing a field value with a reference");
    alert.informativeText = NSLocalizedString(@"FIELD_REFERENCE_REPLACE_MESSAGE", "Message of the confirmation shown before replacing a field value with a reference");
    [alert addButtonWithTitle:NSLocalizedString(@"REPLACE", "Button that replaces an existing field value")];
    [alert addButtonWithTitle:NSLocalizedString(@"CANCEL", "Cancel button")];
    NSWindow *window = self.presentingViewController.view.window ?: self.view.window;
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
      if(returnCode == NSAlertFirstButtonReturn) {
        [self _completeReferenceSelection];
      }
    }];
    return;
  }
  [self _completeReferenceSelection];
}

- (void)_completeReferenceSelection {
  NSString *reference = self.referenceString;
  void (^completionHandler)(NSString *) = self.completionHandler;
  [self dismissController:nil];
  dispatch_async(dispatch_get_main_queue(), ^{
    completionHandler(reference);
  });
}

- (NSString *)_valueForField:(KPKReferenceField)field inEntry:(KPKEntry *)entry {
  switch(field) {
    case KPKReferenceFieldTitle: return entry.title;
    case KPKReferenceFieldUsername: return entry.username;
    case KPKReferenceFieldPassword: return entry.password;
    case KPKReferenceFieldUrl: return entry.url;
    case KPKReferenceFieldNotes: return entry.notes;
    case KPKReferenceFieldUUID: return entry.uuid.UUIDString;
    case KPKReferenceFieldOther: return @"";
  }
  return @"";
}

- (void)_updateReferenceString {
  KPKEntry *sourceEntry = self.searchKeyPopUpButton.selectedItem.representedObject;
  NSString *fieldCode = self.valuePopUpButton.selectedItem.representedObject;
  KPKReferenceField field = [@{ kKPKReferenceTitleKey: @(KPKReferenceFieldTitle),
                               kKPKReferenceUsernameKey: @(KPKReferenceFieldUsername),
                               kKPKReferencePasswordKey: @(KPKReferenceFieldPassword),
                               kKPKReferenceURLKey: @(KPKReferenceFieldUrl),
                               kKPKReferenceNotesKey: @(KPKReferenceFieldNotes),
                               kKPKReferenceUUIDKey: @(KPKReferenceFieldUUID) }[fieldCode] unsignedIntegerValue];
  self.referenceString = sourceEntry == nil ? @"" : [KPKReferenceBuilder referenceToField:field inEntry:sourceEntry];
  NSString *sourceValue = sourceEntry == nil ? @"" : [self _valueForField:field inEntry:sourceEntry];
  self.previewValue = sourceEntry == nil ? @"" : [sourceValue kpk_finalValueForEntry:sourceEntry options:KPKCommandEvaluationOptionSkipUserInteraction|KPKCommandEvaluationOptionReadOnly] ?: @"";
  [self _updatePreviewField];
  self.referenceStringTextField.toolTip = self.referenceString.length > 0
                                          ? [NSString stringWithFormat:NSLocalizedString(@"FIELD_REFERENCE_SOURCE_TOOLTIP_FORMAT", "Reference builder source preview tooltip"), self.referenceString]
                                          : nil;
}

- (void)_updatePreviewField {
  BOOL isPassword = [self.valuePopUpButton.selectedItem.representedObject isEqualToString:kKPKReferencePasswordKey];
  self.revealPreviewButton.hidden = !isPassword || self.previewValue.length == 0;
  self.revealPreviewButton.state = self.previewPasswordRevealed ? NSControlStateValueOn : NSControlStateValueOff;
  self.referenceStringTextField.stringValue = isPassword && !self.previewPasswordRevealed && self.previewValue.length > 0
                                              ? @"••••••••"
                                              : self.previewValue ?: @"";
}
@end
