//
//  MPPassphraseGenerator.m
//  MacPass
//
//  Created by MacPass on 03.03.26.
//  Copyright (c) 2026 HicknHack Software GmbH. All rights reserved.
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

#import "MPPassphraseGenerator.h"

@interface MPPassphraseGenerator ()
@property (nonatomic, strong) NSArray<NSString *> *wordList;
@end

@implementation MPPassphraseGenerator

+ (MPPassphraseGenerator *)sharedGenerator {
  static MPPassphraseGenerator *sharedInstance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sharedInstance = [[MPPassphraseGenerator alloc] init];
  });
  return sharedInstance;
}

- (instancetype)init {
  self = [super init];
  if(self) {
    [self _loadWordList];
  }
  return self;
}

- (void)_loadWordList {
  NSString *path = [NSBundle.mainBundle pathForResource:@"eff_large_wordlist" ofType:@"txt"];
  if(!path) {
    NSLog(@"ERROR: EFF word list not found in bundle!");
    self.wordList = @[@"error"];
    return;
  }
  
  NSError *error = nil;
  NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
  if(error) {
    NSLog(@"ERROR: Failed to load EFF word list: %@", error.localizedDescription);
    self.wordList = @[@"error"];
    return;
  }
  
  NSMutableArray<NSString *> *words = [NSMutableArray arrayWithCapacity:7776];
  NSArray<NSString *> *lines = [content componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
  
  for(NSString *line in lines) {
    NSString *trimmedLine = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if(trimmedLine.length == 0) {
      continue;
    }
    // Format: "11111\tabacus" - dice number followed by tab and word
    NSArray<NSString *> *components = [trimmedLine componentsSeparatedByString:@"\t"];
    if(components.count >= 2) {
      NSString *word = [components[1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
      if(word.length > 0) {
        [words addObject:word];
      }
    }
  }
  
  self.wordList = [words copy];
  NSLog(@"Loaded EFF word list with %lu words", (unsigned long)self.wordList.count);
}

- (NSUInteger)wordListSize {
  return self.wordList.count;
}

+ (NSString *)separatorStringForType:(MPPassphraseSeparator)separator {
  switch(separator) {
    case MPPassphraseSeparatorDash:
      return @"-";
    case MPPassphraseSeparatorSpace:
      return @" ";
    case MPPassphraseSeparatorDot:
      return @".";
    case MPPassphraseSeparatorUnderscore:
      return @"_";
    case MPPassphraseSeparatorComma:
      return @",";
    case MPPassphraseSeparatorNone:
      return @"";
    default:
      return @"-";
  }
}

- (NSString *)_randomWord {
  if(self.wordList.count == 0) {
    return @"error";
  }
  uint32_t index = arc4random_uniform((uint32_t)self.wordList.count);
  return self.wordList[index];
}

- (NSString *)passphraseWithWordCount:(NSUInteger)wordCount
                            separator:(MPPassphraseSeparator)separator
                           capitalize:(BOOL)capitalize
                       includeNumbers:(BOOL)includeNumbers {
  if(wordCount < 1) {
    wordCount = 1;
  }
  
  NSString *separatorString = [MPPassphraseGenerator separatorStringForType:separator];
  NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:wordCount * 2];
  
  for(NSUInteger i = 0; i < wordCount; i++) {
    NSString *word = [self _randomWord];
    
    if(capitalize) {
      word = [word capitalizedString];
    }
    
    if(i > 0 && includeNumbers) {
      // Insert a random digit between words
      uint32_t digit = arc4random_uniform(10);
      [parts addObject:[NSString stringWithFormat:@"%u", digit]];
    }
    
    [parts addObject:word];
  }
  
  return [parts componentsJoinedByString:separatorString];
}

- (CGFloat)entropyForWordCount:(NSUInteger)wordCount
                     separator:(MPPassphraseSeparator)separator
                    capitalize:(BOOL)capitalize
                includeNumbers:(BOOL)includeNumbers {
  if(wordCount < 1 || self.wordList.count == 0) {
    return 0;
  }
  
  // Each word: log2(wordListSize) bits
  CGFloat bitsPerWord = log2((CGFloat)self.wordList.count);
  CGFloat entropy = wordCount * bitsPerWord;
  
  // Capitalization: adds 1 bit per word (capitalize or not)
  if(capitalize) {
    // The capitalization itself is deterministic (always capitalize), so no additional entropy.
    // But if the user could toggle it, the attacker must consider both possibilities.
    // For simplicity, we don't add entropy for always-on capitalization.
  }
  
  // Numbers between words: log2(10) ~= 3.32 bits per digit
  if(includeNumbers && wordCount > 1) {
    CGFloat bitsPerDigit = log2(10.0);
    entropy += (wordCount - 1) * bitsPerDigit;
  }
  
  return entropy;
}

@end
