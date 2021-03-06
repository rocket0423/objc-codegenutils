//
//  CGUCodeGenTool.h
//  codegenutils
//
//  Created by Jim Puls on 9/6/13.
//  Licensed to Square, Inc. under one or more contributor license agreements.
//  See the LICENSE file distributed with this work for the terms under
//  which Square, Inc. licenses this file to you.

#import <Foundation/Foundation.h>

@interface NSString (CGUCodeGenToolAddition)

- (NSString *)IDS_titlecaseString;

@end

@interface CGUCodeGenTool : NSObject

+ (int)startWithArgc:(int)argc argv:(const char **)argv;

+ (NSArray *)inputFileExtension;

@property (copy) NSURL *inputURL;
@property (copy) NSURL *searchingURL;
@property (copy) NSArray *allFileURLs;
@property (copy) NSString *classPrefix;
@property float appVersion;
@property BOOL targetObjC;
@property BOOL skipClassDeclaration;
@property BOOL writeSingleFile;
@property BOOL lastFile;
@property BOOL verifyItems;
@property (copy) NSString *className;

@property (copy) NSString *infoPlistFile;
@property (strong) NSMutableArray *implementationContents;
@property (strong) NSMutableArray *objcItems;
@property BOOL hasWarning;

- (void)startWithCompletionHandler:(dispatch_block_t)completionBlock;

- (void)writeOutputFiles;

- (NSString *)methodNameForKey:(NSString *)key;

+ (NSString *)runStringAsCommand:(NSString *)string;

@end
