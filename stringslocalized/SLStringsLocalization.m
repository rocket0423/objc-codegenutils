//
//  SLStringsLocalization.m
//  stringslocalized
//
//  Created by Jim Puls on 8/29/13.
//  Licensed to Square, Inc. under one or more contributor license agreements.
//  See the LICENSE file distributed with this work for the terms under
//  which Square, Inc. licenses this file to you.

#import "SLStringsLocalization.h"

@interface NSString (SLStringsAddition)

- (NSString *)SLS_formattedString;
- (NSString *)SLS_titlecaseString;

@end

@interface SLStringsLocalization ()

@property (strong) NSArray *imageSetURLs;

@end


@implementation SLStringsLocalization

+ (NSArray *)inputFileExtension;
{
    return @[@"strings"];
}

- (void)startWithCompletionHandler:(dispatch_block_t)completionBlock;
{
    NSArray *pathComponents = [self.inputURL pathComponents];
    if ([pathComponents count] > 1) {
        if (![[pathComponents objectAtIndex:([pathComponents count] - 2)] isEqualToString:@"Base.lproj"]) {
            if (self.writeSingleFile && self.lastFile && self.implementationContents) {
                [self writeOutputFiles];
            }
            completionBlock();
            return;
        }
    }
    BOOL hasTranslations = [self synchronizeFiles];
    
    NSString *localizationFileName = [[self.inputURL lastPathComponent] stringByDeletingPathExtension];
    if (self.writeSingleFile)
        self.className = [NSString stringWithFormat:@"%@Strings", self.classPrefix];
    else
        self.className = [NSString stringWithFormat:@"%@%@Strings", self.classPrefix, localizationFileName];
    if (!self.implementationContents)
        self.implementationContents = [NSMutableArray array];
    if (!self.objcItems && self.targetObjC)
        self.objcItems = [NSMutableArray array];
    
    NSDictionary *localizationDict = [NSDictionary dictionaryWithContentsOfURL:self.inputURL];
    for (NSString *nextKey in [localizationDict allKeys]) {
        NSString *localizedString = [[localizationDict objectForKey:nextKey] SLS_formattedString];
        NSMutableString *implementation = nil;
        if (self.targetObjC){
            implementation = [[NSMutableString alloc] init];
            NSString *interface = [NSString stringWithFormat:@"+ (NSString *)%@;\n", [[self methodNameForKey:nextKey] SLS_titlecaseString]];
            @synchronized(self.objcItems) {
                [self.objcItems addObject:interface];
            }
            
            [implementation appendFormat:@"/// %@\n", localizedString];
            [implementation appendString:interface];
            [implementation appendString:@"{\n"];
            if (hasTranslations) {
                [implementation appendFormat:@"    return NSLocalizedStringFromTable(@\"%@\", @\"%@\", @\"%@\");\n", nextKey, localizationFileName, localizedString];
            } else {
                [implementation appendFormat:@"    return @\"%@\";\n", localizedString];
            }
            [implementation appendString:@"}\n\n"];
        } else {
            implementation = [[NSMutableString alloc] init];
            [implementation appendFormat:@"    /// %@\n", localizedString];
            [implementation appendFormat:@"    static var %@: String {\n", [[self methodNameForKey:nextKey] SLS_titlecaseString]];
            if (hasTranslations) {
                [implementation appendFormat:@"        return NSLocalizedString(\"%@\", tableName: \"%@\", comment: \"%@\")\n", nextKey, localizationFileName, localizedString];
            } else {
                [implementation appendFormat:@"        return \"%@\"\n", localizedString];
            }
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

- (BOOL)synchronizeFiles {
    BOOL hasTranslations = NO;
    NSString *mainString = [NSString stringWithContentsOfURL:self.inputURL encoding:NSUTF8StringEncoding error:nil];
    NSArray *mainComponents = [mainString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSURL *nextFile in self.allFileURLs) {
        if (nextFile == self.inputURL || ![[nextFile lastPathComponent] isEqualToString:[self.inputURL lastPathComponent]]) {
            continue;
        }
        hasTranslations = YES;
        NSArray *currentPathComponents = [self.inputURL pathComponents];
        NSArray *nextSetOfPathComponents = [nextFile pathComponents];
        NSUInteger max = 4;
        if (currentPathComponents.count < max) {
            max = currentPathComponents.count;
        }
        if (nextSetOfPathComponents.count < max) {
            max = nextSetOfPathComponents.count;
        }
        BOOL sameLocalizationFile = YES;
        for (int i = 3; i <= max; i++) {
            if (![[currentPathComponents objectAtIndex:(currentPathComponents.count - i)] isEqualToString:[nextSetOfPathComponents objectAtIndex:(nextSetOfPathComponents.count - i)]]) {
                sameLocalizationFile = NO;
                break;
            }
        }
        if (!sameLocalizationFile) {
            continue;
        }
        
        NSMutableString *mutableString = [[NSMutableString alloc] init];
        NSString *nextString = [NSString stringWithContentsOfURL:nextFile encoding:NSUTF8StringEncoding error:nil];
        NSArray *nextComponents = [nextString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        for (NSString *nextMainComponent in mainComponents) {
            if (![nextMainComponent hasPrefix:@"\""]) {
                [mutableString appendString:nextMainComponent];
            } else {
                NSString *translation = [self stringForKey:[self keyForComponent:nextMainComponent] components:nextComponents];
                if (translation) {
                    [mutableString appendString:translation];
                } else {
                    [mutableString appendFormat:@"%@ // Needs Translation", nextMainComponent];
                }
            }
            [mutableString appendString:@"\n"];
        }
        [[mutableString substringToIndex:(mutableString.length - 1)] writeToURL:nextFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    return hasTranslations;
}

- (NSString *)keyForComponent:(NSString *)component {
    NSArray *keys = [component componentsSeparatedByString:@"\""];
    if ([keys count] > 1) {
        return [keys objectAtIndex:1];
    }
    return nil;
}

- (NSString *)stringForKey:(NSString *)key components:(NSArray *)components {
    for (NSString *nextComponent in components) {
        if ([nextComponent hasPrefix:@"\""]) {
            if ([key isEqualToString:[self keyForComponent:nextComponent]]) {
                return nextComponent;
            }
        }
    }
    return nil;
}

@end


@implementation NSString (SLStringsAddition)

- (NSString *)SLS_formattedString;
{
    return [self stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
}

- (NSString *)SLS_titlecaseString;
{
    NSArray *words = [self componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableString *output = [NSMutableString string];
    for (NSString *word in words) {
        [output appendFormat:@"%@%@_", [[word substringToIndex:1] lowercaseString], [word substringFromIndex:1]];
    }
    return [output substringToIndex:(output.length - 1 )];
}

@end
