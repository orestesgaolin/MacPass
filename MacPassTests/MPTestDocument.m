//
//  MPDatabaseCreation.m
//  MacPass
//
//  Created by Michael Starke on 10.07.13.
//  Copyright (c) 2013 HicknHack Software GmbH. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <KeePassKit/KeePassKit.h>

#import "MPDocument.h"
#import "MPConstants.h"

@interface MPTestDocument : XCTestCase

@end

@implementation MPTestDocument

- (void)testCreateEmptyDocument {
  MPDocument *document = [[MPDocument alloc] init];
  XCTAssertNotNil(document, @"Document should be created");
  XCTAssertNil(document.tree, @"Allocated document should not have a tree");
  XCTAssertFalse(document.encrypted, @"Document cannot be encrypted without a tree");
  XCTAssertNil(document.compositeKey, @"Document shoudl have not key at all");
}

- (void)testCreateUntitledDocument {
  MPDocument *document = [[MPDocument alloc] initWithType:@"" error:nil];
  XCTAssertNotNil(document, @"Document should be created");
  KPKFileVersion kdb = { KPKDatabaseFormatKdb, kKPKKdbFileVersion };
  XCTAssertEqual(NSOrderedSame, KPKFileVersionCompare(kdb, document.tree.minimumVersion), @"Tree should be Legacy Version in default case");
  XCTAssertFalse(document.encrypted, @"Document cannot be encrypted at creation");
  XCTAssertFalse(document.compositeKey.hasKeys, @"Document has no Password/Keyfile and thus is not secured");

}

- (void)testNewEntryUsesNearestFolderDefaultEmail {
  MPDocument *document = [[MPDocument alloc] initWithType:@"" error:nil];
  document.tree.metaData.defaultUserName = @"database@example.com";
  [document.tree.root setCustomData:@"root@example.com" forKey:MPGroupDefaultEmailCustomDataKey];

  KPKGroup *parent = [document createGroup:document.tree.root];
  KPKGroup *child = [document createGroup:parent];
  XCTAssertEqualObjects([document createEntry:child].username, @"root@example.com");

  [parent setCustomData:@"parent@example.com" forKey:MPGroupDefaultEmailCustomDataKey];
  XCTAssertEqualObjects([document createEntry:child].username, @"parent@example.com");

  [parent removeCustomDataForKey:MPGroupDefaultEmailCustomDataKey];
  XCTAssertEqualObjects([document createEntry:child].username, @"root@example.com");
}

- (void)testNewEntryFallsBackToDatabaseDefaultEmail {
  MPDocument *document = [[MPDocument alloc] initWithType:@"" error:nil];
  document.tree.metaData.defaultUserName = @"database@example.com";
  XCTAssertEqualObjects([document createEntry:document.tree.root].username, @"database@example.com");
}

@end
