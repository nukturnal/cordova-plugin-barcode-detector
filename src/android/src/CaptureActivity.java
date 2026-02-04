package com.mobisys.cordova.plugins.mlkit.barcode.scanner;

import android.Manifest;
import android.animation.Animator;
import android.animation.AnimatorListenerAdapter;

import android.annotation.SuppressLint;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.os.Bundle;

import android.util.Log;

import android.view.GestureDetector;
import android.view.MotionEvent;
import android.view.ScaleGestureDetector;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ImageButton;
import android.widget.ImageView;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import androidx.camera.core.AspectRatio;
import androidx.camera.core.Camera;
import androidx.camera.core.CameraSelector;
import androidx.camera.core.ImageAnalysis;
import androidx.camera.core.ImageProxy;
import androidx.camera.core.Preview;
import androidx.camera.lifecycle.ProcessCameraProvider;
import androidx.camera.view.PreviewView;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import androidx.lifecycle.LifecycleOwner;
import androidx.lifecycle.LiveData;

import com.google.android.gms.common.api.CommonStatusCodes;
import com.google.android.gms.tasks.OnCompleteListener;
import com.google.android.gms.tasks.OnFailureListener;
import com.google.android.gms.tasks.OnSuccessListener;
import com.google.android.gms.tasks.Task;
import com.google.android.material.snackbar.Snackbar;
import com.google.common.util.concurrent.ListenableFuture;
import com.google.mlkit.vision.barcode.common.Barcode;
import com.google.mlkit.vision.barcode.BarcodeScanner;
import com.google.mlkit.vision.barcode.BarcodeScannerOptions;
import com.google.mlkit.vision.barcode.BarcodeScanning;
import com.google.mlkit.vision.common.InputImage;
import com.mobisys.cordova.plugins.mlkit.barcode.scanner.utils.BitmapUtils;

import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class CaptureActivity extends AppCompatActivity {

  public Integer BarcodeFormats;
  public double DetectorSize = .5;

  public static final String BarcodeFormat = "MLKitBarcodeFormat";
  public static final String BarcodeType = "MLKitBarcodeType";
  public static final String BarcodeValue = "MLKitBarcodeValue";

  private ListenableFuture<ProcessCameraProvider> cameraProviderFuture;
  private ExecutorService executor = Executors.newSingleThreadExecutor();
  private PreviewView mCameraView;
  private ScannerBracketsView _ScannerBrackets;

  private static final int RC_HANDLE_CAMERA_PERM = 2;
  private ImageButton _TorchButton;
  private Camera camera;

  private ScaleGestureDetector _ScaleGestureDetector;
  private GestureDetector _GestureDetector;

  // Continuous mode fields
  private boolean _ContinuousMode = false;
  private View _FlashOverlay;
  private ImageButton _CloseButton;
  private TextView _TitleText;
  private TextView _SubtitleText;
  private TextView _StatsText;
  private ImageView _LogoView;
  private ImageView _ScannerLogo;
  private boolean _ShowLogo = true;
  private int _LogoHeight = 40;
  private String _LastScannedValue = "";
  private long _LastScanTime = 0;
  private static final long SCAN_DEBOUNCE_MS = 1500; // Prevent duplicate scans
  private static final String TAG = "CaptureActivity";
  
  // UI initialization tracking
  private boolean _UIInitialized = false;
  private boolean _CameraStarted = false;

  // Broadcast actions for communication with plugin
  public static final String ACTION_FLASH_OVERLAY = "com.mobisys.barcode.FLASH_OVERLAY";
  public static final String ACTION_CLOSE_SCANNER = "com.mobisys.barcode.CLOSE_SCANNER";
  public static final String ACTION_UPDATE_UI = "com.mobisys.barcode.UPDATE_UI";
  public static final String ACTION_BARCODE_SCANNED = "com.mobisys.barcode.BARCODE_SCANNED";
  public static final String ACTION_SCANNER_READY = "com.mobisys.barcode.SCANNER_READY";

  private BroadcastReceiver _CommandReceiver;

  @Override
  protected void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    setContentView(getResources().getIdentifier("capture_activity", "layout", getPackageName()));

    // read parameters from the intent used to launch the activity.
    BarcodeFormats = getIntent().getIntExtra("BarcodeFormats", 1234);
    DetectorSize = getIntent().getDoubleExtra("DetectorSize", .5);
    _ContinuousMode = getIntent().getBooleanExtra("ContinuousMode", false);

    if (DetectorSize <= 0 || DetectorSize >= 1) { // setting boundary detectorSize must be between 0 to 1.
      DetectorSize = 0.5;
    }

    // Initialize scanner brackets overlay (animatable)
    _ScannerBrackets = findViewById(getResources().getIdentifier("scannerBrackets", "id", getPackageName()));
    if (_ScannerBrackets != null) {
      _ScannerBrackets.setDetectorSize((float) DetectorSize);
    }

    // Initialize flash overlay
    _FlashOverlay = findViewById(getResources().getIdentifier("flashOverlay", "id", getPackageName()));

    // Initialize close button
    _CloseButton = findViewById(getResources().getIdentifier("closeButton", "id", getPackageName()));
    if (_CloseButton != null) {
      _CloseButton.setOnClickListener(v -> closeScanner());
    }

    // Initialize title/subtitle/stats text views
    _TitleText = findViewById(getResources().getIdentifier("titleText", "id", getPackageName()));
    _SubtitleText = findViewById(getResources().getIdentifier("subtitleText", "id", getPackageName()));
    _StatsText = findViewById(getResources().getIdentifier("statsText", "id", getPackageName()));
    _LogoView = findViewById(getResources().getIdentifier("logoView", "id", getPackageName()));
    _ScannerLogo = findViewById(getResources().getIdentifier("scannerLogo", "id", getPackageName()));

    // Set initial text from intent if provided
    String title = getIntent().getStringExtra("Title");
    String subtitle = getIntent().getStringExtra("Subtitle");
    if (title != null && !title.isEmpty() && _TitleText != null) {
      _TitleText.setText(title);
      _TitleText.setVisibility(View.VISIBLE);
    }
    if (subtitle != null && !subtitle.isEmpty() && _SubtitleText != null) {
      _SubtitleText.setText(subtitle);
      _SubtitleText.setVisibility(View.VISIBLE);
    }
    
    // Set up scanner logo (below scan frame) - works for all scan modes
    _ShowLogo = getIntent().getBooleanExtra("ShowLogo", true);
    _LogoHeight = getIntent().getIntExtra("LogoHeight", 40);
    
    if (_ShowLogo && _ScannerLogo != null) {
      // Set height while maintaining aspect ratio - visibility set after layout
      ViewGroup.LayoutParams params = _ScannerLogo.getLayoutParams();
      params.height = (int) (getResources().getDisplayMetrics().density * _LogoHeight);
      _ScannerLogo.setLayoutParams(params);
      
      Log.d(TAG, "Scanner logo enabled: height=" + _LogoHeight + "dp");
    }

    // Register broadcast receiver for commands from plugin
    registerCommandReceiver();

    int rc = ActivityCompat.checkSelfPermission(this, Manifest.permission.CAMERA);

    if (rc == PackageManager.PERMISSION_GRANTED) {
      // Start Camera
      startCamera();
    } else {
      requestCameraPermission();
    }

    _GestureDetector = new GestureDetector(this, new CaptureGestureListener());
    _ScaleGestureDetector = new ScaleGestureDetector(this, new ScaleListener());

    _TorchButton = findViewById(getResources().getIdentifier("torch_button", "id", this.getPackageName()));

    _TorchButton.setOnClickListener(new View.OnClickListener() {
      @Override
      public void onClick(View v) {

        LiveData<Integer> flashState = camera.getCameraInfo().getTorchState();
        if (flashState.getValue() != null) {
          boolean state = flashState.getValue() == 1;
          _TorchButton.setBackgroundResource(getResources().getIdentifier(!state ? "torch_active" : "torch_inactive",
              "drawable", CaptureActivity.this.getPackageName()));
          camera.getCameraControl().enableTorch(!state);
        }

      }
    });

  }

  // ----------------------------------------------------------------------------
  // | Helper classes
  // ----------------------------------------------------------------------------
  private class CaptureGestureListener extends GestureDetector.SimpleOnGestureListener {
    @Override
    public boolean onSingleTapConfirmed(MotionEvent e) {
      return super.onSingleTapConfirmed(e);
    }
  }

  private class ScaleListener implements ScaleGestureDetector.OnScaleGestureListener {
    @Override
    public boolean onScale(ScaleGestureDetector detector) {
      return false;
    }

    @Override
    public boolean onScaleBegin(ScaleGestureDetector detector) {
      return true;
    }

    @Override
    public void onScaleEnd(ScaleGestureDetector detector) {

      if (camera != null) {
        float scale = camera.getCameraInfo().getZoomState().getValue().getZoomRatio() * detector.getScaleFactor();
        camera.getCameraControl().setZoomRatio(scale);
      }
    }
  }

  private void requestCameraPermission() {

    final String[] permissions = new String[] { Manifest.permission.CAMERA,
        Manifest.permission.WRITE_EXTERNAL_STORAGE };

    boolean shouldShowPermission = !ActivityCompat.shouldShowRequestPermissionRationale(this,
        Manifest.permission.CAMERA);
    shouldShowPermission = shouldShowPermission
        && !ActivityCompat.shouldShowRequestPermissionRationale(this, Manifest.permission.WRITE_EXTERNAL_STORAGE);

    if (shouldShowPermission) {
      ActivityCompat.requestPermissions(this, permissions, RC_HANDLE_CAMERA_PERM);
      return;
    }

    View.OnClickListener listener = new View.OnClickListener() {
      @Override
      public void onClick(View view) {
        ActivityCompat.requestPermissions(CaptureActivity.this, permissions, RC_HANDLE_CAMERA_PERM);
      }
    };

    View topLayout = findViewById(getResources().getIdentifier("topLayout", "id", getPackageName()));
    topLayout.setOnClickListener(listener);
    Snackbar
        .make(topLayout, getResources().getIdentifier("permission_camera_rationale", "string", getPackageName()),
            Snackbar.LENGTH_INDEFINITE)
        .setAction(getResources().getIdentifier("ok", "string", getPackageName()), listener).show();

  }

  @Override
  public void onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
    if (requestCode != RC_HANDLE_CAMERA_PERM) {
      super.onRequestPermissionsResult(requestCode, permissions, grantResults);
      return;
    }

    if (grantResults.length != 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
      startCamera();
      return;
    }

    DialogInterface.OnClickListener listener = new DialogInterface.OnClickListener() {
      public void onClick(DialogInterface dialog, int id) {
        finish();
      }
    };

    AlertDialog.Builder builder = new AlertDialog.Builder(this);
    builder.setTitle("Camera permission required")
        .setMessage(getResources().getIdentifier("no_camera_permission", "string", getPackageName()))
        .setPositiveButton(getResources().getIdentifier("ok", "string", getPackageName()), listener).show();
  }
  
  /**
   * Initialize UI elements that depend on layout being complete.
   * Called once when layout is ready and camera has started.
   */
  private void initializeUIAfterLayout() {
    if (_UIInitialized || mCameraView == null) return;
    
    int height = mCameraView.getHeight();
    int width = mCameraView.getWidth();
    
    // Wait for valid dimensions
    if (width == 0 || height == 0) {
      Log.d(TAG, "Layout not ready, waiting...");
      mCameraView.post(this::initializeUIAfterLayout);
      return;
    }
    
    Log.d(TAG, "Initializing UI after layout: " + width + "x" + height);
    _UIInitialized = true;
    
    // Position logo
    positionScannerLogo(width, height);
    
    // Start breathing animation
    if (_ScannerBrackets != null) {
      _ScannerBrackets.invalidate(); // Force redraw with correct dimensions
      _ScannerBrackets.startBreathingAnimation();
    }
    
    // Send SCANNER_READY now that UI is fully initialized
    Intent readyIntent = new Intent(ACTION_SCANNER_READY);
    readyIntent.setPackage(getPackageName());
    sendBroadcast(readyIntent);
    Log.d(TAG, "Sent SCANNER_READY broadcast (UI initialized)");
  }
  
  private void positionScannerLogo(int viewWidth, int viewHeight) {
    if (_ScannerLogo == null || !_ShowLogo) {
      Log.d(TAG, "Scanner logo skipped: null=" + (_ScannerLogo == null) + " showLogo=" + _ShowLogo);
      return;
    }
    
    int diameter = Math.min(viewWidth, viewHeight);
    int offset = (int) ((1 - DetectorSize) * diameter);
    diameter -= offset;
    
    // Calculate scan frame bounds (same logic as ScannerBracketsView)
    int right = viewWidth / 2 + diameter / 2;
    int bottom = viewHeight / 2 + diameter / 2;
    
    // Position logo below scan frame, right-aligned to bracket edge
    float logoPadding = 16 * getResources().getDisplayMetrics().density; // 16dp
    float logoHeight = _LogoHeight * getResources().getDisplayMetrics().density;
    
    // Calculate logo width based on aspect ratio
    if (_ScannerLogo.getDrawable() != null) {
      float aspectRatio = (float) _ScannerLogo.getDrawable().getIntrinsicWidth() / 
                         (float) _ScannerLogo.getDrawable().getIntrinsicHeight();
      float logoWidth = logoHeight * aspectRatio;
      
      // Use translationX/Y for positioning (works with ConstraintLayout)
      float logoX = right - logoWidth;
      float logoY = bottom + logoPadding;
      
      _ScannerLogo.setTranslationX(logoX);
      _ScannerLogo.setTranslationY(logoY);
      _ScannerLogo.setVisibility(View.VISIBLE);
      
      Log.d(TAG, "Scanner logo visible: translationX=" + logoX + ", translationY=" + logoY + 
            ", w=" + logoWidth + ", h=" + logoHeight);
    } else {
      Log.w(TAG, "Scanner logo drawable is null");
    }
  }

  @Override
  public boolean onTouchEvent(MotionEvent e) {
    boolean b = _ScaleGestureDetector.onTouchEvent(e);
    boolean c = _GestureDetector.onTouchEvent(e);

    return b || c || super.onTouchEvent(e);
  }

  @Override
  protected void onPause() {
    super.onPause();
    // Pause animation when activity pauses
    if (_ScannerBrackets != null) {
      _ScannerBrackets.pauseBreathingAnimation();
    }
  }

  @Override
  protected void onResume() {
    super.onResume();
    // Only resume animation if UI was already initialized
    if (_UIInitialized && _ScannerBrackets != null) {
      _ScannerBrackets.startBreathingAnimation();
    }
  }

  void startCamera() {
    mCameraView = findViewById(getResources().getIdentifier("previewView", "id", getPackageName()));
    mCameraView.setImplementationMode(PreviewView.ImplementationMode.COMPATIBLE);

    Boolean rotateCamera = getIntent().getBooleanExtra("RotateCamera", false);
    if (rotateCamera) {
      mCameraView.setScaleX(-1F);
      mCameraView.setScaleY(-1F);
    } else {
      mCameraView.setScaleX(1F);
      mCameraView.setScaleY(1F);
    }

    // mCameraView.setScaleType(PreviewView.ScaleType.FIT_CENTER);

    cameraProviderFuture = ProcessCameraProvider.getInstance(this);
    cameraProviderFuture.addListener(new Runnable() {
      @Override
      public void run() {
        try {
          ProcessCameraProvider cameraProvider = cameraProviderFuture.get();
          CaptureActivity.this.bindPreview(cameraProvider);
          _CameraStarted = true;
          
          // Initialize UI after camera binds and layout is ready
          runOnUiThread(() -> initializeUIAfterLayout());

        } catch (ExecutionException | InterruptedException e) {
          Log.e(TAG, "Error starting camera", e);
        }
      }
    }, ContextCompat.getMainExecutor(this));
  }

  /**
   * Binding to camera
   */
  private void bindPreview(ProcessCameraProvider cameraProvider) {

    int barcodeFormat;
    if (BarcodeFormats == 0 || BarcodeFormats == 1234) {
      barcodeFormat = (Barcode.FORMAT_CODE_39 | Barcode.FORMAT_DATA_MATRIX);
    } else {
      barcodeFormat = BarcodeFormats;
    }

    Preview preview = new Preview.Builder().build();

    CameraSelector cameraSelector = new CameraSelector.Builder().requireLensFacing(CameraSelector.LENS_FACING_BACK)
        .build();

    preview.setSurfaceProvider(mCameraView.getSurfaceProvider());

    ImageAnalysis imageAnalysis = new ImageAnalysis.Builder()
        .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).setTargetAspectRatio(AspectRatio.RATIO_16_9)
        .build();

    BarcodeScanner scanner = BarcodeScanning
        .getClient(new BarcodeScannerOptions.Builder().setBarcodeFormats(barcodeFormat).build());

    imageAnalysis.setAnalyzer(executor, new ImageAnalysis.Analyzer() {
      @SuppressLint("UnsafeExperimentalUsageError")
      @Override
      public void analyze(@NonNull ImageProxy image) {

        if (image == null || image.getImage() == null) {
          return;
        }

        Bitmap bmp = BitmapUtils.getBitmap(image);

        int height = bmp.getHeight();
        int width = bmp.getWidth();

        int left, right, top, bottom, diameter, boxHeight, boxWidth;

        diameter = width;
        if (height < width) {
          diameter = height;
        }

        int offset = (int) ((1 - DetectorSize) * diameter);
        diameter -= offset;

        left = width / 2 - diameter / 2;
        top = height / 2 - diameter / 2;
        right = width / 2 + diameter / 2;
        bottom = height / 2 + diameter / 2;

        boxHeight = bottom - top;
        boxWidth = right - left;

        Bitmap bitmap = Bitmap.createBitmap(bmp, left, top, boxWidth, boxHeight);
        scanner.process(InputImage.fromBitmap(bitmap, image.getImageInfo().getRotationDegrees()))
            .addOnSuccessListener(new OnSuccessListener<List<Barcode>>() {
              @Override
              public void onSuccess(List<Barcode> barCodes) {

                if (barCodes.size() > 0) {
                  for (Barcode barcode : barCodes) {
                    String value = barcode.getRawValue();

                    // rawValue returns null if string is not UTF-8 encoded.
                    // If that's the case, we will decode it as ASCII,
                    // because it's the most common encoding for barcodes.
                    if (barcode.getRawValue() == null) {
                      value = new String(barcode.getRawBytes(), StandardCharsets.US_ASCII);
                    }

                    // Debounce duplicate scans
                    if (!shouldProcessBarcode(value)) {
                      return;
                    }

                    // Send the result
                    sendBarcodeResult(barcode, value);
                    break;
                  }
                }
              }
            }).addOnFailureListener(new OnFailureListener() {
              @Override
              public void onFailure(@NonNull Exception e) {

              }
            }).addOnCompleteListener(new OnCompleteListener<List<Barcode>>() {
              @Override
              public void onComplete(@NonNull Task<List<Barcode>> task) {
                image.close();
              }
            });
      }

    });

    camera = cameraProvider.bindToLifecycle((LifecycleOwner) this, cameraSelector, imageAnalysis, preview);
  }

  /**
   * Close the scanner and return to the calling activity
   */
  private void closeScanner() {
    unregisterCommandReceiver();
    Intent data = new Intent();
    data.putExtra("err", "USER_CANCELLED");
    setResult(CommonStatusCodes.CANCELED, data);
    finish();
  }

  /**
   * Register broadcast receiver for commands from plugin
   */
  private void registerCommandReceiver() {
    _CommandReceiver = new BroadcastReceiver() {
      @Override
      public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        Log.d(TAG, "CommandReceiver received action: " + action);
        if (action == null) return;

        switch (action) {
          case ACTION_FLASH_OVERLAY:
            int color = intent.getIntExtra("color", Color.GREEN);
            int duration = intent.getIntExtra("duration", 500);
            float opacity = intent.getFloatExtra("opacity", 0.4f);
            showFlashOverlay(color, duration, opacity);
            break;
          case ACTION_CLOSE_SCANNER:
            closeScanner();
            break;
          case ACTION_UPDATE_UI:
            String stats = intent.getStringExtra("stats");
            Log.d(TAG, "UPDATE_UI received with stats: " + stats);
            if (stats != null && _StatsText != null) {
              runOnUiThread(() -> {
                Log.d(TAG, "Setting stats text to: " + stats);
                _StatsText.setText(stats);
                _StatsText.setVisibility(View.VISIBLE);
              });
            } else {
              Log.w(TAG, "Stats is null (" + (stats == null) + ") or _StatsText is null (" + (_StatsText == null) + ")");
            }
            break;
        }
      }
    };

    IntentFilter filter = new IntentFilter();
    filter.addAction(ACTION_FLASH_OVERLAY);
    filter.addAction(ACTION_CLOSE_SCANNER);
    filter.addAction(ACTION_UPDATE_UI);

    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
      registerReceiver(_CommandReceiver, filter, Context.RECEIVER_EXPORTED);
    } else {
      registerReceiver(_CommandReceiver, filter);
    }
    Log.d(TAG, "CommandReceiver registered for actions: FLASH_OVERLAY, CLOSE_SCANNER, UPDATE_UI");
    // Note: SCANNER_READY is sent from initializeUIAfterLayout() once layout is complete
  }

  /**
   * Unregister broadcast receiver
   */
  private void unregisterCommandReceiver() {
    if (_CommandReceiver != null) {
      try {
        unregisterReceiver(_CommandReceiver);
      } catch (IllegalArgumentException e) {
        // Receiver was not registered
      }
      _CommandReceiver = null;
    }
  }

  /**
   * Show flash overlay with color animation
   */
  private void showFlashOverlay(int color, int duration, float opacity) {
    if (_FlashOverlay == null) return;

    runOnUiThread(() -> {
      Log.d(TAG, String.format("[Android Flash] Showing overlay - color: #%06X, opacity: %.2f, duration: %dms", 
          (color & 0xFFFFFF), opacity, duration));
      
      // CRITICAL: Bring overlay to front and ensure it's above everything
      // Without this, other views might render on top, reducing perceived opacity
      _FlashOverlay.bringToFront();
      _FlashOverlay.setElevation(999f); // Maximum elevation to ensure it's on top
      
      // Show instantly - flat, in your face
      _FlashOverlay.setBackgroundColor(color);
      _FlashOverlay.setAlpha(opacity);
      _FlashOverlay.setVisibility(View.VISIBLE);
      
      Log.d(TAG, String.format("[Android Flash] Overlay shown with alpha: %.2f, visibility: %d, elevation: %.1f", 
          _FlashOverlay.getAlpha(), _FlashOverlay.getVisibility(), _FlashOverlay.getElevation()));

      // Stay visible for the duration, then hide instantly
      _FlashOverlay.postDelayed(() -> {
        _FlashOverlay.setVisibility(View.GONE);
        _FlashOverlay.setAlpha(0f);
        Log.d(TAG, "[Android Flash] Overlay hidden after duration");
      }, duration);
    });
  }

  /**
   * Check if we should process this barcode (debouncing)
   */
  private boolean shouldProcessBarcode(String value) {
    long now = System.currentTimeMillis();
    if (value.equals(_LastScannedValue) && (now - _LastScanTime) < SCAN_DEBOUNCE_MS) {
      return false;
    }
    _LastScannedValue = value;
    _LastScanTime = now;
    return true;
  }

  /**
   * Send barcode result - either finish activity or broadcast for continuous mode
   */
  private void sendBarcodeResult(Barcode barcode, String value) {
    // Trigger focus animation
    animateFocusEffect();
    
    Intent data = new Intent();
    data.putExtra(BarcodeFormat, barcode.getFormat());
    data.putExtra(BarcodeType, barcode.getValueType());
    data.putExtra(BarcodeValue, value);

    if (_ContinuousMode) {
      // Broadcast the result instead of finishing
      Intent broadcastIntent = new Intent(ACTION_BARCODE_SCANNED);
      broadcastIntent.putExtra(BarcodeFormat, barcode.getFormat());
      broadcastIntent.putExtra(BarcodeType, barcode.getValueType());
      broadcastIntent.putExtra(BarcodeValue, value);
      sendBroadcast(broadcastIntent);
      Log.d(TAG, "Continuous mode: broadcast barcode " + value);
    } else {
      // Single scan mode - finish activity
      setResult(CommonStatusCodes.SUCCESS, data);
      finish();
    }
  }
  
  /**
   * Animate focus effect on scan frame (corner brackets)
   */
  private void animateFocusEffect() {
    if (_ScannerBrackets == null) return;
    
    runOnUiThread(() -> {
      _ScannerBrackets.animateFocusEffect();
    });
  }

  @Override
  protected void onDestroy() {
    super.onDestroy();
    unregisterCommandReceiver();
    if (_ScannerBrackets != null) {
      _ScannerBrackets.pauseBreathingAnimation();
    }
  }

  @SuppressWarnings("deprecation")
  @Override
  public void onBackPressed() {
    // Handle back button press - close scanner with USER_CANCELLED result
    closeScanner();
  }
}
