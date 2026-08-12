#import "MPAutoFillServiceMatcher.h"

static NSString *MPAutoFillNormalizedHost(NSString *host) {
  if (host.length == 0 || ![host canBeConvertedToEncoding:NSUTF8StringEncoding]) {
    return nil;
  }
  NSString *normalized = host.lowercaseString;
  if ([normalized hasPrefix:@"["] && [normalized hasSuffix:@"]"]) {
    normalized = [normalized substringWithRange:NSMakeRange(1, normalized.length - 2)];
  }
  if ([normalized hasSuffix:@".."]) {
    return nil;
  }
  if ([normalized hasSuffix:@"."]) {
    normalized = [normalized substringToIndex:normalized.length - 1];
  }
  return normalized.length > 0 ? normalized : nil;
}

static BOOL MPAutoFillValidURLPort(NSString *value) {
  NSRange schemeRange = [value rangeOfString:@"://"];
  if (schemeRange.location == NSNotFound) {
    return NO;
  }
  NSUInteger authorityStart = NSMaxRange(schemeRange);
  NSRange authorityEnd = [value rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/?#"]
                                                options:0
                                                  range:NSMakeRange(authorityStart, value.length - authorityStart)];
  NSString *authority = [value substringWithRange:NSMakeRange(
      authorityStart, (authorityEnd.location == NSNotFound ? value.length : authorityEnd.location) - authorityStart)];
  NSString *port = nil;
  if ([authority hasPrefix:@"["]) {
    NSRange bracket = [authority rangeOfString:@"]"];
    if (bracket.location == NSNotFound) {
      return NO;
    }
    NSString *remainder = [authority substringFromIndex:NSMaxRange(bracket)];
    if (remainder.length > 0) {
      if (![remainder hasPrefix:@":"]) {
        return NO;
      }
      port = [remainder substringFromIndex:1];
    }
  } else {
    NSArray<NSString *> *parts = [authority componentsSeparatedByString:@":"];
    if (parts.count > 2) {
      return NO;
    }
    if (parts.count == 2) {
      port = parts[1];
    }
  }
  if (!port) {
    return YES;
  }
  NSCharacterSet *nonDigits = NSCharacterSet.decimalDigitCharacterSet.invertedSet;
  NSInteger portNumber = port.integerValue;
  return port.length > 0 && [port rangeOfCharacterFromSet:nonDigits].location == NSNotFound &&
      portNumber >= 1 && portNumber <= 65535;
}

static NSNumber *MPAutoFillEffectivePort(NSURLComponents *components) {
  if (components.port) {
    return components.port;
  }
  if ([components.scheme.lowercaseString isEqualToString:@"http"]) {
    return @80;
  }
  if ([components.scheme.lowercaseString isEqualToString:@"https"]) {
    return @443;
  }
  return nil;
}

static NSURLComponents *MPAutoFillURLComponents(NSString *value) {
  if (![value isKindOfClass:NSString.class] || value.length == 0 ||
      ![value canBeConvertedToEncoding:NSUTF8StringEncoding] ||
      [value rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound ||
      !MPAutoFillValidURLPort(value)) {
    return nil;
  }
  NSURLComponents *components = [NSURLComponents componentsWithString:value];
  NSString *scheme = components.scheme.lowercaseString;
  if (!components || (! [scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) ||
      components.user.length > 0 || components.password.length > 0 ||
      !MPAutoFillNormalizedHost(components.host) || !components.URL) {
    return nil;
  }
  return components;
}

static NSString *MPAutoFillDomainHost(NSString *value) {
  if (![value isKindOfClass:NSString.class] || value.length == 0 ||
      [value rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound ||
      [value containsString:@"/"] || [value containsString:@"?"] || [value containsString:@"#"] ||
      [value containsString:@"@"] || [value containsString:@"://"]) {
    return nil;
  }
  NSURLComponents *components = [NSURLComponents componentsWithString:[@"https://" stringByAppendingString:value]];
  BOOL bracketedIPv6 = [value hasPrefix:@"["] && [value hasSuffix:@"]"];
  if (!components || components.port || !components.URL ||
      (!bracketedIPv6 && [value containsString:@":"])) {
    return nil;
  }
  return MPAutoFillNormalizedHost(components.host);
}

@implementation MPAutoFillServiceMatcher

+ (BOOL)credentialServiceIdentifier:(NSString *)credentialServiceIdentifier
    matchesRequestedServiceIdentifier:(NSString *)requestedServiceIdentifier
                                 type:(MPAutoFillServiceIdentifierType)type {
  NSURLComponents *credential = MPAutoFillURLComponents(credentialServiceIdentifier);
  if (!credential) {
    return NO;
  }
  NSString *credentialHost = MPAutoFillNormalizedHost(credential.host);
  if (type == MPAutoFillServiceIdentifierTypeDomain) {
    return [credentialHost isEqualToString:MPAutoFillDomainHost(requestedServiceIdentifier)];
  }
  if (type != MPAutoFillServiceIdentifierTypeURL) {
    return NO;
  }
  NSURLComponents *requested = MPAutoFillURLComponents(requestedServiceIdentifier);
  return requested &&
      [credentialHost isEqualToString:MPAutoFillNormalizedHost(requested.host)] &&
      [credential.scheme.lowercaseString isEqualToString:requested.scheme.lowercaseString] &&
      [MPAutoFillEffectivePort(credential) isEqualToNumber:MPAutoFillEffectivePort(requested)];
}

+ (NSString *)normalizedCredentialServiceIdentifier:(NSString *)serviceIdentifier {
  NSURLComponents *components = MPAutoFillURLComponents(serviceIdentifier);
  if (!components) {
    return nil;
  }
  components.scheme = components.scheme.lowercaseString;
  NSString *host = MPAutoFillNormalizedHost(components.host);
  components.host = [host containsString:@":"] ? [NSString stringWithFormat:@"[%@]", host] : host;
  components.path = @"";
  components.query = nil;
  components.fragment = nil;
  NSNumber *defaultPort = [components.scheme isEqualToString:@"http"] ? @80 : @443;
  if ([components.port isEqualToNumber:defaultPort]) {
    components.port = nil;
  }
  return components.string;
}

@end
