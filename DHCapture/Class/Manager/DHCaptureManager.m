//
//  DHCaptureManager.m
//  DHCapture
//
//  Created by Dareen Hsu on 7/25/16.
//  Copyright © 2016 SKL. All rights reserved.
//

#import "DHCaptureManager.h"
@import AVFoundation;

typedef NS_ENUM(NSInteger, AVCamSetupResult) {
    AVCamSetupResultSuccess,
    AVCamSetupResultCameraNotAuthorized,
    AVCamSetupResultSessionConfigurationFailed
};

static DHCaptureManager *_manager = nil;

@interface DHCaptureManager () <AVCaptureVideoDataOutputSampleBufferDelegate,AVCaptureAudioDataOutputSampleBufferDelegate> {
    CGSize _imageSize;
    BOOL _isCreateNow;
}

@property (nonatomic) dispatch_queue_t sessionQueue;
@property (nonatomic) AVCaptureSession *session;
@property (nonatomic) AVCaptureDeviceInput *videoDeviceInput;
@property (nonatomic) AVCamSetupResult setupResult;
@property (nonatomic) AVCaptureVideoDataOutput *videoDataOutput;
@property (nonatomic) AVCaptureAudioDataOutput *audioDataOutput;

@property (nonatomic) UIBackgroundTaskIdentifier backgroundRecordingID;

@property (nonatomic, strong) NSMutableArray *imageFrameArray;

@property (nonatomic, strong) NSTimer *saveTimer;

@property (copy) void(^CaptureProcess)(UIImage *);

@property (nonnull, strong) NSOperationQueue *queue;

@end

@implementation DHCaptureManager

+ (instancetype) shardInstance {
    @synchronized (_manager) {
        if (!_manager) {
            _manager = [DHCaptureManager new];
            _manager.imageFrameArray = [NSMutableArray new];
            _manager.queue = [NSOperationQueue new];
        }
    }
    return _manager;
}

- (void) initializeWithView:(DHPreviewView *) view {
    _manager.sessionQueue = dispatch_queue_create( "session queue", DISPATCH_QUEUE_SERIAL);

    _session = [AVCaptureSession new];
    _manager.setupResult = AVCamSetupResultSuccess;
    view.session = _session;

    switch([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo]) {
        case AVAuthorizationStatusAuthorized: {
            break;
        } case AVAuthorizationStatusNotDetermined: {
            dispatch_suspend(_sessionQueue);
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
                if (!granted) {
                    _setupResult = AVCamSetupResultCameraNotAuthorized;
                }
                dispatch_resume(_sessionQueue);
            }];
            break;
        } default: {
            _setupResult = AVCamSetupResultCameraNotAuthorized;
            break;
        }
    }

    dispatch_async(_sessionQueue, ^{
        if (_setupResult != AVCamSetupResultSuccess)
            return;

        _backgroundRecordingID = UIBackgroundTaskInvalid;
        NSError *error = nil;

        AVCaptureDevice *videoDevice = [self deviceWithMediaType:AVMediaTypeVideo preferringPosition:AVCaptureDevicePositionBack];
        AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];

        if (!videoDeviceInput)
            NSLog(@"Could not create video device input: %@", error);

        [_session beginConfiguration];

        if ([_session canAddInput:videoDeviceInput]) {
            [_session addInput:videoDeviceInput];
            _videoDeviceInput = videoDeviceInput;

            dispatch_async( dispatch_get_main_queue(), ^{
                UIInterfaceOrientation statusBarOrientation = [UIApplication sharedApplication].statusBarOrientation;
                AVCaptureVideoOrientation initialVideoOrientation = AVCaptureVideoOrientationPortrait;
                if ( statusBarOrientation != UIInterfaceOrientationUnknown )
                    initialVideoOrientation = (AVCaptureVideoOrientation)statusBarOrientation;

                AVCaptureVideoPreviewLayer *previewLayer = (AVCaptureVideoPreviewLayer *)view.layer;
                previewLayer.connection.videoOrientation = initialVideoOrientation;
            });
        } else {
            NSLog( @"Could not add video device input to the session" );
            _setupResult = AVCamSetupResultSessionConfigurationFailed;
        }

        AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
        AVCaptureDeviceInput *audioDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:&error];

        if (!audioDeviceInput)
            NSLog( @"Could not create audio device input: %@", error );

        if ([_session canAddInput:audioDeviceInput]) {
            [_session addInput:audioDeviceInput];
        } else {
            NSLog( @"Could not add audio device input to the session" );
        }

        AVCaptureVideoDataOutput *videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
        if ([_session canAddOutput:videoDataOutput]) {
            dispatch_queue_t queue = dispatch_queue_create("VideoCaptureQueue", NULL);

            [videoDataOutput setSampleBufferDelegate:self queue:queue];
            videoDataOutput.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey: [NSNumber numberWithInt:kCVPixelFormatType_32BGRA]};

            [_session addOutput:videoDataOutput];
            _videoDataOutput = videoDataOutput;
        }else {
            NSLog( @"Could not add video data output to the session" );
            self.setupResult = AVCamSetupResultSessionConfigurationFailed;
        }

//        AVCaptureAudioDataOutput *audioDataOutput = [[AVCaptureAudioDataOutput alloc] init];
//        if ([_session canAddOutput:audioDataOutput]) {
//            [audioDataOutput setSampleBufferDelegate:self queue:dispatch_queue_create("audio capture queue", NULL)];
//            [_session addOutput:audioDataOutput];
//            _audioDataOutput = audioDataOutput;
//        }else {
//            NSLog( @"Could not add audio data output to the session" );
//            self.setupResult = AVCamSetupResultSessionConfigurationFailed;
//        }
//
//        AVCaptureMovieFileOutput *movieFileOutput = [[AVCaptureMovieFileOutput alloc] init];
//        if ( [self.session canAddOutput:movieFileOutput] ) {
//            [self.session addOutput:movieFileOutput];
//            AVCaptureConnection *connection = [movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
//            if ( connection.isVideoStabilizationSupported ) {
//                connection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationModeAuto;
//            }
//            self.movieFileOutput = movieFileOutput;
//        }
//        else {
//            NSLog( @"Could not add movie file output to the session" );
//            self.setupResult = AVCamSetupResultSessionConfigurationFailed;
//        }
//        
//        AVCaptureStillImageOutput *stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
//        if ( [self.session canAddOutput:stillImageOutput] ) {
//            stillImageOutput.outputSettings = @{AVVideoCodecKey : AVVideoCodecJPEG};
//            [self.session addOutput:stillImageOutput];
//            self.stillImageOutput = stillImageOutput;
//        }
//        else {
//            NSLog( @"Could not add still image output to the session" );
//            self.setupResult = AVCamSetupResultSessionConfigurationFailed;
//        }
        
        [self.session commitConfiguration];
    });
}

- (AVCaptureDevice *) deviceWithMediaType:(NSString *) mediaType preferringPosition:(AVCaptureDevicePosition) position {
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:mediaType];
    AVCaptureDevice *captureDevice = devices.firstObject;

    for (AVCaptureDevice *device in devices) {
        if (device.position == position) {
            captureDevice = device;
            break;
        }
    }
    
    return captureDevice;
}

- (void) startSuccess:(void(^)(void)) success cameraNotAuthorized:(void(^)(void)) cameraNotAuthorized failed:(void(^)(void)) failed {
    dispatch_async(_sessionQueue, ^{
        switch (_setupResult) {
            case AVCamSetupResultSuccess: {
//                [self addObservers];
                [_session startRunning];
                _sessionRunning = _session.isRunning;
                NSLog(@"capture start");
                break;
            } case AVCamSetupResultCameraNotAuthorized: {
                dispatch_async( dispatch_get_main_queue(), ^{
                    if (cameraNotAuthorized) cameraNotAuthorized();
                });
                break;
            } case AVCamSetupResultSessionConfigurationFailed: {
                dispatch_async( dispatch_get_main_queue(), ^{
                    if (failed) failed();
                } );
                break;
            }
        }
    });

    _saveTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(createMovie) userInfo:nil repeats:YES];

}

- (void) startSuccess:(void(^)(void)) success
         captureImage:(void(^)(UIImage *image)) capture
  cameraNotAuthorized:(void(^)(void)) cameraNotAuthorized
               failed:(void(^)(void)) failed {

    _CaptureProcess = capture;

    [self startSuccess:success cameraNotAuthorized:cameraNotAuthorized failed:failed];
}

- (void) stopCompletely:(void(^)(void)) complete {
    [_saveTimer invalidate];

    dispatch_async(_sessionQueue, ^{
        if (!_sessionRunning) return;

        if (_setupResult == AVCamSetupResultSuccess ) {
            [_session stopRunning];
            _sessionRunning = [_session isRunning];

            [_imageFrameArray removeAllObjects];

//            [self removeObservers];

            dispatch_async( dispatch_get_main_queue(), ^{
                if (complete) complete();
            });

            NSLog(@"capture stop");
        }
    });
}

- (UIImage *) imageFromSampleBuffer:(CMSampleBufferRef) sampleBuffer {
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(imageBuffer, 0);

    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8, bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGImageRef quartzImage = CGBitmapContextCreateImage(context);
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);

    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);

    UIImage *image = [UIImage imageWithCGImage:quartzImage];

    CGImageRelease(quartzImage);
    
    return (image);
}

- (NSString *) getBasePath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *tempDirectory = [[paths objectAtIndex:0] stringByAppendingFormat:@"/movie"];
    NSFileManager *manager = [NSFileManager defaultManager];
    if (![manager fileExistsAtPath:tempDirectory]) {
        NSError *error;
        [manager createDirectoryAtPath:tempDirectory withIntermediateDirectories:YES attributes:nil error:&error];
    }

    return tempDirectory;
}

- (NSArray *) getMovieFiles {
    NSString *basePath = [self getBasePath];
    NSError *error;
    NSArray *directoryContent = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:basePath error:&error];
    NSMutableArray *matches = [NSMutableArray new];

    for (NSString *item in directoryContent) {
        if ([[item pathExtension] isEqualToString:@"mp4"]) {
            [matches addObject:item];
        }
    }

    return matches;
}

#pragma mark - Write Image into movie
- (void) write:(NSString *) key imageAsMovie:(NSArray *) array toPath:(NSString*) path size:(CGSize) size duration:(CGFloat) duration complete:(void (^)(void))handler {
    NSError *error = nil;
    AVAssetWriter *videoWriter = [[AVAssetWriter alloc] initWithURL:[NSURL fileURLWithPath:path]
                                                           fileType:AVFileTypeMPEG4
                                                              error:&error];

    NSParameterAssert(videoWriter);

    NSDictionary *videoSettings = @{AVVideoCodecKey: AVVideoCodecH264,
                                    AVVideoWidthKey: [NSNumber numberWithInt:size.width],
                                    AVVideoHeightKey: [NSNumber numberWithInt:size.height]};

    AVAssetWriterInput *writerInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
    AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:writerInput sourcePixelBufferAttributes:nil];

    NSParameterAssert(writerInput);
    NSParameterAssert([videoWriter canAddInput:writerInput]);

    [videoWriter addInput:writerInput];
    [videoWriter startWriting];
    [videoWriter startSessionAtSourceTime:kCMTimeZero];

    CVPixelBufferRef buffer = [self pixelBufferFromCGImage:[[array objectAtIndex:0] CGImage] size:CGSizeMake(480, 320)];
    CVPixelBufferPoolCreatePixelBuffer(NULL, adaptor.pixelBufferPool, &buffer);

    [adaptor appendPixelBuffer:buffer withPresentationTime:kCMTimeZero];
    int i = 0;
    while (writerInput.readyForMoreMediaData) {
        CMTime frameTime = CMTimeMake(150, 600);
        CMTime lastTime = CMTimeMake(150 * i, 600);
        CMTime presentTime = CMTimeAdd(lastTime, frameTime);

//        if (i == 0) presentTime = CMTimeMake(0, 600);

        if (i >= [array count]) {
            buffer = NULL;
        } else {
            buffer = [self pixelBufferFromCGImage:[[array objectAtIndex:i] CGImage] size:size];
        }

        NSLog(@"%@ %f %zd", key, (CGFloat)presentTime.value / (CGFloat)presentTime.timescale,i);

        if (buffer) {
            [adaptor appendPixelBuffer:buffer withPresentationTime:presentTime];
            i++;
        } else {
            [writerInput markAsFinished];
            [videoWriter finishWritingWithCompletionHandler:^{
                if (!videoWriter.error) {
                    NSLog(@"Video writing succeeded.");

                    if (handler)
                        handler();

                } else {
                    NSLog(@"Video writing failed: %@", videoWriter.error);
                }
            }];

            CVPixelBufferPoolRelease(adaptor.pixelBufferPool);
            break;
        }
    }
}

- (CVPixelBufferRef) pixelBufferFromCGImage: (CGImageRef) image  size:(CGSize)imageSize {
    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
                             [NSNumber numberWithBool:YES], kCVPixelBufferCGImageCompatibilityKey,
                             [NSNumber numberWithBool:YES], kCVPixelBufferCGBitmapContextCompatibilityKey,nil];

    CVPixelBufferRef pxbuffer = NULL;
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, imageSize.width,
                                          imageSize.height, kCVPixelFormatType_32ARGB, (__bridge CFDictionaryRef)options,
                                          &pxbuffer);

    NSParameterAssert(status == kCVReturnSuccess && pxbuffer != NULL);

    CVPixelBufferLockBaseAddress(pxbuffer, 0);
    void *pxdata = CVPixelBufferGetBaseAddress(pxbuffer);
    NSParameterAssert(pxdata != NULL);

    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pxdata, imageSize.width,
                                                 imageSize.height, 8, 4 * imageSize.width, rgbColorSpace,
                                                 kCGImageAlphaNoneSkipFirst);

    NSParameterAssert(context);

    CGContextDrawImage(context, CGRectMake(0, 0, CGImageGetWidth(image), CGImageGetHeight(image)), image);
    CGColorSpaceRelease(rgbColorSpace);
    CGContextRelease(context);
    CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
    
    return pxbuffer;
}

- (void) createMovie {
    NSMutableArray *tmpArray = [NSMutableArray new];
    for (UIImage *image in _imageFrameArray)
        [tmpArray addObject:image];

    [_queue addOperationWithBlock:^{
        NSString *key = [NSString stringWithFormat:@"%zd",arc4random_uniform(74)];
        NSLog(@"%@ create start",key);

        if (tmpArray.count == 0) return;

        NSLog(@"%@ createMovie %zd",key,tmpArray.count);

        NSString *path = [[self getBasePath] stringByAppendingFormat:@"/%@.mp4",[NSDate new]];

        [self write:key imageAsMovie:tmpArray toPath:path size:_imageSize duration:1 complete:^{
            NSLog(@"%@ image count %zd",key,tmpArray.count);
            NSLog(@"%@ write file %@",key,path);

            [tmpArray removeAllObjects];

            _isCreateNow = NO;
        }];
    }];
}

#pragma mark - AVCaptureDataOutputSampleBufferDelegate Methods
- (void) captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (captureOutput == _videoDataOutput) {

        if (_isCreateNow) return;

        UIImage *image = [self imageFromSampleBuffer:sampleBuffer];
        _imageSize = image.size;

        [_imageFrameArray addObject:image];

        dispatch_async( dispatch_get_main_queue(), ^{
            if (_imageFrameArray.count >= 10) {
                _isCreateNow = YES;

                [self createMovie];
                [self stopCompletely:NULL];
            }

            if (_CaptureProcess)
                _CaptureProcess(image);
        });

    }else {

    }
}

- (void) captureOutput:(AVCaptureOutput *)captureOutput didDropSampleBuffer:(CMSampleBufferRef) sampleBuffer fromConnection:(AVCaptureConnection *)connection {
//    NSLog(@"%@",NSStringFromSelector(_cmd));
}

@end