//
//  MPTouchIdCompositeKeyStore.m
//  MacPass
//
//  Created by Julius Zint on 14.03.21.
//  Copyright © 2021 HicknHack Software GmbH. All rights reserved.
//
#import "MPSettingsHelper.h"
#import "MPTouchIdCompositeKeyStore.h"
#import "MPConstants.h"
#import "MPSettingsHelper.h"

#import "NSError+Messages.h"

@interface MPTouchIdCompositeKeyStore ()
@property (readonly, strong) NSMutableDictionary* keys;
@property (nonatomic) MPTouchIDKeyStorage touchIdEnabledState;
- (void)_deleteTouchIdKeyPair;
@end

@implementation MPTouchIdCompositeKeyStore

+ (instancetype)defaultStore {
  static MPTouchIdCompositeKeyStore *instance;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [[MPTouchIdCompositeKeyStore alloc] init];
  });
  return instance;
}

- (instancetype)init {
  self = [super init];
  if(self) {
    _keys = [[NSMutableDictionary alloc] init];
    [self bind:NSStringFromSelector(@selector(touchIdEnabledState))
      toObject:NSUserDefaultsController.sharedUserDefaultsController
   withKeyPath:[MPSettingsHelper defaultControllerPathForKey:kMPSettingsKeyTouchIdEnabled]
       options:nil];
  }
  return self;
}

- (void)setTouchIdEnabledState:(MPTouchIDKeyStorage)touchIdEnabledState {
  switch(touchIdEnabledState) {
    case MPTouchIDKeyStorageTransient:
      // clear persistent store
      [self _clearPersistenCompositeKeyData];
      break;
    case MPTouchIDKeyStoragePersistent:
      // clear transient store
      [self.keys removeAllObjects];
      break;
    default:
      // clear persitent and transient store
      [self _clearPersistenCompositeKeyData];
      [self.keys removeAllObjects];
  }
  _touchIdEnabledState = touchIdEnabledState;
}

- (void)saveCompositeKey:(KPKCompositeKey *)compositeKey forDocumentKey:(NSString *)documentKey {
  if(self.touchIdEnabledState == MPTouchIDKeyStorageDisabled) {
    [self _clearPersistenCompositeKeyData];
    self.keys[documentKey] = nil;
    return;
  }

  NSError *error;
  NSData *encryptedCompositeKey = [self encryptedDataForCompositeKey:compositeKey error:&error];
  if(!encryptedCompositeKey) {
    NSLog(@"Unable ot encrypt composite key: %@", error);
    return;
  }

  switch(self.touchIdEnabledState) {
    case MPTouchIDKeyStorageTransient:
      [self _clearPersistenCompositeKeyData];
      if(nil != encryptedCompositeKey) {
        self.keys[documentKey] = encryptedCompositeKey;
      }
      break;
    case MPTouchIDKeyStoragePersistent:
      self.keys[documentKey] = nil;
      if(nil != encryptedCompositeKey) {
        [self _persistCompositeKeyData:encryptedCompositeKey forDocumentKey:documentKey];
      }
      break;
    default:
      NSAssert(NO,@"Unsupported internal touchID preferences value.");
      break;
  }
}
- (NSData *)loadEncryptedCompositeKeyForDocumentKey:(NSString *)documentKey {
  NSInteger touchIdMode = [NSUserDefaults.standardUserDefaults integerForKey:kMPSettingsKeyTouchIdEnabled];
  NSData* transientKey  = self.keys[documentKey];
  NSData* persistentKey = [self _persitentCompositeKeyDataForDocumentKey:documentKey];
  if(nil == transientKey && nil == persistentKey) {
    return nil;
  }
  if(nil == transientKey || nil == persistentKey) {
    return transientKey == nil ? persistentKey : transientKey;
  }
  if(touchIdMode == NSControlStateValueOn) {
    return persistentKey;
  }
  return transientKey;
}

- (KPKCompositeKey *)compositeKeyForEncryptedKeyData:(NSData *)data error:(NSError *__autoreleasing  _Nullable *)error {
  if(nil == data) {
    return nil;
  }
  
  NSData* tag = [MPTouchIdUnlockPrivateKeyTag dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary *queryPrivateKey = @{
    (id)kSecClass: (id)kSecClassKey,
    (id)kSecAttrApplicationTag: tag,
    (id)kSecAttrKeyType: (id)kSecAttrKeyTypeRSA,
    (id)kSecReturnRef: @YES,
  };
  SecKeyRef privateKey = NULL;
  OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)queryPrivateKey, (CFTypeRef *)&privateKey);
  if(status != errSecSuccess) {
    if(error != NULL) {
      NSString* description = CFBridgingRelease(SecCopyErrorMessageString(status, NULL));
      *error = [NSError errorWithCode:status description:description];
    }
    if(privateKey) {
      CFRelease(privateKey);
    }
    return nil;
  }
  
  SecKeyAlgorithm algorithm = kSecKeyAlgorithmRSAEncryptionOAEPSHA256AESGCM;
  BOOL canDecrypt = SecKeyIsAlgorithmSupported(privateKey, kSecKeyOperationTypeDecrypt, algorithm);
  if(!canDecrypt) {
    if(error != NULL) {
      *error = [NSError errorWithCode:MPErrorTouchIdUnsupportedKeyForEncrpytion description:NSLocalizedString(@"ERROR_TOUCH_ID_UNSUPPORTED_KEY", @"The key stored for TouchID is not suitable for encrpytion")];
    }
    if(privateKey) {
      CFRelease(privateKey);
    }
    return nil;
  }
  
  CFErrorRef errorRef = NULL; // FIXME: Release?
  NSData* clearText = (NSData*)CFBridgingRelease(SecKeyCreateDecryptedData(privateKey, algorithm, (__bridge CFDataRef)data, &errorRef));
  if(clearText) {
    return [NSKeyedUnarchiver unarchiveObjectWithData:clearText];
  }
  if(error != NULL) {
    *error = CFBridgingRelease(errorRef);
  }
  if(privateKey) {
    CFRelease(privateKey);
  }
  return nil;
}


- (NSData *)encryptedDataForCompositeKey:(KPKCompositeKey *)compositeKey error:(NSError *__autoreleasing  _Nullable *)error {
  NSData* keyData = [NSKeyedArchiver archivedDataWithRootObject:compositeKey];
  OSStatus status = errSecSuccess;
  SecKeyRef publicKey = [self _copyPublicKeyForEncryption:&status];
  if(nil == publicKey) {
    [self _deleteTouchIdKeyPair];
    [self _createAndAddRSAKeyPair];
    publicKey = [self _copyPublicKeyForEncryption:&status];
    if(nil == publicKey) {
      NSString* description = CFBridgingRelease(SecCopyErrorMessageString(status, NULL));
      NSLog(@"Error while trying to query public key from Keychain: %@", description);
      return nil;
    }
  }
  SecKeyAlgorithm algorithm = kSecKeyAlgorithmRSAEncryptionOAEPSHA256AESGCM;
  BOOL canEncrypt = SecKeyIsAlgorithmSupported(publicKey, kSecKeyOperationTypeEncrypt, algorithm);
  NSData *encryptedKey = nil;
  if(canEncrypt) {
    CFErrorRef encryptionError = NULL;
    encryptedKey = (NSData*)CFBridgingRelease(SecKeyCreateEncryptedData(publicKey, algorithm, (__bridge CFDataRef)keyData, &encryptionError));
    if (!encryptedKey) {
      NSError *err = CFBridgingRelease(encryptionError);
      NSLog(@"Error while trying to decrypt the CompositeKey for TouchID unlock: %@", [err description]);

      if(publicKey) {
        CFRelease(publicKey);
        publicKey = NULL;
      }

      [self _deleteTouchIdKeyPair];
      [self _createAndAddRSAKeyPair];
      publicKey = [self _copyPublicKeyForEncryption:&status];
      if(nil != publicKey && SecKeyIsAlgorithmSupported(publicKey, kSecKeyOperationTypeEncrypt, algorithm)) {
        CFErrorRef retryError = NULL;
        encryptedKey = (NSData*)CFBridgingRelease(SecKeyCreateEncryptedData(publicKey, algorithm, (__bridge CFDataRef)keyData, &retryError));
        if(!encryptedKey && retryError && error != NULL) {
          *error = CFBridgingRelease(retryError);
        }
      }
    }
  }
  else {
    NSLog(@"The key retreived from the Keychain is unable to encrypt data");

    if(publicKey) {
      CFRelease(publicKey);
      publicKey = NULL;
    }

    [self _deleteTouchIdKeyPair];
    [self _createAndAddRSAKeyPair];
    publicKey = [self _copyPublicKeyForEncryption:&status];
    if(nil != publicKey && SecKeyIsAlgorithmSupported(publicKey, kSecKeyOperationTypeEncrypt, algorithm)) {
      CFErrorRef retryError = NULL;
      encryptedKey = (NSData*)CFBridgingRelease(SecKeyCreateEncryptedData(publicKey, algorithm, (__bridge CFDataRef)keyData, &retryError));
      if(!encryptedKey && retryError && error != NULL) {
        *error = CFBridgingRelease(retryError);
      }
    }
  }
  if (publicKey)  {
    CFRelease(publicKey);
  }
  return encryptedKey;
}

- (SecKeyRef)_copyPublicKeyForEncryption:(OSStatus *)status {
  NSData* publicTag = [MPTouchIdUnlockPublicKeyTag dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary *publicQuery = @{
    (id)kSecClass: (id)kSecClassKey,
    (id)kSecAttrApplicationTag: publicTag,
    (id)kSecAttrKeyType: (id)kSecAttrKeyTypeRSA,
    (id)kSecReturnRef: @YES,
  };

  SecKeyRef publicKey = NULL;
  OSStatus localStatus = SecItemCopyMatching((__bridge CFDictionaryRef)publicQuery, (CFTypeRef *)&publicKey);
  if(localStatus == errSecSuccess && publicKey != NULL) {
    if(status != NULL) {
      *status = localStatus;
    }
    return publicKey;
  }

  NSData* privateTag = [MPTouchIdUnlockPrivateKeyTag dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary *privateQuery = @{
    (id)kSecClass: (id)kSecClassKey,
    (id)kSecAttrApplicationTag: privateTag,
    (id)kSecAttrKeyType: (id)kSecAttrKeyTypeRSA,
    (id)kSecReturnRef: @YES,
  };
  SecKeyRef privateKey = NULL;
  localStatus = SecItemCopyMatching((__bridge CFDictionaryRef)privateQuery, (CFTypeRef *)&privateKey);
  if(localStatus != errSecSuccess || privateKey == NULL) {
    if(status != NULL) {
      *status = localStatus;
    }
    if(privateKey) {
      CFRelease(privateKey);
    }
    return NULL;
  }

  publicKey = SecKeyCopyPublicKey(privateKey);
  CFRelease(privateKey);
  if(status != NULL) {
    *status = (publicKey != NULL) ? errSecSuccess : errSecInternalComponent;
  }
  return publicKey;
}

- (void)_deleteTouchIdKeyPair {
  NSData *publicKeyTag = [MPTouchIdUnlockPublicKeyTag dataUsingEncoding:NSUTF8StringEncoding];
  NSData *privateKeyTag = [MPTouchIdUnlockPrivateKeyTag dataUsingEncoding:NSUTF8StringEncoding];

  NSDictionary *publicQuery = @{
    (id)kSecClass: (id)kSecClassKey,
    (id)kSecAttrApplicationTag: publicKeyTag,
    (id)kSecAttrKeyType: (id)kSecAttrKeyTypeRSA,
  };

  NSDictionary *privateQuery = @{
    (id)kSecClass: (id)kSecClassKey,
    (id)kSecAttrApplicationTag: privateKeyTag,
    (id)kSecAttrKeyType: (id)kSecAttrKeyTypeRSA,
  };

  SecItemDelete((__bridge CFDictionaryRef)publicQuery);
  SecItemDelete((__bridge CFDictionaryRef)privateQuery);
}

- (void)_createAndAddRSAKeyPair {
  NSString* privateKeyLabel = @"MacPass TouchID Feature Private Key";
  NSData* privateKeyTag = [MPTouchIdUnlockPrivateKeyTag dataUsingEncoding:NSUTF8StringEncoding];
  if (@available(macOS 10.13.4, *)) {
    SecAccessControlCreateFlags flags = kSecAccessControlUserPresence;
    CFErrorRef createError = NULL;

    SecAccessControlRef access = SecAccessControlCreateWithFlags(kCFAllocatorDefault,
                                                                 kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                                                 flags,
                                                                 &createError);
    if(access == NULL) {
      NSError *err = CFBridgingRelease(createError);
      NSLog(@"Error while trying to create AccessControl for TouchID unlock feature: %@", [err description]);
      return;
    }

    NSDictionary* attributes = @{
      (id)kSecAttrKeyType:        (id)kSecAttrKeyTypeRSA,
      (id)kSecAttrKeySizeInBits:  @2048,
      (id)kSecPrivateKeyAttrs:
           @{ (id)kSecAttrIsPermanent:    @YES,
              (id)kSecAttrApplicationTag: privateKeyTag,
              (id)kSecAttrLabel: privateKeyLabel,
              (id)kSecAttrAccessControl:  (__bridge id)access
            },
    };
    SecKeyRef result = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes, &createError);
    CFRelease(access);

    if(result != NULL) {
      CFRelease(result);
      return;
    }

    CFIndex errorCode = createError ? CFErrorGetCode(createError) : 0;
    NSError *firstError = CFBridgingRelease(createError);

    if(errorCode != errSecMissingEntitlement) {
      NSLog(@"Error while trying to create a RSA keypair for TouchID unlock feature: %@", [firstError description]);
      return;
    }

    NSLog(@"Retrying TouchID key creation with relaxed accessibility due to missing entitlement context.");

    CFErrorRef retryError = NULL;
    SecAccessControlRef retryAccess = SecAccessControlCreateWithFlags(kCFAllocatorDefault,
                                                                      kSecAttrAccessibleWhenUnlocked,
                                                                      flags,
                                                                      &retryError);
    if(retryAccess == NULL) {
      NSError *err = CFBridgingRelease(retryError);
      NSLog(@"Error while trying to create fallback AccessControl for TouchID unlock feature: %@", [err description]);
      return;
    }

    NSDictionary* retryAttributes = @{
      (id)kSecAttrKeyType:        (id)kSecAttrKeyTypeRSA,
      (id)kSecAttrKeySizeInBits:  @2048,
      (id)kSecPrivateKeyAttrs:
           @{ (id)kSecAttrIsPermanent:    @YES,
              (id)kSecAttrApplicationTag: privateKeyTag,
              (id)kSecAttrLabel: privateKeyLabel,
              (id)kSecAttrAccessControl:  (__bridge id)retryAccess
            },
    };

    SecKeyRef retryResult = SecKeyCreateRandomKey((__bridge CFDictionaryRef)retryAttributes, &retryError);
    CFRelease(retryAccess);

    if(retryResult == NULL) {
      NSError *err = CFBridgingRelease(retryError);
      NSLog(@"Error while trying to create fallback RSA keypair for TouchID unlock feature: %@", [err description]);
      return;
    }
    CFRelease(retryResult);
  }
  else {
    return;
  }
}

- (NSData *)_persitentCompositeKeyDataForDocumentKey:(NSString *)key {
  if(key.length == 0) {
    return nil;
  }
  return [NSUserDefaults.standardUserDefaults objectForKey:kMPSettingsKeyTouchIdEncryptedKeyStore][key];
}

- (void)_persistCompositeKeyData:(NSData *)data forDocumentKey:(NSString *)key {
  if(data.length == 0 || key.length == 0) {
    return;
  }
  NSMutableDictionary *dict = [[NSUserDefaults.standardUserDefaults objectForKey:kMPSettingsKeyTouchIdEncryptedKeyStore] mutableCopy];
  if(nil == dict) {
    dict = [[NSMutableDictionary alloc] init];
  }
  dict[key] = data;
  [NSUserDefaults.standardUserDefaults setObject:[dict copy] forKey:kMPSettingsKeyTouchIdEncryptedKeyStore];
}

- (void)_clearPersistenCompositeKeyData {
  [NSUserDefaults.standardUserDefaults removeObjectForKey:kMPSettingsKeyTouchIdEncryptedKeyStore];
}

@end
