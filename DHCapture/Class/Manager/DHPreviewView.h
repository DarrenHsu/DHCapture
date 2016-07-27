//
//  DHPreviewView.h
//  DHCapture
//
//  Created by Dareen Hsu on 7/25/16.
//  Copyright © 2016 SKL. All rights reserved.
//

#import <UIKit/UIKit.h>
@import AVFoundation;

@interface DHPreviewView : UIView

@property (nonatomic) AVCaptureSession *session;

@end