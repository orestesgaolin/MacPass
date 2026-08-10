//
//  MPPasswordInputController.h
//  MacPass
//
//  Created by Michael Starke on 17.02.13.
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

#import "MPViewController.h"
#import "KeePassKit/KeePassKit.h"

@class KPKCompositeKey;

typedef NS_OPTIONS(NSUInteger, MPPasswordInputPresentationState) {
  MPPasswordInputPresentationManualOnly          = 0,
  MPPasswordInputPresentationTouchIDAvailable    = 1 << 0,
  MPPasswordInputPresentationProvisioningNeeded  = 1 << 1,
  MPPasswordInputPresentationShortcutAvailable   = 1 << 2,
};

@interface MPPasswordInputController : MPViewController <NSTouchBarDelegate>

typedef BOOL (^passwordInputCompletionBlock)(KPKCompositeKey *key, NSURL* keyFileURL, BOOL didCancel, NSError *__autoreleasing*error);

- (void)requestPasswordWithMessage:(NSString *)message cancelLabel:(NSString *)cancelLabel completionHandler:(passwordInputCompletionBlock)completionHandler;
- (void)requestPasswordWithMessage:(NSString *)message cancelLabel:(NSString *)cancelLabel attemptTouchID:(BOOL)attemptTouchID completionHandler:(passwordInputCompletionBlock)completionHandler;

+ (MPPasswordInputPresentationState)presentationStateForTouchIDMode:(NSInteger)touchIDMode
                                                        keyAvailable:(BOOL)keyAvailable
                                                     shortcutEnabled:(BOOL)shortcutEnabled
                                                       shortcutValid:(BOOL)shortcutValid
                                                            supported:(BOOL)supported;
+ (NSString *)touchIDShortcutHintForKeyData:(NSData *)keyData enabled:(BOOL)enabled;


@end
