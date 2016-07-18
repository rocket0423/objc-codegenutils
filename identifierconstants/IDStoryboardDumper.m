//
//  IDStoryboardDumper.m
//  codegenutils
//
//  Created by Jim Puls on 2/3/14.
//  Licensed to Square, Inc. under one or more contributor license agreements.
//  See the LICENSE file distributed with this work for the terms under
//  which Square, Inc. licenses this file to you.

#import "IDStoryboardDumper.h"


@implementation IDStoryboardDumper

+ (NSArray *)inputFileExtension;
{
    return @[@"storyboard", @"xib"];
}

- (void)startWithCompletionHandler:(dispatch_block_t)completionBlock;
{
    NSString *extension = [[self.inputURL pathExtension] IDS_titlecaseString];
//    self.skipClassDeclaration = YES;
    NSString *filename = [[self.inputURL lastPathComponent] stringByDeletingPathExtension];
    NSString *formattedFilename = [filename stringByReplacingOccurrencesOfString:@" " withString:@""];
    BOOL containsExtensionText = NO;
    if (self.writeSingleFile){
        self.className = [NSString stringWithFormat:@"%@Identifiers", self.classPrefix];
    } else if ([formattedFilename rangeOfString:extension options:NSCaseInsensitiveSearch].location == NSNotFound){
        self.className = [NSString stringWithFormat:@"%@%@%@Identifiers", self.classPrefix, formattedFilename, extension];
    } else {
        containsExtensionText = YES;
        self.className = [NSString stringWithFormat:@"%@%@Identifiers", self.classPrefix, formattedFilename];
    }
    NSError *error = nil;
    NSXMLDocument *document = [[NSXMLDocument alloc] initWithContentsOfURL:self.inputURL options:0 error:&error];
    
    NSArray *storyboardIdentifiers = [[document nodesForXPath:@"//@storyboardIdentifier" error:&error] valueForKey:NSStringFromSelector(@selector(stringValue))];
    NSArray *reuseIdentifiers = [[document nodesForXPath:@"//@reuseIdentifier" error:&error] valueForKey:NSStringFromSelector(@selector(stringValue))];
    NSArray *segueIdentifiers = [[document nodesForXPath:@"//segue/@identifier" error:&error] valueForKey:NSStringFromSelector(@selector(stringValue))];
    
    NSMutableArray *identifiers = [NSMutableArray arrayWithArray:storyboardIdentifiers];
    [identifiers addObjectsFromArray:reuseIdentifiers];
    [identifiers addObjectsFromArray:segueIdentifiers];
    
    if (!self.implementationContents)
        self.implementationContents = [NSMutableArray array];
    if (!self.objcItems && self.targetObjC)
        self.objcItems = [NSMutableArray array];
    
    NSMutableDictionary *uniqueKeys = [NSMutableDictionary dictionary];
	NSMutableArray *allKeys = [[NSMutableArray alloc] init];
	NSString *extensionKey;
    if (self.writeSingleFile) {
        if (containsExtensionText){
            extensionKey = [NSString stringWithFormat:@"%@Name", formattedFilename];
        } else {
            extensionKey = [NSString stringWithFormat:@"%@%@Name", formattedFilename, extension];
        }
    } else {
        if (containsExtensionText){
            extensionKey = [NSString stringWithFormat:@"Name"];
        } else {
            extensionKey = [NSString stringWithFormat:@"%@Name", extension];
        }
    }
    uniqueKeys[extensionKey] = filename;
	[allKeys addObject:extensionKey];
    
    for (NSString *identifier in identifiers) {
        if ([identifier stringByReplacingOccurrencesOfString:@" " withString:@""].length > 0){
            NSString *key = [NSString stringWithFormat:@"%@", [identifier IDS_titlecaseString]];
            uniqueKeys[key] = identifier;
            [allKeys addObject:key];
        }
    }
	
	NSArray *loadedKeys;
	if (self.verifyItems){
		loadedKeys = allKeys;
	} else {
		loadedKeys = [uniqueKeys allKeys];
    }
    
    for (NSString *key in [loadedKeys sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]) {
        NSString *identifierValue = uniqueKeys[key];
        NSMutableString *implementation = nil;
        if (self.targetObjC) {
            implementation = [[NSMutableString alloc] init];
            NSString *interface = [NSString stringWithFormat:@"+ (NSString *)%@;\n", key];
            @synchronized(self.objcItems) {
                [self.objcItems addObject:interface];
            }
            
            [implementation appendFormat:@"/// %@\n", identifierValue];
            [implementation appendString:interface];
            [implementation appendString:@"{\n"];
            [implementation appendFormat:@"    return @\"%@\";\n", identifierValue];
            [implementation appendString:@"}\n\n"];
        } else {
            implementation = [[NSMutableString alloc] init];
            [implementation appendFormat:@"    /// %@\n", identifierValue];
            [implementation appendFormat:@"    static var %@: String {\n", key];
            [implementation appendFormat:@"        return \"%@\"\n", identifierValue];
            [implementation appendString:@"    }\n\n"];
        }
        
        @synchronized(self.implementationContents) {
            [self.implementationContents addObject:implementation];
        }
    }
    
    if (!self.writeSingleFile || self.lastFile)
        [self writeOutputFiles];
    completionBlock();
}

@end
