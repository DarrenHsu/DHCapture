//
//  DHCaptureManager.m
//  DHCapture
//
//  Created by Dareen Hsu on 7/25/16.
//  Copyright © 2016 SKL. All rights reserved.
//

#import "DHCaptureManager.h"
@import AVFoundation;

#define CAPTURE_FRAMES_PER_SECOND_MAX	20
#define CAPTURE_FRAMES_PER_SECOND_MIN   10

typedef NS_ENUM(NSInteger, AVCamSetupResult) {
    AVCamSetupResultSuccess,
    AVCamSetupResultCameraNotAuthorized,
    AVCamSetupResultSessionConfigurationFailed
};

typedef NS_ENUM(NSInteger, AVOutputType) {
    AVOutputTypeRecording,
    AVOutputTypeAssertWriter
};


#pragma mark -
/* --------------------------------------------------- Process -------------------------------------------- */

@interface DHCaptureManager (Process)

- (UIImage *) imageFromSampleBuffer:(CMSampleBufferRef) sampleBuffer;

@end

@implementation DHCaptureManager (Process)

- (UIImage *) imageFromSampleBuffer:(CMSampleBufferRef) sampleBuffer {
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    
    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(baseAddress, width / 4, height / 4, 8, bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGImageRef quartzImage = CGBitmapContextCreateImage(context);
    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
    
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    UIImage *image = [UIImage imageWithCGImage:quartzImage];
    CGImageRelease(quartzImage);
    
    return image;
}

@end

#pragma mark -
/* --------------------------------------------------- Resource -------------------------------------------- */

@implementation DHCaptureManager (Resource)

- (NSString *) getCurrentFileName {
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"yyyy-MM-dd_HH:mm:ss"];
    NSString *fileName = [dateFormatter stringFromDate:[NSDate new]];
    
    NSString *outputPath = [NSString stringWithFormat:@"%@/%@.mov",[self getMoviesFolder], fileName];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:outputPath]) {
        NSError *error;
        [fileManager removeItemAtPath:outputPath error:&error];
    }
    
    return outputPath;
}

- (NSString *) getMoviesFolder {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *tempDirectory = [[paths objectAtIndex:0] stringByAppendingFormat:@"/movie"];
    NSFileManager *manager = [NSFileManager defaultManager];
    if (![manager fileExistsAtPath:tempDirectory]) {
        NSError *error;
        [manager createDirectoryAtPath:tempDirectory withIntermediateDirectories:YES attributes:nil error:&error];
    }
    
    return tempDirectory;
}

- (NSString *) getFramesFolder {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *tempDirectory = [[paths objectAtIndex:0] stringByAppendingFormat:@"/frames"];
    NSFileManager *manager = [NSFileManager defaultManager];
    if (![manager fileExistsAtPath:tempDirectory]) {
        NSError *error;
        [manager createDirectoryAtPath:tempDirectory withIntermediateDirectories:YES attributes:nil error:&error];
    }
    
    return tempDirectory;
}

- (NSArray *) getMovieFiles {
    NSString *basePath = [self getMoviesFolder];
    NSError *error;
    NSArray *directoryContent = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:basePath error:&error];
    NSMutableArray *matches = [NSMutableArray new];
    
    for (NSString *item in directoryContent) {
        [matches addObject:item];
    }
    
    return matches;
}

@end


/* --------------------------------------------------- Resource -------------------------------------------- */

static DHCaptureManager *_manager = nil;



@interface DHCaptureManager () <AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, AVCaptureFileOutputRecordingDelegate> {
    CGSize _imageSize;
    BOOL _isCreateNow;
    BOOL _isStartSession;
    AVOutputType _type;
    
    Float64 _currentCaptureSecond;
    Float64 _orignalCaptureSecond;
}

@property (nonatomic) AVCamSetupResult setupResult;

@property (nonatomic) dispatch_queue_t sessionQueue;
@property (nonatomic) dispatch_queue_t captureVideoQueue;
@property (nonatomic) dispatch_queue_t captureAudioQueue;

@property (nonatomic) AVCaptureVideoOrientation initialVideoOrientation;
@property (nonatomic) AVCaptureSession *session;

@property (nonatomic) AVCaptureDeviceInput *videoDeviceInput;

@property (nonatomic) AVAssetWriter *asserWriter;
@property (nonatomic) AVAssetWriterInput *videoWriterInput;
@property (nonatomic) AVAssetWriterInput *audioWriterInput;

@property (nonatomic) AVCaptureMovieFileOutput *movieDataOutput;
@property (nonatomic) AVCaptureVideoDataOutput *videoDataOutput;
@property (nonatomic) AVCaptureAudioDataOutput *audioDataOutput;

@property (nonatomic) CMTime lastSampleTime;

@property (copy) void(^CaptureProcess)(UIImage *);
@property (copy) void(^CaptureFinish)(void);

@end

@implementation DHCaptureManager

void mainThread(dispatch_block_t block) {
    dispatch_async(dispatch_get_main_queue(), block);
}

void sessionThread(dispatch_block_t block) {
    dispatch_async(_manager.sessionQueue, block);
}

+ (instancetype) shardInstance {
    @synchronized (_manager) {
        if (!_manager) {
            _manager = [DHCaptureManager new];
            _manager.sessionQueue = dispatch_queue_create( "session queue", DISPATCH_QUEUE_SERIAL);
            _manager.captureAudioQueue = dispatch_queue_create( "capture audio queue", DISPATCH_QUEUE_SERIAL);
            _manager.captureVideoQueue = dispatch_queue_create( "capture video queue", DISPATCH_QUEUE_SERIAL);
        }
    }
    return _manager;
}

- (void) initializeWithView:(DHPreviewView *) view {
    _session = [AVCaptureSession new];
    _manager.setupResult = AVCamSetupResultSuccess;
    view.session = _session;
    
    _type = AVOutputTypeAssertWriter;

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
    
    sessionThread(^{
        if (_setupResult != AVCamSetupResultSuccess)
            return;

        [self addInput:view];
        
        [self addOutput];
        
        if ([self.session canSetSessionPreset:AVCaptureSessionPresetiFrame960x540])
            [self.session setSessionPreset:AVCaptureSessionPresetiFrame960x540];
        
        [self.session commitConfiguration];
    });
}

#pragma mark - AV Model Process
- (AVCaptureDevice *) deviceWithMediaType:(NSString *) mediaType preferringPosition:(AVCaptureDevicePosition) position {
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:mediaType];
    AVCaptureDevice *captureDevice = devices.firstObject;
    
    for (AVCaptureDevice *device in devices) {
        if (device.position == position) {
            captureDevice = device;
            break;
        }
    }
    
    if([captureDevice isTorchModeSupported:AVCaptureTorchModeOn]) {
        [captureDevice lockForConfiguration:nil];
        [captureDevice setActiveVideoMaxFrameDuration:CMTimeMake(1, CAPTURE_FRAMES_PER_SECOND_MAX)];
        [captureDevice setActiveVideoMinFrameDuration:CMTimeMake(1, CAPTURE_FRAMES_PER_SECOND_MIN)];
        [captureDevice unlockForConfiguration];
    }
    
    return captureDevice;
}

#pragma mark - Add Input Methods
- (void) addInput:(UIView *) view {
    NSError *error = nil;
    
    AVCaptureDevice *videoDevice = [self deviceWithMediaType:AVMediaTypeVideo preferringPosition:AVCaptureDevicePositionBack];
    AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
    
    if (!videoDeviceInput)
        NSLog(@"Could not create video device input: %@", error);
    
    [_session beginConfiguration];
    
    if ([_session canAddInput:videoDeviceInput]) {
        [_session addInput:videoDeviceInput];
        _videoDeviceInput = videoDeviceInput;
        
        mainThread(^{
            UIInterfaceOrientation statusBarOrientation = [UIApplication sharedApplication].statusBarOrientation;
            _initialVideoOrientation = AVCaptureVideoOrientationPortrait;
            if (statusBarOrientation != UIInterfaceOrientationUnknown )
                _initialVideoOrientation = (AVCaptureVideoOrientation)statusBarOrientation;
            
            AVCaptureVideoPreviewLayer *previewLayer = (AVCaptureVideoPreviewLayer *)view.layer;
            previewLayer.connection.videoOrientation = _initialVideoOrientation;
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
}

#pragma mark - Add Output Methods
- (void) addOutput {
    [self addVideoOutput];
    [self addAudioOutput];
    
    if (_type == AVOutputTypeRecording) {
        [self addMovieOutput];
    }
}

- (void) addVideoOutput {
    /* Add Video Output */
    AVCaptureVideoDataOutput *videoDataOutput = [AVCaptureVideoDataOutput new];
    if ([_session canAddOutput:videoDataOutput]) {
        videoDataOutput.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA)};
        [videoDataOutput setSampleBufferDelegate:self queue:_captureVideoQueue];
        
        [_session addOutput:videoDataOutput];
        _videoDataOutput = videoDataOutput;
    }else {
        NSLog( @"Could not add video data output to the session" );
        _setupResult = AVCamSetupResultSessionConfigurationFailed;
    }
}

- (void) addAudioOutput {
    AVCaptureAudioDataOutput *audioDataOutput = [AVCaptureAudioDataOutput new];
    if ([_session canAddOutput:audioDataOutput]) {
        [audioDataOutput setSampleBufferDelegate:self queue:_captureAudioQueue];
        
        [_session addOutput:audioDataOutput];
        _audioDataOutput = audioDataOutput;
    }else {
        NSLog( @"Could not add audio data output to the session" );
        _setupResult = AVCamSetupResultSessionConfigurationFailed;
    }
}

- (void) addMovieOutput {
    /* Add Movie Output */
    AVCaptureMovieFileOutput *movieDataOutput = [AVCaptureMovieFileOutput new];
    if ([_session canAddOutput:movieDataOutput]) {
        
        Float64 TotalSeconds = 60;
        int32_t preferredTimeScale = 30;
        CMTime maxDuration = CMTimeMakeWithSeconds(TotalSeconds, preferredTimeScale);
        movieDataOutput.maxRecordedDuration = maxDuration;
        movieDataOutput.minFreeDiskSpaceLimit = 1024 * 1024;
        
        [_session addOutput:movieDataOutput];
        _movieDataOutput = movieDataOutput;
    }else {
        NSLog( @"Could not add movie data output to the session" );
        _setupResult = AVCamSetupResultSessionConfigurationFailed;
    }
}

- (void) addAssertWriter {
    NSString *outputPath = [self getCurrentFileName];
    NSURL *outputURL = [[NSURL alloc] initFileURLWithPath:outputPath];

    CGSize size = CGSizeMake(540, 960);
    
    NSDictionary *videoCompressionPropertys = @{AVVideoAverageBitRateKey : @(128.0 * 1024.0)};
    NSDictionary *videoSettings = @{AVVideoCodecKey : AVVideoCodecH264,
                                    AVVideoWidthKey : @(size.width),
                                    AVVideoHeightKey : @(size.height),
                                    AVVideoCompressionPropertiesKey : videoCompressionPropertys};
    
    /* assert writer */
    NSError *error;
    _asserWriter = [[AVAssetWriter alloc] initWithURL:outputURL fileType:AVFileTypeQuickTimeMovie error:&error];
    
    if (error)
        NSLog(@"error: %@", [error localizedDescription]);
    
    _videoWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
    _videoWriterInput.expectsMediaDataInRealTime = YES;
    
    if ([_asserWriter canAddInput:_videoWriterInput])
        [_asserWriter addInput:_videoWriterInput];
    else
        NSLog(@"Could not add video input");

    AudioChannelLayout acl;
    bzero( &acl, sizeof(acl));
    acl.mChannelLayoutTag = kAudioChannelLayoutTag_Mono;
    
    NSDictionary *audioOutputSettings = @{AVFormatIDKey :@(kAudioFormatMPEG4AAC),
                                          AVEncoderBitRateKey: @(64000),
                                          AVSampleRateKey: @(44100.0),
                                          AVNumberOfChannelsKey: @(1),
                                          AVChannelLayoutKey: [NSData dataWithBytes:&acl length:sizeof(acl)]};
    
    _audioWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:audioOutputSettings];
    _audioWriterInput.expectsMediaDataInRealTime = YES;

    if ([_asserWriter canAddInput:_audioWriterInput])
        [_asserWriter addInput:_audioWriterInput];
    else
        NSLog(@"Could not add audio input");
}

#pragma mark - Action Methods
- (void) startSuccess:(void(^)(void)) success completely:(void(^)(void)) complete cameraNotAuthorized:(void(^)(void)) cameraNotAuthorized failed:(void(^)(void)) failed {
    _CaptureFinish = complete;
    _currentCaptureSecond = 0;
    _orignalCaptureSecond = 0;
    
    sessionThread(^{
        if (_sessionRunning) return;
        
        switch (_setupResult) {
            case AVCamSetupResultSuccess: {
                [_session startRunning];
                
                _sessionRunning = _session.isRunning;
                
                if (_type == AVOutputTypeRecording) {
                    [self startRecording];
                }else {
                    [self startAssertWirter];
                }
                
                mainThread(^{
                    if (success) success();
                });
                break;
            } case AVCamSetupResultCameraNotAuthorized: {
                mainThread(^{
                    if (cameraNotAuthorized) cameraNotAuthorized();
                });
                break;
            } case AVCamSetupResultSessionConfigurationFailed: {
                mainThread(^{
                    if (failed) failed();
                });
                break;
            }
        }
    });
}

- (void) stopCompletely:(void(^)(void)) complete {
    _CaptureFinish = complete;
    
    sessionThread(^{
        if (!_sessionRunning) return;
        
        if (_setupResult == AVCamSetupResultSuccess ) {
            [_session stopRunning];

            if (_type == AVOutputTypeAssertWriter) {
                [self stopAssertWriter];
            }
            
            NSLog(@"capture stop");
        }
    });
}

#pragma mark - Recording
- (void) startRecording {
    NSString *outputPath = [self getCurrentFileName];
    NSURL *outputURL = [[NSURL alloc] initFileURLWithPath:outputPath];
    
    /* movie dat recording */
    [_movieDataOutput startRecordingToOutputFileURL:outputURL recordingDelegate:self];
}

#pragma mark - AssertWriter
- (void) startAssertWirter {
    [self addAssertWriter];
    
    if (_asserWriter && _asserWriter.status != AVAssetWriterStatusWriting) {
        [_asserWriter startWriting];
    }
}

- (void) startSessionAtSourceTime {
    if (_asserWriter.status == AVAssetWriterStatusWriting) {
        [_asserWriter startSessionAtSourceTime:_lastSampleTime];
        _isStartSession = YES;
    }
}

- (void) stopAssertWriter {
    if (_asserWriter.status == AVAssetWriterStatusWriting) {
        [_asserWriter finishWritingWithCompletionHandler:^{
            _sessionRunning = NO;
            
            mainThread(^{
                if (_CaptureFinish) _CaptureFinish();
            });
            
            _asserWriter = nil;
            _audioWriterInput = nil;
            _videoWriterInput = nil;
        }];
    }
}

#pragma mark - AVCaptureFileOutputRecordingDelegate Methods
- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didStartRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections {
    NSLog(@"%@", NSStringFromSelector(_cmd));
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)error {
    NSLog(@"%@", NSStringFromSelector(_cmd));
    
    BOOL recordedSuccessfully = YES;
    if ([error code] != noErr) {
        id value = [[error userInfo] objectForKey:AVErrorRecordingSuccessfullyFinishedKey];
        if (value)
            recordedSuccessfully = [value boolValue];
    }
    
    if (!recordedSuccessfully)
        return;
    
    mainThread(^{
        _sessionRunning = NO;
        
        if (_CaptureFinish) _CaptureFinish();
    });
}

#pragma mark - AVCaptureFileOutputDelegate Delegate
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
//    NSLog(@"%@ %@", NSStringFromSelector(_cmd), NSStringFromClass([captureOutput class]));
//
//    if (captureOutput == _videoDataOutput) {
//        UIImage *image = [self imageFromSampleBuffer:sampleBuffer];
//    }
    
    if (_orignalCaptureSecond == 0)
        _orignalCaptureSecond = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer));
    
    _lastSampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    _currentCaptureSecond = CMTimeGetSeconds(_lastSampleTime) - _orignalCaptureSecond;
    
    if (!_isStartSession) {
        [self startSessionAtSourceTime];
        return;
    }
    
    @autoreleasepool {
        if (captureOutput == _videoDataOutput) {
            if (connection.isVideoOrientationSupported) {
                connection.videoOrientation = _initialVideoOrientation;
            }
            
            if (_asserWriter && _asserWriter.status > AVAssetWriterStatusWriting) {
                NSLog(@"Warning: writer status is %ld", (long)_asserWriter.status);
                
                if (_asserWriter.status == AVAssetWriterStatusFailed) {
                    NSLog(@"Error: %@", _asserWriter.error);
                    return;
                }
            }
            
            if (_videoWriterInput && [_videoWriterInput isReadyForMoreMediaData]) {
                if (![_videoWriterInput appendSampleBuffer:sampleBuffer]) {
                    NSLog(@"unable to write video frame : %lld",_lastSampleTime.value);
                } else {
                    NSLog(@"recorded video frame time %.2f", CMTimeGetSeconds(_lastSampleTime));
                }
            }
        } else {
            if (_asserWriter && _asserWriter.status > AVAssetWriterStatusWriting) {
                NSLog(@"Warning: writer status is %ld", (long)_asserWriter.status);
                
                if (_asserWriter.status == AVAssetWriterStatusFailed) {
                    NSLog(@"Error: %@", _asserWriter.error);
                    return;
                }
            }
            
            if (_audioWriterInput && [_audioWriterInput isReadyForMoreMediaData]) {
                if (![_audioWriterInput appendSampleBuffer:sampleBuffer]) {
                    NSLog(@"unable to write audio frame : %lld",_lastSampleTime.value);
                } else {
                    NSLog(@"recorded audio frame time %.2f", CMTimeGetSeconds(_lastSampleTime));
                }
            }
        }
    }
}

- (void) captureOutput:(AVCaptureOutput *)captureOutput didDropSampleBuffer:(CMSampleBufferRef) sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    NSLog(@"%@", NSStringFromSelector(_cmd));
}

@end
