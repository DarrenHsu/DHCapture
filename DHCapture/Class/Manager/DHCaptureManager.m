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

@interface DHCaptureManager () <AVCaptureVideoDataOutputSampleBufferDelegate,AVCaptureAudioDataOutputSampleBufferDelegate>

@property (nonatomic) dispatch_queue_t sessionQueue;
@property (nonatomic) AVCaptureSession *session;
@property (nonatomic) AVCaptureDeviceInput *videoDeviceInput;
@property (nonatomic) AVCamSetupResult setupResult;
@property (nonatomic) AVCaptureVideoDataOutput *videoDataOutput;
@property (nonatomic) AVCaptureAudioDataOutput *audioDataOutput;

@property (nonatomic) UIBackgroundTaskIdentifier backgroundRecordingID;

@property (copy) void(^CaptureProcess)(UIImage *);

@end

@implementation DHCaptureManager

+ (instancetype) shardInstance {
    @synchronized (_manager) {
        if (!_manager) {
            _manager = [DHCaptureManager new];
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
            dispatch_queue_t queue = dispatch_queue_create("video capture queue", NULL);

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
}

- (void) startSuccess:(void(^)(void)) success
         captureImage:(void(^)(UIImage *image)) capture
  cameraNotAuthorized:(void(^)(void)) cameraNotAuthorized
               failed:(void(^)(void)) failed {

    _CaptureProcess = capture;

    [self startSuccess:success cameraNotAuthorized:cameraNotAuthorized failed:failed];
}

- (void) stop {
    dispatch_async(_sessionQueue, ^{
        if (_setupResult == AVCamSetupResultSuccess ) {
            [_session stopRunning];
//            [self removeObservers];
            _sessionRunning = [_session isRunning];
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

#pragma mark - AVCaptureDataOutputSampleBufferDelegate Methods
- (void) captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    NSLog(@"%@",NSStringFromSelector(_cmd));

    if (captureOutput == _videoDataOutput) {
         UIImage *image = [self imageFromSampleBuffer:sampleBuffer];

        dispatch_async( dispatch_get_main_queue(), ^{
            if (_CaptureProcess)
                _CaptureProcess(image);
        });

    }else {

    }
}

- (void) captureOutput:(AVCaptureOutput *)captureOutput didDropSampleBuffer:(CMSampleBufferRef) sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    NSLog(@"%@",NSStringFromSelector(_cmd));
}

@end