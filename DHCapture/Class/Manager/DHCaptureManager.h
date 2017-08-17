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
- (void) startSuccess:(void(^)(void)) success completely:(void(^)(void)) complete cameraNotAuthorized:(void(^)(void)) cameraNotAuthorized failed:(void(^)(void)) failed;
- (void) stopCompletely:(void(^)(void)) complete;

@end

@interface DHCaptureManager (Resource)

- (NSString *) getMoviesFolder;
- (NSString *) getFramesFolder;
- (NSArray *) getMovieFiles;

@end
