//
//  IDStoryboardDumper.m
//  codegenutils
//
//  Created by Jim Puls on 2/3/14.
//  Licensed to Square, Inc. under one or more contributor license agreements.
//  See the LICENSE file distributed with this work for the terms under
//  which Square, Inc. licenses this file to you.

#import "IDStoryboardDumper.h"


@interface NSString (IDStoryboardAddition)

- (NSString *)IDS_titlecaseString;

@end


@implementation IDStoryboardDumper

+ (NSArray *)inputFileExtension;
{
    return @[@"storyboard", @"xib"];
}

- (void)startWithCompletionHandler:(dispatch_block_t)completionBlock;
{
    NSString *pathExtension = [[self.inputURL lastPathComponent] pathExtension];
    if ([pathExtension isEqualToString:@"storyboard"]){
        [self startStoryboardWithCompletionHandler:completionBlock];
    } else if ([pathExtension isEqualToString:@"xib"]){
        [self startXibWithCompletionHandler:completionBlock];
    } else{
        completionBlock();
    }
}

- (void)startStoryboardWithCompletionHandler:(dispatch_block_t)completionBlock;
{
    self.skipClassDeclaration = YES;
    NSString *storyboardFilename = [[self.inputURL lastPathComponent] stringByDeletingPathExtension];
    NSString *storyboardName = [storyboardFilename stringByReplacingOccurrencesOfString:@" " withString:@""];
    BOOL containsStoryboardText = NO;
    if (self.writeSingleFile){
        self.className = [NSString stringWithFormat:@"%@Identifiers", self.classPrefix];
    } else if ([storyboardName rangeOfString:@"Storyboard" options:NSCaseInsensitiveSearch].location == NSNotFound){
        self.className = [NSString stringWithFormat:@"%@%@StoryboardIdentifiers", self.classPrefix, storyboardName];
    } else {
        containsStoryboardText = YES;
        self.className = [NSString stringWithFormat:@"%@%@Identifiers", self.classPrefix, storyboardName];
    }
    NSError *error = nil;
    NSXMLDocument *document = [[NSXMLDocument alloc] initWithContentsOfURL:self.inputURL options:0 error:&error];
    
    NSArray *storyboardIdentifiers = [[document nodesForXPath:@"//@storyboardIdentifier" error:&error] valueForKey:NSStringFromSelector(@selector(stringValue))];
    NSArray *reuseIdentifiers = [[document nodesForXPath:@"//@reuseIdentifier" error:&error] valueForKey:NSStringFromSelector(@selector(stringValue))];
    NSArray *segueIdentifiers = [[document nodesForXPath:@"//segue/@identifier" error:&error] valueForKey:NSStringFromSelector(@selector(stringValue))];
    
    NSMutableArray *identifiers = [NSMutableArray arrayWithArray:storyboardIdentifiers];
    [identifiers addObjectsFromArray:reuseIdentifiers];
    [identifiers addObjectsFromArray:segueIdentifiers];
    
    if (!self.interfaceContents)
        self.interfaceContents = [NSMutableArray array];
    if (!self.implementationContents)
        self.implementationContents = [NSMutableArray array];
    
    NSMutableDictionary *uniqueKeys = [NSMutableDictionary dictionary];
	NSMutableArray *allKeys = [[NSMutableArray alloc] init];
	NSString *storyboardKey;
    if (containsStoryboardText){
		storyboardKey = [NSString stringWithFormat:@"%@%@Name", self.classPrefix, storyboardName];
    } else {
       storyboardKey = [NSString stringWithFormat:@"%@%@StoryboardName", self.classPrefix, storyboardName];
    }
	uniqueKeys[storyboardKey] = storyboardFilename;
	[allKeys addObject:storyboardKey];
    
    for (NSString *identifier in identifiers) {
        if ([identifier stringByReplacingOccurrencesOfString:@" " withString:@""].length > 0){
            NSString *key = nil;
            if (containsStoryboardText){
                key = [NSString stringWithFormat:@"%@%@%@Identifier", self.classPrefix, storyboardName, [identifier IDS_titlecaseString]];
            } else {
                key = [NSString stringWithFormat:@"%@%@Storyboard%@Identifier", self.classPrefix, storyboardName, [identifier IDS_titlecaseString]];
            }
            uniqueKeys[key] = identifier;
            [allKeys addObject:key];
        }
    }
	
	NSArray *loadedKeys;
	if (self.uniqueItemCheck){
		loadedKeys = allKeys;
	} else {
		loadedKeys = [uniqueKeys allKeys];
	}
	
    for (NSString *key in [loadedKeys sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]) {
        [self.interfaceContents addObject:[NSString stringWithFormat:@"extern NSString *const %@;\n", key]];
        [self.implementationContents addObject:[NSString stringWithFormat:@"NSString *const %@ = @\"%@\";\n", key, uniqueKeys[key]]];
    }
    
    if (!self.writeSingleFile || self.lastFile)
        [self writeOutputFiles];
    completionBlock();
}

- (void)startXibWithCompletionHandler:(dispatch_block_t)completionBlock;
{
    self.skipClassDeclaration = YES;
    NSString *xibFilename = [[self.inputURL lastPathComponent] stringByDeletingPathExtension];
    NSString *xibName = [xibFilename stringByReplacingOccurrencesOfString:@" " withString:@""];
    BOOL containsXibText = NO;
    if (self.writeSingleFile){
        self.className = [NSString stringWithFormat:@"%@Identifiers", self.classPrefix];
    } else if ([xibName rangeOfString:@"Xib" options:NSCaseInsensitiveSearch].location == NSNotFound){
        self.className = [NSString stringWithFormat:@"%@%@XibIdentifiers", self.classPrefix, xibName];
    } else {
        containsXibText = YES;
        self.className = [NSString stringWithFormat:@"%@%@Identifiers", self.classPrefix, xibName];
    }
    NSError *error = nil;
    NSXMLDocument *document = [[NSXMLDocument alloc] initWithContentsOfURL:self.inputURL options:0 error:&error];
    
    NSArray *storyboardIdentifiers = [[document nodesForXPath:@"//@storyboardIdentifier" error:&error] valueForKey:NSStringFromSelector(@selector(stringValue))];
    NSArray *reuseIdentifiers = [[document nodesForXPath:@"//@reuseIdentifier" error:&error] valueForKey:NSStringFromSelector(@selector(stringValue))];
    NSArray *segueIdentifiers = [[document nodesForXPath:@"//segue/@identifier" error:&error] valueForKey:NSStringFromSelector(@selector(stringValue))];
    
    NSMutableArray *identifiers = [NSMutableArray arrayWithArray:storyboardIdentifiers];
    [identifiers addObjectsFromArray:reuseIdentifiers];
    [identifiers addObjectsFromArray:segueIdentifiers];
    
    if (!self.interfaceContents)
        self.interfaceContents = [NSMutableArray array];
    if (!self.implementationContents)
        self.implementationContents = [NSMutableArray array];
    
    NSMutableDictionary *uniqueKeys = [NSMutableDictionary dictionary];
	NSMutableArray *allKeys = [[NSMutableArray alloc] init];
	NSString *xibKey;
    if (containsXibText){
		xibKey = [NSString stringWithFormat:@"%@%@Name", self.classPrefix, xibName];
    } else {
		xibKey = [NSString stringWithFormat:@"%@%@XibName", self.classPrefix, xibName];
    }
	uniqueKeys[xibKey] = xibFilename;
	[allKeys addObject:xibKey];
    
    for (NSString *identifier in identifiers) {
        if ([identifier stringByReplacingOccurrencesOfString:@" " withString:@""].length > 0){
            NSString *key = nil;
            if (containsXibText){
                key = [NSString stringWithFormat:@"%@%@%@Identifier", self.classPrefix, xibName, [identifier IDS_titlecaseString]];
            } else {
                key = [NSString stringWithFormat:@"%@%@Xib%@Identifier", self.classPrefix, xibName, [identifier IDS_titlecaseString]];
            }
            uniqueKeys[key] = identifier;
            [allKeys addObject:key];
        }
    }
	
	NSArray *loadedKeys;
	if (self.uniqueItemCheck){
		loadedKeys = allKeys;
	} else {
		loadedKeys = [uniqueKeys allKeys];
	}
	
    for (NSString *key in [loadedKeys sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]) {
        [self.interfaceContents addObject:[NSString stringWithFormat:@"extern NSString *const %@;\n", key]];
        [self.implementationContents addObject:[NSString stringWithFormat:@"NSString *const %@ = @\"%@\";\n", key, uniqueKeys[key]]];
    }
    
    if (!self.writeSingleFile || self.lastFile)
        [self writeOutputFiles];
    completionBlock();
}

@end


@implementation NSString (IDStoryboardAddition)

- (NSString *)IDS_titlecaseString;
{
    NSArray *words = [self componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableString *output = [NSMutableString string];
    for (NSString *word in words) {
        [output appendFormat:@"%@%@", [[word substringToIndex:1] uppercaseString], [word substringFromIndex:1]];
    }
    return output;
}

@end
