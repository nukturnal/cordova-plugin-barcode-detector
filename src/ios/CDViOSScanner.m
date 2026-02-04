@import MLKitBarcodeScanning;

#import "CDViOSScanner.h"

@class UIViewController;

@interface CDViOSScanner ()
{
    NSInteger _previousStatusBarStyle;
    UIInterfaceOrientation _previousOrientation;
}
@end


@implementation CDViOSScanner

- (void)pluginInitialize
{
    _previousStatusBarStyle = -1;
    _previousOrientation = UIInterfaceOrientationUnknown;
    NSString *beepSoundPath = [[NSBundle mainBundle] pathForResource:@"beep" ofType:@"caf"];
    NSURL *beepSoundUrl = [NSURL fileURLWithPath:beepSoundPath];
    self->_player = [[AVAudioPlayer alloc] initWithContentsOfURL:beepSoundUrl
                                                               error:nil];
}

- (void)startScan:(CDVInvokedUrlCommand *)command
{
    _previousOrientation = [[UIApplication sharedApplication] statusBarOrientation];

    BOOL hasCamera = [UIImagePickerController isSourceTypeAvailable: UIImagePickerControllerSourceTypeCamera];

    if (hasCamera)
    {
        //Force portrait orientation.
        [[UIDevice currentDevice] setValue: [NSNumber numberWithInteger: UIInterfaceOrientationPortrait] forKey:@"orientation"];
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"Arguments %@", command.arguments);
            if (self->_scannerOpen == YES)
            {
                //Scanner is currently open, throw error.
                NSArray *response = @[@"SCANNER_OPEN", @"", @""];
                CDVPluginResult *pluginResult=[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsArray:response];

                [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            }
            else
            {
                //Open scanner.
                self->_scannerOpen = YES;
                self.cameraViewController = [[CameraViewController alloc] init];
                self.cameraViewController.delegate = self;

                //Provide settings to the camera view.
                NSNumberFormatter* f = [[NSNumberFormatter alloc] init];
                f.numberStyle = NSNumberFormatterDecimalStyle;
                NSDictionary* config = [command.arguments objectAtIndex:0];
                self->_beepOnSuccess = [[config valueForKey:@"beepOnSuccess"] boolValue] ?: NO;
                self->_vibrateOnSuccess = [[config valueForKey:@"vibrateOnSuccess"] boolValue] ?: NO;
                NSNumber* barcodeFormats = [config valueForKey:@"barcodeFormats"] ?: @1234;
                self.cameraViewController.barcodeFormats = barcodeFormats;
                self.cameraViewController.detectorSize = (CGFloat)[[config valueForKey:@"detectorSize"] ?: @0.5 floatValue];
                self.cameraViewController.modalPresentationStyle = UIModalPresentationFullScreen;
                
                // Set title and subtitle for single scan mode (same as continuous)
                NSString* title = [config valueForKey:@"title"];
                NSString* subtitle = [config valueForKey:@"subtitle"];
                if (title) {
                    self.cameraViewController.titleText = title;
                }
                if (subtitle) {
                    self.cameraViewController.subtitleText = subtitle;
                }
                
                // Set logo options (default: show logo at 40pt height)
                NSNumber* showLogoNum = [config valueForKey:@"showLogo"];
                self.cameraViewController.showLogo = showLogoNum ? [showLogoNum boolValue] : YES;
                NSNumber* logoHeightNum = [config valueForKey:@"logoHeight"];
                self.cameraViewController.logoHeight = logoHeightNum ? [logoHeightNum floatValue] : 40.0;

                NSLog(@"scanAreaSize: %f, barcodeFormats: %@, showLogo: %d", 
                      self.cameraViewController.detectorSize, 
                      self.cameraViewController.barcodeFormats,
                      self.cameraViewController.showLogo);

                [self.viewController presentViewController:self.cameraViewController animated: NO completion:nil];
                self->_callback = command.callbackId;
            }
        });
    }
    else
    {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:NSLocalizedString(@"The device has no camera.", @"Message to the user if the device has no camera.") preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *defaultAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
        [alert addAction:defaultAction];

        [self.viewController presentViewController:alert animated:YES completion:nil];
    }
}

- (void)sendResult:(MLKBarcode *)barcode
{
    [self.cameraViewController dismissViewControllerAnimated:NO completion:nil];
    _scannerOpen = NO;

    NSString* value = barcode.rawValue;

    // rawValue returns null if string is not UTF-8 encoded.
    // If that's the case, we will decode it as ASCII,
    // because it's the most common encoding for barcodes.
    // e.g. https://www.barcodefaq.com/1d/code-128/
    if(barcode.rawValue == nil)
    {
        value = [[NSString alloc] initWithData:barcode.rawData encoding:NSASCIIStringEncoding];
    }

    NSArray* response = @[value, @(barcode.format), @(barcode.valueType)];
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:response];

    [self playBeep];

    [self resetOrientation];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:_callback];
}

- (void)playBeep
{
    if (self->_beepOnSuccess)
    {
        [self->_player prepareToPlay];
        [self->_player play];
    }

    if (self->_vibrateOnSuccess)
    {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
    }
}

- (void)closeScanner
{
    [self.cameraViewController dismissViewControllerAnimated:NO completion:nil];
    _scannerOpen = NO;

    NSArray *response = @[@"USER_CANCELLED", @"", @""];
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsArray:response];

    [self resetOrientation];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:_callback];
}

- (void)resetOrientation
{
    if (_previousOrientation != UIInterfaceOrientationUnknown && _previousOrientation != UIInterfaceOrientationPortrait)
    {
        [[UIDevice currentDevice] setValue: [NSNumber numberWithInteger: _previousOrientation] forKey:@"orientation"];
        NSLog(@"Changing device orientation to previous orientation");
    }
}


- (void)show:(CDVInvokedUrlCommand*)command
{
    if (self.cameraViewController == nil)
    {
        NSLog(@"Tried to show scanner after it was closed.");
        return;
    }

    if (_previousStatusBarStyle != -1)
    {
        NSLog(@"Tried to show scanner while already shown");
        return;
    }

    _previousStatusBarStyle = [UIApplication sharedApplication].statusBarStyle;
    _previousOrientation = [[UIApplication sharedApplication] statusBarOrientation];

    __block UINavigationController* nav = [[UINavigationController alloc]
                                           initWithRootViewController:self.cameraViewController];

    nav.navigationBarHidden = YES;
    nav.modalPresentationStyle = UIModalPresentationFullScreen;

    __weak CDViOSScanner* weakSelf = self;

    // Run later to avoid the "took a long time" log message.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (weakSelf.cameraViewController != nil)
        {
            CGRect frame = [[UIScreen mainScreen] bounds];
            UIWindow* tmpWindow = [[UIWindow alloc] initWithFrame:frame];
            UIViewController* tmpController = [[UIViewController alloc] init];
            [tmpWindow setRootViewController:tmpController];
            [tmpWindow setWindowLevel:UIWindowLevelNormal];
            [tmpWindow makeKeyAndVisible];
            [tmpController presentViewController:nav animated:NO completion:nil];
        }
    });
}

#pragma mark - Continuous Mode Methods

- (void)startContinuousScan:(CDVInvokedUrlCommand *)command
{
    _previousOrientation = [[UIApplication sharedApplication] statusBarOrientation];
    
    BOOL hasCamera = [UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera];
    
    if (hasCamera)
    {
        // Force portrait orientation.
        [[UIDevice currentDevice] setValue:[NSNumber numberWithInteger:UIInterfaceOrientationPortrait] forKey:@"orientation"];
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"startContinuousScan Arguments %@", command.arguments);
            if (self->_scannerOpen == YES)
            {
                // Scanner is currently open, throw error.
                NSArray *response = @[@"SCANNER_OPEN", @"", @""];
                CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsArray:response];
                [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            }
            else
            {
                // Open scanner in continuous mode.
                self->_scannerOpen = YES;
                self->_continuousMode = YES;
                self.cameraViewController = [[CameraViewController alloc] init];
                self.cameraViewController.delegate = self;
                self.cameraViewController.continuousMode = YES;
                
                // Provide settings to the camera view.
                NSDictionary* config = [command.arguments objectAtIndex:0];
                self->_beepOnSuccess = [[config valueForKey:@"beepOnSuccess"] boolValue] ?: NO;
                self->_vibrateOnSuccess = [[config valueForKey:@"vibrateOnSuccess"] boolValue] ?: NO;
                NSNumber* barcodeFormats = [config valueForKey:@"barcodeFormats"] ?: @1234;
                self.cameraViewController.barcodeFormats = barcodeFormats;
                self.cameraViewController.detectorSize = (CGFloat)[[config valueForKey:@"detectorSize"] ?: @0.5 floatValue];
                self.cameraViewController.modalPresentationStyle = UIModalPresentationFullScreen;
                
                // Set title and subtitle for continuous mode
                NSString* title = [config valueForKey:@"title"];
                NSString* subtitle = [config valueForKey:@"subtitle"];
                if (title) {
                    self.cameraViewController.titleText = title;
                }
                if (subtitle) {
                    self.cameraViewController.subtitleText = subtitle;
                }
                
                // Set logo options (default: show logo at 40pt height)
                NSNumber* showLogoNum = [config valueForKey:@"showLogo"];
                self.cameraViewController.showLogo = showLogoNum ? [showLogoNum boolValue] : YES;
                NSNumber* logoHeightNum = [config valueForKey:@"logoHeight"];
                self.cameraViewController.logoHeight = logoHeightNum ? [logoHeightNum floatValue] : 40.0;
                
                NSLog(@"Continuous scan - scanAreaSize: %f, barcodeFormats: %@, showLogo: %d, logoHeight: %f", 
                      self.cameraViewController.detectorSize, 
                      self.cameraViewController.barcodeFormats,
                      self.cameraViewController.showLogo,
                      self.cameraViewController.logoHeight);
                
                [self.viewController presentViewController:self.cameraViewController animated:NO completion:nil];
                self->_callback = command.callbackId;
            }
        });
    }
    else
    {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:NSLocalizedString(@"The device has no camera.", @"Message to the user if the device has no camera.") preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *defaultAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
        [alert addAction:defaultAction];
        [self.viewController presentViewController:alert animated:YES completion:nil];
    }
}

- (void)sendContinuousResult:(MLKBarcode *)barcode
{
    // Don't dismiss - keep scanning in continuous mode
    NSString* value = barcode.rawValue;
    
    // rawValue returns null if string is not UTF-8 encoded.
    // If that's the case, we will decode it as ASCII.
    if (barcode.rawValue == nil)
    {
        value = [[NSString alloc] initWithData:barcode.rawData encoding:NSASCIIStringEncoding];
    }
    
    NSArray* response = @[value ?: @"", @(barcode.format), @(barcode.valueType)];
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:response];
    
    // IMPORTANT: Keep callback for continuous results
    [pluginResult setKeepCallbackAsBool:YES];
    
    [self playBeep];
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:_callback];
}

- (void)flashOverlay:(CDVInvokedUrlCommand *)command
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.cameraViewController == nil)
        {
            NSLog(@"flashOverlay: Scanner not open");
            return;
        }
        
        NSDictionary* config = [command.arguments objectAtIndex:0];
        NSString* colorHex = [config valueForKey:@"color"] ?: @"#22c55e";
        NSNumber* durationNum = [config valueForKey:@"duration"] ?: @500; // Default 500ms (was 300ms)
        NSNumber* opacityNum = [config valueForKey:@"opacity"] ?: @0.4;   // Default 0.4 (40%)
        
        NSTimeInterval duration = [durationNum doubleValue] / 1000.0; // Convert ms to seconds
        CGFloat opacity = [opacityNum doubleValue];
        
        // Clamp opacity between 0.0 and 1.0
        opacity = MAX(0.0, MIN(1.0, opacity));
        
        // Parse hex color
        UIColor* color = [self colorFromHexString:colorHex];
        
        [self.cameraViewController showFlashOverlayWithColor:color duration:duration opacity:opacity];
        
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    });
}

- (void)closeScanner:(CDVInvokedUrlCommand *)command
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.cameraViewController != nil)
        {
            [self.cameraViewController dismissViewControllerAnimated:NO completion:nil];
        }
        self->_scannerOpen = NO;
        self->_continuousMode = NO;
        
        // Send close event on the continuous callback
        NSArray *response = @[@"SCANNER_CLOSED", @"", @""];
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsArray:response];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self->_callback];
        
        [self resetOrientation];
        
        // Send success on the command callback
        CDVPluginResult* commandResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [self.commandDelegate sendPluginResult:commandResult callbackId:command.callbackId];
    });
}

- (void)updateStats:(CDVInvokedUrlCommand *)command
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.cameraViewController == nil)
        {
            NSLog(@"updateStats: Scanner not open");
            CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Scanner not open"];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            return;
        }
        
        // Handle both formats: { stats: "..." } or just "..."
        id firstArg = [command.arguments objectAtIndex:0];
        NSString* stats;
        if ([firstArg isKindOfClass:[NSDictionary class]]) {
            stats = [firstArg valueForKey:@"stats"] ?: @"";
        } else {
            stats = firstArg ?: @"";
        }
        
        [self.cameraViewController updateStatsText:stats];
        
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    });
}

#pragma mark - Helper Methods

- (UIColor *)colorFromHexString:(NSString *)hexString
{
    // Remove # if present
    if ([hexString hasPrefix:@"#"]) {
        hexString = [hexString substringFromIndex:1];
    }
    
    // Handle shorthand (3 chars) or full (6 chars)
    if ([hexString length] == 3) {
        NSString *r = [hexString substringWithRange:NSMakeRange(0, 1)];
        NSString *g = [hexString substringWithRange:NSMakeRange(1, 1)];
        NSString *b = [hexString substringWithRange:NSMakeRange(2, 1)];
        hexString = [NSString stringWithFormat:@"%@%@%@%@%@%@", r, r, g, g, b, b];
    }
    
    unsigned int hexValue = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hexString];
    [scanner scanHexInt:&hexValue];
    
    CGFloat red = ((hexValue & 0xFF0000) >> 16) / 255.0;
    CGFloat green = ((hexValue & 0x00FF00) >> 8) / 255.0;
    CGFloat blue = (hexValue & 0x0000FF) / 255.0;
    
    return [UIColor colorWithRed:red green:green blue:blue alpha:1.0];
}

@end
