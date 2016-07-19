//
//  CGUCodeGenTool.m
//  codegenutils
//
//  Created by Jim Puls on 9/6/13.
//  Licensed to Square, Inc. under one or more contributor license agreements.
//  See the LICENSE file distributed with this work for the terms under
//  which Square, Inc. licenses this file to you.

#import "CGUCodeGenTool.h"

#import <libgen.h>


@interface CGUCodeGenTool ()

@property (copy) NSString *toolName;

@end


@implementation CGUCodeGenTool

+ (NSArray *)inputFileExtension;
{
    NSAssert(NO, @"Unimplemented abstract method: %@", NSStringFromSelector(_cmd));
    return nil;
}

+ (int)startWithArgc:(int)argc argv:(const char **)argv;
{
    NSDate *startTime = [NSDate date];
    NSString *workingTool = [[NSString stringWithUTF8String:argv[0]] lastPathComponent];
    NSURL *searchURL = nil;
    NSString *classPrefix = @"";
    NSString *infoPlist = @"";
    BOOL singleFile = YES;
    BOOL objc = NO;
    BOOL verify = YES;
    
    NSMutableArray *inputURLs = [NSMutableArray array];
    
    float currentVersion = [[CGUCodeGenTool runStringAsCommand:@"echo \"$IPHONEOS_DEPLOYMENT_TARGET\""] floatValue];
	
    infoPlist = [CGUCodeGenTool runStringAsCommand:@"echo \"$SRCROOT/$INFOPLIST_FILE\""];
    if (![[NSFileManager defaultManager] fileExistsAtPath:infoPlist]){
        infoPlist = [CGUCodeGenTool runStringAsCommand:@"echo \"$INFOPLIST_FILE\""];
    }
    
    for (NSString *fileExtension in [self inputFileExtension]) {
        for (int i=0;i<argc;i++){
            NSString *nextArgument = [NSString stringWithFormat:@"%s", argv[i]];
            if ([nextArgument isEqualToString:@"-h"]){
                printf("Usage: %s [-dnverify] [-version] [-i] [-objc] [-iplist <path>] [-o <path>] [-f <path>] [-p <prefix>]\n", basename((char *)argv[0]));
                printf("       %s -h\n\n", basename((char *)argv[0]));
                printf("Options:\n");
                printf("    -o <path>   Output files at <path>\n");
                printf("    -f <path>   Search for *.%s folders starting from <path>\n", [fileExtension UTF8String]);
                printf("    -p <prefix> Use <prefix> as the class prefix in the generated code\n");
                printf("    -i          Generates everything in their own file instead of one file");
                printf("    -objc       Generates files that can be used by objc by default they are created for swift only");
                printf("    -version    Minimum app version supported\n");
                printf("    -dnverify   Do not verify any of the code default is to always verify\n");
                printf("    -iplist <path>   Info Plist file at <path>\n");
                printf("    -h          Print this help and exit\n");
                return 0;
            } else if ([nextArgument isEqualToString:@"-o"]){
                NSString *outputPath = [NSString stringWithFormat:@"%s", argv[++i]];
                outputPath = [outputPath stringByExpandingTildeInPath];
                [[NSFileManager defaultManager] changeCurrentDirectoryPath:outputPath];
            } else if ([nextArgument isEqualToString:@"-f"]){
                NSString *searchPath = [NSString stringWithFormat:@"%s", argv[++i]];
                searchPath = [searchPath stringByExpandingTildeInPath];
                searchURL = [NSURL fileURLWithPath:searchPath];
            } else if ([nextArgument isEqualToString:@"-p"]){
                classPrefix = [NSString stringWithFormat:@"%s", argv[++i]];
            } else if ([nextArgument isEqualToString:@"-i"]){
                singleFile = NO;
            } else if ([nextArgument isEqualToString:@"-iplist"]){
                infoPlist = [[NSString stringWithFormat:@"%s", argv[++i]] stringByExpandingTildeInPath];
            } else if ([nextArgument isEqualToString:@"-objc"]){
                objc = YES;
            } else if ([nextArgument isEqualToString:@"-version"]){
                currentVersion = [[NSString stringWithFormat:@"%s", argv[++i]] floatValue];
            } else if ([nextArgument isEqualToString:@"-dnverify"]){
                verify = NO;
            }
        }
        
        if (searchURL) {
            NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtURL:searchURL includingPropertiesForKeys:@[NSURLNameKey] options:0 errorHandler:NULL];
            for (NSURL *url in enumerator) {
                if ([url.pathExtension isEqualToString:fileExtension]) {
                    [inputURLs addObject:url];
                }
            }
        }
    }
    
    dispatch_group_t group = dispatch_group_create();
   
    CGUCodeGenTool *target;
    if (singleFile){
        target = [self new];
        target.hasWarning = NO;
    }
    for (NSURL *url in inputURLs) {
        dispatch_group_enter(group);
        if (!singleFile){
            target = [self new];
            target.hasWarning = NO;
        }
        target.searchingURL = searchURL;
        target.infoPlistFile = infoPlist;
        target.allFileURLs = inputURLs;
        target.inputURL = url;
        target.appVersion = currentVersion;
        target.targetObjC = objc;
        target.verifyItems = verify;
        target.classPrefix = classPrefix;
        target.writeSingleFile = singleFile;
        target.lastFile = ([inputURLs lastObject] == url);
        target.toolName = workingTool;
        [target startWithCompletionHandler:^{
            dispatch_group_leave(group);
        }];
    }
    
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    NSLog(@"Tool %@ finished in %f seconds", workingTool, [[NSDate date] timeIntervalSinceDate:startTime]);
    return 0;
}

- (void)startWithCompletionHandler:(dispatch_block_t)completionBlock;
{
    NSAssert(NO, @"Unimplemented abstract method: %@", NSStringFromSelector(_cmd));
}

- (void)writeOutputFiles;
{
    NSAssert(self.className, @"Class name isn't set");

    NSString *classNameSwift = [self.className stringByAppendingPathExtension:@"swift"];

    NSURL *currentDirectory = [NSURL fileURLWithPath:[[NSFileManager new] currentDirectoryPath]];
    NSURL *implementationURL = [currentDirectory URLByAppendingPathComponent:classNameSwift];
    
    [self.implementationContents sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        return [obj1 compare:obj2];
    }];
    [self.objcItems sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        return [obj1 compare:obj2];
    }];
    
    NSMutableString *implementation;
    if (self.writeSingleFile){
        implementation = [NSMutableString stringWithFormat:@"//\n// This file is generated from all .%@ files by %@.\n// Please do not edit.\n//\n\n", self.inputURL.pathExtension, self.toolName];
    } else {
        implementation = [NSMutableString stringWithFormat:@"//\n// This file is generated from %@ by %@.\n// Please do not edit.\n//\n\n", self.inputURL.lastPathComponent, self.toolName];
    }
    
    if (self.skipClassDeclaration) {
        if (self.targetObjC){
            NSString *classNameH = [self.className stringByAppendingPathExtension:@"h"];
            NSString *classNameM = [self.className stringByAppendingPathExtension:@"m"];
            NSURL *objcInterfaceURL = [currentDirectory URLByAppendingPathComponent:classNameH];
            implementationURL = [currentDirectory URLByAppendingPathComponent:classNameM];
            
            NSMutableString *interface = [implementation mutableCopy];
            [interface appendFormat:@"#import <UIKit/UIKit.h>\n\n\n"];
            [interface appendString:[self.objcItems componentsJoinedByString:@""]];
            
            [implementation appendFormat:@"#import \"%@\"\n\n\n", classNameH];
            [implementation appendString:[self.implementationContents componentsJoinedByString:@""]];
            
            if (![interface isEqualToString:[NSString stringWithContentsOfURL:objcInterfaceURL encoding:NSUTF8StringEncoding error:NULL]]) {
                [interface writeToURL:objcInterfaceURL atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            }
        } else {
            [implementation appendFormat:@"import UIKit\n\n\n"];
            [implementation appendString:[self.implementationContents componentsJoinedByString:@""]];
        }
    } else {
        if (self.targetObjC){
            NSString *classNameH = [self.className stringByAppendingPathExtension:@"h"];
            NSString *classNameM = [self.className stringByAppendingPathExtension:@"m"];
            NSURL *objcInterfaceURL = [currentDirectory URLByAppendingPathComponent:classNameH];
            implementationURL = [currentDirectory URLByAppendingPathComponent:classNameM];
            
            NSMutableString *interface = [implementation mutableCopy];
            [interface appendFormat:@"#import <UIKit/UIKit.h>\n\n\n"];
            [interface appendFormat:@"@interface %@ : NSObject\n\n%@\n@end\n", self.className, [self.objcItems componentsJoinedByString:@""]];
            
            [implementation appendFormat:@"#import \"%@\"\n\n\n", classNameH];
            [implementation appendFormat:@"@implementation %@\n\n%@\n@end\n", self.className, [self.implementationContents componentsJoinedByString:@"\n"]];
            
            if (![interface isEqualToString:[NSString stringWithContentsOfURL:objcInterfaceURL encoding:NSUTF8StringEncoding error:NULL]]) {
                [interface writeToURL:objcInterfaceURL atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            }
        } else {
            [implementation appendFormat:@"import UIKit\n\n\n"];
            [implementation appendFormat:@"%@class %@: NSObject {\n\n%@}\n", (self.targetObjC ? @"@objc " : @""), self.className, [self.implementationContents componentsJoinedByString:@""]];
        }
    }

    if (![implementation isEqualToString:[NSString stringWithContentsOfURL:implementationURL encoding:NSUTF8StringEncoding error:NULL]]) {
        [implementation writeToURL:implementationURL atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    }
    
    NSLog(@"Wrote %@ to %@", self.className, currentDirectory);
}

- (NSString *)methodNameForKey:(NSString *)key;
{
    NSMutableString *mutableKey = [key mutableCopy];
    // If the string is already all caps, it's an abbrevation. Lowercase the whole thing.
    // Otherwise, camelcase it by lowercasing the first character.
    if ([mutableKey isEqualToString:[mutableKey uppercaseString]]) {
        mutableKey = [[mutableKey lowercaseString] mutableCopy];
    } else {
        [mutableKey replaceCharactersInRange:NSMakeRange(0, 1) withString:[[key substringToIndex:1] lowercaseString]];
    }
    [mutableKey replaceOccurrencesOfString:@"-" withString:@"_" options:0 range:NSMakeRange(0, mutableKey.length)];
    
    NSMutableCharacterSet *charactersWanted = [NSMutableCharacterSet alphanumericCharacterSet];
    [charactersWanted addCharactersInString:@"_"];
    mutableKey = [[[mutableKey componentsSeparatedByCharactersInSet: [charactersWanted invertedSet]] componentsJoinedByString: @""] mutableCopy];
    
    while ([mutableKey rangeOfString:@"^\\d" options:NSRegularExpressionSearch].location != NSNotFound) {
        [mutableKey deleteCharactersInRange:NSMakeRange(0, 1)];
    }
    return [mutableKey copy];
}

+ (NSString *)runStringAsCommand:(NSString *)string{
	NSPipe *pipe = [NSPipe pipe];
	NSTask *task = [[NSTask alloc] init];
	[task setLaunchPath:@"/bin/sh"];
	[task setArguments:@[@"-c", [NSString stringWithFormat:@"%@", string]]];
	[task setStandardOutput:pipe];
	
	NSFileHandle *file = [pipe fileHandleForReading];
	[task launch];
	
    NSString *resultString = [[NSString alloc] initWithData:[file readDataToEndOfFile] encoding:NSUTF8StringEncoding];
    if (resultString.length > 0){
        return [resultString substringToIndex:resultString.length - 1];
    } else {
        return nil;
    }
}

@end


@implementation NSString (CGUCodeGenToolAddition)

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
