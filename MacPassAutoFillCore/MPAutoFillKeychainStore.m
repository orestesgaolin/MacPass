#import "MPAutoFillKeychainStore.h"

#import <LocalAuthentication/LocalAuthentication.h>

#import "MPAutoFillErrors.h"

static NSString * const MPAutoFillCurrentGenerationService = @"dev.roszkowski.macpass.autofill.current-generation.v1";
static NSString * const MPAutoFillGenerationHighWaterService = @"dev.roszkowski.macpass.autofill.generation-high-water.v1";
static const NSInteger MPAutoFillActivationSchemaVersion = 2;
static const NSUInteger MPAutoFillMaximumKeychainPublications = 1024;

static BOOL MPAutoFillKeychainCanonicalUUID(NSString *value) {
  if (![value isKindOfClass:NSString.class] || value.length != 36 || ![value canBeConvertedToEncoding:NSASCIIStringEncoding]) {
    return NO;
  }
  NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:value];
  return uuid && [uuid.UUIDString.lowercaseString isEqualToString:value];
}

@interface MPAutoFillKeychainStore ()
@property(nonatomic, copy) NSString *accessGroup;
@end


@implementation MPAutoFillKeychainStore

- (instancetype)initWithAccessGroup:(NSString *)accessGroup {
  NSParameterAssert(accessGroup.length > 0);
  self = [super init];
  if (self) {
    _accessGroup = [accessGroup copy];
  }
  return self;
}

- (NSData *)tagForPublicationIdentifier:(NSString *)publicationIdentifier privateKey:(BOOL)privateKey {
  NSString *kind = privateKey ? @"private" : @"public";
  NSString *tag = [NSString stringWithFormat:@"dev.roszkowski.macpass.autofill.%@.v1:%@", kind, publicationIdentifier];
  return [tag dataUsingEncoding:NSUTF8StringEncoding];
}

- (BOOL)createKeyPairForPublicationIdentifier:(NSString *)publicationIdentifier error:(NSError **)error {
  if (!MPAutoFillKeychainCanonicalUUID(publicationIdentifier)) {
    if (error) {
      *error = MPAutoFillError(MPAutoFillErrorInvalidArgument, @"The publication identifier is invalid.", nil);
    }
    return NO;
  }
  if (@available(macOS 10.15, *)) {
    CFErrorRef accessError = NULL;
    SecAccessControlRef accessControl = SecAccessControlCreateWithFlags(
        kCFAllocatorDefault, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        kSecAccessControlUserPresence | kSecAccessControlPrivateKeyUsage, &accessError);
    if (!accessControl) {
      NSError *underlyingError = CFBridgingRelease(accessError);
      if (error) {
        *error = MPAutoFillError(MPAutoFillErrorKeychainUnavailable, @"Private-key access control could not be created.", underlyingError);
      }
      return NO;
    }
    NSDictionary *attributes = @{
      (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeRSA,
      (__bridge id)kSecAttrKeySizeInBits: @3072,
      (__bridge id)kSecUseDataProtectionKeychain: @YES,
      (__bridge id)kSecPrivateKeyAttrs: @{
        (__bridge id)kSecAttrIsPermanent: @YES,
        (__bridge id)kSecAttrApplicationTag: [self tagForPublicationIdentifier:publicationIdentifier privateKey:YES],
        (__bridge id)kSecAttrAccessGroup: self.accessGroup,
        (__bridge id)kSecAttrAccessControl: (__bridge id)accessControl,
        (__bridge id)kSecAttrSynchronizable: @NO,
      },
      (__bridge id)kSecPublicKeyAttrs: @{
        (__bridge id)kSecAttrIsPermanent: @YES,
        (__bridge id)kSecAttrApplicationTag: [self tagForPublicationIdentifier:publicationIdentifier privateKey:NO],
        (__bridge id)kSecAttrAccessGroup: self.accessGroup,
        (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        (__bridge id)kSecAttrSynchronizable: @NO,
      },
    };
    CFErrorRef createError = NULL;
    SecKeyRef privateKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes, &createError);
    CFRelease(accessControl);
    if (!privateKey) {
      NSError *underlyingError = CFBridgingRelease(createError);
      if (error) {
        *error = MPAutoFillError(MPAutoFillErrorKeychainUnavailable, @"The publication key pair could not be created.", underlyingError);
      }
      return NO;
    }
    CFRelease(privateKey);
    return YES;
  }
  if (error) {
    *error = MPAutoFillError(MPAutoFillErrorKeychainUnavailable, @"The data-protection Keychain is unavailable.", nil);
  }
  return NO;
}

- (SecKeyRef)copyPublicKeyForPublicationIdentifier:(NSString *)publicationIdentifier error:(NSError **)error {
  if (!MPAutoFillKeychainCanonicalUUID(publicationIdentifier)) {
    if (error) {
      *error = MPAutoFillError(MPAutoFillErrorInvalidArgument, @"The publication identifier is invalid.", nil);
    }
    return NULL;
  }
  return [self copyKeyForPublicationIdentifier:publicationIdentifier privateKey:NO authenticationContext:nil error:error];
}

- (SecKeyRef)copyPrivateKeyForPublicationIdentifier:(NSString *)publicationIdentifier
                              authenticationContext:(LAContext *)context
                                 interactionAllowed:(BOOL)interactionAllowed
                                              error:(NSError **)error {
  if (!MPAutoFillKeychainCanonicalUUID(publicationIdentifier)) {
    if (error) {
      *error = MPAutoFillError(MPAutoFillErrorInvalidArgument, @"The publication identifier is invalid.", nil);
    }
    return NULL;
  }
  context.interactionNotAllowed = !interactionAllowed;
  return [self copyKeyForPublicationIdentifier:publicationIdentifier privateKey:YES authenticationContext:context error:error];
}

- (SecKeyRef)copyKeyForPublicationIdentifier:(NSString *)publicationIdentifier
                                  privateKey:(BOOL)privateKey
                       authenticationContext:(LAContext *)context
                                       error:(NSError **)error {
  if (@available(macOS 10.15, *)) {
    NSMutableDictionary *query = [@{
      (__bridge id)kSecClass: (__bridge id)kSecClassKey,
      (__bridge id)kSecAttrKeyClass: privateKey ? (__bridge id)kSecAttrKeyClassPrivate : (__bridge id)kSecAttrKeyClassPublic,
      (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeRSA,
      (__bridge id)kSecAttrApplicationTag: [self tagForPublicationIdentifier:publicationIdentifier privateKey:privateKey],
      (__bridge id)kSecAttrAccessGroup: self.accessGroup,
      (__bridge id)kSecAttrSynchronizable: @NO,
      (__bridge id)kSecUseDataProtectionKeychain: @YES,
      (__bridge id)kSecReturnRef: @YES,
      (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
    } mutableCopy];
    if (context) {
      query[(__bridge id)kSecUseAuthenticationContext] = context;
    }
    SecKeyRef key = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&key);
    if (status == errSecSuccess && key && CFGetTypeID(key) == SecKeyGetTypeID()) {
      return key;
    }
    if (key) {
      CFRelease(key);
    }
    if (error) {
      *error = status == errSecSuccess
          ? MPAutoFillError(MPAutoFillErrorKeychainUnavailable, @"The publication key has an invalid type.", nil)
          : MPAutoFillKeychainError(status, @"The publication key could not be read.");
    }
    return NULL;
  }
  if (error) {
    *error = MPAutoFillError(MPAutoFillErrorKeychainUnavailable, @"The data-protection Keychain is unavailable.", nil);
  }
  return NULL;
}

- (BOOL)deleteKeyPairForPublicationIdentifier:(NSString *)publicationIdentifier error:(NSError **)error {
  if (!MPAutoFillKeychainCanonicalUUID(publicationIdentifier)) {
    if (error) {
      *error = MPAutoFillError(MPAutoFillErrorInvalidArgument, @"The publication identifier is invalid.", nil);
    }
    return NO;
  }
  if (@available(macOS 10.15, *)) {
    for (NSNumber *privateKey in @[@YES, @NO]) {
      NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassKey,
        (__bridge id)kSecAttrKeyClass: privateKey.boolValue ? (__bridge id)kSecAttrKeyClassPrivate : (__bridge id)kSecAttrKeyClassPublic,
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeRSA,
        (__bridge id)kSecAttrApplicationTag: [self tagForPublicationIdentifier:publicationIdentifier privateKey:privateKey.boolValue],
        (__bridge id)kSecAttrAccessGroup: self.accessGroup,
        (__bridge id)kSecAttrSynchronizable: @NO,
        (__bridge id)kSecUseDataProtectionKeychain: @YES,
      };
      OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
      if (status != errSecSuccess && status != errSecItemNotFound) {
        if (error) {
          *error = MPAutoFillKeychainError(status, @"The publication key could not be deleted.");
        }
        return NO;
      }
    }
    return YES;
  }
  if (error) {
    *error = MPAutoFillError(MPAutoFillErrorKeychainUnavailable, @"The data-protection Keychain is unavailable.", nil);
  }
  return NO;
}

+ (NSArray<NSString *> *)publicationIdentifiersFromKeyAttributes:(NSArray<NSDictionary *> *)keyAttributes
                                             activationAttributes:(NSArray<NSDictionary *> *)activationAttributes
                                              highWaterAttributes:(NSArray<NSDictionary *> *)highWaterAttributes
                                                            error:(NSError **)error {
  NSMutableSet<NSString *> *identifiers = [NSMutableSet set];
  NSArray<NSString *> *prefixes = @[@"dev.roszkowski.macpass.autofill.private.v1:",
                                    @"dev.roszkowski.macpass.autofill.public.v1:"];
  for (NSDictionary *item in keyAttributes) {
    NSData *tagData = [item isKindOfClass:NSDictionary.class] ? item[(__bridge id)kSecAttrApplicationTag] : nil;
    NSString *tag = [tagData isKindOfClass:NSData.class] ? [[NSString alloc] initWithData:tagData
        encoding:NSUTF8StringEncoding] : nil;
    NSString *publicationIdentifier = nil;
    for (NSString *prefix in prefixes) {
      if ([tag hasPrefix:prefix]) {
        publicationIdentifier = [tag substringFromIndex:prefix.length];
        break;
      }
    }
    if (!publicationIdentifier) continue;
    if (!MPAutoFillKeychainCanonicalUUID(publicationIdentifier) ||
        (![identifiers containsObject:publicationIdentifier] && identifiers.count >= MPAutoFillMaximumKeychainPublications)) {
      if (error) *error = MPAutoFillError(MPAutoFillErrorContextMismatch,
          @"The AutoFill Keychain namespace contains invalid publication state.", nil);
      return nil;
    }
    [identifiers addObject:publicationIdentifier];
  }
  for (NSArray<NSDictionary *> *attributes in @[activationAttributes, highWaterAttributes]) {
    for (NSDictionary *item in attributes) {
      NSString *publicationIdentifier = [item isKindOfClass:NSDictionary.class] ?
          item[(__bridge id)kSecAttrAccount] : nil;
      if (!MPAutoFillKeychainCanonicalUUID(publicationIdentifier) ||
          (![identifiers containsObject:publicationIdentifier] && identifiers.count >= MPAutoFillMaximumKeychainPublications)) {
        if (error) *error = MPAutoFillError(MPAutoFillErrorContextMismatch,
            @"The AutoFill Keychain namespace contains invalid publication state.", nil);
        return nil;
      }
      [identifiers addObject:publicationIdentifier];
    }
  }
  return [identifiers.allObjects sortedArrayUsingSelector:@selector(compare:)];
}

- (NSArray<NSDictionary *> *)attributesForQuery:(NSDictionary *)baseQuery error:(NSError **)error {
  NSMutableDictionary *query = [baseQuery mutableCopy];
  query[(__bridge id)kSecReturnAttributes] = @YES;
  query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitAll;
  LAContext *context = [[LAContext alloc] init];
  context.interactionNotAllowed = YES;
  query[(__bridge id)kSecUseAuthenticationContext] = context;
  CFTypeRef result = NULL;
  OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
  if (status == errSecItemNotFound) return @[];
  if (status != errSecSuccess) {
    if (error) *error = MPAutoFillKeychainError(status, @"AutoFill Keychain state could not be enumerated.");
    return nil;
  }
  id value = CFBridgingRelease(result);
  if ([value isKindOfClass:NSDictionary.class]) return @[value];
  if (![value isKindOfClass:NSArray.class]) {
    if (error) *error = MPAutoFillError(MPAutoFillErrorKeychainUnavailable,
        @"AutoFill Keychain enumeration returned an invalid type.", nil);
    return nil;
  }
  for (id item in value) {
    if (![item isKindOfClass:NSDictionary.class]) {
      if (error) *error = MPAutoFillError(MPAutoFillErrorKeychainUnavailable,
          @"AutoFill Keychain enumeration returned invalid attributes.", nil);
      return nil;
    }
  }
  return value;
}

- (NSArray<NSString *> *)publicationIdentifiersWithError:(NSError **)error {
  if (@available(macOS 10.15, *)) {
    NSDictionary *keyQuery = @{
      (__bridge id)kSecClass: (__bridge id)kSecClassKey,
      (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeRSA,
      (__bridge id)kSecAttrAccessGroup: self.accessGroup,
      (__bridge id)kSecAttrSynchronizable: @NO,
      (__bridge id)kSecUseDataProtectionKeychain: @YES,
    };
    NSArray *keyAttributes = [self attributesForQuery:keyQuery error:error];
    if (!keyAttributes) return nil;
    NSMutableArray<NSArray<NSDictionary *> *> *genericAttributes = [NSMutableArray array];
    for (NSString *service in @[MPAutoFillCurrentGenerationService, MPAutoFillGenerationHighWaterService]) {
      NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: service,
        (__bridge id)kSecAttrAccessGroup: self.accessGroup,
        (__bridge id)kSecAttrSynchronizable: @NO,
        (__bridge id)kSecUseDataProtectionKeychain: @YES,
      };
      NSArray *attributes = [self attributesForQuery:query error:error];
      if (!attributes) return nil;
      [genericAttributes addObject:attributes];
    }
    return [self.class publicationIdentifiersFromKeyAttributes:keyAttributes
        activationAttributes:genericAttributes[0] highWaterAttributes:genericAttributes[1] error:error];
  }
  if (error) *error = MPAutoFillError(MPAutoFillErrorKeychainUnavailable,
      @"The data-protection Keychain is unavailable.", nil);
  return nil;
}

- (NSDictionary *)currentGenerationQueryForPublicationIdentifier:(NSString *)publicationIdentifier {
  return [self generationQueryForPublicationIdentifier:publicationIdentifier service:MPAutoFillCurrentGenerationService];
}

- (NSDictionary *)generationHighWaterQueryForPublicationIdentifier:(NSString *)publicationIdentifier {
  return [self generationQueryForPublicationIdentifier:publicationIdentifier service:MPAutoFillGenerationHighWaterService];
}

- (NSDictionary *)generationQueryForPublicationIdentifier:(NSString *)publicationIdentifier service:(NSString *)service {
  if (@available(macOS 10.15, *)) {
    return @{
      (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
      (__bridge id)kSecAttrService: service,
      (__bridge id)kSecAttrAccount: publicationIdentifier,
      (__bridge id)kSecAttrAccessGroup: self.accessGroup,
      (__bridge id)kSecAttrSynchronizable: @NO,
      (__bridge id)kSecUseDataProtectionKeychain: @YES,
    };
  }
  return @{};
}

- (NSData *)dataForQuery:(NSDictionary *)baseQuery missingAllowed:(BOOL)missingAllowed error:(NSError **)error {
  NSMutableDictionary *query = [baseQuery mutableCopy];
  query[(__bridge id)kSecReturnData] = @YES;
  query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
  CFTypeRef result = NULL;
  OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
  if (status == errSecItemNotFound && missingAllowed) return nil;
  if (status != errSecSuccess) {
    if (error) *error = MPAutoFillKeychainError(status, @"The AutoFill generation state could not be read.");
    return nil;
  }
  if (!result || CFGetTypeID(result) != CFDataGetTypeID()) {
    if (result) CFRelease(result);
    if (error) *error = MPAutoFillError(MPAutoFillErrorKeychainUnavailable,
        @"The AutoFill generation state has an invalid type.", nil);
    return nil;
  }
  return CFBridgingRelease(result);
}

- (BOOL)setData:(NSData *)data forQuery:(NSDictionary *)query error:(NSError **)error {
  OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query,
                                  (__bridge CFDictionaryRef)@{(__bridge id)kSecValueData: data});
  if (status == errSecItemNotFound) {
    NSMutableDictionary *attributes = [query mutableCopy];
    attributes[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly;
    attributes[(__bridge id)kSecValueData] = data;
    status = SecItemAdd((__bridge CFDictionaryRef)attributes, NULL);
    if (status == errSecDuplicateItem) {
      status = SecItemUpdate((__bridge CFDictionaryRef)query,
                             (__bridge CFDictionaryRef)@{(__bridge id)kSecValueData: data});
    }
  }
  if (status == errSecSuccess) return YES;
  if (error) *error = MPAutoFillKeychainError(status, @"The AutoFill generation state could not be updated.");
  return NO;
}

+ (NSData *)activationDataForGenerationIdentifier:(NSString *)generationIdentifier error:(NSError **)error {
  if (!MPAutoFillKeychainCanonicalUUID(generationIdentifier)) {
    if (error) *error = MPAutoFillError(MPAutoFillErrorInvalidArgument,
        @"The generation identifier is invalid.", nil);
    return nil;
  }
  NSDictionary *activation = @{@"schema": @(MPAutoFillActivationSchemaVersion),
                                @"generation": generationIdentifier};
  return [NSPropertyListSerialization dataWithPropertyList:activation format:NSPropertyListBinaryFormat_v1_0
                                                   options:0 error:error];
}

+ (NSString *)generationIdentifierFromActivationData:(NSData *)activationData
                                        highWaterData:(NSData *)highWaterData
                                                error:(NSError **)error {
  NSString *legacy = [[NSString alloc] initWithData:activationData encoding:NSUTF8StringEncoding];
  if (MPAutoFillKeychainCanonicalUUID(legacy)) {
    if (!highWaterData) return legacy;
    if (error) *error = MPAutoFillError(MPAutoFillErrorContextMismatch,
        @"Legacy AutoFill generation state conflicts with its high-water marker.", nil);
    return nil;
  }
  NSPropertyListFormat format = NSPropertyListOpenStepFormat;
  NSDictionary *activation = [NSPropertyListSerialization propertyListWithData:activationData
      options:NSPropertyListImmutable format:&format error:NULL];
  NSSet *keys = [NSSet setWithArray:@[@"schema", @"generation"]];
  NSNumber *schema = [activation isKindOfClass:NSDictionary.class] ? activation[@"schema"] : nil;
  BOOL valid = [activation isKindOfClass:NSDictionary.class] && format == NSPropertyListBinaryFormat_v1_0 &&
      [keys isEqualToSet:[NSSet setWithArray:activation.allKeys]] &&
      schema && CFGetTypeID((__bridge CFTypeRef)schema) == CFNumberGetTypeID() &&
      !CFNumberIsFloatType((__bridge CFNumberRef)schema) &&
      schema.integerValue == MPAutoFillActivationSchemaVersion &&
      MPAutoFillKeychainCanonicalUUID(activation[@"generation"]);
  if (!valid || !highWaterData || ![activationData isEqualToData:highWaterData]) {
    if (error) *error = MPAutoFillError(MPAutoFillErrorContextMismatch,
        @"The AutoFill generation state is malformed or has been rolled back.", nil);
    return nil;
  }
  return activation[@"generation"];
}

- (NSString *)currentGenerationForPublicationIdentifier:(NSString *)publicationIdentifier error:(NSError **)error {
  if (!MPAutoFillKeychainCanonicalUUID(publicationIdentifier)) {
    if (error) {
      *error = MPAutoFillError(MPAutoFillErrorInvalidArgument, @"The publication identifier is invalid.", nil);
    }
    return nil;
  }
  if (@available(macOS 10.15, *)) {
    NSData *activationData = [self dataForQuery:[self currentGenerationQueryForPublicationIdentifier:publicationIdentifier]
                                  missingAllowed:NO error:error];
    if (!activationData) return nil;
    NSError *highWaterError = nil;
    NSData *highWaterData = [self dataForQuery:[self generationHighWaterQueryForPublicationIdentifier:publicationIdentifier]
                                 missingAllowed:YES error:&highWaterError];
    if (!highWaterData && highWaterError) {
      if (error) *error = highWaterError;
      return nil;
    }
    return [self.class generationIdentifierFromActivationData:activationData highWaterData:highWaterData error:error];
  }
  if (error) {
    *error = MPAutoFillError(MPAutoFillErrorKeychainUnavailable, @"The data-protection Keychain is unavailable.", nil);
  }
  return nil;
}

- (BOOL)setCurrentGeneration:(NSString *)generationIdentifier
     forPublicationIdentifier:(NSString *)publicationIdentifier
                        error:(NSError **)error {
  if (!MPAutoFillKeychainCanonicalUUID(publicationIdentifier) || !MPAutoFillKeychainCanonicalUUID(generationIdentifier)) {
    if (error) {
      *error = MPAutoFillError(MPAutoFillErrorInvalidArgument, @"The publication or generation identifier is invalid.", nil);
    }
    return NO;
  }
  if (@available(macOS 10.15, *)) {
    NSData *data = [self.class activationDataForGenerationIdentifier:generationIdentifier error:error];
    if (!data) return NO;
    if (![self setData:data forQuery:[self generationHighWaterQueryForPublicationIdentifier:publicationIdentifier]
                       error:error]) return NO;
    return [self setData:data forQuery:[self currentGenerationQueryForPublicationIdentifier:publicationIdentifier]
                   error:error];
  }
  if (error) {
    *error = MPAutoFillError(MPAutoFillErrorKeychainUnavailable, @"The data-protection Keychain is unavailable.", nil);
  }
  return NO;
}

- (BOOL)deleteCurrentGenerationForPublicationIdentifier:(NSString *)publicationIdentifier error:(NSError **)error {
  if (!MPAutoFillKeychainCanonicalUUID(publicationIdentifier)) {
    if (error) {
      *error = MPAutoFillError(MPAutoFillErrorInvalidArgument, @"The publication identifier is invalid.", nil);
    }
    return NO;
  }
  if (@available(macOS 10.15, *)) {
    for (NSDictionary *query in @[[self generationHighWaterQueryForPublicationIdentifier:publicationIdentifier],
                                  [self currentGenerationQueryForPublicationIdentifier:publicationIdentifier]]) {
      OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
      if (status != errSecSuccess && status != errSecItemNotFound) {
        if (error) *error = MPAutoFillKeychainError(status, @"The current AutoFill generation could not be deleted.");
        return NO;
      }
    }
    return YES;
  }
  if (error) {
    *error = MPAutoFillError(MPAutoFillErrorKeychainUnavailable, @"The data-protection Keychain is unavailable.", nil);
  }
  return NO;
}

@end
