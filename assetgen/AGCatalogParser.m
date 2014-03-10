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
            
            if (!self.interfaceContents)
                self.interfaceContents = [NSMutableArray array];
            if (!self.implementationContents)
                self.implementationContents = [NSMutableArray array];
            
            if (self.writeSingleFile)
                self.className = [[NSString stringWithFormat:@"%@ImageCatalog", self.classPrefix] stringByReplacingOccurrencesOfString:@" " withString:@""];
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
        
        if (!self.interfaceContents)
            self.interfaceContents = [NSMutableArray array];
        if (!self.implementationContents)
            self.implementationContents = [NSMutableArray array];
        
        if (self.writeSingleFile)
            self.className = [[NSString stringWithFormat:@"%@ImageCatalog", self.classPrefix] stringByReplacingOccurrencesOfString:@" " withString:@""];
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
    
    NSDictionary *contents = [NSJSONSerialization JSONObjectWithData:contentsData options:0 error:NULL];
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

    NSString *interface = [NSString stringWithFormat:@"+ (UIImage *)%@Image;\n", methodName];
    @synchronized(self.interfaceContents) {
        [self.interfaceContents addObject:interface];
    }
    
    NSMutableString *implementation = [interface mutableCopy];
    [implementation appendString:@"{\n"];
    
    // If we're only targeting iOS 7, short circuit since the asset catalog will have been compiled for us.
    if (!self.targetiOS6) {
        [implementation appendFormat:@"    return [UIImage imageNamed:@\"%@\"];\n", imageSetName];
        [implementation appendString:@"}\n"];
    } else {
        
        // If there are only one or two variants and they only differ by 1x or 2x and they're not resizable, short circuit
        BOOL shortCircuit = (variants.count == 1);
        if (variants.count == 2) {
            if (!variants[0][@"resizing"] && !variants[1][@"resizing"]) {
                NSString *filename1 = [variants[0][@"filename"] stringByReplacingOccurrencesOfString:@"@2x" withString:@""];
                NSString *filename2 = [variants[1][@"filename"] stringByReplacingOccurrencesOfString:@"@2x" withString:@""];
                shortCircuit = [filename1 isEqualToString:filename2];
            }
        }
        if (shortCircuit) {
            [implementation appendFormat:@"    return [UIImage imageNamed:@\"%@\"];\n", [variants lastObject][@"filename"]];
            [implementation appendString:@"}\n"];

        } else {
            [implementation appendString:@"    UIImage *image = nil;\n\n"];
            
            for (NSDictionary *variant in variants) {
                if (!variant[@"filename"]) {
                    continue;
                }
                BOOL isUniversal = [variant[@"idiom"] isEqualToString:@"universal"];
                BOOL isRetina4Inch = [variant[@"subtype"] isEqualToString:@"retina4"];
                NSString *indentation = @"";
                if (!isUniversal) {
                    NSString *idiom = [variant[@"idiom"] isEqualToString:@"iphone"] ? @"UIUserInterfaceIdiomPhone" : @"UIUserInterfaceIdiomPad";
                    [implementation appendFormat:@"    if (UI_USER_INTERFACE_IDIOM() == %@%@) {\n", idiom, isRetina4Inch ? @" && [UIScreen mainScreen].bounds.size.height == 568.0f" : @""];
                    indentation = @"    ";
                }
                
                CGFloat scale = [variant[@"scale"] floatValue];
                NSString *sizeExtension = isRetina4Inch ? @"-568h" : @"";
                NSString *filename = [variant[@"filename"] stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"@%@", variant[@"scale"]] withString:sizeExtension];
                NSString *scaleIndentation = [indentation stringByAppendingString:@"    "];
                [implementation appendFormat:@"%@if ([UIScreen mainScreen].scale == %.1ff) {\n", scaleIndentation, scale];
                [implementation appendFormat:@"%@    image = [UIImage imageNamed:@\"%@\"];\n", scaleIndentation, filename];
                
                NSDictionary *resizing = variant[@"resizing"];
                if (resizing) {
                    CGFloat top = [resizing[@"capInsets"][@"top"] floatValue] / scale;
                    CGFloat left = [resizing[@"capInsets"][@"left"] floatValue] / scale;
                    CGFloat bottom = [resizing[@"capInsets"][@"bottom"] floatValue] / scale;
                    CGFloat right = [resizing[@"capInsets"][@"right"] floatValue] / scale;
                    NSString *mode = [resizing[@"center"][@"mode"] isEqualToString:@"stretch"] ? @"UIImageResizingModeStretch" : @"UIImageResizingModeTile";
                    
                    [implementation appendFormat:@"%@    image = [image resizableImageWithCapInsets:UIEdgeInsetsMake(%.1ff, %.1ff, %.1ff, %.1ff) resizingMode:%@];\n", scaleIndentation, top, left, bottom, right, mode];
                }
                
                [implementation appendFormat:@"%@}\n", scaleIndentation];
                
                if (!isUniversal) {
                    [implementation appendFormat:@"%@}\n", indentation];
                }
                
                [implementation appendString:@"\n"];
            }
            
            [implementation appendString:@"    return image;\n"];
            [implementation appendString:@"}\n"];
        }
    }
    
    @synchronized(self.implementationContents) {
        [self.implementationContents addObject:implementation];
    }
}

@end
