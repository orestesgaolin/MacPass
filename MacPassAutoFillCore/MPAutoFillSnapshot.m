#import "MPAutoFillSnapshot.h"

#import "MPAutoFillCredentialRecord.h"
#import "MPAutoFillErrors.h"

const NSInteger MPAutoFillSnapshotSchemaVersion = 1;
const NSUInteger MPAutoFillMaximumSnapshotBytes = 4 * 1024 * 1024;
const NSUInteger MPAutoFillMaximumRecordCount = 5000;

static BOOL MPAutoFillSnapshotUUID(NSString *value) {
  if (![value isKindOfClass:NSString.class] || value.length != 36 || ![value canBeConvertedToEncoding:NSASCIIStringEncoding]) {
    return NO;
  }
  NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:value];
  return uuid && [uuid.UUIDString.lowercaseString isEqualToString:value];
}

static BOOL MPAutoFillConstantTimeDataEqual(NSData *left, NSData *right) {
  if (left.length != right.length) {
    return NO;
  }
  const uint8_t *leftBytes = left.bytes;
  const uint8_t *rightBytes = right.bytes;
  uint8_t difference = 0;
  for (NSUInteger index = 0; index < left.length; index++) {
    difference |= leftBytes[index] ^ rightBytes[index];
  }
  return difference == 0;
}

@interface MPAutoFillSnapshot ()
@property(nonatomic, readwrite) NSInteger schemaVersion;
@property(nonatomic, readwrite, copy) NSString *publicationIdentifier;
@property(nonatomic, readwrite, copy) NSString *generationIdentifier;
@property(nonatomic, readwrite, copy) NSData *indexDigest;
@property(nonatomic, readwrite, copy) NSArray<MPAutoFillCredentialRecord *> *records;
@end

@implementation MPAutoFillSnapshot

- (instancetype)initWithPublicationIdentifier:(NSString *)publicationIdentifier
                           generationIdentifier:(NSString *)generationIdentifier
                                    indexDigest:(NSData *)indexDigest
                                        records:(NSArray<MPAutoFillCredentialRecord *> *)records
                                          error:(NSError **)error {
  if (!MPAutoFillSnapshotUUID(publicationIdentifier) || !MPAutoFillSnapshotUUID(generationIdentifier) ||
      ![indexDigest isKindOfClass:NSData.class] || indexDigest.length != 32 ||
      ![records isKindOfClass:NSArray.class] || records.count > MPAutoFillMaximumRecordCount) {
    if (error) {
      *error = MPAutoFillError(MPAutoFillErrorInvalidArgument, @"Invalid snapshot metadata.", nil);
    }
    return nil;
  }
  NSMutableSet<NSString *> *entryIdentifiers = [NSMutableSet setWithCapacity:records.count];
  for (id record in records) {
    if (![record isKindOfClass:MPAutoFillCredentialRecord.class] ||
        [entryIdentifiers containsObject:[record entryIdentifier]]) {
      if (error) {
        *error = MPAutoFillError(MPAutoFillErrorInvalidArgument, @"Snapshot records are invalid.", nil);
      }
      return nil;
    }
    [entryIdentifiers addObject:[record entryIdentifier]];
  }
  self = [super init];
  if (self) {
    _schemaVersion = MPAutoFillSnapshotSchemaVersion;
    _publicationIdentifier = [publicationIdentifier copy];
    _generationIdentifier = [generationIdentifier copy];
    _indexDigest = [indexDigest copy];
    _records = [records copy];
  }
  return self;
}

- (NSData *)serializedDataWithError:(NSError **)error {
  NSMutableArray *recordPropertyLists = [NSMutableArray arrayWithCapacity:self.records.count];
  for (MPAutoFillCredentialRecord *record in self.records) {
    [recordPropertyLists addObject:record.propertyListRepresentation];
  }
  NSDictionary *root = @{
    @"schema": @(self.schemaVersion),
    @"publication": self.publicationIdentifier,
    @"generation": self.generationIdentifier,
    @"indexDigest": self.indexDigest,
    @"records": recordPropertyLists,
  };
  NSData *data = [NSPropertyListSerialization dataWithPropertyList:root
                                                            format:NSPropertyListBinaryFormat_v1_0
                                                           options:0
                                                             error:error];
  if (data.length > MPAutoFillMaximumSnapshotBytes) {
    if (error) {
      *error = MPAutoFillError(MPAutoFillErrorLimitExceeded, @"Snapshot exceeds the maximum size.", nil);
    }
    return nil;
  }
  return data;
}

+ (instancetype)snapshotWithSerializedData:(NSData *)data
              expectedPublicationIdentifier:(NSString *)publicationIdentifier
               expectedGenerationIdentifier:(NSString *)generationIdentifier
                        expectedIndexDigest:(NSData *)indexDigest
                                      error:(NSError **)error {
  if (![data isKindOfClass:NSData.class] || data.length == 0 || data.length > MPAutoFillMaximumSnapshotBytes ||
      !MPAutoFillSnapshotUUID(publicationIdentifier) || !MPAutoFillSnapshotUUID(generationIdentifier) ||
      ![indexDigest isKindOfClass:NSData.class] || indexDigest.length != 32) {
    if (error) {
      *error = MPAutoFillError(MPAutoFillErrorInvalidArgument, @"Snapshot data or expected metadata is invalid.", nil);
    }
    return nil;
  }
  NSPropertyListFormat format = NSPropertyListOpenStepFormat;
  NSError *parseError = nil;
  id propertyList = [NSPropertyListSerialization propertyListWithData:data
                                                              options:NSPropertyListImmutable
                                                               format:&format
                                                                error:&parseError];
  if (![propertyList isKindOfClass:NSDictionary.class] || format != NSPropertyListBinaryFormat_v1_0) {
    if (error) {
      *error = MPAutoFillError(MPAutoFillErrorMalformedSnapshot, @"Snapshot is not a binary property list.", parseError);
    }
    return nil;
  }
  NSDictionary *root = propertyList;
  NSSet *expectedKeys = [NSSet setWithArray:@[@"schema", @"publication", @"generation", @"indexDigest", @"records"]];
  id schema = root[@"schema"];
  CFTypeRef schemaObject = (__bridge CFTypeRef)schema;
  if (![expectedKeys isEqualToSet:[NSSet setWithArray:root.allKeys]] ||
      !schema || CFGetTypeID(schemaObject) != CFNumberGetTypeID() ||
      CFNumberIsFloatType((__bridge CFNumberRef)schema)) {
    if (error) {
      *error = MPAutoFillError(MPAutoFillErrorMalformedSnapshot, @"Snapshot schema is malformed.", nil);
    }
    return nil;
  }
  if ([schema integerValue] != MPAutoFillSnapshotSchemaVersion) {
    if (error) {
      *error = MPAutoFillError(MPAutoFillErrorUnsupportedSchema, @"Snapshot schema is unsupported.", nil);
    }
    return nil;
  }
  if (![root[@"records"] isKindOfClass:NSArray.class] || [root[@"records"] count] > MPAutoFillMaximumRecordCount) {
    if (error) {
      *error = MPAutoFillError(MPAutoFillErrorLimitExceeded, @"Snapshot record count is invalid.", nil);
    }
    return nil;
  }
  NSMutableArray *records = [NSMutableArray arrayWithCapacity:[root[@"records"] count]];
  for (id recordPropertyList in root[@"records"]) {
    MPAutoFillCredentialRecord *record = [MPAutoFillCredentialRecord recordWithPropertyList:recordPropertyList error:error];
    if (!record) {
      return nil;
    }
    [records addObject:record];
  }
  MPAutoFillSnapshot *snapshot = [[self alloc] initWithPublicationIdentifier:root[@"publication"]
                                                       generationIdentifier:root[@"generation"]
                                                                indexDigest:root[@"indexDigest"]
                                                                    records:records
                                                                      error:error];
  if (!snapshot) {
    return nil;
  }
  if (![snapshot.publicationIdentifier isEqualToString:publicationIdentifier] ||
      ![snapshot.generationIdentifier isEqualToString:generationIdentifier] ||
      !MPAutoFillConstantTimeDataEqual(snapshot.indexDigest, indexDigest)) {
    if (error) {
      *error = MPAutoFillError(MPAutoFillErrorContextMismatch, @"Snapshot context does not match the active generation.", nil);
    }
    return nil;
  }
  return snapshot;
}

@end
