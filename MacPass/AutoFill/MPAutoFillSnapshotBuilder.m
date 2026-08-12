#import "MPAutoFillSnapshotBuilder.h"

#import <KeePassKit/KeePassKit.h>

#import "MPAutoFillCredentialRecord.h"
#import "MPAutoFillServiceMatcher.h"

MPAutoFillEligibilityReason const MPAutoFillEligibilityReasonHistory = @"history";
MPAutoFillEligibilityReason const MPAutoFillEligibilityReasonTrash = @"trash";
MPAutoFillEligibilityReason const MPAutoFillEligibilityReasonTemplate = @"template";
MPAutoFillEligibilityReason const MPAutoFillEligibilityReasonMeta = @"meta";
MPAutoFillEligibilityReason const MPAutoFillEligibilityReasonExpired = @"expired";
MPAutoFillEligibilityReason const MPAutoFillEligibilityReasonEmptyPassword = @"empty-password";
MPAutoFillEligibilityReason const MPAutoFillEligibilityReasonMalformedURL = @"malformed-url";
MPAutoFillEligibilityReason const MPAutoFillEligibilityReasonUnsupportedPlaceholder = @"unsupported-placeholder";
MPAutoFillEligibilityReason const MPAutoFillEligibilityReasonUnresolvedReference = @"unresolved-reference";
MPAutoFillEligibilityReason const MPAutoFillEligibilityReasonInvalidRecord = @"invalid-record";

@interface MPAutoFillSnapshotBuildResult ()
@property(nonatomic, readwrite, copy) NSArray<MPAutoFillCredentialRecord *> *records;
@property(nonatomic, readwrite, copy) NSDictionary<NSString *, MPAutoFillEligibilityReason> *excludedEntryReasons;
@end

@implementation MPAutoFillSnapshotBuildResult
@end

@implementation MPAutoFillSnapshotBuilder

+ (NSRegularExpression *)commandExpression {
  static NSRegularExpression *expression;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    expression = [NSRegularExpression regularExpressionWithPattern:@"\\{[^{}]*\\}" options:0 error:NULL];
  });
  return expression;
}

+ (NSRegularExpression *)UUIDReferenceExpression {
  static NSRegularExpression *expression;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    expression = [NSRegularExpression
        regularExpressionWithPattern:@"\\{REF:([TUPAN])@I:([0-9A-F]{32}|[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12})\\}"
        options:NSRegularExpressionCaseInsensitive error:NULL];
  });
  return expression;
}

+ (NSString *)literalValue:(NSString *)value
                   forEntry:(KPKEntry *)entry
                     atDate:(NSDate *)date
                    visited:(NSMutableSet<NSUUID *> *)visited
                     reason:(MPAutoFillEligibilityReason _Nullable *)reason {
  NSArray<NSTextCheckingResult *> *commands = [[self commandExpression]
      matchesInString:value options:0 range:NSMakeRange(0, value.length)];
  for (NSTextCheckingResult *command in commands) {
    NSRange tokenRange = command.range;
    NSTextCheckingResult *reference = [[self UUIDReferenceExpression]
        firstMatchInString:value options:0 range:tokenRange];
    if (!reference || !NSEqualRanges(reference.range, tokenRange)) {
      if (reason) {
        *reason = MPAutoFillEligibilityReasonUnsupportedPlaceholder;
      }
      return nil;
    }
  }
  if ([value rangeOfString:@"{REF:" options:NSCaseInsensitiveSearch].location != NSNotFound && commands.count == 0) {
    if (reason) {
      *reason = MPAutoFillEligibilityReasonUnresolvedReference;
    }
    return nil;
  }

  NSMutableString *literal = [value mutableCopy];
  for (NSTextCheckingResult *command in commands.reverseObjectEnumerator) {
    NSTextCheckingResult *reference = [[self UUIDReferenceExpression]
        firstMatchInString:value options:0 range:command.range];
    NSString *uuidString = [value substringWithRange:[reference rangeAtIndex:2]];
    if (uuidString.length == 32) {
      uuidString = [NSString stringWithFormat:@"%@-%@-%@-%@-%@",
          [uuidString substringWithRange:NSMakeRange(0, 8)], [uuidString substringWithRange:NSMakeRange(8, 4)],
          [uuidString substringWithRange:NSMakeRange(12, 4)], [uuidString substringWithRange:NSMakeRange(16, 4)],
          [uuidString substringWithRange:NSMakeRange(20, 12)]];
    }
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:uuidString];
    KPKEntry *referencedEntry = [entry.tree.root entryForUUID:uuid];
    if (!referencedEntry || [visited containsObject:uuid] || [self structuralReasonForEntry:referencedEntry atDate:date]) {
      if (reason) {
        *reason = MPAutoFillEligibilityReasonUnresolvedReference;
      }
      return nil;
    }
    NSDictionary<NSString *, NSString *> *fieldKeys = @{
      @"T": kKPKTitleKey, @"U": kKPKUsernameKey, @"P": kKPKPasswordKey,
      @"A": kKPKURLKey, @"N": kKPKNotesKey,
    };
    NSString *field = [[value substringWithRange:[reference rangeAtIndex:1]] uppercaseString];
    [visited addObject:uuid];
    NSString *replacement = [self literalValue:[referencedEntry valueForAttributeWithKey:fieldKeys[field]]
                                        forEntry:referencedEntry atDate:date visited:visited reason:reason];
    [visited removeObject:uuid];
    if (!replacement) {
      return nil;
    }
    [literal replaceCharactersInRange:command.range withString:replacement];
  }
  if ([[self commandExpression] firstMatchInString:literal options:0 range:NSMakeRange(0, literal.length)] ||
      [literal rangeOfString:@"{REF:" options:NSCaseInsensitiveSearch].location != NSNotFound) {
    if (reason) {
      *reason = MPAutoFillEligibilityReasonUnsupportedPlaceholder;
    }
    return nil;
  }
  return [literal copy];
}

+ (MPAutoFillEligibilityReason)structuralReasonForEntry:(KPKEntry *)entry atDate:(NSDate *)date {
  if (entry.isHistory) {
    return MPAutoFillEligibilityReasonHistory;
  }
  if (entry.isTrashed) {
    return MPAutoFillEligibilityReasonTrash;
  }
  if (entry.isUserTemplate) {
    return MPAutoFillEligibilityReasonTemplate;
  }
  if (entry.isMeta) {
    return MPAutoFillEligibilityReasonMeta;
  }
  if (entry.timeInfo.expires && entry.timeInfo.expirationDate &&
      [entry.timeInfo.expirationDate compare:date] != NSOrderedDescending) {
    return MPAutoFillEligibilityReasonExpired;
  }
  return nil;
}

+ (MPAutoFillSnapshotBuildResult *)buildRecordsFromTree:(KPKTree *)tree atDate:(NSDate *)date {
  NSMutableArray<MPAutoFillCredentialRecord *> *records = [NSMutableArray array];
  NSMutableDictionary<NSString *, MPAutoFillEligibilityReason> *excluded = [NSMutableDictionary dictionary];
  NSInteger rank = 0;
  for (KPKEntry *entry in tree.allEntries) {
    NSString *entryIdentifier = entry.uuid.UUIDString.lowercaseString;
    MPAutoFillEligibilityReason reason = [self structuralReasonForEntry:entry atDate:date];
    if (!reason) {
      NSMutableSet<NSUUID *> *visited = [NSMutableSet setWithObject:entry.uuid];
      NSString *title = [self literalValue:entry.title forEntry:entry atDate:date visited:visited reason:&reason];
      NSString *username = reason ? nil : [self literalValue:entry.username forEntry:entry atDate:date visited:visited reason:&reason];
      NSString *password = reason ? nil : [self literalValue:entry.password forEntry:entry atDate:date visited:visited reason:&reason];
      NSString *service = reason ? nil : [self literalValue:entry.url forEntry:entry atDate:date visited:visited reason:&reason];
      if (!reason && password.length == 0) {
        reason = MPAutoFillEligibilityReasonEmptyPassword;
      }
      NSString *normalizedService = reason ? nil : [MPAutoFillServiceMatcher normalizedCredentialServiceIdentifier:service];
      if (!reason && !normalizedService) {
        reason = MPAutoFillEligibilityReasonMalformedURL;
      }
      if (!reason) {
        NSError *recordError = nil;
        int64_t modificationTime = (int64_t)entry.timeInfo.modificationDate.timeIntervalSince1970;
        MPAutoFillCredentialRecord *record = [[MPAutoFillCredentialRecord alloc]
            initWithEntryIdentifier:entryIdentifier title:title username:username password:password
            serviceIdentifiers:@[normalizedService] modificationTime:modificationTime rank:rank++ error:&recordError];
        if (record) {
          [records addObject:record];
        } else {
          reason = MPAutoFillEligibilityReasonInvalidRecord;
        }
      }
    }
    if (reason) {
      excluded[entryIdentifier] = reason;
    }
  }
  MPAutoFillSnapshotBuildResult *result = [[MPAutoFillSnapshotBuildResult alloc] init];
  result.records = records;
  result.excludedEntryReasons = excluded;
  return result;
}

@end
