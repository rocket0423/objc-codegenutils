//
//  AGCatalogVerify.m
//  codegenutils
//
//  Created by Justin Carstens on 5/19/14.
//  Copyright (c) 2014 Square, Inc. All rights reserved.
//

#import "AGCatalogVerify.h"
#import "CGUCodeGenTool.h"

@interface AGCatalogVerify ()

@property (strong) NSArray *imageSetURLs;

@end

@implementation AGCatalogVerify

+ (NSArray *)inputFileExtension;
{
    return @[@"xcassets"];
}

- (void)startWithCompletionHandler:(dispatch_block_t)completionBlock;
{
    if (!self.writeSingleFile){
        // Added to que to do multiple assets at one time
        dispatch_group_t dispatchGroup = dispatch_group_create();
        dispatch_queue_t dispatchQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
        dispatch_async(dispatchQueue, ^{
            [self findImageSetURLs];
            
            if (!self.implementationContents)
                self.implementationContents = [@[[[NSMutableDictionary alloc] initWithCapacity:[self.imageSetURLs count]]] mutableCopy];
            
            if (self.writeSingleFile)
                self.className = [[NSString stringWithFormat:@"%@CatalogVerify", self.classPrefix] stringByReplacingOccurrencesOfString:@" " withString:@""];
            else
                self.className = [[NSString stringWithFormat:@"%@%@CatalogVerify", self.classPrefix, [[self.inputURL lastPathComponent] stringByDeletingPathExtension]] stringByReplacingOccurrencesOfString:@" " withString:@""];
            
            for (NSURL *imageSetURL in self.imageSetURLs) {
                dispatch_group_async(dispatchGroup, dispatchQueue, ^{
                    [self parseImageSetAtURL:imageSetURL];
                });
            }
            
            dispatch_group_wait(dispatchGroup, DISPATCH_TIME_FOREVER);
            
            if (!self.writeSingleFile || self.lastFile)
                [self writeToPlist];
            
            completionBlock();
        });
    } else {
        // Since writing to the same file need to do consecutively
        [self findImageSetURLs];
        
        if (!self.implementationContents)
            self.implementationContents = [@[[[NSMutableDictionary alloc] initWithCapacity:[self.imageSetURLs count]]] mutableCopy];
        
        if (self.writeSingleFile)
            self.className = [[NSString stringWithFormat:@"%@CatalogVerify", self.classPrefix] stringByReplacingOccurrencesOfString:@" " withString:@""];
        else
            self.className = [[NSString stringWithFormat:@"%@%@CatalogVerify", self.classPrefix, [[self.inputURL lastPathComponent] stringByDeletingPathExtension]] stringByReplacingOccurrencesOfString:@" " withString:@""];
        
        for (NSURL *imageSetURL in self.imageSetURLs) {
			[self parseImageSetAtURL:imageSetURL];
        }
        
        if (!self.writeSingleFile || self.lastFile)
            [self writeToPlist];
        
        completionBlock();
    }
}

- (void)writeToPlist{
    NSString *plistFile = [self.className stringByAppendingPathExtension:@"plist"];
    
    NSURL *currentDirectory = [NSURL fileURLWithPath:[[NSFileManager new] currentDirectoryPath]];
    NSURL *plistURL = [currentDirectory URLByAppendingPathComponent:plistFile];
    NSDictionary *dictionary = [self.implementationContents firstObject];
    [dictionary writeToFile:[[[plistURL absoluteString] substringFromIndex:7] stringByReplacingPercentEscapesUsingEncoding:NSStringEncodingConversionAllowLossy] atomically:YES];
    NSLog(@"Wrote %@ to %@", self.className, currentDirectory);
    
}

- (void)findImageSetURLs;
{
    NSMutableArray *imageSetURLs = [NSMutableArray array];
    NSDirectoryEnumerator *enumerator = [[NSFileManager new] enumeratorAtURL:self.inputURL includingPropertiesForKeys:@[NSURLNameKey] options:0 errorHandler:NULL];
    for (NSURL *url in enumerator) {
        if ([url.pathExtension isEqualToString:@"imageset"]) {
            [imageSetURLs addObject:url];
        }
    }
    self.imageSetURLs = [imageSetURLs copy];
}

- (void)parseImageSetAtURL:(NSURL *)url;
{
    NSString *absolutePath = [[[self.searchingURL absoluteString] substringFromIndex:7] stringByReplacingPercentEscapesUsingEncoding:NSStringEncodingConversionAllowLossy];
    NSString *imageSetName = [[url lastPathComponent] stringByDeletingPathExtension];
    NSMutableDictionary *finalDictionary = [self.implementationContents firstObject];
    NSMutableDictionary *resultDictionary = [finalDictionary objectForKey:imageSetName];
    if (!resultDictionary){
        resultDictionary = [[NSMutableDictionary alloc] init];
    }
    NSArray *extensionsToCheck = @[@"m", @"storyboard", @"xib", @"html", @"txt", @"css"];
    for (NSString *extension in extensionsToCheck){
        NSString *comand = [NSString stringWithFormat:@"grep -i -r --include=*.%@ \"%@\" \"%@\"", extension, imageSetName, absolutePath];
        NSString *result = [CGUCodeGenTool runStringAsCommand:comand];
        if (result){
            NSArray *components = [result componentsSeparatedByString:@"\n"];
            for (NSString *nextResult in components){
                NSRange extensionRange = [nextResult rangeOfString:[NSString stringWithFormat:@".%@:", extension]];
                if (extensionRange.location != NSNotFound){
                    NSString *file = [[nextResult substringToIndex:(extensionRange.location + extensionRange.length - 1)] lastPathComponent];
                    NSString *text = [nextResult substringFromIndex:(extensionRange.location + extensionRange.length)];
                    NSMutableArray *fileArray = [resultDictionary objectForKey:file];
                    if (!fileArray){
                        fileArray = [[NSMutableArray alloc] initWithCapacity:[components count]];
                    }
                    [fileArray addObject:text];
                    [resultDictionary setObject:fileArray forKey:file];
                }
            }
        }
    }
    [finalDictionary setObject:resultDictionary forKey:imageSetName];
    self.implementationContents = [@[finalDictionary] mutableCopy];
}

@end