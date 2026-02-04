/*
 Copyright 2016-present Google Inc. All Rights Reserved.

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

@import AVFoundation;
@import MLKitBarcodeScanning;
@import MLKitVision;

#import "CameraViewController.h"

@interface CameraViewController ()<AVCaptureVideoDataOutputSampleBufferDelegate>

@property(nonatomic, weak) IBOutlet UIView *placeHolderView;
@property(nonatomic, weak) IBOutlet UIView *overlayView;
@property(nonatomic, strong) UIImageView *imageView;

@property(nonatomic, strong) AVCaptureSession *session;
@property(nonatomic, strong) AVCaptureVideoDataOutput *videoDataOutput;
@property(nonatomic, strong) dispatch_queue_t videoDataOutputQueue;
@property(nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;

@property(nonatomic, strong) MLKBarcodeScanner *barcodeDetector;
@property(nonatomic, strong) UIButton *torchButton;

// New properties for continuous mode
@property(nonatomic, strong) UIView *flashOverlayView;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UILabel *subtitleLabel;
@property(nonatomic, strong) UILabel *statsLabel;
@property(nonatomic, strong) UIView *scanFrameView;  // Reference to scan frame for animations
@property(nonatomic, strong) UIImageView *logoImageView;  // Logo below scan frame
@property(nonatomic, copy) NSString *lastScannedValue;
@property(nonatomic, assign) NSTimeInterval lastScanTime;

@end

static const NSTimeInterval kScanDebounceSeconds = 1.5;

@implementation CameraViewController
@synthesize delegate;

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

- (BOOL)prefersHomeIndicatorAutoHidden
{
    return YES;
}

- (BOOL) shouldAutorotate
{
    return NO;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        _videoDataOutputQueue = dispatch_queue_create("VideoDataOutputQueue",
                                                      DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Set up camera.
    self.session = [[AVCaptureSession alloc] init];
    self.session.sessionPreset = AVCaptureSessionPresetHigh;

    _videoDataOutputQueue = dispatch_queue_create("VideoDataOutputQueue",
                                                  DISPATCH_QUEUE_SERIAL);

    [self updateCameraSelection];

    // Set up video processing pipeline.
    [self setUpVideoProcessing];

    // Set up camera preview.
    [self setUpCameraPreview];

    //Parse Cordova settings.
    NSNumber *formats = 0;
    //If barcodeFormats == 0 then process as a VIN with VIN verifications.
    if([_barcodeFormats  isEqual: @0]) {
        NSLog(@"Running VIN style");
        formats = @(MLKBarcodeFormatCode39|MLKBarcodeFormatDataMatrix);
    } else if([_barcodeFormats  isEqual: @1234]) {
        // @todo: investigating what should be done here
    } else {
        formats = _barcodeFormats;
    }
    NSLog(@"_barcodeFormats %@, %@", _barcodeFormats, formats);

    // Initialize barcode detector.
    MLKBarcodeScannerOptions *options = [[MLKBarcodeScannerOptions alloc] initWithFormats: [formats intValue]];
    self.barcodeDetector = [MLKBarcodeScanner barcodeScannerWithOptions:options];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    self.previewLayer.frame = self.view.layer.bounds;
    self.previewLayer.position = CGPointMake(CGRectGetMidX(self.previewLayer.frame),
                                             CGRectGetMidY(self.previewLayer.frame));
}

- (void)dealloc {
    [self cleanupCaptureSession];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (authStatus == AVAuthorizationStatusDenied) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Camera permission required" message:@"Access to the camera has been prohibited, please enable it in the settings to continue." preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *primaryAction = [UIAlertAction actionWithTitle:@"Settings" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];
            [self.delegate closeScanner];
        }];
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            [self.delegate closeScanner];
        }];
        [alert addAction:cancelAction];
        [alert addAction:primaryAction];
        alert.preferredAction = primaryAction;
        [self presentViewController:alert animated:YES completion:nil];
    } else {
        //Force portrait orientation.
        [[UIDevice currentDevice] setValue:
         [NSNumber numberWithInteger: UIInterfaceOrientationPortrait]
                                    forKey:@"orientation"];
        
        [self.session startRunning];
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.session stopRunning];
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {

    //Convert sampleBuffer into an image.
    //MLKVisionImage *image = [[MLKVisionImage alloc] initWithBuffer:sampleBuffer];
    CVImageBufferRef imageBuffer =
    CMSampleBufferGetImageBuffer(sampleBuffer);
    CIImage *ciImage = [CIImage imageWithCVPixelBuffer:imageBuffer];
    CIContext *temporaryContext = [CIContext contextWithOptions:nil];
    CGImageRef videoImage = [temporaryContext
                             createCGImage:ciImage
                             fromRect:CGRectMake(0, 0,
                                                 CVPixelBufferGetWidth(imageBuffer),
                                                 CVPixelBufferGetHeight(imageBuffer))];

    UIImage *image = [[UIImage alloc] initWithCGImage:videoImage];
    CGImageRelease(videoImage);

    //We're going to crop UIImage to the onscreen viewfinder's box size for faster processing.
    UIImage *croppedImg = nil;

    //Define the crop coordinates.
    CGRect screenRect = [[UIScreen mainScreen] bounds];
    CGFloat screenWidth = screenRect.size.width;
    CGFloat screenHeight = screenRect.size.height;
    
    CGFloat imageWidth = image.size.width;
    CGFloat imageHeight = image.size.height;
    
    CGFloat actualFrameWidth = 0;
    CGFloat actualFrameHeight = 0;
    
    //Figure out which ratio is bigger and then subtract a value off the frame width in case some of the camera preview is hanging off screen.
    if(imageWidth/screenWidth < imageHeight/screenHeight){
        actualFrameWidth = imageWidth * _detectorSize;
        actualFrameHeight = actualFrameWidth;
    } else {
        actualFrameHeight = imageHeight * _detectorSize;
        actualFrameWidth = actualFrameHeight;
    }

    //Define crop rectangle.
    CGRect cropRect = CGRectMake(imageWidth/2 - actualFrameWidth/2, imageHeight/2 - actualFrameHeight/2, actualFrameWidth, actualFrameHeight);

    //Crop image
    croppedImg = [self croppIngimageByImageName:image toRect:cropRect];

    //Rotate the image.
    MLKVisionImage *portraitImage = [[MLKVisionImage alloc] initWithImage:croppedImg];
    portraitImage.orientation = UIImageOrientationRight;

    //Send the image through the barcode reader.
    [self.barcodeDetector processImage:portraitImage completion:^(NSArray<MLKBarcode *> *barcodes,
                                                          NSError *error) {
        if (error != nil) {
            return;
        } else if (barcodes != nil) {
            for (MLKBarcode *barcode in barcodes) {
                NSLog(@"Barcode value: %@", barcode.rawValue);
                
                if (self.continuousMode) {
                    // Continuous mode: debounce and keep scanning
                    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
                    NSString *barcodeValue = barcode.rawValue ?: @"";
                    
                    // Check if this is the same barcode within debounce period
                    BOOL isDuplicate = [barcodeValue isEqualToString:self.lastScannedValue] &&
                                       (currentTime - self.lastScanTime) < kScanDebounceSeconds;
                    
                    if (!isDuplicate) {
                        // Update last scan info
                        self.lastScannedValue = barcodeValue;
                        self.lastScanTime = currentTime;
                        
                        // Trigger focus animation
                        [self animateFocusEffect];
                        
                        // Send result via delegate (don't stop camera)
                        [self->delegate sendContinuousResult:barcode];
                    }
                } else {
                    // Single scan mode: stop and return result
                    
                    // Trigger focus animation
                    [self animateFocusEffect];
                    
                    [self cleanupCaptureSession];
                    [self->_session stopRunning];
                    [self->delegate sendResult:barcode];
                }
                break;
            }
        }
    }];

}

#pragma mark - Camera setup

- (void)cleanupVideoProcessing {
    if (self.videoDataOutput) {
        [self.session removeOutput:self.videoDataOutput];
    }
    self.videoDataOutput = nil;
}

- (void)cleanupCaptureSession {
    [self.session stopRunning];
    [self cleanupVideoProcessing];
    self.session = nil;
    [self.previewLayer removeFromSuperlayer];
}

- (void)setUpVideoProcessing {
    self.videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    NSDictionary *rgbOutputSettings = @{
        (__bridge NSString*)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA)
    };
    [self.videoDataOutput setVideoSettings:rgbOutputSettings];

    if (![self.session canAddOutput:self.videoDataOutput]) {
        [self cleanupVideoProcessing];
        NSLog(@"Failed to setup video output");
        return;
    }
    [self.videoDataOutput setAlwaysDiscardsLateVideoFrames:YES];
    [self.videoDataOutput setSampleBufferDelegate:self queue:self.videoDataOutputQueue];
    [self.session addOutput:self.videoDataOutput];
}

- (void)setUpCameraPreview {
    self.previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.session];
    [self.previewLayer setBackgroundColor:[UIColor blackColor].CGColor];
    [self.previewLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];

    self.previewLayer.frame = self.view.superview.bounds;
    [self.view.layer addSublayer:self.previewLayer];

    CGRect screenRect = [[UIScreen mainScreen] bounds];
    CGFloat screenWidth = screenRect.size.width;
    CGFloat screenHeight = screenRect.size.height;

    CGFloat frameWidth = screenWidth*_detectorSize;
    CGFloat frameHeight = frameWidth;

    // Create corner brackets overlay instead of full square
    CGFloat cornerLength = 40.0;  // Length of each corner line
    CGFloat cornerWidth = 4.0;    // Thickness of corner lines
    UIColor *cornerColor = [UIColor whiteColor];
    
    UIView *scanFrameView = [[UIView alloc] init];
    scanFrameView.frame = CGRectMake(screenWidth/2 - frameWidth/2, screenHeight/2 - frameHeight/2, frameWidth, frameHeight);
    scanFrameView.backgroundColor = [UIColor clearColor];
    scanFrameView.userInteractionEnabled = YES;
    
    UITapGestureRecognizer* tapScanner = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(focusAtPoint:)];
    [scanFrameView addGestureRecognizer:tapScanner];
    
    // Top-left corner (horizontal + vertical)
    UIView *topLeftH = [[UIView alloc] initWithFrame:CGRectMake(0, 0, cornerLength, cornerWidth)];
    topLeftH.backgroundColor = cornerColor;
    [scanFrameView addSubview:topLeftH];
    
    UIView *topLeftV = [[UIView alloc] initWithFrame:CGRectMake(0, 0, cornerWidth, cornerLength)];
    topLeftV.backgroundColor = cornerColor;
    [scanFrameView addSubview:topLeftV];
    
    // Top-right corner (horizontal + vertical)
    UIView *topRightH = [[UIView alloc] initWithFrame:CGRectMake(frameWidth - cornerLength, 0, cornerLength, cornerWidth)];
    topRightH.backgroundColor = cornerColor;
    [scanFrameView addSubview:topRightH];
    
    UIView *topRightV = [[UIView alloc] initWithFrame:CGRectMake(frameWidth - cornerWidth, 0, cornerWidth, cornerLength)];
    topRightV.backgroundColor = cornerColor;
    [scanFrameView addSubview:topRightV];
    
    // Bottom-left corner (horizontal + vertical)
    UIView *bottomLeftH = [[UIView alloc] initWithFrame:CGRectMake(0, frameHeight - cornerWidth, cornerLength, cornerWidth)];
    bottomLeftH.backgroundColor = cornerColor;
    [scanFrameView addSubview:bottomLeftH];
    
    UIView *bottomLeftV = [[UIView alloc] initWithFrame:CGRectMake(0, frameHeight - cornerLength, cornerWidth, cornerLength)];
    bottomLeftV.backgroundColor = cornerColor;
    [scanFrameView addSubview:bottomLeftV];
    
    // Bottom-right corner (horizontal + vertical)
    UIView *bottomRightH = [[UIView alloc] initWithFrame:CGRectMake(frameWidth - cornerLength, frameHeight - cornerWidth, cornerLength, cornerWidth)];
    bottomRightH.backgroundColor = cornerColor;
    [scanFrameView addSubview:bottomRightH];
    
    UIView *bottomRightV = [[UIView alloc] initWithFrame:CGRectMake(frameWidth - cornerWidth, frameHeight - cornerLength, cornerWidth, cornerLength)];
    bottomRightV.backgroundColor = cornerColor;
    [scanFrameView addSubview:bottomRightV];

    CGFloat buttonSize = 45.0;

    UIButton *_cancelButton = [[UIButton alloc] init];
    [_cancelButton addTarget:self
                      action:@selector(closeView:)
            forControlEvents:UIControlEventTouchUpInside];

    NSString * cancelBase64String = @"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAQAAABpN6lAAAAABGdBTUEAALGPC/xhBQAAACBjSFJNAAB6JgAAgIQAAPoAAACA6AAAdTAAAOpgAAA6mAAAF3CculE8AAAAAmJLR0QAAKqNIzIAAAAJcEhZcwAADdcAAA3XAUIom3gAAAAHdElNRQfhCxMVEyaNvw4TAAADNElEQVR42u2dv1LqQBSHv1DwBjY0FjyAA7wCtna2ttrwLr6GY4PWKfQBJGNtb2PDMFQ2ewvmDheBC0l295zjYVO6Cb/vC4b82c0p+Lf1GDNkwAVfzKh4oyRguxWMGTFgyBnvVMwo+dzd8Y4F4cfyQl+aoFXr87LFtOCW4mfHc8qtjqtlyWS7u4lWMGG5h6rkfBN/vqfjapnSlaap3bpM/8s0Xyso9u799fJkTEGXp4NM5d9v9t3BrtYUHIMfCNwC9HYc+mwrOBY/sKAHN0d2tqLgePxA4Abua3TXr6AefuAeXmutoFtBXfzAKwd+AC0pqI8fmMNH7ZV0KmiCH/iAhwar6VPQDD/w0KFq9IFXPCpS0OWRq0ZrVnDZyJymb0HTvR8IXEKx43rJkoI2+C+rk+H+3msm/Qra4C/Xl/qTxhuRVdAGPzBZb6g4cOmoU0E7/OnmXY52G5NQED2xLQVJ0tpRkCypDQVJU+pXkDyhbgVZ0ulVkC2ZTgVZU+lTkD2RLgUiafQoEEuiQ4FoCnkF4glkA4jjy4ZQgS8XRA2+TBhV+PkDqcPPG0olfr5gavHzhFONnz6gevy0IU3gpwtqBj9NWFP48QObw48b2iR+vOBm8eOEN40fQ4Fx/PYKzONLKVCEL6FAGX5uBQrxcypQip9LgWL8HAqU46dWYAA/pQIj+KkUGMJPocAYfmwFBvFjKjCKH0uBYfwYCpLjd6QN/e7m/F/A+UHQ+c+g8xMh56fCzi+GnF8OO78h4vyWmPObos5vizt/MOL80Zjzh6POH487HyDhfIiM80FSzofJOR8o6XyorPPB0s6HyzufMOF8yozzSVPOp805nzjpfOqs88nTzqfPiwfw/v4I0RQ68MWS6MEXSaMLP3siffhZU+nEz5ZML36WdLrxkyfUj580pQ38ZEnt4CdJaws/emL3r9Z2/nJ156/Xd19gwXmJjQ6jhh/7zDXf0uwAfHPNc8N1R+7L7JwKLZ1KbTkvtla30pSeQ9+uVv9wWJ0KLp5Kbrovunoqu4v7wssrBa5Lb6+6uyy+vrlve4wZMuCCL2ZUvFESpBlatoIxIwYMOeOdihkln+s//wFFdoCM42fEswAAACV0RVh0ZGF0ZTpjcmVhdGUAMjAxNy0xMS0xOVQyMToxOTozOCswMTowMPNH2M8AAAAldEVYdGRhdGU6bW9kaWZ5ADIwMTctMTEtMTlUMjE6MTk6MzgrMDE6MDCCGmBzAAAAGXRFWHRTb2Z0d2FyZQB3d3cuaW5rc2NhcGUub3Jnm+48GgAAAABJRU5ErkJggg==";

    NSURL *cancelImageUrl = [NSURL URLWithString:cancelBase64String];
    NSData *cancelImageData = [NSData dataWithContentsOfURL:cancelImageUrl];
    UIImage *cancelIcon = [UIImage imageWithData:cancelImageData];
    [_cancelButton setImage:cancelIcon
                   forState:UIControlStateNormal];

    CGFloat screenOffset = (screenWidth/2 - frameWidth/2)/2 - buttonSize/2;
    NSLog(@"screenOffset %f", screenOffset);

    _cancelButton.frame = CGRectMake(screenOffset, screenHeight-screenOffset-buttonSize, buttonSize, buttonSize);
    _cancelButton.backgroundColor = [UIColor colorWithWhite:1 alpha:0.4];
    _cancelButton.transform=CGAffineTransformMakeRotation(M_PI / 2);
    _cancelButton.layer.cornerRadius = buttonSize/2;
    _cancelButton.contentEdgeInsets = UIEdgeInsetsMake(15, 15, 15, 15);

    [self.view addSubview:_cancelButton];




    self.torchButton = [[UIButton alloc] init];
    [self.torchButton addTarget:self
                         action:@selector(toggleFlashlight:)
               forControlEvents:UIControlEventTouchUpInside];

    NSString * torchBase64String = @"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAQAAABpN6lAAAAABGdBTUEAALGPC/xhBQAAACBjSFJNAAB6JgAAgIQAAPoAAACA6AAAdTAAAOpgAAA6mAAAF3CculE8AAAAAmJLR0QAAKqNIzIAAAAJcEhZcwAADdcAAA3XAUIom3gAAAAHdElNRQfhCxMVAzOqoPipAAADM0lEQVR42u2dv2sTcRyG38RWzGYHhxYHp+B+Lk7iIlhFXZvdPeAouOuS1X/AVCiiCBU6OjgIOffG+gvEgCIqlsQi9JxEbC/XJt8fz136eTJecve+T+6Su8t9czX5oqmWEiVa9DbHfAZKlaqrfuDlTERNbQ2VRXwM1VaNrv2v/nrU8n8f62VR0EbqZ8rUpqtLUjPyyv//htB0jV93FrCiBia/oRYv4BxWX5IS1xm4f4x8Cv7FV8RAS7SADKzvoYH7JlBxTAAdgMYE0AFoTAAdwDAMwzAMo7q8ws4IZsr0wjW++57gFqrfeenuAt6YAJLXvADbBFABJVgDPmobrP+DF5BpAxPwyH0WPk6IPKmyAB8/MJ/UZ80D9T/ojPtMfKwB3/UcqO/l/fd1TvAxIuAhstRclrQT/ShgzU/0Y17m8lMLOh9V+UjX3L8CfbKgr1Hf/zt04f3EvFLorU7QdfdzXFuR6v/SRbpsPjci1b9MFx3P7eD1d3SFLlnM3cD1r9IFD+Z+wJW/AvWluh4EqT/UJbraYZnTmvf627pA12IV3KQrTa7gqcf6z+g603BKXzzV/+Z6NSjFiicB9+gi07PhRcBZusb0XPdQ3/nXP5J5D58Dt8JGDHuZ3G8Pp60C//AS+jrBl85zeBc24FxgAe/HTulrVT2lkhIlao0d/RNYQGhO527Xu+rsGWnUUEe7uc+tOPXc+su5z13OVVB59lfqjH1u5ygI2CwYZtfQZmwB8a8WX9Vo7LSRurHjxBfQK5yaRs8TnL2rdPEow8XZ3wRKRnwBicPUmRBQPNY4uoDwlPxrML6AI78jZLvC5ToYCv83JOMqHPZwOHBCTkBJEtqOEB2AxgTQAWhMAB2AxgTQAWhMAB2AxgTQAWhMAB2AxgTQAWhMAB2AxgTQAWhMAB2AxgTQAWhMAB2AxgTQAWhMAB2AxgTQAWhMAB2AxgTQAWhMAB2AxgTQAWhMAB2AxgTQAWhMAB2AxgQEX8IAfHUpBLgNhg0+lDa8gJ7Tq2dgLLHLbXk93Fa3DEz/d6ttOrofpr01d2lure1DwaQ3Z492c/V4jptqKVFy4F2KB0qVqqt+nFh/ADjJgLiaxweIAAAAJXRFWHRkYXRlOmNyZWF0ZQAyMDE3LTExLTE5VDIxOjAzOjUxKzAxOjAwdhzbkgAAACV0RVh0ZGF0ZTptb2RpZnkAMjAxNy0xMS0xOVQyMTowMzo1MSswMTowMAdBYy4AAAAZdEVYdFNvZnR3YXJlAHd3dy5pbmtzY2FwZS5vcmeb7jwaAAAAAElFTkSuQmCCconv";

    NSURL *torchImageUrl = [NSURL URLWithString:torchBase64String];
    NSData *torchImageData = [NSData dataWithContentsOfURL:torchImageUrl];
    UIImage *torchIcon = [UIImage imageWithData:torchImageData];
    [self.torchButton setImage:torchIcon
                      forState:UIControlStateNormal];

    self.torchButton.frame = CGRectMake(screenWidth-screenOffset-buttonSize, screenHeight-screenOffset-buttonSize, buttonSize, buttonSize);
    self.torchButton.backgroundColor = [UIColor colorWithWhite:1 alpha:0.4];
    self.torchButton.transform=CGAffineTransformMakeRotation(M_PI / 2);
    self.torchButton.layer.cornerRadius = buttonSize/2;
    self.torchButton.contentEdgeInsets = UIEdgeInsetsMake(10, 10, 10, 10);

    [self.view addSubview:self.torchButton];

    [self.view addSubview:scanFrameView];
    
    // Store reference for animations
    self.scanFrameView = scanFrameView;

    self.imageView = [[UIImageView alloc] initWithImage:nil];

    UIView *catView = [[UIView alloc] initWithFrame:CGRectMake(0,0,frameWidth,frameHeight)];
    self.imageView.frame = catView.bounds;

    // add the imageview to the superview
    [catView addSubview:self.imageView];

    //add the view to the main view

    [self.view addSubview:catView];

    // Set up flash overlay view (for continuous mode feedback)
    self.flashOverlayView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.flashOverlayView.backgroundColor = [UIColor greenColor];
    self.flashOverlayView.alpha = 0.0;
    self.flashOverlayView.hidden = YES;
    self.flashOverlayView.userInteractionEnabled = NO;
    [self.view addSubview:self.flashOverlayView];

    // Set up text overlays (top-right corner, right-aligned) for continuous mode
    if (self.titleText && self.titleText.length > 0) {
        CGFloat topPadding = 60.0; // Account for notch/status bar area
        CGFloat rightPadding = 20.0;
        CGFloat labelWidth = screenWidth - 40; // Allow enough width for text
        CGFloat lineHeight = 24.0;
        CGFloat verticalSpacing = 4.0; // Tight spacing between lines
        
        // Title label (Line 1)
        self.titleLabel = [[UILabel alloc] init];
        self.titleLabel.frame = CGRectMake(rightPadding, topPadding, labelWidth, lineHeight);
        self.titleLabel.text = self.titleText;
        self.titleLabel.textColor = [UIColor whiteColor];
        self.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        self.titleLabel.textAlignment = NSTextAlignmentRight;
        self.titleLabel.numberOfLines = 1;
        [self.view addSubview:self.titleLabel];
        
        // Subtitle label (Line 2)
        if (self.subtitleText && self.subtitleText.length > 0) {
            self.subtitleLabel = [[UILabel alloc] init];
            self.subtitleLabel.frame = CGRectMake(rightPadding, topPadding + lineHeight + verticalSpacing, labelWidth, lineHeight - 4);
            self.subtitleLabel.text = self.subtitleText;
            self.subtitleLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.7];
            self.subtitleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
            self.subtitleLabel.textAlignment = NSTextAlignmentRight;
            self.subtitleLabel.numberOfLines = 1;
            [self.view addSubview:self.subtitleLabel];
        }
    }
    
    // Stats label (Line 3, below title/subtitle for continuous mode)
    if (self.continuousMode) {
        CGFloat topPadding = 60.0;
        CGFloat rightPadding = 20.0;
        CGFloat labelWidth = screenWidth - 40;
        CGFloat lineHeight = 24.0;
        CGFloat verticalSpacing = 4.0;
        
        // Calculate Y position (below subtitle if it exists, otherwise below title)
        CGFloat statsY = topPadding + lineHeight + verticalSpacing;
        if (self.subtitleText && self.subtitleText.length > 0) {
            statsY += (lineHeight - 4) + verticalSpacing;
        }
        
        self.statsLabel = [[UILabel alloc] init];
        self.statsLabel.frame = CGRectMake(rightPadding, statsY, labelWidth, lineHeight - 4);
        self.statsLabel.text = @"";
        self.statsLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.65];
        self.statsLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightMedium];
        self.statsLabel.textAlignment = NSTextAlignmentRight;
        self.statsLabel.numberOfLines = 1;
        [self.view addSubview:self.statsLabel];
    }
    
    // Set up logo image below scan frame (for continuous mode)
    if (self.continuousMode && self.showLogo) {
        UIImage *logoImage = [UIImage imageNamed:@"scanner_logo"];
        if (logoImage) {
            // Calculate logo size maintaining aspect ratio based on specified height
            CGFloat logoHeight = self.logoHeight > 0 ? self.logoHeight : 40.0;
            CGFloat aspectRatio = logoImage.size.width / logoImage.size.height;
            CGFloat logoWidth = logoHeight * aspectRatio;
            
            // Position: below scan frame, right-aligned to bracket edge
            // scanFrameView.frame gives us the scan area position
            CGFloat scanFrameBottom = screenHeight/2 + frameHeight/2;
            CGFloat scanFrameRight = screenWidth/2 + frameWidth/2;
            CGFloat logoPadding = 16.0; // Padding below brackets
            
            CGFloat logoX = scanFrameRight - logoWidth; // Right-align to bracket edge
            CGFloat logoY = scanFrameBottom + logoPadding;
            
            self.logoImageView = [[UIImageView alloc] initWithImage:logoImage];
            self.logoImageView.frame = CGRectMake(logoX, logoY, logoWidth, logoHeight);
            self.logoImageView.contentMode = UIViewContentModeScaleAspectFit;
            self.logoImageView.userInteractionEnabled = NO;
            [self.view addSubview:self.logoImageView];
            
            NSLog(@"Logo added: size=%.0fx%.0f, position=(%.0f, %.0f)", logoWidth, logoHeight, logoX, logoY);
        } else {
            NSLog(@"Warning: scanner_logo image not found in bundle");
        }
    }

}

#pragma mark - Helper Functions

- (void)focusAtPoint:(id) sender {
    NSLog(@"captured touch");
    CGPoint touchPoint = [(UITapGestureRecognizer*)sender locationInView:self.view];
    double focus_x = touchPoint.x/self.previewLayer.frame.size.width;
    double focus_y = (touchPoint.y+66)/self.previewLayer.frame.size.height;

    NSError *error;
    NSArray *devices = [AVCaptureDevice devices];
    for (AVCaptureDevice *device in devices){
        NSLog(@"Device name: %@", [device localizedName]);
        if ([device hasMediaType:AVMediaTypeVideo]) {
            if ([device position] == AVCaptureDevicePositionBack) {
                NSLog(@"Device position : back");
                CGPoint point = CGPointMake(focus_y, 1-focus_x);
                if ([device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus] && [device lockForConfiguration:&error]){
                    [device setFocusPointOfInterest:point];

                    for (UIView *subView in self.view.subviews)
                    {
                        if (subView.tag == 99)
                        {
                            [subView removeFromSuperview];
                        }
                    }

                    CGRect rect = CGRectMake(touchPoint.x-30, touchPoint.y-30, 60, 60);
                    UIView *focusRect = [[UIView alloc] initWithFrame:rect];
                    focusRect.layer.borderColor = [UIColor colorWithRed:0.98 green:0.80 blue:0.18 alpha:.7].CGColor;
                    focusRect.layer.borderWidth = 1;
                    focusRect.tag = 99;
                    [self.view addSubview:focusRect];

                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                        [focusRect removeFromSuperview];
                    });

                    [device setFocusMode:AVCaptureFocusModeAutoFocus];
                    [device unlockForConfiguration];
                }
            }
        }
    }
}
static inline double radians (double degrees) {return degrees * M_PI/180;}
- (UIImage*) rotateImage:(UIImage*)src toOrientation:(UIImageOrientation) orientation
{
    UIGraphicsBeginImageContext(src.size);

    CGContextRef context = UIGraphicsGetCurrentContext();

    if (orientation == UIImageOrientationRight) {
        CGContextRotateCTM (context, radians(90));
    } else if (orientation == UIImageOrientationLeft) {
        CGContextRotateCTM (context, radians(-90));
    } else if (orientation == UIImageOrientationDown) {
        // NOTHING
    } else if (orientation == UIImageOrientationUp) {
        CGContextRotateCTM (context, radians(90));
    }

    [src drawAtPoint:CGPointMake(0, 0)];

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

- (UIImage *)croppIngimageByImageName:(UIImage *)imageToCrop toRect:(CGRect)rect
{
    //CGRect CropRect = CGRectMake(rect.origin.x, rect.origin.y, rect.size.width, rect.size.height+15);

    CGImageRef imageRef = CGImageCreateWithImageInRect([imageToCrop CGImage], rect);
    UIImage *cropped = [UIImage imageWithCGImage:imageRef];
    CGImageRelease(imageRef);

    return cropped;
}

- (void) toggleFlashlight:(id)sender
{
    // check if flashlight available
    Class captureDeviceClass = NSClassFromString(@"AVCaptureDevice");
    if (captureDeviceClass != nil) {
        AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        AVCapturePhotoSettings *photosettings = [AVCapturePhotoSettings photoSettings];
        if ([device hasTorch] && [device hasFlash]){

            [device lockForConfiguration:nil];
            if (device.torchMode == AVCaptureTorchModeOff)
            {
                self.torchButton.backgroundColor = [UIColor colorWithWhite:1 alpha:1];
                [device setTorchMode:AVCaptureTorchModeOn];
                photosettings.flashMode = AVCaptureFlashModeOn;
                //torchIsOn = YES;
            }
            else
            {
                self.torchButton.backgroundColor = [UIColor colorWithWhite:1 alpha:.4];
                [device setTorchMode:AVCaptureTorchModeOff];
                photosettings.flashMode = AVCaptureFlashModeOff;
                // torchIsOn = NO;
            }
            [device unlockForConfiguration];
        }
    } }

- (void)closeView:(id)sender{
    [ self cleanupCaptureSession];
    [_session stopRunning];
    [delegate closeScanner];
}

#pragma mark - Continuous Mode Methods

- (void)showFlashOverlayWithColor:(UIColor *)color duration:(NSTimeInterval)duration opacity:(CGFloat)opacity {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.flashOverlayView == nil) {
            return;
        }
        
        NSLog(@"[iOS Flash] Showing overlay - color: %@, opacity: %.2f, duration: %.2fs", color, opacity, duration);
        
        // CRITICAL: Bring overlay to the very front of view hierarchy
        // Without this, text labels and other views can render on top, reducing perceived opacity
        [self.view bringSubviewToFront:self.flashOverlayView];
        
        // Show instantly - flat, in your face
        self.flashOverlayView.backgroundColor = color;
        self.flashOverlayView.alpha = opacity;
        self.flashOverlayView.hidden = NO;
        
        NSLog(@"[iOS Flash] Overlay shown with alpha: %.2f, hidden: %d", self.flashOverlayView.alpha, self.flashOverlayView.hidden);
        
        // Stay visible for the duration, then hide instantly
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            self.flashOverlayView.hidden = YES;
            self.flashOverlayView.alpha = 0.0;
            NSLog(@"[iOS Flash] Overlay hidden after duration");
        });
    });
}

- (void)animateFocusEffect {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.scanFrameView == nil) {
            return;
        }
        
        // Quick focus effect: scale down then spring back
        [UIView animateWithDuration:0.15
                              delay:0.0
             usingSpringWithDamping:0.5
              initialSpringVelocity:0.8
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            // Shrink slightly (focus in)
            self.scanFrameView.transform = CGAffineTransformMakeScale(0.92, 0.92);
        } completion:^(BOOL finished) {
            // Spring back to normal with bounce
            [UIView animateWithDuration:0.4
                                  delay:0.0
                 usingSpringWithDamping:0.4
                  initialSpringVelocity:1.0
                                options:UIViewAnimationOptionCurveEaseInOut
                             animations:^{
                self.scanFrameView.transform = CGAffineTransformIdentity;
            } completion:nil];
        }];
    });
}

- (void)updateStatsText:(NSString *)stats {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.statsLabel != nil) {
            self.statsLabel.text = stats;
        }
    });
}


- (void)updateCameraSelection {
    [self.session beginConfiguration];

    // Remove old inputs
    NSArray *oldInputs = [self.session inputs];
    for (AVCaptureInput *oldInput in oldInputs) {
        [self.session removeInput:oldInput];
    }

    AVCaptureDevicePosition desiredPosition = AVCaptureDevicePositionBack;
    AVCaptureDeviceInput *input = [self captureDeviceInputForPosition:desiredPosition];
    if (!input) {
        // Failed, restore old inputs
        for (AVCaptureInput *oldInput in oldInputs) {
            [self.session addInput:oldInput];
        }
    } else {
        // Succeeded, set input and update connection states
        [self.session addInput:input];
    }
    [self.session commitConfiguration];
}

- (AVCaptureDeviceInput *)captureDeviceInputForPosition:(AVCaptureDevicePosition)desiredPosition {
    for (AVCaptureDevice *device in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
        if (device.position == desiredPosition) {
            NSError *error = nil;
            AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device
                                                                                error:&error];
            if (error) {
                NSLog(@"Could not initialize for AVMediaTypeVideo for device %@", device);
            } else if ([self.session canAddInput:input]) {
                return input;
            }
        }
    }
    return nil;
}



@end
