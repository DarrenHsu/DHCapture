//
//  DHListViewController.m
//  DHCapture
//
//  Created by Dareen Hsu on 8/2/16.
//  Copyright © 2016 SKL. All rights reserved.
//

#import "DHListViewController.h"
#import "DHCaptureManager.h"

@import MediaPlayer;
@import AVKit;

@interface DHListViewController () <AVPlayerViewControllerDelegate, UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, weak) IBOutlet UITableView *tableView;

@property (nonatomic, strong) DHCaptureManager *manager;
@property (nonatomic, strong) NSMutableArray *movies;


@end

@implementation DHListViewController

- (void) viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.

    _manager = [DHCaptureManager shardInstance];
}

- (void) didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void) viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    _movies = [NSMutableArray arrayWithArray:[_manager getMovieFiles]];

    [_tableView reloadData];
}

- (void) playMovie:(NSString *) path {
    NSString *fullPath = [[_manager getBasePath] stringByAppendingFormat:@"/%@",path];
    NSURL *url = [[NSURL alloc] initFileURLWithPath:fullPath];

    NSError *error;
    NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:&error];

    NSNumber *fileSizeNumber = [fileAttributes objectForKey:NSFileSize];
    long long fileSize = [fileSizeNumber longLongValue];

    NSLog(@"%lld",fileSize);

    AVPlayerViewController *controller = [[AVPlayerViewController alloc] init];
    controller.delegate = self;
    controller.player = [[AVPlayer alloc] initWithURL:url];
    [self presentViewController:controller animated:YES completion:NULL];
}

#pragma mark - UITableViewDataSource Methods
- (NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _movies.count;
}

- (UITableViewCell *) tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifer = @"tablecell";

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifer];
    if (!cell)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifer];

    cell.textLabel.text = _movies[indexPath.row];

    return cell;
}

#pragma mark - UITableViewDelegate Methods
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSString *file = _movies[indexPath.row];
    [self playMovie:file];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSString *fullPath = [[_manager getBasePath] stringByAppendingFormat:@"/%@",_movies[indexPath.row]];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if ([fileManager fileExistsAtPath:fullPath]) {
            NSError *error;
            [fileManager removeItemAtPath:fullPath error:&error];

            [_movies removeObjectAtIndex:indexPath.row];
            [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationBottom];
        }
    }
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleDelete;
}

- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
    return @"刪除";
}

#pragma mark - AVPlayerViewControllerDelegate Methods
- (void)playerViewControllerWillStartPictureInPicture:(AVPlayerViewController *)playerViewController {
    NSLog(@"%@",NSStringFromSelector(_cmd));
}

- (void)playerViewControllerDidStartPictureInPicture:(AVPlayerViewController *)playerViewController {
    NSLog(@"%@",NSStringFromSelector(_cmd));
}

- (void)playerViewController:(AVPlayerViewController *)playerViewController failedToStartPictureInPictureWithError:(NSError *)error {
    NSLog(@"%@",NSStringFromSelector(_cmd));
}

- (void)playerViewControllerWillStopPictureInPicture:(AVPlayerViewController *)playerViewController {
    NSLog(@"%@",NSStringFromSelector(_cmd));
}

- (void)playerViewControllerDidStopPictureInPicture:(AVPlayerViewController *)playerViewController {
    NSLog(@"%@",NSStringFromSelector(_cmd));
}

- (BOOL)playerViewControllerShouldAutomaticallyDismissAtPictureInPictureStart:(AVPlayerViewController *)playerViewController {
    NSLog(@"%@",NSStringFromSelector(_cmd));

    return YES;
}

- (void)playerViewController:(AVPlayerViewController *)playerViewController restoreUserInterfaceForPictureInPictureStopWithCompletionHandler:(void (^)(BOOL restored))completionHandler {
    NSLog(@"%@",NSStringFromSelector(_cmd));
}

@end