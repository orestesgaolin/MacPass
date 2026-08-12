#import "MPAutoFillCredentialRecord.h"

#import "MPAutoFillErrors.h"

const NSUInteger MPAutoFillMaximumTitleBytes = 1024;
const NSUInteger MPAutoFillMaximumUsernameBytes = 4096;
const NSUInteger MPAutoFillMaximumPasswordBytes = 65536;
const NSUInteger MPAutoFillMaximumServiceIdentifierBytes = 2048;
const NSUInteger MPAutoFillMaximumServicesPerRecord = 32;

static BOOL MPAutoFillCanonicalUUID(NSString *value) {
  if (![value isKindOfClass:NSString.class] || value.length != 36 || ![value canBeConvertedToEncoding:NSASCIIStringEncoding]) {
    return NO;
  }
  NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:value];
  return uuid && [uuid.UUIDString.lowercaseString isEqualToString:value];
}

static BOOL MPAutoFillStringWithinLimit(id value, NSUInteger limit, BOOL allowEmpty) {
  if (![value isKindOfClass:NSString.class] || (!allowEmpty && [value length] == 0)) {
    return NO;
  }
  NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
  return data && data.length <= limit;
}

static BOOL MPAutoFillIntegerNumber(id value) {
  if (!value) {
    return NO;
  }
  CFTypeRef object = (__bridge CFTypeRef)value;
  return CFGetTypeID(object) == CFNumberGetTypeID() && !CFNumberIsFloatType((__bridge CFNumberRef)value);
}

@interface MPAutoFillCredentialRecord ()
@property(nonatomic, readwrite, copy) NSString *entryIdentifier;
@property(nonatomic, readwrite, copy) NSString *title;
@property(nonatomic, readwrite, copy) NSString *username;
@property(nonatomic, readwrite, copy) NSString *password;
@property(nonatomic, readwrite, copy) NSArray<NSString *> *serviceIdentifiers;
@property(nonatomic, readwrite) int64_t modificationTime;
@property(nonatomic, readwrite) int64_t rank;
@end

@implementation MPAutoFillCredentialRecord

- (instancetype)initWithEntryIdentifier:(NSString *)entryIdentifier
                                    title:(NSString *)title
                                 username:(NSString *)username
                                 password:(NSString *)password
                       serviceIdentifiers:(NSArray<NSString *> *)serviceIdentifiers
                         modificationTime:(int64_t)modificationTime
                                     rank:(int64_t)rank
                                    error:(NSError **)error {
  if (!MPAutoFillCanonicalUUID(entryIdentifier) ||
      !MPAutoFillStringWithinLimit(title, MPAutoFillMaximumTitleBytes, YES) ||
      !MPAutoFillStringWithinLimit(username, MPAutoFillMaximumUsernameBytes, YES) ||
      !MPAutoFillStringWithinLimit(password, MPAutoFillMaximumPasswordBytes, NO) ||
      ![serviceIdentifiers isKindOfClass:NSArray.class] || serviceIdentifiers.count == 0 ||
      serviceIdentifiers.count > MPAutoFillMaximumServicesPerRecord) {
    if (error) {
      *error = MPAutoFillError(MPAutoFillErrorInvalidArgument, @"Invalid credential record.", nil);
    }
    return nil;
  }

  NSMutableSet<NSString *> *uniqueServices = [NSMutableSet setWithCapacity:serviceIdentifiers.count];
  NSMutableArray<NSString *> *immutableServices = [NSMutableArray arrayWithCapacity:serviceIdentifiers.count];
  for (id service in serviceIdentifiers) {
    if (!MPAutoFillStringWithinLimit(service, MPAutoFillMaximumServiceIdentifierBytes, NO) ||
        [uniqueServices containsObject:service]) {
      if (error) {
        *error = MPAutoFillError(MPAutoFillErrorInvalidArgument, @"Invalid credential service identifier.", nil);
      }
      return nil;
    }
    [uniqueServices addObject:service];
    [immutableServices addObject:[service copy]];
  }

  self = [super init];
  if (self) {
    _entryIdentifier = [entryIdentifier copy];
    _title = [title copy];
    _username = [username copy];
    _password = [password copy];
    _serviceIdentifiers = [immutableServices copy];
    _modificationTime = modificationTime;
    _rank = rank;
  }
  return self;
}

- (NSDictionary<NSString *, id> *)propertyListRepresentation {
  return @{
    @"entry": self.entryIdentifier,
    @"title": self.title,
    @"username": self.username,
    @"password": self.password,
    @"services": self.serviceIdentifiers,
    @"modified": @(self.modificationTime),
    @"rank": @(self.rank),
  };
}

+ (instancetype)recordWithPropertyList:(id)propertyList error:(NSError **)error {
  if (![propertyList isKindOfClass:NSDictionary.class]) {
    if (error) {
      *error = MPAutoFillError(MPAutoFillErrorMalformedSnapshot, @"Credential record is not a dictionary.", nil);
    }
    return nil;
  }
  NSDictionary *dictionary = propertyList;
  NSSet *expectedKeys = [NSSet setWithArray:@[@"entry", @"title", @"username", @"password", @"services", @"modified", @"rank"]];
  if (![expectedKeys isEqualToSet:[NSSet setWithArray:dictionary.allKeys]] ||
      !MPAutoFillIntegerNumber(dictionary[@"modified"]) || !MPAutoFillIntegerNumber(dictionary[@"rank"])) {
    if (error) {
      *error = MPAutoFillError(MPAutoFillErrorMalformedSnapshot, @"Credential record schema is invalid.", nil);
    }
    return nil;
  }
  return [[self alloc] initWithEntryIdentifier:dictionary[@"entry"]
                                         title:dictionary[@"title"]
                                      username:dictionary[@"username"]
                                      password:dictionary[@"password"]
                            serviceIdentifiers:dictionary[@"services"]
                              modificationTime:[dictionary[@"modified"] longLongValue]
                                          rank:[dictionary[@"rank"] longLongValue]
                                         error:error];
}

@end
