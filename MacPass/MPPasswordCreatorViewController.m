//
//  PasswordCreatorView.m
//  MacPass
//
//  Created by Michael Starke on 31.03.13.
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

#import "MPPasswordCreatorViewController.h"
#import "MPPasteBoardController.h"
#import "NSString+MPPasswordCreation.h"
#import "MPUniqueCharactersFormatter.h"
#import "MPSettingsHelper.h"
#import "MPDocument.h"
#import "MPModelChangeObserving.h"
#import "MPPrettyPasswordTransformer.h"
#import "MPPassphraseGenerator.h"

#import "MPFlagsHelper.h"

#import "KeePassKit/KeePassKit.h"

/*
 
 0 - 20 Terrible
 21 - 31 Weak
 32 - 55 Good
 56 - 85 Excellent
 85 - Fantastic
 
 Scale 0-90
 */
typedef NS_ENUM(NSUInteger, MPPasswordRating) {
  MPPasswordTerrible = 10,
  MPPasswordWeak = 20,
  MPPasswordOk = 30,
  MPPasswordGood = 50,
  MPPasswordStrong = 60
};

#define MIN_PASSWORD_LENGTH 1
#define MAX_PASSWORD_LENGTH 256

@interface MPPasswordCreatorViewController ()

@property (nonatomic, copy) NSString *password;

/* Existing Password UI */
@property (strong) IBOutlet NSTextField *passwordTextField;
@property (strong) IBOutlet NSTextField *passwordLengthTextField;
@property (strong) IBOutlet NSTextField *customCharactersTextField;
@property (strong) IBOutlet NSSlider *passwordLengthSlider;
@property (strong) IBOutlet NSButton *shouldCopyPasswordToPasteboardButton;
@property (strong) IBOutlet NSButton *upperCaseButton;
@property (strong) IBOutlet NSButton *lowerCaseButton;
@property (strong) IBOutlet NSButton *numbersButton;
@property (strong) IBOutlet NSButton *symbolsButton;
@property (strong) IBOutlet NSButton *customButton;
@property (strong) IBOutlet NSButton *ensureOccuranceButton;
@property (strong) IBOutlet NSButton *setDefaultButton;
@property (strong) IBOutlet NSTextField *entropyTextField;
@property (strong) IBOutlet NSLevelIndicator *entropyIndicator;
@property (strong) IBOutlet NSButton *useEntryDefaultsButton;

/* Password mode properties */
@property (nonatomic, copy) NSString *customString;
@property (nonatomic, assign) BOOL useCustomString;
@property (nonatomic, assign) BOOL ensureOccurance;
@property (nonatomic, assign) NSUInteger passwordLength;
@property (nonatomic, assign) CGFloat entropy;

@property (nonatomic, assign) BOOL useEntryDefaults;
@property (nonatomic, assign) MPPasswordCharacterFlags characterFlags;

/* Passphrase mode toggle */
@property (nonatomic, assign) BOOL usePassphraseMode;

/* Passphrase UI - connected via XIB */
@property (strong) IBOutlet NSSegmentedControl *modeToggle;
@property (strong) IBOutlet NSTextField *wordCountLabel;
@property (strong) IBOutlet NSSlider *wordCountSlider;
@property (strong) IBOutlet NSTextField *wordCountTextField;
@property (strong) IBOutlet NSBox *passphraseOptionsBox;
@property (strong) IBOutlet NSButton *capitalizeButton;
@property (strong) IBOutlet NSButton *includeNumbersButton;
@property (strong) IBOutlet NSPopUpButton *separatorPopUp;

/* Password-mode controls connected via XIB */
@property (strong) IBOutlet NSTextField *lengthLabel;
@property (strong) IBOutlet NSBox *characterOptionsBox;

/* Passphrase mode properties */
@property (nonatomic, assign) NSUInteger passphraseWordCount;
@property (nonatomic, assign) MPPassphraseSeparator passphraseSeparator;
@property (nonatomic, assign) BOOL passphraseCapitalize;
@property (nonatomic, assign) BOOL passphraseIncludeNumbers;

@end

@implementation MPPasswordCreatorViewController

- (NSString *)nibName {
  return @"PasswordCreatorView";
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
  self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
  if (self) {
    _password = @"";
    _entropy = 0.0;
    _useEntryDefaults = NO;
    _allowsEntryDefaults = NO;
    _ensureOccurance = NO;
    _usePassphraseMode = NO;
    _passphraseWordCount = 6;
    _passphraseSeparator = MPPassphraseSeparatorDash;
    _passphraseCapitalize = NO;
    _passphraseIncludeNumbers = NO;
    [self _setupDefaults];
  }
  return self;
}

- (void)awakeFromNib {
  self.setDefaultButton.enabled = NO;
  [self _updateSetDefaultsButton:NO];
  
  self.passwordLengthSlider.minValue = MIN_PASSWORD_LENGTH;
  self.passwordLengthSlider.maxValue = MAX_PASSWORD_LENGTH;
  self.passwordLengthSlider.continuous = YES;
  
  self.customCharactersTextField.stringValue = self.customString;
  
  /* Value Transformer */
  id formatter = [[MPUniqueCharactersFormatter alloc] init];
  self.customCharactersTextField.formatter = formatter;
  
  [self.passwordLengthSlider bind:NSValueBinding toObject:self withKeyPath:NSStringFromSelector(@selector(passwordLength)) options:nil];
  [self.passwordLengthTextField bind:NSValueBinding toObject:self withKeyPath:NSStringFromSelector(@selector(passwordLength)) options:nil];
  [self.passwordTextField bind:NSValueBinding toObject:self withKeyPath:NSStringFromSelector(@selector(password)) options:@{ NSValueTransformerNameBindingOption: MPPrettyPasswordTransformerName }];
  
  [self.entropyIndicator bind:NSValueBinding toObject:self withKeyPath:NSStringFromSelector(@selector(entropy)) options:nil];
  [self.entropyTextField bind:NSValueBinding toObject:self withKeyPath:NSStringFromSelector(@selector(entropy)) options:nil];
  
  self.customCharactersTextField.delegate = self;
  [self.customButton bind:NSValueBinding toObject:self withKeyPath:NSStringFromSelector(@selector(useCustomString)) options:nil];
  
  [self.ensureOccuranceButton bind:NSValueBinding toObject:self withKeyPath:NSStringFromSelector(@selector(ensureOccurance)) options:nil];
  
  NSString *copyToPasteBoardKeyPath = [MPSettingsHelper defaultControllerPathForKey:kMPSettingsKeyCopyGeneratedPasswordToClipboard];
  NSUserDefaultsController *defaultsController = NSUserDefaultsController.sharedUserDefaultsController;
  [self.shouldCopyPasswordToPasteboardButton bind:NSValueBinding toObject:defaultsController withKeyPath:copyToPasteBoardKeyPath options:nil];
  
  if(self.allowsEntryDefaults) {
    [self.useEntryDefaultsButton bind:NSValueBinding toObject:self withKeyPath:NSStringFromSelector(@selector(useEntryDefaults)) options:nil];
  }
  else {
    self.useEntryDefaultsButton.enabled = self.allowsEntryDefaults;
  }
  
  self.numbersButton.tag = MPPasswordCharactersNumbers;
  self.upperCaseButton.tag = MPPasswordCharactersUpperCase;
  self.lowerCaseButton.tag = MPPasswordCharactersLowerCase;
  self.symbolsButton.tag = MPPasswordCharactersSymbols;
  
  /* Bind passphrase word count controls */
  [self.wordCountSlider bind:NSValueBinding toObject:self withKeyPath:NSStringFromSelector(@selector(passphraseWordCount)) options:nil];
  [self.wordCountTextField bind:NSValueBinding toObject:self withKeyPath:NSStringFromSelector(@selector(passphraseWordCount)) options:nil];
  self.wordCountTextField.delegate = self;
  
  /* Apply initial mode visibility */
  [self _updateModeVisibility];
  
  [self reset];
}

- (void)reset {
  [self _resetCharacters];
  [self _generatePassword:self];
}

#pragma mark -
#pragma mark Key Events

- (void)flagsChanged:(NSEvent *)theEvent {
  if(!self.allowsEntryDefaults || (nil == [self _currentEntryDefaults])) {
    return; // We aren't using entry so just leave;
  }
  BOOL deleteEntryDefaults = MPIsFlagSetInOptions(NSEventModifierFlagOption, NSEvent.modifierFlags);
  [self _updateSetDefaultsButton:deleteEntryDefaults];
}

#pragma mark -
#pragma mark Actions

- (IBAction)_generatePassword:(id)sender {
  if(self.usePassphraseMode) {
    MPPassphraseGenerator *generator = MPPassphraseGenerator.sharedGenerator;
    self.password = [generator passphraseWithWordCount:self.passphraseWordCount
                                            separator:self.passphraseSeparator
                                           capitalize:self.passphraseCapitalize
                                       includeNumbers:self.passphraseIncludeNumbers];
  }
  else {
    self.password = [NSString passwordWithCharactersets:self.characterFlags
                                   withCustomCharacters:self._customCharacters
                                        ensureOccurence:self.ensureOccurance
                                                 length:self.passwordLength];
  }
}

- (NSString *)_customCharacters{
  if(self.useCustomString && self.customCharactersTextField.stringValue.length > 0) {
    return self.customCharactersTextField.stringValue;
  }
  else{
    return @"";
  }
  
}

- (IBAction)_toggleCharacters:(id)sender {
  self.setDefaultButton.enabled = YES;
  self.characterFlags ^= [sender tag];
  [self reset];
}

- (IBAction)_usePassword:(id)sender {
  if(self.shouldCopyPasswordToPasteboardButton.state == NSOnState) {
    [MPPasteBoardController.defaultController copyObject:self.password];
  }
  KPKEntry *entry = self.representedObject;
  if(entry && self.password.length > 0) {
    [self.observer willChangeModelProperty];
    entry.password = self.password;
    [self.observer didChangeModelProperty];
  }
  if(self.presentingViewController) {
    [self dismissController:sender];
  }
  else {
    [self.view.window performClose:sender];
  }
}

- (IBAction)_cancel:(id)sender {
  if(self.presentingViewController) {
    [self dismissController:sender];
  }
  else {
    [self.view.window performClose:sender];
  }
}

- (IBAction)_setDefault:(id)sender {
  if(self.useEntryDefaults && self.representedObject) {
    NSMutableDictionary *entryDefaults = [[self _currentEntryDefaults] mutableCopy];
    if(!entryDefaults) {
      entryDefaults = [[NSMutableDictionary alloc] initWithCapacity:4]; // we will only add one enty to new settings
    }
    entryDefaults[kMPSettingsKeyDefaultPasswordLength] = @(self.passwordLength);
    entryDefaults[kMPSettingsKeyPasswordCharacterFlags] = @(self.characterFlags);
    entryDefaults[kMPSettingsKeyPasswordUseCustomString] = @(self.useCustomString);
    entryDefaults[kMPSettingsKeyPasswordCustomString] = self.customCharactersTextField.stringValue;
    entryDefaults[kMPSettingsKeyPasswordEnsureOccurance] = @(self.ensureOccurance);
    entryDefaults[kMPSettingsKeyUsePassphraseGenerator] = @(self.usePassphraseMode);
    entryDefaults[kMPSettingsKeyPassphraseWordCount] = @(self.passphraseWordCount);
    entryDefaults[kMPSettingsKeyPassphraseSeparator] = @(self.passphraseSeparator);
    entryDefaults[kMPSettingsKeyPassphraseCapitalize] = @(self.passphraseCapitalize);
    entryDefaults[kMPSettingsKeyPassphraseIncludeNumbers] = @(self.passphraseIncludeNumbers);
    NSMutableDictionary *availableDefaults = [[self _availableEntryDefaults] mutableCopy];
    if(!availableDefaults) {
      availableDefaults = [[NSMutableDictionary alloc] initWithCapacity:1];
    }
    availableDefaults[[self.representedObject uuid].UUIDString] = entryDefaults;
    [NSUserDefaults.standardUserDefaults setObject:availableDefaults forKey:kMPSettingsKeyPasswordDefaultsForEntry];
  }
  else if(!self.useEntryDefaults) {
    [NSUserDefaults.standardUserDefaults setInteger:self.passwordLength forKey:kMPSettingsKeyDefaultPasswordLength];
    [NSUserDefaults.standardUserDefaults setInteger:self.characterFlags forKey:kMPSettingsKeyPasswordCharacterFlags];
    [NSUserDefaults.standardUserDefaults setBool:self.useCustomString forKey:kMPSettingsKeyPasswordUseCustomString];
    [NSUserDefaults.standardUserDefaults setObject:self.customCharactersTextField.stringValue forKey:kMPSettingsKeyPasswordCustomString];
    [NSUserDefaults.standardUserDefaults setBool:self.ensureOccurance forKey:kMPSettingsKeyPasswordEnsureOccurance];
    [NSUserDefaults.standardUserDefaults setBool:self.usePassphraseMode forKey:kMPSettingsKeyUsePassphraseGenerator];
    [NSUserDefaults.standardUserDefaults setInteger:self.passphraseWordCount forKey:kMPSettingsKeyPassphraseWordCount];
    [NSUserDefaults.standardUserDefaults setInteger:self.passphraseSeparator forKey:kMPSettingsKeyPassphraseSeparator];
    [NSUserDefaults.standardUserDefaults setBool:self.passphraseCapitalize forKey:kMPSettingsKeyPassphraseCapitalize];
    [NSUserDefaults.standardUserDefaults setBool:self.passphraseIncludeNumbers forKey:kMPSettingsKeyPassphraseIncludeNumbers];
  }
  else {
    NSLog(@"Cannot set password generator defaults. Inconsistent state. Aborting.");
  }
  self.setDefaultButton.enabled = NO;
}

- (IBAction)_resetEntryDefaults:(id)sender {
  NSMutableDictionary *entryDefaults = [[self _currentEntryDefaults] mutableCopy];
  if(!entryDefaults) {
    return; // We have no defaults, hence nothing to delete
  }
  NSMutableDictionary *availableDefaults = [[self _availableEntryDefaults] mutableCopy];
  NSAssert(availableDefaults, @"Password generator defaults for should be present!");
  [availableDefaults removeObjectForKey:[self.representedObject uuid].UUIDString];
  [NSUserDefaults.standardUserDefaults setObject:availableDefaults forKey:kMPSettingsKeyPasswordDefaultsForEntry];
  self.useEntryDefaults = NO; /* Resetting the UI and Defaults is handled via the setter */
  [self _updateSetDefaultsButton:NO];
}

#pragma mark -
#pragma mark Custom Setter

- (void)setUseEntryDefaults:(BOOL)useEntryDefaults {
  if(self.useEntryDefaults != useEntryDefaults) {
    _useEntryDefaults = useEntryDefaults;
    self.setDefaultButton.enabled = YES;
    [self _setupDefaults];
    [self reset];
  }
}

- (void)setRepresentedObject:(id)representedObject {
  [super setRepresentedObject:representedObject];
  self.useEntryDefaults = [self _hasValidDefaultsForCurrentEntry];
}

- (void)setPassword:(NSString *)password {
  if(![_password isEqualToString:password]) {
    _password = [password copy];
    if(self.usePassphraseMode) {
      MPPassphraseGenerator *generator = MPPassphraseGenerator.sharedGenerator;
      self.entropy = [generator entropyForWordCount:self.passphraseWordCount
                                          separator:self.passphraseSeparator
                                         capitalize:self.passphraseCapitalize
                                     includeNumbers:self.passphraseIncludeNumbers];
    }
    else {
      NSString *customString = self.useCustomString ? self.customCharactersTextField.stringValue : nil;
      self.entropy = [password entropyWhithCharacterSet:self.characterFlags customCharacters:customString ensureOccurance:self.ensureOccurance];
    }
  }
}

- (void)setUseCustomString:(BOOL)useCustomString {
  if(self.useCustomString != useCustomString) {
    self.setDefaultButton.enabled = YES;
    _useCustomString = useCustomString;
    [self _resetCharacters];
  }
}

- (void)setPasswordLength:(NSUInteger)passwordLength {
  if(self.passwordLength != passwordLength) {
    self.setDefaultButton.enabled = YES;
    _passwordLength = passwordLength;
    [self _resetCharacters];
    [self _generatePassword:nil];
  }
}

- (void)setEnsureOccurance:(BOOL)useCharacterFromEachGroup {
  if(self.ensureOccurance != useCharacterFromEachGroup) {
    self.setDefaultButton.enabled = YES;
    _ensureOccurance = useCharacterFromEachGroup;
    [self _resetCharacters];
    [self _generatePassword:nil];
  }
}

#pragma mark -
#pragma mark NSTextFieldDelegate

- (void)controlTextDidChange:(NSNotification *)obj {
  if([obj object] == self.customCharactersTextField) {
    self.setDefaultButton.enabled = YES;
    [self _resetCharacters];
    [self _generatePassword:nil];
  }
  else if([obj object] == self.wordCountTextField) {
    NSInteger value = self.wordCountTextField.integerValue;
    if(value >= 1 && value <= 20) {
      self.passphraseWordCount = value;
    }
  }
}

#pragma mark -
#pragma mark Helper
- (void)_updateSetDefaultsButton:(BOOL)shouldDeleteEntryDefaults {
  if(shouldDeleteEntryDefaults) {
    self.setDefaultButton.title = NSLocalizedString(@"PASSWORD_GENERATOR_RESET_ENTRY_DEFAULTS", "Button to reset the password defaults for a single entry");
    self.setDefaultButton.enabled = YES;
    self.setDefaultButton.action = @selector(_resetEntryDefaults:);
  }
  else {
    self.setDefaultButton.title = NSLocalizedString(@"PASSWORD_GENERATOR_SET_DEFAULTS", "Button to set the defaults of the password generator");
    self.setDefaultButton.action = @selector(_setDefault:);
  }
}

- (NSDictionary *)_availableEntryDefaults {
  return [NSUserDefaults.standardUserDefaults dictionaryForKey:kMPSettingsKeyPasswordDefaultsForEntry];
}

- (NSDictionary *)_currentEntryDefaults {
  if(self.representedObject) {
    NSAssert([self.representedObject isKindOfClass:KPKEntry.class], @"Only KPKEntry as represented object supported!");
    return [self _availableEntryDefaults][[self.representedObject uuid].UUIDString];
  }
  return nil;
}

- (void)_setupDefaults {
  NSDictionary *entryDefaults = [self _currentEntryDefaults];
  if(entryDefaults && self.useEntryDefaults) {
    self.passwordLength = [entryDefaults[kMPSettingsKeyDefaultPasswordLength] integerValue];
    self.characterFlags = [entryDefaults[kMPSettingsKeyPasswordCharacterFlags] integerValue];
    self.useCustomString = [entryDefaults[kMPSettingsKeyPasswordUseCustomString] boolValue];
    self.customString = entryDefaults[kMPSettingsKeyPasswordCustomString];
    self.ensureOccurance = [entryDefaults[kMPSettingsKeyPasswordEnsureOccurance] boolValue];
    self.usePassphraseMode = [entryDefaults[kMPSettingsKeyUsePassphraseGenerator] boolValue];
    self.passphraseWordCount = [entryDefaults[kMPSettingsKeyPassphraseWordCount] integerValue];
    self.passphraseSeparator = [entryDefaults[kMPSettingsKeyPassphraseSeparator] integerValue];
    self.passphraseCapitalize = [entryDefaults[kMPSettingsKeyPassphraseCapitalize] boolValue];
    self.passphraseIncludeNumbers = [entryDefaults[kMPSettingsKeyPassphraseIncludeNumbers] boolValue];
  }
  else {
    self.passwordLength = [NSUserDefaults.standardUserDefaults integerForKey:kMPSettingsKeyDefaultPasswordLength];
    self.characterFlags = [NSUserDefaults.standardUserDefaults integerForKey:kMPSettingsKeyPasswordCharacterFlags];
    self.useCustomString = [NSUserDefaults.standardUserDefaults boolForKey:kMPSettingsKeyPasswordUseCustomString];
    self.customString = [NSUserDefaults.standardUserDefaults stringForKey:kMPSettingsKeyPasswordCustomString];
    self.ensureOccurance = [NSUserDefaults.standardUserDefaults boolForKey:kMPSettingsKeyPasswordEnsureOccurance];
    self.usePassphraseMode = [NSUserDefaults.standardUserDefaults boolForKey:kMPSettingsKeyUsePassphraseGenerator];
    self.passphraseWordCount = [NSUserDefaults.standardUserDefaults integerForKey:kMPSettingsKeyPassphraseWordCount];
    self.passphraseSeparator = [NSUserDefaults.standardUserDefaults integerForKey:kMPSettingsKeyPassphraseSeparator];
    self.passphraseCapitalize = [NSUserDefaults.standardUserDefaults boolForKey:kMPSettingsKeyPassphraseCapitalize];
    self.passphraseIncludeNumbers = [NSUserDefaults.standardUserDefaults boolForKey:kMPSettingsKeyPassphraseIncludeNumbers];
  }
  if(self.passphraseWordCount < 1) {
    self.passphraseWordCount = 6;
  }
}

- (BOOL)_hasValidDefaultsForCurrentEntry {
  return (nil != [self _currentEntryDefaults]);
}

- (void)_resetCharacters {
  if(self.useCustomString) {
    self.customButton.state = NSOnState;
  }
  self.customCharactersTextField.enabled = self.useCustomString;
  
  /* Set to defaults, if we got nothing */
  if(self.characterFlags == 0 && !self.useCustomString) {
    self.characterFlags = MPPasswordCharactersAll;
  }
  
  const BOOL userLowercase = (0 != (MPPasswordCharactersLowerCase & self.characterFlags));
  const BOOL useUppercase = (0 != (MPPasswordCharactersUpperCase & self.characterFlags));
  const BOOL useNumbers = (0 != (MPPasswordCharactersNumbers & self.characterFlags));
  const BOOL useSymbols = (0 != (MPPasswordCharactersSymbols & self.characterFlags));
  
  self.upperCaseButton.state = (useUppercase ? NSOnState : NSOffState);
  self.lowerCaseButton.state = (userLowercase ? NSOnState : NSOffState);
  self.numbersButton.state = (useNumbers ? NSOnState : NSOffState);
  self.symbolsButton.state = (useSymbols ? NSOnState : NSOffState);

  // ensure minimum character lenght
  if(self.ensureOccurance) {
    NSUInteger minimumLength = [NSString minimumPasswordLengthWithCharacterSet:self.characterFlags customCharacters:[self _customCharacters] ensureOccurance:self.ensureOccurance];
    if(self.passwordLength < minimumLength) {
      self.passwordLength = minimumLength;
    }
  }
  
}

#pragma mark -
#pragma mark Passphrase UI

- (void)_modeChanged:(NSSegmentedControl *)sender {
  self.setDefaultButton.enabled = YES;
  self.usePassphraseMode = (sender.selectedSegment == 1);
  [self _updateModeVisibility];
  [self _generatePassword:nil];
}

- (void)_wordCountSliderChanged:(NSSlider *)sender {
  self.passphraseWordCount = sender.integerValue;
}

- (void)_passphraseOptionChanged:(id)sender {
  self.setDefaultButton.enabled = YES;
  self.passphraseCapitalize = (self.capitalizeButton.state == NSOnState);
  self.passphraseIncludeNumbers = (self.includeNumbersButton.state == NSOnState);
  [self _generatePassword:nil];
}

- (void)_separatorChanged:(NSPopUpButton *)sender {
  self.setDefaultButton.enabled = YES;
  self.passphraseSeparator = sender.indexOfSelectedItem;
  [self _generatePassword:nil];
}

- (void)setPassphraseWordCount:(NSUInteger)passphraseWordCount {
  if(_passphraseWordCount != passphraseWordCount) {
    self.setDefaultButton.enabled = YES;
    _passphraseWordCount = passphraseWordCount;
    if(self.usePassphraseMode) {
      [self _generatePassword:nil];
    }
  }
}

- (void)_updateModeVisibility {
  BOOL isPassphrase = self.usePassphraseMode;
  
  /* Password-mode controls */
  self.passwordLengthSlider.hidden = isPassphrase;
  self.passwordLengthTextField.hidden = isPassphrase;
  self.lengthLabel.hidden = isPassphrase;
  self.characterOptionsBox.hidden = isPassphrase;
  
  /* Passphrase-mode controls */
  self.wordCountLabel.hidden = !isPassphrase;
  self.wordCountSlider.hidden = !isPassphrase;
  self.wordCountTextField.hidden = !isPassphrase;
  self.passphraseOptionsBox.hidden = !isPassphrase;
  
  /* Sync passphrase UI state from model */
  self.capitalizeButton.state = self.passphraseCapitalize ? NSOnState : NSOffState;
  self.includeNumbersButton.state = self.passphraseIncludeNumbers ? NSOnState : NSOffState;
  [self.separatorPopUp selectItemAtIndex:self.passphraseSeparator];
  
  /* Update mode toggle selection */
  [self.modeToggle setSelected:!isPassphrase forSegment:0];
  [self.modeToggle setSelected:isPassphrase forSegment:1];
}

@end
