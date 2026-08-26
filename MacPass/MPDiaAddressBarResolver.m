//
//  MPDiaAddressBarResolver.m
//  MacPass
//

#import "MPDiaAddressBarResolver.h"

#import <ApplicationServices/ApplicationServices.h>

static NSString *const MPDiaBundleIdentifier = @"company.thebrowser.dia";
static NSUInteger const MPDiaAccessibilityTraversalLimit = 600;
static NSUInteger const MPDiaAccessibilityDepthLimit = 16;

static id _Nullable MPCopyAccessibilityAttribute(AXUIElementRef element, CFStringRef attribute) {
  CFTypeRef value = NULL;
  AXError error = AXUIElementCopyAttributeValue(element, attribute, &value);
  return error == kAXErrorSuccess && value ? CFBridgingRelease(value) : nil;
}

static NSString *MPAccessibilityString(NSDictionary<NSString *, id> *attributes, CFStringRef attribute) {
  id value = attributes[(__bridge NSString *)attribute];
  return [value isKindOfClass:NSString.class] ? value : @"";
}

static BOOL MPStringContainsAnyToken(NSString *string, NSArray<NSString *> *tokens) {
  for(NSString *token in tokens) {
    if([string localizedCaseInsensitiveContainsString:token]) {
      return YES;
    }
  }
  return NO;
}

@implementation MPDiaAddressBarResolver

+ (NSString *)_normalizedHostForURLString:(NSString *)URLString {
  NSString *trimmedString = [URLString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if(trimmedString.length == 0 || [trimmedString rangeOfCharacterFromSet:NSCharacterSet.whitespaceCharacterSet].location != NSNotFound) {
    return nil;
  }
  if([trimmedString rangeOfString:@"://"].location == NSNotFound) {
    trimmedString = [@"https://" stringByAppendingString:trimmedString];
  }
  NSURLComponents *components = [NSURLComponents componentsWithString:trimmedString];
  NSString *host = components.host.lowercaseString;
  if([host hasPrefix:@"www."]) {
    host = [host substringFromIndex:4];
  }
  return host.length > 0 ? host : nil;
}

+ (NSString *)normalizedHostForAddressBarValue:(NSString *)addressBarValue {
  NSRange displaySeparatorRange = [addressBarValue rangeOfString:@" / "];
  NSString *URLString = displaySeparatorRange.location == NSNotFound
                      ? addressBarValue
                      : [addressBarValue substringToIndex:displaySeparatorRange.location];
  return [self _normalizedHostForURLString:URLString];
}

+ (NSString *)normalizedHostForEntryURL:(NSString *)entryURL {
  return [self _normalizedHostForURLString:entryURL];
}

+ (NSString *)addressBarValueForRunningApplication:(NSRunningApplication *)runningApplication {
  if(![runningApplication.bundleIdentifier isEqualToString:MPDiaBundleIdentifier]) {
    return nil;
  }

  id applicationElement = CFBridgingRelease(AXUIElementCreateApplication(runningApplication.processIdentifier));
  AXUIElementRef application = (__bridge AXUIElementRef)applicationElement;
  id window = MPCopyAccessibilityAttribute(application, kAXFocusedWindowAttribute);
  if(!window) {
    window = MPCopyAccessibilityAttribute(application, kAXMainWindowAttribute);
  }
  if(!window) {
    return nil;
  }

  NSMutableArray<NSDictionary<NSString *, id> *> *queue = [NSMutableArray arrayWithObject:@{
    @"element": window,
    @"insideToolbar": @NO,
    @"depth": @0
  }];
  NSUInteger visitedCount = 0;

  while(queue.count > 0 && visitedCount < MPDiaAccessibilityTraversalLimit) {
    NSDictionary<NSString *, id> *node = queue.firstObject;
    [queue removeObjectAtIndex:0];
    visitedCount += 1;

    AXUIElementRef element = (__bridge AXUIElementRef)node[@"element"];
    NSUInteger depth = [node[@"depth"] unsignedIntegerValue];
    NSMutableDictionary<NSString *, id> *attributes = [NSMutableDictionary dictionary];
    NSString *roleAttribute = (__bridge NSString *)kAXRoleAttribute;
    id roleValue = MPCopyAccessibilityAttribute(element, kAXRoleAttribute);
    if(roleValue) {
      attributes[roleAttribute] = roleValue;
    }
    BOOL insideToolbar = [node[@"insideToolbar"] boolValue];
    NSString *role = MPAccessibilityString(attributes, kAXRoleAttribute);
    insideToolbar = insideToolbar || [role isEqualToString:(__bridge NSString *)kAXToolbarRole];
    BOOL isTextInput = [role isEqualToString:(__bridge NSString *)kAXTextFieldRole]
                    || [role isEqualToString:(__bridge NSString *)kAXComboBoxRole];
    if(isTextInput) {
      NSArray<NSString *> *candidateAttributeNames = @[
        (__bridge NSString *)kAXSubroleAttribute,
        (__bridge NSString *)kAXIdentifierAttribute,
        (__bridge NSString *)kAXTitleAttribute,
        (__bridge NSString *)kAXDescriptionAttribute,
        (__bridge NSString *)kAXHelpAttribute,
        (__bridge NSString *)kAXValueAttribute,
        (__bridge NSString *)kAXValueDescriptionAttribute
      ];
      for(NSString *attributeName in candidateAttributeNames) {
        id value = MPCopyAccessibilityAttribute(element, (__bridge CFStringRef)attributeName);
        if(value) {
          attributes[attributeName] = value;
        }
      }
      NSString *addressBarValue = [self addressBarValueForAccessibilityAttributes:attributes insideToolbar:insideToolbar];
      if(addressBarValue.length > 0) {
        return addressBarValue;
      }
    }

    if(depth >= MPDiaAccessibilityDepthLimit) {
      continue;
    }
    id children = MPCopyAccessibilityAttribute(element, kAXChildrenAttribute);
    if(![children isKindOfClass:NSArray.class]) {
      continue;
    }
    for(id child in (NSArray *)children) {
      [queue addObject:@{
        @"element": child,
        @"insideToolbar": @(insideToolbar),
        @"depth": @(depth + 1)
      }];
    }
  }
  return nil;
}

+ (NSString *)addressBarValueForAccessibilityAttributes:(NSDictionary<NSString *,id> *)attributes
                                           insideToolbar:(BOOL)insideToolbar {
  NSString *role = MPAccessibilityString(attributes, kAXRoleAttribute);
  BOOL isTextInput = [role isEqualToString:(__bridge NSString *)kAXTextFieldRole]
                  || [role isEqualToString:(__bridge NSString *)kAXComboBoxRole];
  if(!isTextInput) {
    return nil;
  }

  NSArray<NSString *> *metadataAttributes = @[
    (__bridge id)kAXIdentifierAttribute,
    (__bridge id)kAXTitleAttribute,
    (__bridge id)kAXDescriptionAttribute,
    (__bridge id)kAXHelpAttribute
  ];
  NSMutableArray<NSString *> *metadataParts = [NSMutableArray array];
  for(NSString *attribute in metadataAttributes) {
    NSString *part = MPAccessibilityString(attributes, (__bridge CFStringRef)attribute);
    if(part.length > 0) {
      [metadataParts addObject:part];
    }
  }
  NSString *metadata = [metadataParts componentsJoinedByString:@" "];
  BOOL explicitlyAddressBar = MPStringContainsAnyToken(metadata, @[@"address", @"location", @"omnibox", @"url bar"]);
  NSString *subrole = MPAccessibilityString(attributes, kAXSubroleAttribute);
  BOOL toolbarSearchField = insideToolbar
                         && ([subrole isEqualToString:(__bridge NSString *)kAXSearchFieldSubrole]
                             || [metadata localizedCaseInsensitiveContainsString:@"search"]);
  if(!explicitlyAddressBar && !toolbarSearchField) {
    return nil;
  }

  NSString *value = MPAccessibilityString(attributes, kAXValueAttribute);
  if(value.length == 0) {
    value = MPAccessibilityString(attributes, kAXValueDescriptionAttribute);
  }
  value = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  return value.length > 0 ? value : nil;
}

@end
