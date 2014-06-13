//
//  CDColorListDumper.m
//  codegenutils
//
//  Created by Jim Puls on 9/6/13.
//  Licensed to Square, Inc. under one or more contributor license agreements.
//  See the LICENSE file distributed with this work for the terms under
//  which Square, Inc. licenses this file to you.

#import "CDColorListDumper.h"


@implementation CDColorListDumper

+ (NSArray *)inputFileExtension;
{
    return @[@"clr"];
}

- (void)startWithCompletionHandler:(dispatch_block_t)completionBlock;
{
    NSString *colorListName = [[self.inputURL lastPathComponent] stringByDeletingPathExtension];
    
    if (self.writeSingleFile)
        self.className = [[NSString stringWithFormat:@"%@AppColorList", self.classPrefix] stringByReplacingOccurrencesOfString:@" " withString:@""];
    else
        self.className = [[NSString stringWithFormat:@"%@%@ColorList", self.classPrefix, colorListName] stringByReplacingOccurrencesOfString:@" " withString:@""];

    NSColorList *colorList = [[NSColorList alloc] initWithName:colorListName fromFile:self.inputURL.path];
    
    // Install this color list
    [colorList writeToFile:nil];
    
    if (!self.implementationContents)
        self.implementationContents = [NSMutableArray array];
    
    for (NSString *key in colorList.allKeys) {
        NSColor *color = [colorList colorWithKey:key];
        if (![color.colorSpaceName isEqualToString:NSDeviceRGBColorSpace]) {
            printf("Color %s isn't device RGB. Skipping.", [key UTF8String]);
            continue;
        }
        
        CGFloat r, g, b, a;
        [color getRed:&r green:&g blue:&b alpha:&a];
        
        NSMutableString *method = [[NSMutableString alloc] initWithFormat:@"    class func %@Color() -> UIColor", [self methodNameForKey:key]];
        [method appendFormat:@"{\n        return UIColor(red: %.3f, green: %.3f, blue: %.3f, alpha: %.3f)\n    }\n\n", r, g, b, a];
        [self.implementationContents addObject:method];
    }
    
    if (!self.writeSingleFile || self.lastFile)
        [self writeOutputFiles];
    completionBlock();
}

@end
