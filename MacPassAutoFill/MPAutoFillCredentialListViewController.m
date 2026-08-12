#import "MPAutoFillCredentialListViewController.h"

#import "MPAutoFillRequestCoordinator.h"

@interface MPAutoFillCredentialListViewController () <NSTableViewDataSource, NSTableViewDelegate>
@property(nonatomic, copy) NSArray<MPAutoFillCredentialSelection *> *selections;
@property(nonatomic, strong) NSTableView *tableView;
@end

@implementation MPAutoFillCredentialListViewController

- (instancetype)initWithSelections:(NSArray<MPAutoFillCredentialSelection *> *)selections {
  self = [super initWithNibName:nil bundle:nil];
  if (self) _selections = [selections copy];
  return self;
}

- (void)loadView {
  NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 460, 320)];
  NSTextField *title = [NSTextField labelWithString:NSLocalizedString(@"AUTOFILL_PROVIDER_CHOOSE_CREDENTIAL", nil)];
  title.font = [NSFont systemFontOfSize:18 weight:NSFontWeightSemibold];
  title.translatesAutoresizingMaskIntoConstraints = NO;

  self.tableView = [[NSTableView alloc] init];
  self.tableView.headerView = nil;
  self.tableView.rowHeight = 42;
  self.tableView.dataSource = self;
  self.tableView.delegate = self;
  self.tableView.target = self;
  self.tableView.doubleAction = @selector(fill:);
  self.tableView.accessibilityLabel = NSLocalizedString(@"AUTOFILL_PROVIDER_CREDENTIALS_ACCESSIBILITY_LABEL", nil);
  [self.tableView addTableColumn:[[NSTableColumn alloc] initWithIdentifier:@"credential"]];
  NSScrollView *scrollView = [[NSScrollView alloc] init];
  scrollView.documentView = self.tableView;
  scrollView.hasVerticalScroller = YES;
  scrollView.translatesAutoresizingMaskIntoConstraints = NO;

  NSButton *cancel = [NSButton buttonWithTitle:NSLocalizedString(@"AUTOFILL_PROVIDER_CANCEL", nil)
                                         target:self action:@selector(cancel:)];
  NSButton *fill = [NSButton buttonWithTitle:NSLocalizedString(@"AUTOFILL_PROVIDER_FILL_PASSWORD", nil)
                                       target:self action:@selector(fill:)];
  fill.keyEquivalent = @"\r";
  cancel.translatesAutoresizingMaskIntoConstraints = NO;
  fill.translatesAutoresizingMaskIntoConstraints = NO;
  [view addSubview:title];
  [view addSubview:scrollView];
  [view addSubview:cancel];
  [view addSubview:fill];
  [NSLayoutConstraint activateConstraints:@[
    [title.topAnchor constraintEqualToAnchor:view.topAnchor constant:20],
    [title.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20],
    [scrollView.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:14],
    [scrollView.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20],
    [scrollView.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-20],
    [scrollView.bottomAnchor constraintEqualToAnchor:fill.topAnchor constant:-16],
    [fill.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-20],
    [fill.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-18],
    [cancel.trailingAnchor constraintEqualToAnchor:fill.leadingAnchor constant:-10],
    [cancel.centerYAnchor constraintEqualToAnchor:fill.centerYAnchor],
  ]];
  self.view = view;
  if (self.selections.count > 0) [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return self.selections.count; }

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
  MPAutoFillCredentialSelection *selection = self.selections[row];
  NSTableCellView *cell = [tableView makeViewWithIdentifier:@"credential" owner:self];
  if (!cell) {
    cell = [[NSTableCellView alloc] init];
    cell.identifier = @"credential";
    NSTextField *label = [NSTextField labelWithString:@""];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    cell.textField = label;
    [cell addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
      [label.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:8],
      [label.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-8],
      [label.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
    ]];
  }
  cell.textField.stringValue = selection.username.length > 0 ?
      [NSString stringWithFormat:@"%@  -  %@", selection.title, selection.username] : selection.title;
  return cell;
}

- (void)fill:(id)sender {
  NSInteger row = self.tableView.selectedRow;
  if (row >= 0 && row < (NSInteger)self.selections.count) {
    [self.delegate credentialListDidSelectCredential:self.selections[row]];
  }
}

- (void)cancel:(id)sender { [self.delegate credentialListDidCancel]; }

@end
