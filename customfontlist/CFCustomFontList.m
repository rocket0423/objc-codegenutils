//
//  CFCustomFontList.m
//  codegenutils
//
//  Created by Justin Carstens on 3/10/14.
//  Copyright (c) 2014 Square, Inc. All rights reserved.
//

#import "CFCustomFontList.h"

@implementation CFCustomFontList

+ (NSArray *)inputFileExtension;
{
    return @[@"ttf"];
}

- (void)startWithCompletionHandler:(dispatch_block_t)completionBlock;
{
    NSString *fontFileName = [[self.inputURL lastPathComponent] stringByDeletingPathExtension];
    if (self.writeSingleFile)
        self.className = [NSString stringWithFormat:@"%@FontList", self.classPrefix];
    else
        self.className = [NSString stringWithFormat:@"%@%@Font", self.classPrefix, fontFileName];
    if (!self.interfaceContents)
        self.interfaceContents = [NSMutableArray array];
    if (!self.implementationContents)
        self.implementationContents = [NSMutableArray array];
    
    NSString *fontName = [CFCustomFontList fontNameFromTTFPath:self.inputURL];
    if (fontName){
        NSString *declaration = [NSString stringWithFormat:@"+ (UIFont *)%@FontOfSize:(CGFloat)fontSize;\n", [self methodNameForKey:fontName]];
        if (self.uniqueItemCheck || ![self.interfaceContents containsObject:declaration]) {
            [self.interfaceContents addObject:declaration];
            
            NSMutableString *method = [declaration mutableCopy];
            [method appendFormat:@"{\n    return [UIFont fontWithName:@\"%@\" size:fontSize];\n}\n", fontName];
            [self.implementationContents addObject:method];
        }
    }
    
    if (!self.writeSingleFile || self.lastFile)
        [self writeOutputFiles];
    
    completionBlock();
}

+ (NSString *)fontNameFromTTFPath:(NSURL*)fontPath;
{
    CGDataProviderRef dataProvider = CGDataProviderCreateWithURL((__bridge CFURLRef)(fontPath));
    if (NULL==dataProvider)
        return nil;
    
    // Create the font with the data provider, then release the data provider.
    CGFontRef fontRef = CGFontCreateWithDataProvider(dataProvider);
    if (NULL == fontRef)
    {
        CGDataProviderRelease(dataProvider);
        return nil;
    }
    
    CTFontRef fontCore = CTFontCreateWithGraphicsFont(fontRef, 30, NULL, NULL);
    CGDataProviderRelease(dataProvider);
    CGFontRelease(fontRef);
    return CFBridgingRelease(CTFontCopyPostScriptName(fontCore));
}

@end
