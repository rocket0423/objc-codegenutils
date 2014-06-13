//
//  AGCatalogParser.m
//  assetgen
//
//  Created by Jim Puls on 8/29/13.
//  Licensed to Square, Inc. under one or more contributor license agreements.
//  See the LICENSE file distributed with this work for the terms under
//  which Square, Inc. licenses this file to you.

#import "AGCatalogParser.h"


@interface AGCatalogParser ()

@property (strong) NSArray *imageSetURLs;

@end


@implementation AGCatalogParser

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
                self.implementationContents = [NSMutableArray array];
            
            if (self.writeSingleFile)
                self.className = [[NSString stringWithFormat:@"%@ImagesCatalog", self.classPrefix] stringByReplacingOccurrencesOfString:@" " withString:@""];
            else
                self.className = [[NSString stringWithFormat:@"%@%@Catalog", self.classPrefix, [[self.inputURL lastPathComponent] stringByDeletingPathExtension]] stringByReplacingOccurrencesOfString:@" " withString:@""];
            
            for (NSURL *imageSetURL in self.imageSetURLs) {
                dispatch_group_async(dispatchGroup, dispatchQueue, ^{
                    [self parseImageSetAtURL:imageSetURL];
                });
            }
            
            dispatch_group_wait(dispatchGroup, DISPATCH_TIME_FOREVER);
            
            if (!self.writeSingleFile || self.lastFile)
                [self writeOutputFiles];
            
            completionBlock();
        });
    } else {
        // Since writing to the same file need to do consecutively
        [self findImageSetURLs];
        
        if (!self.implementationContents)
            self.implementationContents = [NSMutableArray array];
        
        if (self.writeSingleFile)
            self.className = [[NSString stringWithFormat:@"%@ImagesCatalog", self.classPrefix] stringByReplacingOccurrencesOfString:@" " withString:@""];
        else
            self.className = [[NSString stringWithFormat:@"%@%@Catalog", self.classPrefix, [[self.inputURL lastPathComponent] stringByDeletingPathExtension]] stringByReplacingOccurrencesOfString:@" " withString:@""];
        
        for (NSURL *imageSetURL in self.imageSetURLs) {
			[self parseImageSetAtURL:imageSetURL];
        }
        
        if (!self.writeSingleFile || self.lastFile)
            [self writeOutputFiles];
        
        completionBlock();
    }
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
    NSString *imageSetName = [[url lastPathComponent] stringByDeletingPathExtension];
    NSString *methodName = [self methodNameForKey:imageSetName];
    NSURL *contentsURL = [url URLByAppendingPathComponent:@"Contents.json"];
    NSData *contentsData = [NSData dataWithContentsOfURL:contentsURL options:NSDataReadingMappedIfSafe error:NULL];
    if (!contentsData) {
        return;
    }
    
    NSMutableDictionary *contents = [[NSJSONSerialization JSONObjectWithData:contentsData options:0 error:NULL] mutableCopy];
    if (!contents) {
        return;
    }
	
    // Sort the variants: retina4 comes first, then iphone/ipad-specific, then universal
    // Within each group, 2x comes before 1x
    NSArray *variants = [contents[@"images"] sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        if (![obj1[@"subtype"] isEqualToString:obj2[@"subtype"]]) {
            if (obj1[@"subtype"]) {
                return NSOrderedDescending;
            }
            if (obj2[@"subtype"]) {
                return NSOrderedAscending;
            }
        }
        
        if (![obj1[@"idiom"] isEqualToString:obj2[@"idiom"]]) {
            if ([obj1[@"idiom"] isEqualToString:@"universal"]) {
                return NSOrderedDescending;
            }
            if ([obj2[@"idiom"] isEqualToString:@"universal"]) {
                return NSOrderedAscending;
            }
        }
        
        return -[obj1[@"scale"] compare:obj2[@"scale"]];
    }];
    
    NSMutableString *implementation = [[NSMutableString alloc] initWithFormat:@"    class func %@Image() -> UIImage? {\n", methodName];
    
    // If we're only targeting iOS 7, short circuit since the asset catalog will have been compiled for us.
    if (!self.targetiOS6) {
        [implementation appendFormat:@"        return UIImage(named: \"%@\")\n", imageSetName];
        [implementation appendString:@"    }\n\n"];
    } else {
        NSMutableArray *updatedImagesJson = [[NSMutableArray alloc] initWithCapacity:[variants count]];
        NSMutableArray *pathsToUpdate = [[NSMutableArray alloc] init];
        BOOL updateJson = NO;
        BOOL hasRetina4Inch = NO;
        BOOL hasResizing = NO;
        NSInteger numImages = 0;
        for (NSDictionary *variant in variants) {
            if (!variant[@"filename"]) {
                [updatedImagesJson addObject:variant];
                continue;
            }
            BOOL isRetina = [variant[@"scale"] floatValue] == 2.0;
            BOOL is4inch = [variant[@"subtype"] isEqualToString:@"retina4"];
            NSString *fileName = [variant[@"filename"] stringByDeletingPathExtension];
            
            numImages++;
            if (is4inch)
                hasRetina4Inch = YES;
            if (variant[@"resizing"])
                hasResizing = YES;
            
            NSString *expectedFileName;
            if (![variant[@"idiom"] isEqualToString:@"universal"] && ![variant[@"idiom"] isEqualToString:@"iphone"]){
                expectedFileName = [NSString stringWithFormat:@"%@~ipad%@", imageSetName, isRetina ? @"@2x" : @""];
            } else {
                if (is4inch){
                    expectedFileName = [NSString stringWithFormat:@"%@-568h@2x", imageSetName];
                } else {
                    expectedFileName = [NSString stringWithFormat:@"%@%@", imageSetName, isRetina ? @"@2x" : @""];
                }
            }
            if (![fileName isEqualToString:expectedFileName]){
                NSURL *currentURL = [url URLByAppendingPathComponent:variant[@"filename"]];
                NSString *newFileName = [NSString stringWithFormat:@"%@.%@", expectedFileName, [variant[@"filename"] pathExtension]];
                NSString *originalFileName = [NSString stringWithFormat:@"%@.%@", expectedFileName, [variant[@"filename"] pathExtension]];
                NSURL *destinationURL = [url URLByAppendingPathComponent:newFileName];
                NSURL *originalDestinationURL = [url URLByAppendingPathComponent:newFileName];
                NSInteger index = 0;
                while ([destinationURL checkResourceIsReachableAndReturnError:nil]) {
                    index++;
                    newFileName = [NSString stringWithFormat:@"%@-%ld.%@", expectedFileName, index++, [variant[@"filename"] pathExtension]];
                    destinationURL = [url URLByAppendingPathComponent:newFileName];
                }
                [[NSFileManager defaultManager] moveItemAtURL:currentURL toURL:destinationURL error:nil];
                if (index != 0){
                    [pathsToUpdate addObject:@{@"currentURL" : destinationURL, @"destinationURL" : originalDestinationURL}];
                }
                NSMutableDictionary *contentsToUpdate = [variant mutableCopy];
                [contentsToUpdate setObject:originalFileName forKey:@"filename"];
                [updatedImagesJson addObject:contentsToUpdate];
                updateJson = YES;
            } else {
                [updatedImagesJson addObject:variant];
            }
        }
        
        if (hasResizing){
            [implementation appendString:@"        var image: UIImage?\n\n"];
            
            for (NSDictionary *variant in variants) {
                if (!variant[@"filename"]) {
                    continue;
                }
                BOOL isUniversal = [variant[@"idiom"] isEqualToString:@"universal"];
                BOOL isRetina4Inch = [variant[@"subtype"] isEqualToString:@"retina4"];
                NSString *indentation = @"    ";
                if (!isUniversal) {
                    indentation = @"        ";
                    NSString *idiom = [variant[@"idiom"] isEqualToString:@"iphone"] ? @"Phone" : @"Pad";
                    [implementation appendFormat:@"%@if (UIDevice.currentDevice().userInterfaceIdiom == UIUserInterfaceIdiom.%@%@) {\n", indentation, idiom, isRetina4Inch ? @" && UIScreen.mainScreen().bounds.height == 568.0" : @""];
                }
                
                CGFloat scale = [variant[@"scale"] floatValue];
                NSString *scaleIndentation = [indentation stringByAppendingString:@"    "];
                [implementation appendFormat:@"%@    if (UIScreen.mainScreen().scale == %.1f || image == nil) {\n", scaleIndentation, scale];
                [implementation appendFormat:@"%@        var tempImage: UIImage? = UIImage(named: \"%@%@\")\n", scaleIndentation, imageSetName, (isRetina4Inch ? @"-568h" : @"")];
                
                NSDictionary *resizing = variant[@"resizing"];
                if (resizing) {
                    CGFloat top = [resizing[@"capInsets"][@"top"] floatValue] / scale;
                    CGFloat left = [resizing[@"capInsets"][@"left"] floatValue] / scale;
                    CGFloat bottom = [resizing[@"capInsets"][@"bottom"] floatValue] / scale;
                    CGFloat right = [resizing[@"capInsets"][@"right"] floatValue] / scale;
                    NSString *mode = [resizing[@"center"][@"mode"] isEqualToString:@"stretch"] ? @"Stretch" : @"Tile";
                    [implementation appendFormat:@"%@        if (tempImage != nil) {\n", scaleIndentation];
                    [implementation appendFormat:@"%@            image = tempImage?.resizableImageWithCapInsets(UIEdgeInsetsMake(%.1f, %.1f, %.1f, %.1f), resizingMode: UIImageResizingMode.%@)\n", scaleIndentation, top, left, bottom, right, mode];
                    [implementation appendFormat:@"%@        }\n", scaleIndentation];
                } else {
                    [implementation appendFormat:@"%@        if (tempImage != nil) {\n", scaleIndentation];
                    [implementation appendFormat:@"%@            image = tempImage\n", scaleIndentation];
                    [implementation appendFormat:@"%@        }\n", scaleIndentation];
                }
                
                [implementation appendFormat:@"%@    }\n", scaleIndentation];
                
                if (!isUniversal) {
                    [implementation appendFormat:@"%@}\n", indentation];
                }
                
                [implementation appendString:@"\n"];
            }
            
            [implementation appendString:@"        return image\n"];
            [implementation appendString:@"    }\n"];
        } else if (hasRetina4Inch){
            if (numImages == 1){
                [implementation appendFormat:@"        return UIImage(named: \"%@-568h\")\n", imageSetName];
                [implementation appendString:@"    }\n"];
            } else {
                [implementation appendString:@"        var image: UIImage?\n\n"];
                [implementation appendString:@"        if (UIDevice.currentDevice().userInterfaceIdiom == UIUserInterfaceIdiom.Phone && UIScreen.mainScreen().bounds.height == 568.0) {\n"];
                [implementation appendString:@"            if (UIScreen.mainScreen().scale == 2.0) {\n"];
                [implementation appendFormat:@"                image = UIImage(named: \"%@-568h\")\n", imageSetName];
                [implementation appendString:@"            }\n"];
                [implementation appendString:@"        }\n\n"];
                [implementation appendString:@"        if (image == nil) {\n"];
                [implementation appendFormat:@"            image = UIImage(named: \"%@\")\n", imageSetName];
                [implementation appendString:@"        }\n\n"];
                [implementation appendString:@"        return image\n"];
                [implementation appendString:@"    }\n"];
            }
        } else {
            [implementation appendFormat:@"        return UIImage(named: \"%@\")\n", imageSetName];
            [implementation appendString:@"    }\n\n"];
        }
        
        if (updateJson){
            [contents setObject:updatedImagesJson forKey:@"images"];
            NSData *formattedJson = [NSJSONSerialization dataWithJSONObject:contents options:NSJSONWritingPrettyPrinted error:nil];
            [formattedJson writeToURL:contentsURL atomically:YES];
            
            for (NSDictionary *nextPath in pathsToUpdate){
                [[NSFileManager defaultManager] moveItemAtURL:nextPath[@"currentURL"] toURL:nextPath[@"destinationURL"] error:nil];
            }
        }
    }

    @synchronized(self.implementationContents) {
        [self.implementationContents addObject:implementation];
    }
}

@end
