#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <Cordova/CDV.h>
#import <UIKit/UIKit.h>
#import "CameraViewController.h"

@class UIViewController;

@interface CDViOSScanner : CDVPlugin {
    NSString *_callback;
    Boolean _scannerOpen;
    Boolean _continuousMode;
    AVAudioPlayer* _player;
    Boolean _beepOnSuccess;
    Boolean _vibrateOnSuccess;
}

@property (nonatomic, retain) CameraViewController* cameraViewController;

- (void) startScan:(CDVInvokedUrlCommand *)command;
- (void) startContinuousScan:(CDVInvokedUrlCommand *)command;
- (void) flashOverlay:(CDVInvokedUrlCommand *)command;
- (void) closeScanner:(CDVInvokedUrlCommand *)command;
- (void) updateStats:(CDVInvokedUrlCommand *)command;

@end
