//
//  DHCaptureViewController.m
//  DHCapture
//
//  Created by Dareen Hsu on 8/2/16.
//  Copyright © 2016 SKL. All rights reserved.
//

#import "DHCaptureViewController.h"
#import "DHCaptureManager.h"

@interface DHCaptureViewController ()

@property (nonatomic, strong) DHCaptureManager *manager;
@property (nonatomic, weak) IBOutlet DHPreviewView *preview;
@property (nonatomic, weak) IBOutlet UIButton *startButton;

@end

@implementation DHCaptureViewController

- (IBAction) startPressed:(id)sender {
    if (!_manager.isSessionRunning) {
        [_manager startSuccess:^{
            [_startButton setImage:[UIImage imageNamed:_manager.isSessionRunning ? @"ic_stop" : @"ic_play"] forState:UIControlStateNormal];
        } completely:^{
            [_startButton setImage:[UIImage imageNamed:_manager.isSessionRunning ? @"ic_stop" : @"ic_play"] forState:UIControlStateNormal];
        } cameraNotAuthorized:^{
            [_startButton setImage:[UIImage imageNamed:_manager.isSessionRunning ? @"ic_stop" : @"ic_play"] forState:UIControlStateNormal];
        } failed:^{
            [_startButton setImage:[UIImage imageNamed:_manager.isSessionRunning ? @"ic_stop" : @"ic_play"] forState:UIControlStateNormal];
        }];
    }else {
        [_manager stopCompletely:^{
            [_startButton setImage:[UIImage imageNamed:_manager.isSessionRunning ? @"ic_stop" : @"ic_play"] forState:UIControlStateNormal];
        }];
    }
}

- (void) viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.

    _manager = [DHCaptureManager shardInstance];
    [_manager initializeWithView:_preview];
    
}

- (void) didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void) viewDidDisappear:(BOOL)animated {
    [_manager stopCompletely:^{
        [_startButton setImage:[UIImage imageNamed:_manager.isSessionRunning ? @"ic_stop" : @"ic_play"] forState:UIControlStateNormal];
    }];

    [super viewDidDisappear:animated];
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
