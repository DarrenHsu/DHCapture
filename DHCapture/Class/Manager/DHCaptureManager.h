//
//  DHCaptureManager.h
//  DHCapture
//
//  Created by Dareen Hsu on 7/25/16.
//  Copyright © 2016 SKL. All rights reserved.
//

@import UIKit;

#import "DHPreviewView.h"

@interface DHCaptureManager : NSObject

@property (nonatomic, getter=isSessionRunning) BOOL sessionRunning;

+ (instancetype) shardInstance;

- (void) initializeWithView:(DHPreviewView *) view;

- (void) startSuccess:(void(^)(void)) success
  cameraNotAuthorized:(void(^)(void)) cameraNotAuthorized
               failed:(void(^)(void)) failed;

- (void) startSuccess:(void(^)(void)) success
         captureImage:(void(^)(UIImage *image)) capture
  cameraNotAuthorized:(void(^)(void)) cameraNotAuthorized
               failed:(void(^)(void)) failed;

- (void) stopCompletely:(void(^)(void)) complete;

- (NSString *) getBasePath;
- (NSArray *) getMovieFiles;

@end