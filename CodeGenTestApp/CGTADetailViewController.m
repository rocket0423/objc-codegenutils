//
//  CGTADetailViewController.m
//  CodeGenTestApp
//
//  Created by Jim Puls on 2/3/14.
//  Licensed to Square, Inc. under one or more contributor license agreements.
//  See the LICENSE file distributed with this work for the terms under
//  which Square, Inc. licenses this file to you.

#import "CGTADetailViewController.h"


@interface CGTADetailViewController ()

@property (nonatomic, strong) IBOutlet UIImageView *imageView;

@end


@implementation CGTADetailViewController

- (void)setImage:(UIImage *)image;
{
    _image = image;
    [self updateView];
}

- (void)viewDidLoad;
{
    [self updateView];
    
    CAGradientLayer *layer = [CAGradientLayer layer];
    layer.startPoint = CGPointMake(0.5, 0.5);
    layer.endPoint = CGPointMake(0.5, 1.0);
    
//    layer.colors = @[(id)[UIColor whiteColor].CGColor, (id)[CGTATestAppColorList tealColor].CGColor];
    layer.frame = self.view.layer.bounds;
    [self.view.layer insertSublayer:layer atIndex:0];
}

- (void)updateView;
{
    self.imageView.image = self.image;
}

@end
