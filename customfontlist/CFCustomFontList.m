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
    if (!self.implementationContents)
        self.implementationContents = [NSMutableArray array];
    
    NSString *fontName = [CFCustomFontList fontNameFromTTFPath:self.inputURL];
    if (fontName){
        NSMutableString *method = [[NSMutableString alloc] initWithFormat:@"    class func %@FontOfSize(fontSize : CGFloat) -> UIFont {", [self methodNameForKey:fontName]];
        [method appendFormat:@"\n        return UIFont(name: \"%@\", size: fontSize)\n    }\n\n", fontName];
        if (self.uniqueItemCheck || ![self.implementationContents containsObject:method]) {
            [self.implementationContents addObject:method];
            
            if (self.infoPlistFile.length > 0){
                NSMutableDictionary *plist = [NSMutableDictionary dictionaryWithContentsOfFile:self.infoPlistFile];
                if (plist){
                    NSString *fontKey = @"UIAppFonts";
                    NSMutableArray *fontList;
                    if ([[plist allKeys] containsObject:fontKey]){
                        fontList = [plist objectForKey:fontKey];
                    } else {
                        fontList = [[NSMutableArray alloc] init];
                    }
                    NSString *fontFile = [self.inputURL lastPathComponent];
                    if (![fontList containsObject:fontFile]){
                        [fontList addObject:fontFile];
                        [plist setObject:fontList forKey:fontKey];
                        [plist writeToFile:self.infoPlistFile atomically:YES];
                    }
                }
            }
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
