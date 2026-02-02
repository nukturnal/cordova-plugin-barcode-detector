# :camera: cordova-plugin-mlkit-barcode-scanner

## Purpose of this Project

The purpose of this project is to provide a barcode scanner utilizing the Google ML Kit Vision library for the Cordova framework on iOS and Android.
The MLKit library is incredibly performant and fast in comparison to any other barcode reader that I have used that are free.

## Plugin Dependencies

| Dependency                        | Version   | Info                       |
| --------------------------------- | --------- | -------------------------- |
| `cordova-android`                 | `>=8.0.0` |                            |
| `cordova-ios`                     | `>=4.5.0` |                            |
| `cordova-plugin-androidx`         | ` ^3.0.0` | If cordova-android < 9.0.0 |
| `cordova-plugin-androidx-adapter` | ` ^1.1.3` |                            |

## Prerequisites

If your `cordova-android` version is below `9.0.0`, you have to install `cordova-plugin-androidx` first before installing this plugin.
Execute this command in your terminal:

```bash
npx cordova plugin add cordova-plugin-androidx
```

## Installation

Run this command in your project root:

```bash
npx cordova plugin add cordova-plugin-mlkit-barcode-scanner
```

## Supported Platforms

- Android
- iOS/iPadOS

## Barcode Support

| 1d formats   | Android | iOS |
| ------------ | ------- | --- |
| Codabar      | ✓       | ✓   |
| Code 39      | ✓       | ✓   |
| Code 93      | ✓       | ✓   |
| Code 128     | ✓       | ✓   |
| EAN-8.       | ✓       | ✓   |
| EAN-13       | ✓       | ✓   |
| ITF          | ✓       | ✓   |
| MSI          | ✗       | ✗   |
| RSS Expanded | ✗       | ✗   |
| RSS-14       | ✗       | ✗   |
| UPC-A        | ✓       | ✓   |
| UPC-E        | ✓       | ✓   |

| 2d formats  | Android | iOS |
| ----------- | ------- | --- |
| Aztec       | ✓       | ✓   |
| Codablock   | ✗       | ✗   |
| Data Matrix | ✓       | ✓   |
| MaxiCode    | ✗       | ✗   |
| PDF417      | ✓       | ✓   |
| QR Code     | ✓       | ✓   |

:information_source: Note that this API does not recognize barcodes in these forms:

- 1D Barcodes with only one character
- Barcodes in ITF format with fewer than six characters
- Barcodes encoded with FNC2, FNC3 or FNC4
- QR codes generated in the ECI mode

## Usage

To use the plugin simply call `cordova.plugins.mlkit.barcodeScanner.scan(options, sucessCallback, failureCallback)`. See the sample below.

```javascript
cordova.plugins.mlkit.barcodeScanner.scan(
  options,
  (result) => {
    // Do something with the data
    alert(result);
  },
  (error) => {
    // Error handling
  },
);
```

### Plugin Options

The default options are shown below.
All values are optional.

Note that the `detectorSize` value must be between `0` and `1`, because it determines how many percent of the screen should be covered by the detector.
If the value is greater than 1 the detector will not be visible on the screen.

```javascript
const defaultOptions = {
  barcodeFormats: {
    Code128: true,
    Code39: true,
    Code93: true,
    CodaBar: true,
    DataMatrix: true,
    EAN13: true,
    EAN8: true,
    ITF: true,
    QRCode: true,
    UPCA: true,
    UPCE: true,
    PDF417: true,
    Aztec: true,
  },
  beepOnSuccess: false,
  vibrateOnSuccess: false,
  detectorSize: 0.6,
  rotateCamera: false,
};
```

### Output/Return value

```javascript
result: {
  text: string;
  format: string;
  type: string;
}
```

---

## Continuous Scanning Mode

The plugin supports a continuous scanning mode where the scanner stays open and calls a callback for each barcode detected. This is ideal for check-in scenarios, inventory management, or any use case where you need to scan multiple barcodes in succession.

### Premium UI Design

The scanner features a **minimalist, premium design** with:

✨ **Clean Text Overlay**
- **Top-right corner positioning** with right-alignment
- **3-line layout:** Title → Subtitle → Stats
- **Typography hierarchy:** Bold title, lighter subtitle, monospaced stats
- **Subtle opacity variations:** 100% → 70% → 65% for visual depth

🎨 **Smooth Flash Feedback**
- **Customizable color overlays** for different scan results
- **Adjustable duration** (default 500ms, customizable up to any duration)
- **Configurable opacity** (default 40%, customizable 0-100%)
- **Smooth animations** with easeOut curves for natural feel

**Visual Layout:**
```
┌─────────────────────────────────────┐
│                  Continuous Mode   ← Line 1: Title
│                   Scan tickets     ← Line 2: Subtitle
│               248 / 500 checked in ← Line 3: Stats
│                                     │
│            [Scan Area]              │
│                                     │
│   (color flash overlay on scan)    │
└─────────────────────────────────────┘
```

### Starting Continuous Scan

```javascript
cordova.plugins.mlkit.barcodeScanner.startContinuousScan(
  options,
  (result) => {
    // Called for each successful scan
    console.log('Scanned:', result.text);
    
    // Process the barcode (e.g., validate ticket, update inventory)
    validateBarcode(result.text).then(status => {
      // Flash feedback based on result
      if (status === 'success') {
        cordova.plugins.mlkit.barcodeScanner.flashOverlay({ color: '#22c55e' });
      } else if (status === 'warning') {
        cordova.plugins.mlkit.barcodeScanner.flashOverlay({ color: '#f59e0b' });
      } else {
        cordova.plugins.mlkit.barcodeScanner.flashOverlay({ color: '#ef4444' });
      }
      
      // Update stats display
      cordova.plugins.mlkit.barcodeScanner.updateStats('247 / 500 checked in');
    });
  },
  (closeResult) => {
    // Called when scanner is closed (user pressed close button or programmatically closed)
    if (closeResult.cancelled) {
      console.log('Scanner closed by user');
    }
  }
);
```

### Continuous Scan Options

All standard scan options are supported, plus additional options for continuous mode:

```javascript
const continuousOptions = {
  // Standard options
  barcodeFormats: {
    QRCode: true,
    Code128: true,
    // ... other formats
  },
  beepOnSuccess: true,
  vibrateOnSuccess: true,
  detectorSize: 0.6,
  
  // Continuous mode specific options
  title: 'Event Check-in',      // Title displayed on scanner screen
  subtitle: '0 / 500 checked in' // Subtitle displayed below title
};
```

### Flash Overlay

Show a color flash overlay on the scanner screen to provide visual feedback for scan results. The flash overlay now supports customizable duration and opacity for a premium feel.

```javascript
cordova.plugins.mlkit.barcodeScanner.flashOverlay({
  color: '#22c55e',  // Hex color (green for success)
  duration: 500,     // Duration in milliseconds (default: 500ms)
  opacity: 0.4       // Opacity 0.0-1.0 (default: 0.4, i.e., 40%)
});
```

**Flash Overlay Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `color` | string | `#22c55e` | Hex color code for the overlay |
| `duration` | number | `500` | How long the flash stays visible (milliseconds) |
| `opacity` | number | `0.4` | Transparency level: 0.0 (invisible) to 1.0 (solid) |

**Recommended Configurations:**

```javascript
// Success - Subtle green flash
cordova.plugins.mlkit.barcodeScanner.flashOverlay({
  color: '#22c55e',
  duration: 600,
  opacity: 0.35
});

// Warning - Medium yellow flash (already checked in)
cordova.plugins.mlkit.barcodeScanner.flashOverlay({
  color: '#f59e0b',
  duration: 600,
  opacity: 0.4
});

// Error - Clear red flash (invalid ticket)
cordova.plugins.mlkit.barcodeScanner.flashOverlay({
  color: '#ef4444',
  duration: 600,
  opacity: 0.4
});

// Custom - Purple flash with high opacity
cordova.plugins.mlkit.barcodeScanner.flashOverlay({
  color: '#a855f7',
  duration: 800,
  opacity: 0.5
});
```

**Recommended Colors:**
- Success (green): `#22c55e` - Use for successful operations
- Warning (yellow/amber): `#f59e0b` - Use for warnings or duplicates
- Error (red): `#ef4444` - Use for errors or invalid scans
- Info (blue): `#3b82f6` - Use for informational feedback

### Update Stats

Update the stats text displayed on the scanner screen. The text overlay has been redesigned with a premium, minimalist aesthetic:

**Text Overlay Design:**
- **Position:** Top-right corner, right-aligned
- **Layout:** Supports up to 3 lines of text
  - Line 1: Title (17pt, Semibold, White)
  - Line 2: Subtitle (14pt, Regular, 70% opacity)
  - Line 3: Stats (13pt, Monospaced, 65% opacity)
- **Style:** Clean typography with subtle opacity hierarchy

```javascript
// Update stats (appears as third line below title/subtitle)
cordova.plugins.mlkit.barcodeScanner.updateStats('247 / 500 checked in');
```

**Text Overlay Configuration:**

The title and subtitle are set when starting continuous scan:

```javascript
cordova.plugins.mlkit.barcodeScanner.startContinuousScan(
  {
    title: 'Event Check-in',        // Line 1: Bold title
    subtitle: 'Scan tickets',       // Line 2: Lighter subtitle
    // Stats updated dynamically via updateStats()
    barcodeFormats: { QRCode: true },
    beepOnSuccess: true,
    vibrateOnSuccess: true
  },
  (result) => {
    // Handle scan...
  }
);
```

**Visual Example:**

```
┌─────────────────────────────────┐
│              Event Check-in   ← Title
│               Scan tickets    ← Subtitle
│          247 / 500 checked in ← Stats (updated via updateStats)
│                                 │
│         [Scan Area]             │
└─────────────────────────────────┘
```

### Close Scanner Programmatically

Close the continuous scanner from your code:

```javascript
cordova.plugins.mlkit.barcodeScanner.closeScanner();
```

### Debouncing

The continuous scanner automatically debounces duplicate scans of the same barcode within 1.5 seconds. This prevents accidental double-scans when the barcode remains in view.

### Complete Example

```javascript
// Check-in workflow example with premium UI feedback
let checkedInCount = 0;
const totalTickets = 500;

function startCheckIn() {
  cordova.plugins.mlkit.barcodeScanner.startContinuousScan(
    {
      title: 'Concert Check-in',
      subtitle: 'Scan tickets',
      barcodeFormats: { QRCode: true },
      beepOnSuccess: true,
      vibrateOnSuccess: true,
      detectorSize: 0.6
    },
    async (result) => {
      try {
        const response = await fetch('/api/checkin', {
          method: 'POST',
          body: JSON.stringify({ code: result.text })
        });
        const data = await response.json();
        
        if (data.status === 'success') {
          checkedInCount++;
          // Subtle green flash for success
          cordova.plugins.mlkit.barcodeScanner.flashOverlay({
            color: '#22c55e',
            duration: 600,
            opacity: 0.35
          });
        } else if (data.status === 'already_checked_in') {
          // Yellow flash for warnings
          cordova.plugins.mlkit.barcodeScanner.flashOverlay({
            color: '#f59e0b',
            duration: 600,
            opacity: 0.4
          });
        } else {
          // Red flash for errors
          cordova.plugins.mlkit.barcodeScanner.flashOverlay({
            color: '#ef4444',
            duration: 600,
            opacity: 0.4
          });
        }
        
        // Update the stats counter (appears as third line)
        cordova.plugins.mlkit.barcodeScanner.updateStats(
          `${checkedInCount} / ${totalTickets} checked in`
        );
      } catch (error) {
        cordova.plugins.mlkit.barcodeScanner.flashOverlay({
          color: '#ef4444',
          duration: 600,
          opacity: 0.4
        });
      }
    },
    () => {
      console.log('Check-in session ended');
      console.log(`Total checked in: ${checkedInCount}`);
    }
  );
}

// To end the session programmatically:
function endCheckIn() {
  cordova.plugins.mlkit.barcodeScanner.closeScanner();
}
```

---

## Known Issues

On some devices the camera may be upside down.

Here is a list of devices with this problem:

- Zebra MC330K (Manufacturer: Zebra Technologies, Model: MC33)

Current Solution:
if your device has this problem, you can call the plugin with the option `rotateCamera` set to `true`.
This will rotate the camera stream by 180 degrees.

## Development

### Build Process

This project uses npm scripts for building:

```shell
# lint the project using eslint
npm run lint

# removes the generated folders
npm run clean

# build the project
# (includes clean and lint)
npm run build

# publish the project
# (includes build)
npm publish
```

A VS Code task for `build` is also included.

## Run the test app

Install cordova:

```
npm i -g cordova
```

Go to test app:

```
cd test/scan-test-app
```

Install node modules:

```
npm i
```

Prepare Cordova:

```
cordova prepare && cordova plugin add ../../ --link --force
```

Build and run the project Android:

```
cordova build android && cordova run android
```

and iOS:

```
cordova build ios && cordova run ios
```

### Versioning

⚠️ Before incrementing the version in `package.json`, remember to increment the version in `plugin.xml` by hand.

### VS Code Extensions

This project is intended to be used with Visual Studio Code and the recommended extensions can be found in [`.vscode/extensions.json`](.vscode/extensions.json).
When you open this repository for the first time in Visual Studio Code you should get a prompt asking you to install the recommended extensions.
