//
//  CLColors.m
//  colorlist
//
//  Created by Jim Puls on 8/29/13.
//  Licensed to Square, Inc. under one or more contributor license agreements.
//  See the LICENSE file distributed with this work for the terms under
//  which Square, Inc. licenses this file to you.

#import "CLColors.h"

@interface NSString (CLColorsAddition)

- (NSString *)CLC_formattedString;
- (NSString *)CLC_titlecaseString;
- (NSString *)CLC_capitalizedString;

@end

@interface CLColors ()

@property (strong) NSArray *colorSetURLs;

@end


@implementation CLColors

+ (NSArray *)inputFileExtension;
{
    return @[@"colors"];
}

- (void)startWithCompletionHandler:(dispatch_block_t)completionBlock;
{
    NSString *colorFileName = [[self.inputURL lastPathComponent] stringByDeletingPathExtension];
    if (self.writeSingleFile)
        self.className = [NSString stringWithFormat:@"%@Colors", self.classPrefix];
    else
        self.className = [NSString stringWithFormat:@"%@%@Colors", self.classPrefix, colorFileName];
    if (!self.implementationContents)
        self.implementationContents = [NSMutableArray array];
    if (!self.objcItems && self.targetObjC)
        self.objcItems = [NSMutableArray array];
    
    NSDictionary *localizationDict = [NSDictionary dictionaryWithContentsOfURL:self.inputURL];
    for (NSString *nextKey in [localizationDict allKeys]) {
        NSString *colorString = [localizationDict objectForKey:nextKey];
        NSArray *rgbColors = [self colorsFromRGBAString:colorString];
        if (!rgbColors) {
            rgbColors = [self convertHexString:colorString];
        }
        NSString *methodName = [[self methodNameForKey:nextKey] CLC_titlecaseString];
        NSMutableString *implementation = [[NSMutableString alloc] init];
        if (rgbColors) {
            if (self.targetObjC){
                NSString *interface = [NSString stringWithFormat:@"+ (UIColor *)%@;\n", methodName];
                @synchronized(self.objcItems) {
                    [self.objcItems addObject:interface];
                }
                [implementation appendFormat:@"// %@ Color %@\n", [methodName CLC_capitalizedString], colorString];
                [implementation appendString:interface];
                [implementation appendString:@"{\n"];
                [implementation appendString:@"    return [UIColor "];
                [implementation appendFormat:@"colorWithRed:%@ ", [self formattedFloat:[rgbColors objectAtIndex:0]]];
                [implementation appendFormat:@"green:%@ ", [self formattedFloat:[rgbColors objectAtIndex:1]]];
                [implementation appendFormat:@"blue:%@ ", [self formattedFloat:[rgbColors objectAtIndex:2]]];
                [implementation appendFormat:@"alpha:%@];\n", [self formattedFloat:[rgbColors objectAtIndex:3]]];
                [implementation appendString:@"}\n\n"];
            } else {
                [implementation appendFormat:@"    // %@ Color %@\n", [methodName CLC_capitalizedString], colorString];
                [implementation appendFormat:@"    static var %@: UIColor {\n", methodName];
                [implementation appendString:@"        return UIColor("];
                [implementation appendFormat:@"red:%@, ", [self formattedFloat:[rgbColors objectAtIndex:0]]];
                [implementation appendFormat:@"green:%@, ", [self formattedFloat:[rgbColors objectAtIndex:1]]];
                [implementation appendFormat:@"blue:%@, ", [self formattedFloat:[rgbColors objectAtIndex:2]]];
                [implementation appendFormat:@"alpha:%@)\n", [self formattedFloat:[rgbColors objectAtIndex:3]]];
                [implementation appendString:@"    }\n\n"];
            }
        } else {
            if (self.targetObjC){
                [implementation appendString:@"#warning Invalid Color"];
                [implementation appendFormat:@"// Invalid Hex Color %@ '%@' please make sure it is in the proper format 'AAAAAA' with no '#'\n", methodName, colorString];
                [implementation appendFormat:@"// Invalid RGB or RGBA Color %@ '%@' please make sure it is in the proper format 'r,g,b,a' or 'r,g,b'\n", methodName, colorString];
            } else {
                self.hasWarning = YES;
                [implementation appendFormat:@"    // Invalid Hex Color %@ '%@' please make sure it is in the proper format 'AAAAAA' with no '#'\n", methodName, colorString];
                [implementation appendFormat:@"    // Invalid RGB or RGBA Color %@ '%@' please make sure it is in the proper format 'r,g,b,a' or 'r,g,b'\n", methodName, colorString];
                [implementation appendFormat:@"    private var %@: UIColor? {\n", methodName];
                [implementation appendString:@"        InvalidColor()\n"];
                [implementation appendFormat:@"        return nil\n"];
                [implementation appendString:@"    }\n\n"];
            }
        }
        
        @synchronized(self.implementationContents) {
            [self.implementationContents addObject:implementation];
        }
    }
    
    if (!self.writeSingleFile || self.lastFile) {
        if (self.hasWarning) {
            [self writeWarning];
        }
        [self writeOutputFiles];
    }
    
    completionBlock();
}

- (NSString *)formattedFloat:(NSString *)floatString {
    if (![floatString containsString:@"."]) {
        return floatString;
    }
    while ([floatString hasSuffix:@"0"]) {
        floatString = [floatString substringToIndex:(floatString.length - 1)];
    }
    if ([floatString hasSuffix:@"."]) {
        return [floatString substringToIndex:(floatString.length - 1)];
    } else {
        return floatString;
    }
}

- (NSArray *)convertHexString:(NSString *)hexString {
    if ([hexString length] != 6) {
        return nil;
    }
    NSCharacterSet *hexChars = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEF"] invertedSet];
    if (NSNotFound != [[hexString uppercaseString] rangeOfCharacterFromSet:hexChars].location) {
        return nil;
    }
    const char *cStr = [hexString cStringUsingEncoding:NSASCIIStringEncoding];
    UInt32 col = (UInt32)strtol(cStr, NULL, 16);
    
    // Convert the color
    unsigned char r, g, b;
    b = col & 0xFF;
    g = (col >> 8) & 0xFF;
    r = (col >> 16) & 0xFF;
    
    NSMutableArray *convertedComponents = [[NSMutableArray alloc] initWithCapacity:4];
    [convertedComponents addObject:[NSString stringWithFormat:@"%f", ((float)r/255.0)]];
    [convertedComponents addObject:[NSString stringWithFormat:@"%f", ((float)g/255.0)]];
    [convertedComponents addObject:[NSString stringWithFormat:@"%f", ((float)b/255.0)]];
    [convertedComponents addObject:[NSString stringWithFormat:@"1"]];
    return convertedComponents;
}

- (NSArray *)colorsFromRGBAString:(NSString *)rgbaString {
    NSMutableArray *components = [[rgbaString componentsSeparatedByString:@","] mutableCopy];
    BOOL is255Components = NO;
    if ([components count] == 3 || [components count] == 4) {
        // Red
        NSString *redValue = [components objectAtIndex:0];
        if (![self isValidFloatString:redValue]) {
            return nil;
        }
        is255Components = (is255Components || [self is255Value:redValue]);
        // Green
        NSString *greenValue = [components objectAtIndex:1];
        if (![self isValidFloatString:greenValue]) {
            return nil;
        }
        is255Components = (is255Components || [self is255Value:greenValue]);
        // Blue
        NSString *blueValue = [components objectAtIndex:2];
        if (![self isValidFloatString:blueValue]) {
            return nil;
        }
        is255Components = (is255Components || [self is255Value:blueValue]);
        // Alpha
        if ([components count] == 3) {
            if (is255Components) {
                [components addObject:@"255"];
            } else {
                [components addObject:@"1"];
            }
        } else {
            NSString *redValue = [components objectAtIndex:3];
            if (![self isValidFloatString:redValue]) {
                return nil;
            }
            is255Components = (is255Components || [self is255Value:redValue]);
        }
        if (is255Components) {
            NSMutableArray *convertedComponents = [[NSMutableArray alloc] initWithCapacity:4];
            [convertedComponents addObject:[NSString stringWithFormat:@"%f", ([[components objectAtIndex:0] floatValue] / 255.0)]];
            [convertedComponents addObject:[NSString stringWithFormat:@"%f", ([[components objectAtIndex:1] floatValue] / 255.0)]];
            [convertedComponents addObject:[NSString stringWithFormat:@"%f", ([[components objectAtIndex:2] floatValue] / 255.0)]];
            [convertedComponents addObject:[NSString stringWithFormat:@"%f", ([[components objectAtIndex:3] floatValue] / 255.0)]];
            return convertedComponents;
        } else {
            return components;
        }
    }
    return nil;
}

- (BOOL)isValidFloatString:(NSString *)str{
    const char *s = str.UTF8String;
    char *end;
    strtod(s, &end);
    return !end[0];
}

- (BOOL)is255Value:(NSString *)str{
    return ([str floatValue] > 1);
}

- (void)writeWarning {
    if (self.targetObjC){
        return;
    }
    NSMutableString *implementation = [[NSMutableString alloc] init];
    [implementation appendString:@"    /// Warning message so console is notified.\n"];
    [implementation appendString:@"    @available(iOS, deprecated=1.0, message=\"Invalid Color\")\n"];
    [implementation appendString:@"    private func InvalidColor(){}\n\n"];
    
    @synchronized(self.implementationContents) {
        [self.implementationContents addObject:implementation];
    }
}

@end


@implementation NSString (CLColorsAddition)

- (NSString *)CLC_formattedString;
{
    return [self stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
}

- (NSString *)CLC_titlecaseString;
{
    NSArray *words = [self componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableString *output = [NSMutableString string];
    for (NSString *word in words) {
        [output appendFormat:@"%@%@_", [[word substringToIndex:1] lowercaseString], [word substringFromIndex:1]];
    }
    return [output substringToIndex:(output.length - 1 )];
}

- (NSString *)CLC_capitalizedString;
{
    return [NSString stringWithFormat:@"%@%@", [[self substringToIndex:1] uppercaseString], [self substringFromIndex:1]];
}

@end
