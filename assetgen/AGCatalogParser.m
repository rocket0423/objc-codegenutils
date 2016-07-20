//
//  AGCatalogParser.m
//  assetgen
//
//  Created by Jim Puls on 8/29/13.
//  Licensed to Square, Inc. under one or more contributor license agreements.
//  See the LICENSE file distributed with this work for the terms under
//  which Square, Inc. licenses this file to you.

#import "AGCatalogParser.h"


@interface AGCatalogParser () {
    NSMutableArray *currentImages;
    NSString *usedImageString;
}

@property (strong) NSArray *imageSetURLs;

@end


@implementation AGCatalogParser

+ (NSArray *)inputFileExtension;
{
    return @[@"xcassets"];
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        currentImages = [[NSMutableArray alloc] init];
    }
    return self;
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
                self.implementationContents = [[NSMutableArray alloc] init];
            if (!self.objcItems && self.targetObjC)
                self.objcItems = [[NSMutableArray alloc] init];
            
            
            if (self.writeSingleFile)
                self.className = [[NSString stringWithFormat:@"%@Images", self.classPrefix] stringByReplacingOccurrencesOfString:@" " withString:@""];
            else
                self.className = [[NSString stringWithFormat:@"%@%@Catalog", self.classPrefix, [[self.inputURL lastPathComponent] stringByDeletingPathExtension]] stringByReplacingOccurrencesOfString:@" " withString:@""];
            
            // Get the verify images
            if (self.verifyItems && usedImageString == nil) {
                [self findUsedImages];
            }
            
            dispatch_group_async(dispatchGroup, dispatchQueue, ^{
                for (NSURL *imageSetURL in self.imageSetURLs) {
                    [self parseImageSetAtURL:imageSetURL];
                }
                if (!self.writeSingleFile || self.lastFile) {
                    if (self.hasWarning) {
                        [self writeWarning];
                    }
                }
            });
            
            dispatch_group_wait(dispatchGroup, DISPATCH_TIME_FOREVER);
            if (!self.writeSingleFile || self.lastFile) {
                [self writeOutputFiles];
            }
            
            completionBlock();
        });
    } else {
        // Since writing to the same file need to do consecutively
        [self findImageSetURLs];
        
        if (!self.implementationContents)
            self.implementationContents = [NSMutableArray array];
        if (!self.objcItems && self.targetObjC)
            self.objcItems = [NSMutableArray array];
        
        if (self.writeSingleFile)
            self.className = [[NSString stringWithFormat:@"%@Images", self.classPrefix] stringByReplacingOccurrencesOfString:@" " withString:@""];
        else
            self.className = [[NSString stringWithFormat:@"%@%@Catalog", self.classPrefix, [[self.inputURL lastPathComponent] stringByDeletingPathExtension]] stringByReplacingOccurrencesOfString:@" " withString:@""];
        
        // Get the verify images
        if (self.verifyItems && usedImageString == nil) {
            [self findUsedImages];
        }
        
        for (NSURL *imageSetURL in self.imageSetURLs) {
            [self parseImageSetAtURL:imageSetURL];
        }
        
        if (!self.writeSingleFile || self.lastFile) {
            if (self.verifyItems && self.writeSingleFile) {
                // Only works for single file
                [self checkStoryboardNibs];
            }
            if (self.hasWarning) {
                [self writeWarning];
            }
            [self writeOutputFiles];
        }
        
        completionBlock();
    }
}

- (void)writeWarning {
    if (self.targetObjC){
        return;
    }
    NSMutableString *implementation = [[NSMutableString alloc] init];
    [implementation appendString:@"    /// Warning message so console is notified.\n"];
    [implementation appendString:@"    @available(iOS, deprecated=1.0, message=\"Image Not Used\")\n"];
    [implementation appendString:@"    private class func ImageNotUsed(){}\n\n"];
    
    @synchronized(self.implementationContents) {
        [self.implementationContents addObject:implementation];
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

- (void)findUsedImages {
    NSString *absolutePath = [[[self.searchingURL absoluteString] substringFromIndex:7] stringByReplacingPercentEscapesUsingEncoding:NSStringEncodingConversionAllowLossy];
    
    // Extensions
    NSArray *extensionsToCheck = @[@"swift", @"m", @"storyboard", @"xib", @"html", @"css"];
    NSMutableString *includeExtensionsString = [[NSMutableString alloc] init];
    for (NSString *extension in extensionsToCheck){
        [includeExtensionsString appendFormat:@" --include=*.%@", extension];
    }
    
    // Patterns
    NSMutableString *commandPatterns = [[NSMutableString alloc] init];
    [commandPatterns appendFormat:@" -e \"image=\\\"*\\\"\""];
    [commandPatterns appendFormat:@" -e \"Images\\.*\""];
    [commandPatterns appendFormat:@" -e \"Images *\""];
    
    // Command
    NSString *command = [NSString stringWithFormat:@"grep -i -r%@%@ \"%@\"", includeExtensionsString, commandPatterns, absolutePath];
    usedImageString = [CGUCodeGenTool runStringAsCommand:command];
}

- (void)checkStoryboardNibs {
    // Get hte storyboard and Nib Images
    NSMutableArray *missingImages = [[NSMutableArray alloc] init];
    NSString *absolutePath = [[[self.searchingURL absoluteString] substringFromIndex:7] stringByReplacingPercentEscapesUsingEncoding:NSStringEncodingConversionAllowLossy];
    
    // Extensions
    NSArray *extensionsToCheck = @[@"storyboard", @"xib"];
    NSMutableString *includeExtensionsString = [[NSMutableString alloc] init];
    for (NSString *extension in extensionsToCheck){
        [includeExtensionsString appendFormat:@" --include=*.%@", extension];
    }
    
    NSString *command = [NSString stringWithFormat:@"grep -i -r%@ \"image=\\\"*\\\"\" \"%@\"", includeExtensionsString, absolutePath];
    NSString *result = [CGUCodeGenTool runStringAsCommand:command];
    if (result){
        // Remove the results from pods because we have no control over those.
        NSArray *results = [result componentsSeparatedByString:@"\n"];
        NSMutableArray *nonPodResults = [[NSMutableArray alloc] initWithCapacity:[results count]];
        NSLog(@"%@", [absolutePath stringByAppendingString:@"/Pods"]);
        for (NSString *nextResult in results) {
            NSLog(@"%@", nextResult);
            if (![nextResult hasPrefix:[absolutePath stringByAppendingString:@"/Pods"]]) {
                [nonPodResults addObject:nextResult];
            }
        }
        result = [nonPodResults componentsJoinedByString:@"\n"];
        
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"image=\".*?\"" options:0 error:NULL];
        NSArray *regexMatches = [regex matchesInString:result options:0 range:NSMakeRange(0, [result length])];
        for (NSTextCheckingResult *match in regexMatches) {
            NSString *fullString = [result substringWithRange:[match rangeAtIndex:0]];
            NSString *imageName = [fullString substringWithRange:NSMakeRange(7, [fullString length] - 8)];
            if (![currentImages containsObject:imageName]) {
                [missingImages addObject:imageName];
            }
        }
    }
    
    // Show the warnings
    for (NSString *nextImage in missingImages) {
        NSMutableString *implementation = [[NSMutableString alloc] init];
        if (self.targetObjC) {
            [implementation appendFormat:@"#warning Storyboard or Nib has a missing image '%@'\n", nextImage];
        } else {
            [implementation appendFormat:@"    // Storyboard or Nib has a missing image '%@'\n", nextImage];
            [implementation appendFormat:@"    private var %@: UIImage? {\n", [self methodNameForKey:nextImage]];
            [implementation appendString:@"        MissingImage()\n"];
            [implementation appendFormat:@"        return nil\n"];
            [implementation appendString:@"    }\n\n"];
        }
        
        @synchronized(self.implementationContents) {
            [self.implementationContents addObject:implementation];
        }
    }
    
    // Write Error Function For Swift so warning will show
    if ([missingImages count] > 0 && !self.targetObjC) {
        NSMutableString *implementation = [[NSMutableString alloc] init];
        [implementation appendString:@"    /// Warning message so console is notified.\n"];
        [implementation appendString:@"    @available(iOS, deprecated=1.0, message=\"Missing Storyboard or Nib Image\")\n"];
        [implementation appendString:@"    private func MissingImage(){}\n\n"];
        
        @synchronized(self.implementationContents) {
            [self.implementationContents addObject:implementation];
        }
    }
}

- (void)parseImageSetAtURL:(NSURL *)url;
{
    NSString *imageSetName = [[url lastPathComponent] stringByDeletingPathExtension];
    [currentImages addObject:imageSetName];
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
    
    BOOL templateImage = NO;
    if ([contents objectForKey:@"info"]){
        NSDictionary *info = [contents objectForKey:@"info"];
        if ([info objectForKey:@"template-rendering-intent"] && [[info objectForKey:@"template-rendering-intent"] isEqualToString:@"template"]){
            templateImage = YES;
        }
    }
    
    BOOL usedImage = [self usedImage:imageSetName];
    
    NSMutableString *implementation;
    if (self.targetObjC){
        NSString *interface = [NSString stringWithFormat:@"+ (UIImage *)%@;\n", methodName];
        @synchronized(self.objcItems) {
            [self.objcItems addObject:interface];
        }
        
        implementation = [interface mutableCopy];
        [implementation appendString:@"{\n"];
        if (self.verifyItems && !usedImage) {
            [implementation appendString:@"#warning UIImage Not Used\n"];
        }
    } else {
        implementation = [[NSMutableString alloc] initWithFormat:@"    static var %@: UIImage? {\n", methodName];
        if (self.verifyItems && !usedImage) {
            self.hasWarning = YES;
            [implementation appendString:@"        ImageNotUsed()\n"];
        }
    }
    
    // If we're only targeting iOS 7, short circuit since the asset catalog will have been compiled for us.
    if (self.appVersion >= 8.0){
        // iOS 8 compiles template template
        if (self.targetObjC){
            [implementation appendFormat:@"    return [UIImage imageNamed:@\"%@\"];\n", imageSetName];
            [implementation appendString:@"}\n"];
        } else {
            [implementation appendFormat:@"        return UIImage(named: \"%@\")\n", imageSetName];
            [implementation appendString:@"    }\n\n"];
        }
    } else if (self.appVersion >= 7.0) {
        if (self.targetObjC){
            if (templateImage) {
                [implementation appendFormat:@"    return [[UIImage imageNamed:@\"%@\"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];\n", imageSetName];
            } else {
                [implementation appendFormat:@"    return [UIImage imageNamed:@\"%@\"];\n", imageSetName];
            }
            [implementation appendString:@"}\n"];
        } else {
            if (templateImage) {
                [implementation appendFormat:@"        return UIImage(named: \"%@\")?.imageWithRenderingMode(UIImageRenderingMode.AlwaysTemplate)\n", imageSetName];
            } else {
                [implementation appendFormat:@"        return UIImage(named: \"%@\")\n", imageSetName];
            }
            [implementation appendString:@"    }\n\n"];
        }
    } else {
        implementation = [self oldiOS6Implementation:contents imageSetName:imageSetName url:url contentsURL:contentsURL];
    }
    
    @synchronized(self.implementationContents) {
        [self.implementationContents addObject:implementation];
    }
}

- (BOOL)usedImage:(NSString *)imageSetName{
    if (usedImageString == nil) {
        return NO;
    }
    if ([usedImageString containsString:[NSString stringWithFormat:@"image=\"%@\"", imageSetName]]) {
        return YES;
    }
    NSString *methodName = [self methodNameForKey:imageSetName];
    if ([usedImageString containsString:[NSString stringWithFormat:@"Images.%@", methodName]]) {
        return YES;
    }
    if ([usedImageString containsString:[NSString stringWithFormat:@"Images %@]", methodName]]) {
        return YES;
    }
    return NO;
}

- (NSMutableString *)oldiOS6Implementation:(NSMutableDictionary *)contents imageSetName:(NSString *)imageSetName url:(NSURL *)url contentsURL:(NSURL *)contentsURL{
    NSMutableString *implementation;
    
    BOOL templateImage = NO;
    if ([contents objectForKey:@"info"]){
        NSDictionary *info = [contents objectForKey:@"info"];
        if ([info objectForKey:@"template-rendering-intent"] && [[info objectForKey:@"template-rendering-intent"] isEqualToString:@"template"]){
            templateImage = YES;
        }
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
        NSString *scaleSuffix = @"";
        if ([variant[@"scale"] floatValue] >= 2.0){
            scaleSuffix = [NSString stringWithFormat:@"@%ldx", (long)[variant[@"scale"] integerValue]];
        }
        BOOL is4inch = [variant[@"subtype"] isEqualToString:@"retina4"];
        NSString *fileName = [variant[@"filename"] stringByDeletingPathExtension];
        
        numImages++;
        if (is4inch)
            hasRetina4Inch = YES;
        if (variant[@"resizing"])
            hasResizing = YES;
        
        NSString *expectedFileName;
        if (![variant[@"idiom"] isEqualToString:@"universal"] && ![variant[@"idiom"] isEqualToString:@"iphone"]){
            expectedFileName = [NSString stringWithFormat:@"%@~ipad%@", imageSetName, scaleSuffix];
        } else {
            if (is4inch){
                expectedFileName = [NSString stringWithFormat:@"%@-568h@2x", imageSetName];
            } else {
                expectedFileName = [NSString stringWithFormat:@"%@%@", imageSetName, scaleSuffix];
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
        if (self.targetObjC){
            [implementation appendString:@"    UIImage *image = nil;\n\n"];
        } else {
            [implementation appendString:@"        var image: UIImage?\n\n"];
        }
        
        for (NSDictionary *variant in variants) {
            if (!variant[@"filename"]) {
                continue;
            }
            BOOL isUniversal = [variant[@"idiom"] isEqualToString:@"universal"];
            BOOL isRetina4Inch = [variant[@"subtype"] isEqualToString:@"retina4"];
            NSString *indentation = @"";
            if (!self.targetObjC){
                indentation = @"    ";
            }
            if (!isUniversal) {
                NSString *idiom = [variant[@"idiom"] isEqualToString:@"iphone"] ? @"Phone" : @"Pad";
                if (self.targetObjC){
                    indentation = @"    ";
                    [implementation appendFormat:@"    if (UI_USER_INTERFACE_IDIOM() == %@%@) {\n", idiom, isRetina4Inch ? @" && [UIScreen mainScreen].bounds.size.height == 568.0f" : @""];
                } else {
                    indentation = @"        ";
                    [implementation appendFormat:@"%@if (UIDevice.currentDevice().userInterfaceIdiom == UIUserInterfaceIdiom.%@%@) {\n", indentation, idiom, isRetina4Inch ? @" && UIScreen.mainScreen().bounds.height == 568.0" : @""];
                }
            }
            
            CGFloat scale = [variant[@"scale"] floatValue];
            if (scale <= 0){
                scale = 1.0;
            }
            NSString *scaleIndentation = [indentation stringByAppendingString:@"    "];
            if (self.targetObjC){
                [implementation appendFormat:@"%@if ([UIScreen mainScreen].scale == %.1ff || image == nil) {\n", scaleIndentation, scale];
                if (templateImage){
                    [implementation appendFormat:@"%@    UIImage *tempImage = [[UIImage imageNamed:@\"%@%@\"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];\n", scaleIndentation, imageSetName, (isRetina4Inch ? @"-568h" : @"")];
                } else {
                    [implementation appendFormat:@"%@    UIImage *tempImage = [UIImage imageNamed:@\"%@%@\"];\n", scaleIndentation, imageSetName, (isRetina4Inch ? @"-568h" : @"")];
                }
            } else {
                [implementation appendFormat:@"%@    if (UIScreen.mainScreen().scale == %.1f || image == nil) {\n", scaleIndentation, scale];
                if (templateImage){
                    [implementation appendFormat:@"%@        var tempImage: UIImage? = UIImage(named: \"%@%@\")?.imageWithRenderingMode(UIImageRenderingMode.AlwaysTemplate)\n", scaleIndentation, imageSetName, (isRetina4Inch ? @"-568h" : @"")];
                } else {
                    [implementation appendFormat:@"%@        var tempImage: UIImage? = UIImage(named: \"%@%@\")\n", scaleIndentation, imageSetName, (isRetina4Inch ? @"-568h" : @"")];
                }
            }
            
            NSDictionary *resizing = variant[@"resizing"];
            if (resizing) {
                CGFloat top = [resizing[@"capInsets"][@"top"] floatValue] / scale;
                CGFloat left = [resizing[@"capInsets"][@"left"] floatValue] / scale;
                CGFloat bottom = [resizing[@"capInsets"][@"bottom"] floatValue] / scale;
                CGFloat right = [resizing[@"capInsets"][@"right"] floatValue] / scale;
                if (self.targetObjC){
                    NSString *mode = [resizing[@"center"][@"mode"] isEqualToString:@"stretch"] ? @"UIImageResizingModeStretch" : @"UIImageResizingModeTile";
                    [implementation appendFormat:@"%@    if(tempImage != nil){\n", scaleIndentation];
                    [implementation appendFormat:@"%@        image = [tempImage resizableImageWithCapInsets:UIEdgeInsetsMake(%.1ff, %.1ff, %.1ff, %.1ff) resizingMode:%@];\n", scaleIndentation, top, left, bottom, right, mode];
                    [implementation appendFormat:@"%@    }\n", scaleIndentation];
                } else {
                    NSString *mode = [resizing[@"center"][@"mode"] isEqualToString:@"stretch"] ? @"Stretch" : @"Tile";
                    [implementation appendFormat:@"%@        if (tempImage != nil) {\n", scaleIndentation];
                    [implementation appendFormat:@"%@            image = tempImage?.resizableImageWithCapInsets(UIEdgeInsetsMake(%.1f, %.1f, %.1f, %.1f), resizingMode: UIImageResizingMode.%@)\n", scaleIndentation, top, left, bottom, right, mode];
                    [implementation appendFormat:@"%@        }\n", scaleIndentation];
                }
            } else {
                if (self.targetObjC){
                    [implementation appendFormat:@"%@    if(tempImage != nil){\n", scaleIndentation];
                    [implementation appendFormat:@"%@        image = tempImage;\n", scaleIndentation];
                    [implementation appendFormat:@"%@    }\n", scaleIndentation];
                } else {
                    [implementation appendFormat:@"%@        if (tempImage != nil) {\n", scaleIndentation];
                    [implementation appendFormat:@"%@            image = tempImage\n", scaleIndentation];
                    [implementation appendFormat:@"%@        }\n", scaleIndentation];
                }
            }
            
            if (self.targetObjC){
                [implementation appendFormat:@"%@}\n", scaleIndentation];
            } else {
                [implementation appendFormat:@"%@    }\n", scaleIndentation];
            }
            
            if (!isUniversal) {
                [implementation appendFormat:@"%@}\n", indentation];
            }
            
            [implementation appendString:@"\n"];
        }
        
        if (self.targetObjC){
            [implementation appendString:@"    return image;\n"];
            [implementation appendString:@"}\n"];
        } else {
            [implementation appendString:@"        return image\n"];
            [implementation appendString:@"    }\n"];
        }
    } else if (hasRetina4Inch){
        if (numImages == 1){
            if (self.targetObjC){
                if (templateImage){
                    [implementation appendFormat:@"    return [[UIImage imageNamed:@\"%@-568h\"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];\n", imageSetName];
                } else {
                    [implementation appendFormat:@"    return [UIImage imageNamed:@\"%@-568h\"];\n", imageSetName];
                }
                [implementation appendString:@"}\n"];
                
            } else {
                if (templateImage){
                    [implementation appendFormat:@"        return UIImage(named: \"%@-568h\")?.imageWithRenderingMode(UIImageRenderingMode.AlwaysTemplate)\n", imageSetName];
                } else {
                    [implementation appendFormat:@"        return UIImage(named: \"%@-568h\")\n", imageSetName];
                }
                [implementation appendString:@"    }\n"];
            }
        } else {
            if (self.targetObjC){
                [implementation appendString:@"    UIImage *image = nil;\n\n"];
                [implementation appendString:@"    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone && [UIScreen mainScreen].bounds.size.height == 568.0f) {\n"];
                [implementation appendString:@"        if ([UIScreen mainScreen].scale == 2.0f) {\n"];
                if (templateImage){
                    [implementation appendFormat:@"            image = [[UIImage imageNamed:@\"%@-568h\"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];\n", imageSetName];
                } else {
                    [implementation appendFormat:@"            image = [UIImage imageNamed:@\"%@-568h\"];\n", imageSetName];
                }
                [implementation appendString:@"        }\n"];
                [implementation appendString:@"    }\n\n"];
                [implementation appendString:@"    if (image == nil){\n"];
                if (templateImage){
                    [implementation appendFormat:@"        image = [[UIImage imageNamed:@\"%@\"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];\n", imageSetName];
                } else {
                    [implementation appendFormat:@"        image = [UIImage imageNamed:@\"%@\"];\n", imageSetName];
                }
                [implementation appendString:@"    }\n\n"];
                [implementation appendString:@"    return image;\n"];
                [implementation appendString:@"}\n"];
            } else {
                [implementation appendString:@"        var image: UIImage?\n\n"];
                [implementation appendString:@"        if (UIDevice.currentDevice().userInterfaceIdiom == UIUserInterfaceIdiom.Phone && UIScreen.mainScreen().bounds.height == 568.0) {\n"];
                [implementation appendString:@"            if (UIScreen.mainScreen().scale == 2.0) {\n"];
                if (templateImage){
                    [implementation appendFormat:@"                image = UIImage(named: \"%@-568h\")?.imageWithRenderingMode(UIImageRenderingMode.AlwaysTemplate)\n", imageSetName];
                } else {
                    [implementation appendFormat:@"                image = UIImage(named: \"%@-568h\")\n", imageSetName];
                }
                [implementation appendString:@"            }\n"];
                [implementation appendString:@"        }\n\n"];
                [implementation appendString:@"        if (image == nil) {\n"];
                if (templateImage){
                    [implementation appendFormat:@"            image = UIImage(named: \"%@\")?.imageWithRenderingMode(UIImageRenderingMode.AlwaysTemplate)\n", imageSetName];
                } else {
                    [implementation appendFormat:@"            image = UIImage(named: \"%@\")\n", imageSetName];
                }
                [implementation appendString:@"        }\n\n"];
                [implementation appendString:@"        return image\n"];
                [implementation appendString:@"    }\n"];
            }
        }
    } else {
        if (self.targetObjC){
            if (templateImage){
                [implementation appendFormat:@"    return [[UIImage imageNamed:@\"%@\"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];\n", imageSetName];
            } else {
                [implementation appendFormat:@"    return [UIImage imageNamed:@\"%@\"];\n", imageSetName];
            }
            [implementation appendString:@"}\n"];
        } else {
            if (templateImage){
                [implementation appendFormat:@"        return UIImage(named: \"%@\")?.imageWithRenderingMode(UIImageRenderingMode.AlwaysTemplate)\n", imageSetName];
            } else {
                [implementation appendFormat:@"        return UIImage(named: \"%@\")\n", imageSetName];
            }
            [implementation appendString:@"    }\n\n"];
        }
    }
    
    if (updateJson){
        [contents setObject:updatedImagesJson forKey:@"images"];
        NSData *formattedJson = [NSJSONSerialization dataWithJSONObject:contents options:NSJSONWritingPrettyPrinted error:nil];
        [formattedJson writeToURL:contentsURL atomically:YES];
        
        for (NSDictionary *nextPath in pathsToUpdate){
            [[NSFileManager defaultManager] moveItemAtURL:nextPath[@"currentURL"] toURL:nextPath[@"destinationURL"] error:nil];
        }
    }
    return implementation;
}

@end
