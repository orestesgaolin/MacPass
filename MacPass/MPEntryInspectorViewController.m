//
//  MPEntryInspectorViewController.m
//  MacPass
//
//  Created by Michael Starke on 27.07.13.
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

#import "MPEntryInspectorViewController.h"
#import "MPInspectorViewController.h"
#import "MPAttachmentTableDataSource.h"
#import "MPAttachmentTableViewDelegate.h"
#import "MPCustomFieldTableViewDelegate.h"
#import "MPPasswordCreatorViewController.h"
#import "MPWindowAssociationsTableViewDelegate.h"
#import "MPWindowTitleComboBoxDelegate.h"
#import "MPTagsTokenFieldDelegate.h"
#import "MPAutotypeBuilderViewController.h"
#import "MPReferenceBuilderViewController.h"
#import "MPTOTPViewController.h"
#import "MPTOTPSetupViewController.h"
#import "MPEntryAttributeViewController.h"
#import "MPNodeExpirationViewController.h"

#import "MPPrettyPasswordTransformer.h"
#import "NSString+MPPasswordCreation.h"

#import "MPDocument.h"
#import "MPIconHelper.h"
#import "MPValueTransformerHelper.h"
#import "MPTemporaryFileStorage.h"
#import "MPTemporaryFileStorageCenter.h"
#import "MPActionHelper.h"
#import "MPSettingsHelper.h"
#import "MPPasteBoardController.h"
#import "MPContextButton.h"
#import "MPAddCustomFieldContextMenuDelegate.h"
#import "KPKEntry+MPCustomAttributeProperties.h"

#import "MPArrayController.h"

#import "KeePassKit/KeePassKit.h"
#import "HNHUi/HNHUi.h"

typedef NS_ENUM(NSUInteger, MPEntryTab) {
  MPEntryTabGeneral,
  MPEntryTabFiles,
  MPEntryTabAutotype
};

typedef NS_ENUM(NSUInteger, MPInpspectorEditorIndex) {
  MPInpspectorEditorIndexImageEditor,
  MPInpspectorEditorIndexTitle,
  MPInpspectorEditorIndexUsername,
  MPInpspectorEditorIndexPassword,
  MPInpspectorEditorIndexURL,
  MPInpspectorEditorIndexExpires,
  MPInpspectorEditorIndexTags,
  MPInpspectorEditorIndexDefaultCount
};


@interface NSObject (MPAppKitPrivateAPI)
- (void)_searchWithGoogleFromMenu:(id)obj;
@end

@interface MPEntryInspectorViewController () {
@private
  NSArrayController *_attachmentsController;
  NSArrayController *_customFieldsController;
  MPArrayController *_windowAssociationsController;
  MPAttachmentTableViewDelegate *_attachmentTableDelegate;
  MPCustomFieldTableViewDelegate *_customFieldTableDelegate;
  MPAttachmentTableDataSource *_attachmentDataSource;
  MPWindowAssociationsTableViewDelegate *_windowAssociationsTableDelegate;
  MPWindowTitleComboBoxDelegate *_windowTitleMenuDelegate;
  MPTagsTokenFieldDelegate *_tagTokenFieldDelegate;
  MPAddCustomFieldContextMenuDelegate *_addCustomFieldContextMenuDelegate;
  NSMutableArray<NSViewController<MPInspectorEditor> *> *_attributeEditorViewControllers;
}

@property (nonatomic, assign) BOOL showPassword;
@property (nonatomic, assign) MPEntryTab activeTab;
@property (nonatomic, readonly) KPKEntry *representedEntry;
@property (strong) MPTOTPViewController *totpViewController;
@property (strong) NSMutableSet<NSString *> *rawReferenceFields;
@property (strong) NSMutableDictionary<NSString *, NSButton *> *referenceButtons;

@property (strong) MPTemporaryFileStorage *quicklookStorage;

@end

@implementation MPEntryInspectorViewController

- (NSString *)nibName {
  return @"EntryInspectorView";
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
  self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
  if (self) {
    _showPassword = NO;
    _attachmentsController = [[NSArrayController alloc] init];
    _customFieldsController = [[NSArrayController alloc] init];
    _windowAssociationsController = [[MPArrayController alloc] init];
    _attachmentTableDelegate = [[MPAttachmentTableViewDelegate alloc] init];
    _customFieldTableDelegate = [[MPCustomFieldTableViewDelegate alloc] init];
    _attachmentDataSource = [[MPAttachmentTableDataSource alloc] init];
    _windowAssociationsTableDelegate = [[MPWindowAssociationsTableViewDelegate alloc] init];
    _windowTitleMenuDelegate = [[MPWindowTitleComboBoxDelegate alloc] init];
    _tagTokenFieldDelegate = [[MPTagsTokenFieldDelegate alloc] init];
    _addCustomFieldContextMenuDelegate = [[MPAddCustomFieldContextMenuDelegate alloc] init];
    _tagTokenFieldDelegate.viewController = self;
    _attachmentTableDelegate.viewController = self;
    _customFieldTableDelegate.viewController = self;
    _addCustomFieldContextMenuDelegate.viewController = self;
    
    _attributeEditorViewControllers = [[NSMutableArray alloc] init];
    _rawReferenceFields = [[NSMutableSet alloc] init];
    _referenceButtons = [[NSMutableDictionary alloc] init];
    _activeTab = MPEntryTabGeneral;
  }
  return self;
}

- (KPKEntry *)representedEntry {
  if([self.representedObject isKindOfClass:KPKEntry.class]) {
    return self.representedObject;
  }
  return nil;
}

- (void)_unbindReferenceValueBindings {
  if(!self.isViewLoaded) {
    return;
  }
  for(NSTextField *textField in @[ self.titleTextField, self.usernameTextField, self.passwordTextField, self.URLTextField ]) {
    if([textField infoForBinding:NSValueBinding] != nil) {
      [textField unbind:NSValueBinding];
    }
  }
}

- (void)setRepresentedObject:(id)representedObject {
  if(self.representedObject) {
    [NSNotificationCenter.defaultCenter removeObserver:self name:KPKWillChangeEntryNotification object:self.representedEntry];
    [NSNotificationCenter.defaultCenter removeObserver:self name:KPKDidChangeEntryNotification object:self.representedEntry];
  }
  /* Detach the bindings while their nested representedObject key paths still
   * point at the object they originally registered with. */
  [self _unbindReferenceValueBindings];
  super.representedObject = representedObject;
  [self.rawReferenceFields removeAllObjects];
  
  [self _updateEditors];
  
  /* only register for a single entry! */
  if(self.representedEntry) {
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(_willChangeEntry:) name:KPKWillChangeEntryNotification object:self.representedEntry];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(_didChangeEntry:) name:KPKDidChangeEntryNotification object:self.representedEntry];
  }
  [self _updateReferencePresentation];
  [self _updateReferenceToolTips];
}

- (void)viewDidLoad {
  
  [self _addScrollViewWithView:self.generalView atTab:MPEntryTabGeneral];
  [self _addScrollViewWithView:self.autotypView atTab:MPEntryTabAutotype];
  
  [self.infoTabControl bind:NSSelectedIndexBinding toObject:self withKeyPath:NSStringFromSelector(@selector(activeTab)) options:nil];
  [self.tabView bind:NSSelectedIndexBinding toObject:self withKeyPath:NSStringFromSelector(@selector(activeTab)) options:nil];

  self.attachmentTableView.backgroundColor = NSColor.clearColor;
  [self.attachmentTableView bind:NSContentBinding toObject:_attachmentsController withKeyPath:NSStringFromSelector(@selector(arrangedObjects)) options:nil];
  self.attachmentTableView.delegate = _attachmentTableDelegate;
  self.attachmentTableView.dataSource = _attachmentDataSource;
  [self.attachmentTableView registerForDraggedTypes:@[NSFilenamesPboardType]];
  [self.attachmentTableView setDraggingSourceOperationMask:NSDragOperationCopy forLocal:NO];
  
  /* extract custom field table view */
  NSView *customFieldTableView = self.customFieldsTableView;
  self.customFieldsTableView.translatesAutoresizingMaskIntoConstraints = NO;
  [self.customFieldsTableView.enclosingScrollView removeFromSuperviewWithoutNeedingDisplay];
  [self.customFieldsTableView removeFromSuperviewWithoutNeedingDisplay];
  
  [self.generalView addSubview:customFieldTableView];
  
  NSDictionary *dict = NSDictionaryOfVariableBindings(customFieldTableView, _fieldsStackView, _addCustomFieldButton);
  [self.generalView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-16-[customFieldTableView]-16-|"
                                                                           options:0
                                                                           metrics:nil
                                                                             views:dict]];
  [self.generalView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[_fieldsStackView]-[customFieldTableView]-[_addCustomFieldButton]"
                                                                           options:0
                                                                           metrics:nil
                                                                             views:dict]];
  
  
  
  self.customFieldsTableView.backgroundColor = NSColor.clearColor;
  self.customFieldsTableView.usesAutomaticRowHeights = YES;
  if (@available(macOS 11.0, *)) {
    self.customFieldsTableView.additionalSafeAreaInsets = NSEdgeInsetsZero;
  }
  [self.customFieldsTableView bind:NSContentBinding toObject:_customFieldsController withKeyPath:NSStringFromSelector(@selector(arrangedObjects)) options:nil];
  self.customFieldsTableView.delegate = _customFieldTableDelegate;
  
  [self.customFieldsTableView sizeLastColumnToFit];
  
  self.windowAssociationsTableView.backgroundColor = NSColor.clearColor;
  self.windowAssociationsTableView.delegate = _windowAssociationsTableDelegate;
  [self.windowAssociationsTableView bind:NSContentBinding toObject:_windowAssociationsController withKeyPath:NSStringFromSelector(@selector(arrangedObjects)) options:nil];
  [self.windowAssociationsTableView bind:NSSelectionIndexesBinding toObject:_windowAssociationsController withKeyPath:NSSelectionIndexesBinding options:nil];
  
  self.windowTitleComboBox.delegate = _windowTitleMenuDelegate;
  
  [self.passwordTextField bind:NSStringFromSelector(@selector(showPassword)) toObject:self withKeyPath:NSStringFromSelector(@selector(showPassword)) options:nil];
  [self.togglePassword bind:NSValueBinding toObject:self withKeyPath:NSStringFromSelector(@selector(showPassword)) options:nil];
  
  self.tagsTokenField.delegate = _tagTokenFieldDelegate;
    
  [self _setupAttributeEditors];
  [self _updateEditors];
  [self _setupReferencePresentationControls];
  
  [self _setupCustomFieldsButton];
  [self _setupViewBindings];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(_didChangePotentialReferenceSource:) name:KPKDidChangeEntryNotification object:nil];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(_didChangePotentialReferenceSource:) name:KPKDidChangeAttributeNotification object:nil];
  [self _updateReferencePresentation];
  [self _updateReferenceToolTips];
}

- (void)registerNotificationsForDocument:(MPDocument *)document {
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(_didAddEntry:)
                                               name:MPDocumentDidAddEntryNotification
                                             object:document];
  _windowAssociationsController.observer = document;
  [NSNotificationCenter.defaultCenter addObserver:self
                                         selector:@selector(_didChangeCurrentItem:)
                                             name:MPDocumentCurrentItemChangedNotification
                                           object:document];
}

#pragma mark -
#pragma mark Actions

- (void)addCustomField:(id)sender {
  [self.observer willChangeModelProperty];
  [self.windowController.document createCustomAttribute:self.representedObject];
  [self.observer didChangeModelProperty];
}
- (void)removeCustomField:(id)sender {
  NSInteger rowIndex = [self.customFieldsTableView rowForView:sender];
  NSAssert(rowIndex >= 0 && rowIndex < self.representedEntry.customAttributes.count, @"Invalid custom attribute index.");
  KPKAttribute *attribute = self.representedEntry.customAttributes[rowIndex];
  [self.observer willChangeModelProperty];
  [self.representedEntry removeCustomAttribute:attribute];
  [self.observer didChangeModelProperty];
}

- (void)saveAttachment:(id)sender {
  NSInteger row = self.attachmentTableView.selectedRow;
  if(row < 0) {
    return; // No selection
  }
  KPKBinary *binary = self.representedEntry.binaries[row];
  NSSavePanel *savePanel = [NSSavePanel savePanel];
  savePanel.canCreateDirectories = YES;
  savePanel.nameFieldStringValue = binary.name;
  
  [savePanel beginSheetModalForWindow:self.windowController.window completionHandler:^(NSInteger result) {
    if(result == NSModalResponseOK) {
      NSError *error;
      BOOL sucess = [binary saveToLocation:savePanel.URL error:&error];
      if(!sucess && error) {
        [NSApp presentError:error];
      }
    }
  }];
}

- (void)addAttachment:(id)sender {
  NSOpenPanel *openPanel = [NSOpenPanel openPanel];
  openPanel.canChooseDirectories = NO;
  openPanel.canChooseFiles = YES;
  openPanel.allowsMultipleSelection = YES;
  openPanel.prompt = NSLocalizedString(@"OPEN_BUTTON_ADD_ATTACHMENT_OPEN_PANEL", "Open button in the open panel to add attachments to an entry");
  openPanel.message = NSLocalizedString(@"MESSAGE_ADD_ATTACHMENT_OPEN_PANEL", "Message in the open panel to add attachments to an entry");
  [openPanel beginSheetModalForWindow:self.windowController.window completionHandler:^(NSInteger result) {
    if(result == NSModalResponseOK) {
      for (NSURL *attachmentURL in openPanel.URLs) {
        KPKBinary *binary = [[KPKBinary alloc] initWithContentsOfURL:attachmentURL];
        [self.observer willChangeModelProperty];
        [self.representedEntry addBinary:binary];
        [self.observer didChangeModelProperty];
      }
    }
  }];
}

- (void)removeAttachment:(id)sender {
  NSInteger row = self.attachmentTableView.selectedRow;
  if(row < 0) {
    return; // no selection
  }
  KPKBinary *binary = self.representedEntry.binaries[row];
  [self.observer willChangeModelProperty];
  [self.representedEntry removeBinary:binary];
  [self.observer didChangeModelProperty];
}

- (void)addWindowAssociation:(id)sender {
  KPKWindowAssociation *associtation = [[KPKWindowAssociation alloc] initWithWindowTitle:NSLocalizedString(@"DEFAULT_WINDOW_TITLE", "Default window title for a new window association") keystrokeSequence:nil];
  [self.observer willChangeModelProperty];
  [self.representedEntry.autotype addAssociation:associtation];
  [self.observer didChangeModelProperty];
}

- (void)removeWindowAssociation:(id)sender {
  NSInteger row = self.windowAssociationsTableView.selectedRow;
  if(row > - 1 && row < self.representedEntry.autotype.associations.count) {
    [self.observer willChangeModelProperty];
    KPKWindowAssociation *association = self.representedEntry.autotype.associations[row];
    if(association) {
      [self.representedEntry.autotype removeAssociation:association];
    }
    [self.observer didChangeModelProperty];
  }
}

- (void)toggleQuicklookPreview:(id)sender {
  if([QLPreviewPanel sharedPreviewPanelExists] && [[QLPreviewPanel sharedPreviewPanel] isVisible]) {
    QLPreviewPanel *panel = [QLPreviewPanel sharedPreviewPanel];
    if([self acceptsPreviewPanelControl:nil]) {
      [self _updatePreviewItemForPanel:panel];
      [panel reloadData];
    }
    else {
      [panel orderOut:sender];
    }
  }
  else {
    [[QLPreviewPanel sharedPreviewPanel] makeKeyAndOrderFront:sender];
  }
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
  switch([MPActionHelper typeForAction:menuItem.action]) {
    case MPActionToggleQuicklook: {
      BOOL enabled = [NSUserDefaults.standardUserDefaults boolForKey:kMPSettingsKeyEnableQuicklookPreview];
      return enabled ? [self acceptsPreviewPanelControl:nil] : NO;
    case MPActionRemoveAttachment:
      return !self.representedEntry.isHistory;
    }
    default:
      return YES;
  }
}
#pragma mark -
#pragma mark QLPreviewPanelDelegate

- (BOOL)acceptsPreviewPanelControl:(QLPreviewPanel *)panel {
  if(self.activeTab == MPEntryTabFiles) {
    return (self.attachmentTableView.selectedRow != -1);
  }
  return NO;
}

- (void)beginPreviewPanelControl:(QLPreviewPanel *)panel {
  [self _updatePreviewItemForPanel:panel];
}

- (void)endPreviewPanelControl:(QLPreviewPanel *)panel {
  MPTemporaryFileStorage *storage = (MPTemporaryFileStorage *)panel.dataSource;
  [MPTemporaryFileStorageCenter.defaultCenter unregisterStorage:storage];
}

- (void)_updatePreviewItemForPanel:(QLPreviewPanel *)panel {
  NSInteger row = self.attachmentTableView.selectedRow;
  NSAssert(row > -1, @"Row needs to be selected");
  KPKBinary *binary = self.representedEntry.binaries[row];
  MPTemporaryFileStorage *oldStorage = (MPTemporaryFileStorage *)panel.dataSource;
  [MPTemporaryFileStorageCenter.defaultCenter unregisterStorage:oldStorage];
  panel.dataSource = [MPTemporaryFileStorageCenter.defaultCenter storageForBinary:binary];
}

#pragma mark -
#pragma mark Popovers

- (IBAction)showReferenceBuilder:(id)sender {
  KPKEntry *destinationEntry = self.representedEntry;
  NSView *location = nil;
  NSString *insertionKey = nil;
  KPKAttribute *insertionAttribute = nil;
  NSString *originalValue = nil;
  NSRange insertionRange = NSMakeRange(NSNotFound, 0);
  if([sender isKindOfClass:NSView.class]) {
    location = sender;
  }
  else if([sender isKindOfClass:NSMenuItem.class]) {
    id representedObject = [sender representedObject];
    if([representedObject isKindOfClass:NSDictionary.class]) {
      location = representedObject[@"textField"];
      insertionKey = representedObject[@"key"];
      insertionAttribute = representedObject[@"attribute"];
      originalValue = representedObject[@"originalValue"];
      insertionRange = [representedObject[@"range"] rangeValue];
    }
    else {
      location = representedObject;
    }
  }
  if(location == nil) {
    location = self.passwordTextField;
  }

  /* Commit the field editor before opening the popover. The captured string is
   * the authoritative value for the selection range used by the menu action. */
  [self commitEditing];
  if(originalValue != nil && insertionAttribute != nil && ![insertionAttribute.value isEqualToString:originalValue]) {
    [self.observer willChangeModelProperty];
    insertionAttribute.value = originalValue;
    [self.observer didChangeModelProperty];
  }
  else if(originalValue != nil && insertionKey.length > 0 && ![[self.representedEntry valueForKey:insertionKey] isEqualToString:originalValue]) {
    [self setValue:originalValue forKeyPath:[NSString stringWithFormat:@"representedObject.%@", insertionKey]];
  }

  MPReferenceBuilderViewController *builder = [[MPReferenceBuilderViewController alloc] init];
  builder.representedObject = destinationEntry;
  builder.valueBeingReplaced = originalValue;
  if(insertionKey != nil) {
    builder.preferredFieldKey = @{ NSStringFromSelector(@selector(title)): kKPKReferenceTitleKey,
                                   NSStringFromSelector(@selector(username)): kKPKReferenceUsernameKey,
                                   NSStringFromSelector(@selector(password)): kKPKReferencePasswordKey,
                                   NSStringFromSelector(@selector(url)): kKPKReferenceURLKey }[insertionKey];
  }
  if((insertionKey.length > 0 || insertionAttribute != nil) && insertionRange.location != NSNotFound) {
    __weak typeof(self) weakSelf = self;
    builder.completionHandler = ^(NSString *reference) {
      typeof(self) strongSelf = weakSelf;
      if(strongSelf == nil || strongSelf.representedEntry != destinationEntry) {
        return;
      }
      NSString *currentValue = insertionAttribute != nil ? insertionAttribute.value : [destinationEntry valueForKey:insertionKey];
      if([currentValue isEqualToString:originalValue]) {
        NSString *newValue = currentValue.length > 0
                             ? reference
                             : [currentValue stringByReplacingCharactersInRange:insertionRange withString:reference];
        if(insertionAttribute != nil) {
          [strongSelf.observer willChangeModelProperty];
          insertionAttribute.value = newValue;
          [strongSelf.observer didChangeModelProperty];
        }
        else {
          [strongSelf setValue:newValue forKeyPath:[NSString stringWithFormat:@"representedObject.%@", insertionKey]];
        }
        [strongSelf _updateReferenceToolTips];
      }
    };
  }
  [self _showPopopver:builder atView:location onEdge:NSMinYEdge];
}

- (IBAction)showAutotypeBuilder:(id)sender {
  NSView *location;
  if([sender isKindOfClass:NSButton.class]) {
    location = sender;
    [sender setEnabled:NO];
  }
  if([sender isKindOfClass:NSMenuItem.class]){
    location = [sender representedObject];
  }
  MPAutotypeBuilderViewController *autotypeBuilder = [[MPAutotypeBuilderViewController alloc] init];
  autotypeBuilder.representedObject = self.representedObject;
  [self _showPopopver:autotypeBuilder atView:location onEdge:NSMinYEdge];
}

- (IBAction)showPasswordGenerator:(id)sender {
  self.generatePasswordButton.enabled = NO;
  MPPasswordCreatorViewController *viewController = [[MPPasswordCreatorViewController alloc] init];
  viewController.allowsEntryDefaults = YES;
  viewController.representedObject = self.representedObject;
  viewController.observer = self.windowController.document;
  [self _showPopopver:viewController atView:sender onEdge:NSMinYEdge];
}

- (IBAction)showOTPSetup:(id)sender {
  NSView *location;
  if([sender isKindOfClass:NSView.class]) {
    location = sender;
  }
  if([sender isKindOfClass:NSMenuItem.class]) {
    if([[sender representedObject] isKindOfClass:NSView.class]) {
      location = [sender representedObject];
    }
  }
  MPTOTPSetupViewController *vc = [[MPTOTPSetupViewController alloc] init];
  vc.representedObject = self.representedObject;
  
  [self _showPopopver:vc atView:location onEdge:NSMinYEdge];
}

- (void)dismissViewController:(NSViewController *)viewController {
  if([viewController isKindOfClass:MPAutotypeBuilderViewController.class]) {
    self.showCustomAssociationSequenceAutotypeBuilderButton.enabled = YES;
    self.showCustomEntrySequenceAutotypeBuilderButton.enabled = YES;
  }
  else if([viewController isKindOfClass:MPPasswordCreatorViewController.class]) {
    self.generatePasswordButton.enabled = YES;
  }
  [super dismissViewController:viewController];
}

- (void)_showPopopver:(NSViewController *)viewController atView:(NSView *)view onEdge:(NSRectEdge)edge {
  if([self.presentedViewControllers containsObject:viewController]) {
    return;
  }
  [self presentViewController:viewController asPopoverRelativeToRect:NSZeroRect ofView:view preferredEdge:edge behavior:NSPopoverBehaviorSemitransient];
}

#pragma mark -
#pragma mark UI Setup
- (void)_addScrollViewWithView:(NSView *)view atTab:(MPEntryTab)tab {
  /* ScrollView setup for the General Tab */
  
  HNHUIScrollView *scrollView = [[HNHUIScrollView alloc] init];
  scrollView.actAsFlipped = NO;
  scrollView.showBottomShadow = NO;
  scrollView.hasVerticalScroller = YES;
  scrollView.drawsBackground = NO;
  scrollView.translatesAutoresizingMaskIntoConstraints = NO;
  NSView *clipView = scrollView.contentView;
  
  NSTabViewItem *tabViewItem = [self.tabView tabViewItemAtIndex:tab];
  NSView *tabView = tabViewItem.view;
  /*
   DO NEVER SET setTranslatesAutoresizingMaskIntoConstraints on NSTabViewItem's view
   [tabView setTranslatesAutoresizingMaskIntoConstraints:NO];
   */
  scrollView.documentView = view;
  [tabView addSubview:scrollView];
  tabViewItem.initialFirstResponder = scrollView;
  
  NSDictionary *views = NSDictionaryOfVariableBindings(view, scrollView);
  [scrollView.superview addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[scrollView]|"
                                                                               options:0
                                                                               metrics:nil
                                                                                 views:views ]];
  [scrollView.superview addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[scrollView]|"
                                                                               options:0
                                                                               metrics:nil
                                                                                 views:views]];
  [clipView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[view]|"
                                                                   options:0
                                                                   metrics:nil
                                                                     views:views]];
  [clipView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[view]"
                                                                   options:0
                                                                   metrics:nil
                                                                     views:views]];
  
  [self.view layoutSubtreeIfNeeded];
}

#pragma mark -
#pragma mark Entry Selection
- (void)_updateEntryValues {
  [self _updateReferencePresentation];
}

- (NSDictionary *)_valueBindingOptionsForTextField:(NSTextField *)textField {
  NSString *placeholder = NSLocalizedString(@"NONE", "Placeholder text for input fields if no entry or group is selected");
  if(textField == self.passwordTextField) {
    return @{ NSNullPlaceholderBindingOption: placeholder, NSValueTransformerNameBindingOption: MPPrettyPasswordTransformerName };
  }
  return @{ NSNullPlaceholderBindingOption: placeholder };
}

- (void)_bindValueForTextField:(NSTextField *)textField modelKey:(NSString *)key {
  if([textField infoForBinding:NSValueBinding] != nil) {
    return;
  }
  [textField bind:NSValueBinding
         toObject:self
      withKeyPath:[NSString stringWithFormat:@"%@.%@", NSStringFromSelector(@selector(representedObject)), key]
          options:[self _valueBindingOptionsForTextField:textField]];
}

- (NSButton *)_referenceButtonForKey:(NSString *)key {
  NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
  button.translatesAutoresizingMaskIntoConstraints = NO;
  button.bezelStyle = NSBezelStyleTexturedRounded;
  button.image = [NSImage imageNamed:NSImageNameFollowLinkFreestandingTemplate];
  button.imagePosition = NSImageOnly;
  button.target = self;
  button.action = @selector(toggleReferenceSource:);
  button.identifier = key;
  button.hidden = YES;
  [button.widthAnchor constraintEqualToConstant:32].active = YES;
  self.referenceButtons[key] = button;
  return button;
}

- (void)_wrapTextField:(NSTextField *)textField modelKey:(NSString *)key {
  NSInteger index = [self.fieldsStackView.arrangedSubviews indexOfObject:textField];
  NSAssert(index != NSNotFound, @"Reference field must be an arranged inspector subview");
  [self.fieldsStackView removeArrangedSubview:textField];
  [textField removeFromSuperview];

  NSButton *button = [self _referenceButtonForKey:key];
  NSStackView *row = [NSStackView stackViewWithViews:@[ textField, button ]];
  row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  row.alignment = NSLayoutAttributeCenterY;
  row.distribution = NSStackViewDistributionFill;
  row.spacing = 4;
  row.detachesHiddenViews = YES;
  row.translatesAutoresizingMaskIntoConstraints = NO;
  [textField setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
  [self.fieldsStackView insertArrangedSubview:row atIndex:index];
  [row.widthAnchor constraintEqualToAnchor:self.fieldsStackView.widthAnchor].active = YES;
}

- (void)_setupReferencePresentationControls {
  [self _wrapTextField:self.titleTextField modelKey:NSStringFromSelector(@selector(title))];
  [self _wrapTextField:self.usernameTextField modelKey:NSStringFromSelector(@selector(username))];
  [self _wrapTextField:self.URLTextField modelKey:NSStringFromSelector(@selector(url))];

  NSStackView *passwordRow = (NSStackView *)self.passwordTextField.superview;
  NSAssert([passwordRow isKindOfClass:NSStackView.class], @"Password editor must use a stack view");
  NSButton *passwordButton = [self _referenceButtonForKey:NSStringFromSelector(@selector(password))];
  [passwordRow insertArrangedSubview:passwordButton atIndex:1];
}

- (NSTextField *)_textFieldForModelKey:(NSString *)key {
  if([key isEqualToString:NSStringFromSelector(@selector(title))]) return self.titleTextField;
  if([key isEqualToString:NSStringFromSelector(@selector(username))]) return self.usernameTextField;
  if([key isEqualToString:NSStringFromSelector(@selector(password))]) return self.passwordTextField;
  if([key isEqualToString:NSStringFromSelector(@selector(url))]) return self.URLTextField;
  return nil;
}

- (void)_updateReferencePresentation {
  if(!self.isViewLoaded) {
    return;
  }
  KPKEntry *entry = self.representedEntry;
  for(NSString *key in @[ NSStringFromSelector(@selector(title)), NSStringFromSelector(@selector(username)), NSStringFromSelector(@selector(password)), NSStringFromSelector(@selector(url)) ]) {
    NSTextField *textField = [self _textFieldForModelKey:key];
    NSButton *button = self.referenceButtons[key];
    NSString *rawValue = entry == nil ? @"" : [entry valueForKey:key];
    BOOL hasReference = [KPKFieldReference referencesInString:rawValue ?: @""].count > 0;
    BOOL showRaw = hasReference && [self.rawReferenceFields containsObject:key];
    button.hidden = !hasReference;
    button.state = showRaw ? NSControlStateValueOn : NSControlStateValueOff;
    button.enabled = entry != nil && !entry.isHistory;
    button.toolTip = showRaw
                     ? NSLocalizedString(@"SHOW_RESOLVED_FIELD_REFERENCE", "Tooltip to show a resolved field reference")
                     : NSLocalizedString(@"EDIT_FIELD_REFERENCE_SOURCE", "Tooltip to edit a field reference expression");

    if(hasReference && !showRaw) {
      if([textField infoForBinding:NSValueBinding] != nil) {
        [textField unbind:NSValueBinding];
      }
      NSString *resolvedValue = [rawValue kpk_finalValueForEntry:entry options:KPKCommandEvaluationOptionSkipUserInteraction|KPKCommandEvaluationOptionReadOnly];
      if(textField == self.passwordTextField) {
        id prettyValue = [[NSValueTransformer valueTransformerForName:MPPrettyPasswordTransformerName] transformedValue:resolvedValue];
        [textField setObjectValue:prettyValue ?: @""];
      }
      else {
        textField.stringValue = resolvedValue ?: @"";
      }
      textField.editable = NO;
      textField.selectable = YES;
    }
    else {
      [self _bindValueForTextField:textField modelKey:key];
      textField.editable = entry != nil && !entry.isHistory;
    }
  }
}

- (IBAction)toggleReferenceSource:(NSButton *)sender {
  NSString *key = sender.identifier;
  if([self.rawReferenceFields containsObject:key]) {
    [self.rawReferenceFields removeObject:key];
  }
  else {
    [self.rawReferenceFields addObject:key];
  }
  [self _updateReferencePresentation];
  [self _updateReferenceToolTips];
}

- (void)_setupViewBindings {
  /* Disable for history view */
  NSArray *inputs = @[self.titleTextField,
                      self.passwordTextField,
                      self.usernameTextField,
                      self.URLTextField,
                      self.expiresCheckButton,
                      self.tagsTokenField,
                      self.generatePasswordButton,
                      self.addAttachmentButton,
                      self.addCustomFieldButton,
                      self.addWindowAssociationButton,
                      self.removeWindowAssociationButton,
                      self.enableAutotypeCheckButton,
                      self.obfuscateAutotypeCheckButton,
                      self.autotypePriorityTextField,
                      self.customEntrySequenceTextField,
                      self.windowTitleComboBox,
                      self.associationSequenceTextField];
  
  for(NSControl *control in inputs) {
    [control bind:NSEnabledBinding
         toObject:self
      withKeyPath:[NSString stringWithFormat:@"%@.%@", NSStringFromSelector(@selector(representedObject)), NSStringFromSelector(@selector(isHistory))]
          options:@{NSConditionallySetsEditableBindingOption: @NO, NSValueTransformerNameBindingOption: NSNegateBooleanTransformerName}];
  }
  
  /* general */
  NSDictionary *nullPlaceholderBindingOptionsDict = @{ NSNullPlaceholderBindingOption: NSLocalizedString(@"NONE", "Placeholder text for input fields if no entry or group is selected")};

  [self _bindValueForTextField:self.titleTextField modelKey:NSStringFromSelector(@selector(title))];
  [self _bindValueForTextField:self.passwordTextField modelKey:NSStringFromSelector(@selector(password))];
  [self _bindValueForTextField:self.usernameTextField modelKey:NSStringFromSelector(@selector(username))];
  [self _bindValueForTextField:self.URLTextField modelKey:NSStringFromSelector(@selector(url))];

  [self.expiresCheckButton bind:NSTitleBinding
                       toObject:self
                    withKeyPath:[NSString stringWithFormat:@"%@.%@.%@", NSStringFromSelector(@selector(representedObject)), NSStringFromSelector(@selector(timeInfo)), NSStringFromSelector(@selector(expirationDate))]
                        options:@{ NSValueTransformerNameBindingOption:MPExpiryDateValueTransformerName }];

  [self.expiresCheckButton bind:NSValueBinding
                       toObject:self
                    withKeyPath:[NSString stringWithFormat:@"%@.%@.%@", NSStringFromSelector(@selector(representedObject)), NSStringFromSelector(@selector(timeInfo)), NSStringFromSelector(@selector(expires))]
                        options:nil];
  
  [self.tagsTokenField bind:NSValueBinding
                   toObject:self
                withKeyPath:[NSString stringWithFormat:@"%@.%@", NSStringFromSelector(@selector(representedObject)), NSStringFromSelector(@selector(tags))]
                    options:nullPlaceholderBindingOptionsDict];
  
  
  [self.uuidTextField bind:NSValueBinding
                  toObject:self
               withKeyPath:[NSString stringWithFormat:@"%@.%@.%@", NSStringFromSelector(@selector(representedObject)), NSStringFromSelector(@selector(uuid)), NSStringFromSelector(@selector(UUIDString))]
                   options:@{ NSConditionallySetsEditableBindingOption: @NO }];
  self.uuidTextField.editable = NO;
    
  /* Attachments */
  [_attachmentsController bind:NSContentArrayBinding
                      toObject:self
                   withKeyPath:[NSString stringWithFormat:@"%@.%@", NSStringFromSelector(@selector(representedObject)), NSStringFromSelector(@selector(binaries))]
                       options:nil];
  
  /* CustomField */
  [_customFieldsController bind:NSContentArrayBinding
                       toObject:self
                    withKeyPath:[NSString stringWithFormat:@"%@.%@", NSStringFromSelector(@selector(representedObject)), NSStringFromSelector(@selector(customAttributes))]
                        options:nil];
  
  /* Autotype */
  [self.enableAutotypeCheckButton bind:NSValueBinding
                              toObject:self
                           withKeyPath:[NSString stringWithFormat:@"%@.%@.%@", NSStringFromSelector(@selector(representedObject)), NSStringFromSelector(@selector(autotype)), NSStringFromSelector(@selector(enabled))] options:nil];
  [self.obfuscateAutotypeCheckButton bind:NSValueBinding
                                 toObject:self
                              withKeyPath:[NSString stringWithFormat:@"%@.%@.%@", NSStringFromSelector(@selector(representedObject)), NSStringFromSelector(@selector(autotype)), NSStringFromSelector(@selector(obfuscateDataTransfer))]
                                  options:nil];
  [self.autotypePriorityTextField bind:NSValueBinding
                              toObject:self
                           withKeyPath:[NSString stringWithFormat:@"%@.%@", NSStringFromSelector(@selector(representedObject)), NSStringFromSelector(@selector(autotypePriority))]
                               options:@{ NSValidatesImmediatelyBindingOption: @YES }];
  
  /* Use enabled2 since NSEnabledBinding is already bound! */
  [self.customEntrySequenceTextField bind:@"enabled2"
                                 toObject:self
                              withKeyPath:[NSString stringWithFormat:@"%@.%@.%@", NSStringFromSelector(@selector(representedObject)), NSStringFromSelector(@selector(autotype)), NSStringFromSelector(@selector(enabled))]
                                  options:nil];
  
  
  [self.customEntrySequenceTextField bind:NSValueBinding
                                 toObject:self
                              withKeyPath:[NSString stringWithFormat:@"%@.%@.%@", NSStringFromSelector(@selector(representedObject)), NSStringFromSelector(@selector(autotype)), NSStringFromSelector(@selector(defaultKeystrokeSequence))]
                                  options:@{ NSValidatesImmediatelyBindingOption: @YES }];
  [_windowAssociationsController bind:NSContentArrayBinding
                             toObject:self
                          withKeyPath:[NSString stringWithFormat:@"%@.%@.%@", NSStringFromSelector(@selector(representedObject)), NSStringFromSelector(@selector(autotype)), NSStringFromSelector(@selector(associations))]
                              options:@{ NSSelectsAllWhenSettingContentBindingOption: @NO }];
  [self.windowTitleComboBox setStringValue:@""];
  [self.windowTitleComboBox bind:NSValueBinding
                        toObject:_windowAssociationsController
                     withKeyPath:[NSString stringWithFormat:@"selection.%@", NSStringFromSelector(@selector(windowTitle))]
                         options:nil];
  
  [self.associationSequenceTextField bind:NSValueBinding
                                 toObject:_windowAssociationsController
                              withKeyPath:[NSString stringWithFormat:@"selection.%@", NSStringFromSelector(@selector(keystrokeSequence))]
                                  options:nil];
  
  
}

- (void)_setupCustomFieldsButton {
  /* FIXME: this is a bug in MPContextButton preventing the image set in IB to be used */
  [self.addCustomFieldButton setImage:[NSImage imageNamed:NSImageNameAddTemplate]];
  NSMenu *customFieldMenu = [[NSMenu alloc] initWithTitle:NSLocalizedString(@"ADD_CUSTOM_FIELD_CONTEXT_MENU", @"Menu displayed for adding special custom keys")];
  customFieldMenu.delegate = _addCustomFieldContextMenuDelegate;
  self.addCustomFieldButton.contextMenu = customFieldMenu;
  //[self.addCustomFieldButton setEnabled:NO forSegment:MPContextButtonSegmentContextButton];
}

- (void)_setupAttributeEditors {
  self.totpViewController = [[MPTOTPViewController alloc] init];
  
  NSInteger urlindex = [self.fieldsStackView.arrangedSubviews indexOfObject:self.URLTextField];
  NSAssert(urlindex != NSNotFound, @"Missing reference view. This should not happen!");
  [self addChildViewController:self.totpViewController];
  [self.fieldsStackView insertArrangedSubview:self.totpViewController.view atIndex:urlindex - 1];

  /*
  MPNodeExpirationViewController *vc = [[MPNodeExpirationViewController alloc] init];
  vc.isEditor = NO;
  [_attributeEditorViewControllers addObject:vc];
  [self.fieldsStackView addArrangedSubview:vc.view];

   MPEntryAttributeViewController *vc = [[MPEntryAttributeViewController alloc] init];
  vc.isEditor = NO;
  [_attributeEditorViewControllers addObject:vc];
  [self.fieldsStackView addArrangedSubview:vc.view];
  
  for(NSUInteger index = 0; index < kKPKDefaultEntryKeysCount; index++) {
    MPEntryAttributeViewController *vc = [[MPEntryAttributeViewController alloc] init];
    vc.isEditor = NO;
    [_attributeEditorViewControllers addObject:vc];
    [self.fieldsStackView addArrangedSubview:vc.view];
  }
   */
}

- (void)_updateEditors {
  self.totpViewController.representedObject = self.representedObject;
  /* Update all the Attribute editors
  _attributeEditorViewControllers[MPInpspectorEditorIndexUsername].representedObject = [self.representedEntry attributeWithKey:kKPKUsernameKey];
   */
}

#pragma mark -
#pragma mark HNHUITextFieldDelegate
- (BOOL)textField:(NSTextField *)textField allowServicesForTextView:(NSTextView *)textView {
  /* disallow servies for password fields */
  if(textField == self.passwordTextField) {
    return NO;
  }
  NSInteger index = MPCustomFieldIndexFromTag(textField.tag);
  if(index > -1) {
    KPKAttribute *attribute = _customFieldsController.arrangedObjects[index];
    return !attribute.protect;
  }
  return YES;
}

- (NSMenu *)textField:(NSTextField *)textField textView:(NSTextView *)view menu:(NSMenu *)menu {
  for(NSMenuItem *item in menu.itemArray) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    if(item.action == @selector(_searchWithGoogleFromMenu:) || item.action == @selector(submenuAction:)) {
      [menu removeItem:item];
    }
#pragma clang diagnostic pop
  }
  if(!self.representedEntry.isHistory) {
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *insertReferenceItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"INSERT_FIELD_REFERENCE", "Menu item to insert a reference to another entry")
                                                                    action:@selector(showReferenceBuilder:)
                                                             keyEquivalent:@""];
    insertReferenceItem.target = self;
    NSString *insertionKey = [self _modelKeyForTextField:textField];
    NSInteger customFieldIndex = MPCustomFieldIndexFromTag(textField.tag);
    KPKAttribute *insertionAttribute = customFieldIndex >= 0 && customFieldIndex < [_customFieldsController.arrangedObjects count]
                                     ? _customFieldsController.arrangedObjects[customFieldIndex]
                                     : nil;
    NSMutableDictionary *insertionInfo = [@{ @"textField": textField,
                                             @"key": insertionKey ?: @"",
                                             @"originalValue": view.string ?: @"",
                                             @"range": [NSValue valueWithRange:view.selectedRange] } mutableCopy];
    if(insertionAttribute != nil) {
      insertionInfo[@"attribute"] = insertionAttribute;
    }
    insertReferenceItem.representedObject = insertionInfo;
    insertReferenceItem.enabled = insertionKey != nil || insertionAttribute != nil;
    [menu addItem:insertReferenceItem];
  }
  NSArray<NSString *> *referenceDescriptions = [self _referenceDescriptionsForString:view.string];
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

- (NSString *)_modelKeyForTextField:(NSTextField *)textField {
  if(textField == self.titleTextField) return NSStringFromSelector(@selector(title));
  if(textField == self.usernameTextField) return NSStringFromSelector(@selector(username));
  if(textField == self.passwordTextField) return NSStringFromSelector(@selector(password));
  if(textField == self.URLTextField) return NSStringFromSelector(@selector(url));
  return nil;
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
  NSMutableArray<NSString *> *descriptions = [[NSMutableArray alloc] init];
  if(self.representedEntry.tree == nil) {
    return descriptions;
  }
  for(KPKFieldReference *reference in [KPKFieldReference referencesInString:string ?: @""]) {
    KPKFieldReferenceResolution *resolution = [KPKReferenceBuilder resolveReference:reference inTree:self.representedEntry.tree excludingEntry:self.representedEntry];
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

- (void)_updateReferenceToolTips {
  if(!self.isViewLoaded) {
    return;
  }
  for(NSTextField *textField in @[ self.titleTextField, self.usernameTextField, self.passwordTextField, self.URLTextField ]) {
    NSString *key = [self _modelKeyForTextField:textField];
    NSString *rawValue = key.length > 0 ? [self.representedEntry valueForKey:key] : @"";
    NSArray<NSString *> *descriptions = [self _referenceDescriptionsForString:rawValue];
    textField.toolTip = descriptions.count > 0 ? [descriptions componentsJoinedByString:@"\n"] : nil;
  }
}

/*- (NSArray<NSString *> *)control:(NSControl *)control textView:(NSTextView *)textView completions:(NSArray<NSString *> *)words forPartialWordRange:(NSRange)charRange indexOfSelectedItem:(NSInteger *)index {
  return @[ @"{USERNAME}", @"{PASSWORD}", @"{URL}", @"{TITLE}" ];
}
*/

- (BOOL)textField:(NSTextField *)textField textView:(NSTextView *)textView performAction:(SEL)action {
  if(action == @selector(copy:)) {
    MPPasteboardOverlayInfoType info = MPPasteboardOverlayInfoCustom;
    NSMutableString *selectedValue = [[NSMutableString alloc] init];
    for(NSValue *rangeValue in textView.selectedRanges) {
      [selectedValue appendString:[textView.string substringWithRange:rangeValue.rangeValue]];
    }
    NSString *name = @"";
    if(selectedValue.length == 0) {
      return YES;
    }
    if(textField == self.usernameTextField) {
      info = MPPasteboardOverlayInfoUsername;
    }
    else if(textField == self.passwordTextField) {
      info = MPPasteboardOverlayInfoPassword;
    }
    else if(textField == self.URLTextField) {
      info = MPPasteboardOverlayInfoURL;
    }
    else if(textField == self.uuidTextField) {
      name = NSLocalizedString(@"UUID", "Displayed name when uuid field was copied");
    }
    else if(textField == self.titleTextField) {
      name = NSLocalizedString(@"TITLE", "Displayed name when title field was copied");
    }
    else {
      NSInteger index = MPCustomFieldIndexFromTag(textField.tag);
      if(index > -1) {
        name = [_customFieldsController.arrangedObjects[index] key];
      }
    }
    [MPPasteBoardController.defaultController copyObject:selectedValue overlayInfo:info name:name atView:self.view];
    return NO;
  }
  return YES;
}

- (IBAction)toggleExpire:(NSButton*)sender {
  if([sender state] == NSOnState && [self.representedEntry.timeInfo.expirationDate isEqualToDate:NSDate.distantFuture]) {
    [NSApp sendAction:self.pickExpireDateButton.action to:nil from:self.pickExpireDateButton];
  }
}

#pragma mark -
#pragma mark MPDocument Notifications

- (void)_didAddEntry:(NSNotification *)notification {
  [self.tabView selectTabViewItemAtIndex:MPEntryTabGeneral];
  [self.titleTextField becomeFirstResponder];
}

- (void)_didChangeCurrentItem:(NSNotification *)notificiation {
  self.showPassword = NO;
}

#pragma mark -
#pragma mark KPKEntry Notifications

- (void)_willChangeEntry:(NSNotification *)notification {
  NSLog(@"willChangeEntry");
}

- (void)_didChangeEntry:(NSNotification *)notification {
  if(notification.object != self.representedObject) {
    NSLog(@"Skipping: didChangeEntry:%@, we do not need this change!", notification.object);
    return;
  }
  NSLog(@"didChangeEntry:%@", notification.object);
  [self _updateEntryValues];
  [self _updateReferenceToolTips];
}

- (void)_refreshReferencePresentationForChangedObject:(id)changedObject {
  KPKEntry *changedEntry = [changedObject isKindOfClass:KPKEntry.class] ? changedObject : nil;
  if([changedObject isKindOfClass:KPKAttribute.class]) {
    for(KPKEntry *entry in self.representedEntry.tree.allEntries) {
      if([entry.attributes indexOfObjectIdenticalTo:changedObject] != NSNotFound) {
        changedEntry = entry;
        break;
      }
    }
  }
  if(changedEntry.tree == nil || changedEntry.tree != self.representedEntry.tree) {
    return;
  }
  [self _updateReferencePresentation];
  [self _updateReferenceToolTips];
}

- (void)_didChangePotentialReferenceSource:(NSNotification *)notification {
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

- (void)_didChangeAttribute:(NSNotification *)notification {
}

@end
