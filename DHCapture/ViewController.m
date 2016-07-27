//
//  ViewController.m
//  DHCapture
//
//  Created by Dareen Hsu on 7/25/16.
//  Copyright © 2016 SKL. All rights reserved.
//

#import "ViewController.h"
#import "DHCaptureManager.h"

@interface ViewController ()

@property (nonatomic, strong) DHCaptureManager *manager;
@property (nonatomic, weak) IBOutlet DHPreviewView *preview;
@property (nonatomic, weak) IBOutlet UIImageView *captureView;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    _manager = [DHCaptureManager shardInstance];
    [_manager initializeWithView:_preview];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [_manager startSuccess:NULL captureImage:^(UIImage *image) {
        _captureView.image = image;
    } cameraNotAuthorized:^{

    } failed:^{

    }];
}

- (void)viewDidDisappear:(BOOL)animated {
    [_manager stop];

    [super viewDidDisappear:animated];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (BOOL)shouldAutorotate {
    return !_manager.isSessionRunning;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];

    UIDeviceOrientation deviceOrientation = [UIDevice currentDevice].orientation;
    if ( UIDeviceOrientationIsPortrait( deviceOrientation ) || UIDeviceOrientationIsLandscape( deviceOrientation ) ) {
        AVCaptureVideoPreviewLayer *previewLayer = (AVCaptureVideoPreviewLayer *)_preview.layer;
        previewLayer.connection.videoOrientation = (AVCaptureVideoOrientation)deviceOrientation;
    }
}


@end
