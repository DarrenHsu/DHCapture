//
//  DHPreviewView.m
//  DHCapture
//
//  Created by Dareen Hsu on 7/25/16.
//  Copyright © 2016 SKL. All rights reserved.
//

#import "DHPreviewView.h"

@implementation DHPreviewView

+ (Class)layerClass {
    return [AVCaptureVideoPreviewLayer class];
}

- (AVCaptureSession *)session {
    AVCaptureVideoPreviewLayer *previewLayer = (AVCaptureVideoPreviewLayer *)self.layer;
    return previewLayer.session;
}

- (void)setSession:(AVCaptureSession *)session {
    AVCaptureVideoPreviewLayer *previewLayer = (AVCaptureVideoPreviewLayer *)self.layer;
    previewLayer.session = session;
}

@end