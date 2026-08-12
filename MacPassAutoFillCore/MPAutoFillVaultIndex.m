#import "MPAutoFillVaultIndex.h"

#import "MPAutoFillCredentialRecord.h"
#import "MPAutoFillErrors.h"
#import "MPAutoFillSnapshot.h"

const NSInteger MPAutoFillVaultIndexSchemaVersion = 1;
const NSUInteger MPAutoFillMaximumVaultIndexBytes = 4 * 1024 * 1024;

static BOOL MPAutoFillIndexUUID(NSString *value) {
  if (![value isKindOfClass:NSString.class] || value.length != 36 ||
      ![value canBeConvertedToEncoding:NSASCIIStringEncoding]) {
    return NO;
  }
  NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:value];
  return uuid && [uuid.UUIDString.lowercaseString isEqualToString:value];
}

static BOOL MPAutoFillIndexString(NSString *value, NSUInteger maximumBytes, BOOL allowEmpty) {
  return [value isKindOfClass:NSString.class] && (allowEmpty || value.length > 0) &&
      [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= maximumBytes;
}

static BOOL MPAutoFillIndexInteger(id value) {
  return value && CFGetTypeID((__bridge CFTypeRef)value) == CFNumberGetTypeID() &&
      !CFNumberIsFloatType((__bridge CFNumberRef)value);
}

@interface MPAutoFillVaultIndexRecord ()
@property(nonatomic, readwrite, copy) NSString *entryIdentifier;
@property(nonatomic, readwrite, copy) NSString *title;
@property(nonatomic, readwrite, copy) NSString *username;
@property(nonatomic, readwrite, copy) NSArray<NSString *> *serviceIdentifiers;
@property(nonatomic, readwrite) int64_t modificationTime;
@property(nonatomic, readwrite) int64_t rank;
@end

@implementation MPAutoFillVaultIndexRecord

+ (instancetype)recordWithCredentialRecord:(MPAutoFillCredentialRecord *)record {
  if (![record isKindOfClass:MPAutoFillCredentialRecord.class]) return nil;
  MPAutoFillVaultIndexRecord *indexRecord = [[self alloc] init];
  indexRecord.entryIdentifier = record.entryIdentifier;
  indexRecord.title = record.title;
  indexRecord.username = record.username;
  indexRecord.serviceIdentifiers = record.serviceIdentifiers;
  indexRecord.modificationTime = record.modificationTime;
  indexRecord.rank = record.rank;
  return indexRecord;
}

- (NSDictionary<NSString *, id> *)propertyListRepresentation {
  return @{
    @"entry": self.entryIdentifier,
    @"title": self.title,
    @"username": self.username,
    @"services": self.serviceIdentifiers,
    @"modified": @(self.modificationTime),
    @"rank": @(self.rank),
  };
}

+ (instancetype)recordWithPropertyList:(id)propertyList error:(NSError **)error {
  if (![propertyList isKindOfClass:NSDictionary.class]) {
    if (error) *error = MPAutoFillError(MPAutoFillErrorMalformedSnapshot, @"Index record is malformed.", nil);
    return nil;
  }
  NSDictionary *dictionary = propertyList;
  NSSet *keys = [NSSet setWithArray:@[@"entry", @"title", @"username", @"services", @"modified", @"rank"]];
  NSArray *services = dictionary[@"services"];
  BOOL valid = [keys isEqualToSet:[NSSet setWithArray:dictionary.allKeys]] &&
      MPAutoFillIndexUUID(dictionary[@"entry"]) &&
      MPAutoFillIndexString(dictionary[@"title"], MPAutoFillMaximumTitleBytes, YES) &&
      MPAutoFillIndexString(dictionary[@"username"], MPAutoFillMaximumUsernameBytes, YES) &&
      [services isKindOfClass:NSArray.class] && services.count > 0 &&
      services.count <= MPAutoFillMaximumServicesPerRecord &&
      MPAutoFillIndexInteger(dictionary[@"modified"]) && MPAutoFillIndexInteger(dictionary[@"rank"]);
  if (![services isKindOfClass:NSArray.class]) {
    if (error) *error = MPAutoFillError(MPAutoFillErrorMalformedSnapshot, @"Index record services are malformed.", nil);
    return nil;
  }
  NSMutableSet *uniqueServices = [NSMutableSet set];
  for (id service in services) {
    valid = valid && MPAutoFillIndexString(service, MPAutoFillMaximumServiceIdentifierBytes, NO) &&
        ![uniqueServices containsObject:service];
    if ([service isKindOfClass:NSString.class]) [uniqueServices addObject:service];
  }
  if (!valid) {
    if (error) *error = MPAutoFillError(MPAutoFillErrorMalformedSnapshot, @"Index record fields are invalid.", nil);
    return nil;
  }
  MPAutoFillVaultIndexRecord *record = [[self alloc] init];
  record.entryIdentifier = dictionary[@"entry"];
  record.title = dictionary[@"title"];
  record.username = dictionary[@"username"];
  record.serviceIdentifiers = [services copy];
  record.modificationTime = [dictionary[@"modified"] longLongValue];
  record.rank = [dictionary[@"rank"] longLongValue];
  return record;
}

@end

@interface MPAutoFillVaultIndex ()
@property(nonatomic, readwrite) NSInteger schemaVersion;
@property(nonatomic, readwrite, copy) NSString *publicationIdentifier;
@property(nonatomic, readwrite, copy) NSString *generationIdentifier;
@property(nonatomic, readwrite, copy) NSArray<MPAutoFillVaultIndexRecord *> *records;
@end

@implementation MPAutoFillVaultIndex

- (instancetype)initWithPublicationIdentifier:(NSString *)publicationIdentifier
                          generationIdentifier:(NSString *)generationIdentifier
                                       records:(NSArray<MPAutoFillVaultIndexRecord *> *)records
                                         error:(NSError **)error {
  if (!MPAutoFillIndexUUID(publicationIdentifier) || !MPAutoFillIndexUUID(generationIdentifier) ||
      ![records isKindOfClass:NSArray.class] || records.count > MPAutoFillMaximumRecordCount) {
    if (error) *error = MPAutoFillError(MPAutoFillErrorInvalidArgument, @"Index metadata is invalid.", nil);
    return nil;
  }
  NSMutableSet *entries = [NSMutableSet set];
  for (id record in records) {
    if (![record isKindOfClass:MPAutoFillVaultIndexRecord.class] ||
        !MPAutoFillIndexUUID([record entryIdentifier]) ||
        !MPAutoFillIndexString([record title], MPAutoFillMaximumTitleBytes, YES) ||
        !MPAutoFillIndexString([record username], MPAutoFillMaximumUsernameBytes, YES) ||
        ![[record serviceIdentifiers] isKindOfClass:NSArray.class] || [record serviceIdentifiers].count == 0 ||
        [entries containsObject:[record entryIdentifier]]) {
      if (error) *error = MPAutoFillError(MPAutoFillErrorInvalidArgument, @"Index records are invalid.", nil);
      return nil;
    }
    [entries addObject:[record entryIdentifier]];
  }
  self = [super init];
  if (self) {
    _schemaVersion = MPAutoFillVaultIndexSchemaVersion;
    _publicationIdentifier = [publicationIdentifier copy];
    _generationIdentifier = [generationIdentifier copy];
    _records = [records copy];
  }
  return self;
}

- (NSData *)serializedDataWithError:(NSError **)error {
  NSMutableArray *records = [NSMutableArray arrayWithCapacity:self.records.count];
  for (MPAutoFillVaultIndexRecord *record in self.records) [records addObject:record.propertyListRepresentation];
  NSDictionary *root = @{
    @"schema": @(self.schemaVersion), @"publication": self.publicationIdentifier,
    @"generation": self.generationIdentifier, @"records": records,
  };
  NSData *data = [NSPropertyListSerialization dataWithPropertyList:root format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
  if (data.length == 0 || data.length > MPAutoFillMaximumVaultIndexBytes) {
    if (error) *error = MPAutoFillError(MPAutoFillErrorLimitExceeded, @"Index exceeds the maximum size.", nil);
    return nil;
  }
  return data;
}

+ (instancetype)indexWithSerializedData:(NSData *)data
           expectedPublicationIdentifier:(NSString *)publicationIdentifier
            expectedGenerationIdentifier:(NSString *)generationIdentifier
                                   error:(NSError **)error {
  if (![data isKindOfClass:NSData.class] || data.length == 0 || data.length > MPAutoFillMaximumVaultIndexBytes ||
      !MPAutoFillIndexUUID(publicationIdentifier) || !MPAutoFillIndexUUID(generationIdentifier)) {
    if (error) *error = MPAutoFillError(MPAutoFillErrorInvalidArgument, @"Index data or context is invalid.", nil);
    return nil;
  }
  NSPropertyListFormat format = NSPropertyListOpenStepFormat;
  NSError *parseError = nil;
  id propertyList = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:&format error:&parseError];
  if (![propertyList isKindOfClass:NSDictionary.class] || format != NSPropertyListBinaryFormat_v1_0) {
    if (error) *error = MPAutoFillError(MPAutoFillErrorMalformedSnapshot, @"Index is not a binary property list.", parseError);
    return nil;
  }
  NSDictionary *root = propertyList;
  NSSet *keys = [NSSet setWithArray:@[@"schema", @"publication", @"generation", @"records"]];
  if (![keys isEqualToSet:[NSSet setWithArray:root.allKeys]] || !MPAutoFillIndexInteger(root[@"schema"]) ||
      ![root[@"records"] isKindOfClass:NSArray.class] || [root[@"records"] count] > MPAutoFillMaximumRecordCount) {
    if (error) *error = MPAutoFillError(MPAutoFillErrorMalformedSnapshot, @"Index schema is malformed.", nil);
    return nil;
  }
  if ([root[@"schema"] integerValue] != MPAutoFillVaultIndexSchemaVersion) {
    if (error) *error = MPAutoFillError(MPAutoFillErrorUnsupportedSchema, @"Index schema is unsupported.", nil);
    return nil;
  }
  NSMutableArray *records = [NSMutableArray array];
  for (id propertyListRecord in root[@"records"]) {
    MPAutoFillVaultIndexRecord *record = [MPAutoFillVaultIndexRecord recordWithPropertyList:propertyListRecord error:error];
    if (!record) return nil;
    [records addObject:record];
  }
  MPAutoFillVaultIndex *index = [[self alloc] initWithPublicationIdentifier:root[@"publication"]
                                                      generationIdentifier:root[@"generation"] records:records error:error];
  if (!index) return nil;
  if (![index.publicationIdentifier isEqualToString:publicationIdentifier] ||
      ![index.generationIdentifier isEqualToString:generationIdentifier]) {
    if (error) *error = MPAutoFillError(MPAutoFillErrorContextMismatch, @"Index context does not match the generation.", nil);
    return nil;
  }
  return index;
}

@end
