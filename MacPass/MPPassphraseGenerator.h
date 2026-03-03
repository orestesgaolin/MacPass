//
//  MPPassphraseGenerator.h
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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, MPPassphraseSeparator) {
  MPPassphraseSeparatorDash = 0,
  MPPassphraseSeparatorSpace,
  MPPassphraseSeparatorDot,
  MPPassphraseSeparatorUnderscore,
  MPPassphraseSeparatorComma,
  MPPassphraseSeparatorNone,
  MPPassphraseSeparatorCount
};

@interface MPPassphraseGenerator : NSObject

@property (class, readonly) MPPassphraseGenerator *sharedGenerator;

/**
 *  Generates a passphrase from the EFF word list.
 *
 *  @param wordCount  Number of words in the passphrase (1+)
 *  @param separator  Separator type between words
 *  @param capitalize Whether to capitalize the first letter of each word
 *  @param includeNumbers Whether to interleave random digits between words
 *
 *  @return Generated passphrase string
 */
- (NSString *)passphraseWithWordCount:(NSUInteger)wordCount
                            separator:(MPPassphraseSeparator)separator
                           capitalize:(BOOL)capitalize
                       includeNumbers:(BOOL)includeNumbers;

/**
 *  Returns the separator string for the given separator type.
 */
+ (NSString *)separatorStringForType:(MPPassphraseSeparator)separator;

/**
 *  Calculates entropy in bits for a passphrase with the given settings.
 */
- (CGFloat)entropyForWordCount:(NSUInteger)wordCount
                     separator:(MPPassphraseSeparator)separator
                    capitalize:(BOOL)capitalize
                includeNumbers:(BOOL)includeNumbers;

/**
 *  Number of words loaded from the word list.
 */
@property (nonatomic, readonly) NSUInteger wordListSize;

@end

NS_ASSUME_NONNULL_END
