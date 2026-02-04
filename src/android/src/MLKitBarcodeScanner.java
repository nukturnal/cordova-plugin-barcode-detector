package com.mobisys.cordova.plugins.mlkit.barcode.scanner;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.content.res.AssetFileDescriptor;
import android.graphics.Color;
import android.hardware.camera2.CameraManager;
import android.media.MediaPlayer;
import android.os.Build;
import android.os.Bundle;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.util.Log;

import com.google.android.gms.common.api.CommonStatusCodes;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.CordovaInterface;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.CordovaWebView;
import org.apache.cordova.PluginResult;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.IOException;

/**
 * This class echoes a string called from JavaScript.
 */
public class MLKitBarcodeScanner extends CordovaPlugin {

  private static final int RC_BARCODE_CAPTURE = 9001;
  private static final String TAG = "MLKitBarcodeScanner";
  private CallbackContext _CallbackContext;
  private CallbackContext _ContinuousCallbackContext;
  private Boolean _BeepOnSuccess;
  private Boolean _VibrateOnSuccess;
  private Boolean _ContinuousMode = false;
  private MediaPlayer _MediaPlayer;
  private Vibrator _Vibrator;
  private BroadcastReceiver _BarcodeReceiver;
  private String _PendingStats = null; // Stats to pass when activity starts

  public void initialize(CordovaInterface cordova, CordovaWebView webView) {
    super.initialize(cordova, webView);

    Context context = cordova.getContext();

    _Vibrator = (Vibrator) context.getSystemService(Context.VIBRATOR_SERVICE);
    _MediaPlayer = new MediaPlayer();

    try {
      AssetFileDescriptor descriptor = context.getAssets().openFd("beep.ogg");
      _MediaPlayer.setDataSource(descriptor.getFileDescriptor(), descriptor.getStartOffset(), descriptor.getLength());
      descriptor.close();
      _MediaPlayer.prepare();
    } catch (IOException e) {
      e.printStackTrace();
    }
  }

  @Override
  public boolean execute(String action, JSONArray args, CallbackContext callbackContext) throws JSONException {
    Activity activity = cordova.getActivity();
    Boolean hasCamera = activity.getPackageManager().hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY);
    CameraManager cameraManager = (CameraManager) activity.getSystemService(Context.CAMERA_SERVICE);

    _CallbackContext = callbackContext;

    int numberOfCameras = 0;

    try {
      numberOfCameras = cameraManager.getCameraIdList().length;
    } catch (Exception e) {
      e.printStackTrace();
    }

    if (!hasCamera || numberOfCameras == 0) {
      AlertDialog alertDialog = new AlertDialog.Builder(activity).create();
      alertDialog.setMessage(activity.getString(activity.getResources()
          .getIdentifier("no_cameras_found", "string", activity.getPackageName())));
      alertDialog.setButton(
          AlertDialog.BUTTON_POSITIVE, activity.getString(activity.getResources()
              .getIdentifier("ok", "string", activity.getPackageName())),
          new DialogInterface.OnClickListener() {
            public void onClick(DialogInterface dialog, int which) {
              dialog.dismiss();
            }
          });
      alertDialog.show();
      return false;
    }

    if (action.equals("startScan")) {
      class OneShotTask implements Runnable {
        private final Context context;
        private final JSONArray args;

        private OneShotTask(Context ctx, JSONArray as) {
          context = ctx;
          args = as;
        }

        public void run() {
          try {
            openNewActivity(context, args);
          } catch (JSONException e) {
            _CallbackContext.sendPluginResult(new PluginResult(PluginResult.Status.ERROR, e.toString()));
          }
        }
      }
      Thread t = new Thread(new OneShotTask(cordova.getContext(), args));
      t.start();
      return true;
    } else if (action.equals("startContinuousScan")) {
      _ContinuousMode = true;
      _ContinuousCallbackContext = callbackContext;
      class ContinuousScanTask implements Runnable {
        private final Context context;
        private final JSONArray args;

        private ContinuousScanTask(Context ctx, JSONArray as) {
          context = ctx;
          args = as;
        }

        public void run() {
          try {
            openContinuousScan(context, args);
          } catch (JSONException e) {
            _ContinuousCallbackContext.sendPluginResult(new PluginResult(PluginResult.Status.ERROR, e.toString()));
          }
        }
      }
      Thread t = new Thread(new ContinuousScanTask(cordova.getContext(), args));
      t.start();
      return true;
    } else if (action.equals("flashOverlay")) {
      flashOverlay(args);
      return true;
    } else if (action.equals("closeScanner")) {
      closeScanner();
      callbackContext.success();
      return true;
    } else if (action.equals("updateStats")) {
      updateStats(args);
      callbackContext.success();
      return true;
    }
    return false;
  }

  private void openNewActivity(Context context, JSONArray args) throws JSONException {
    JSONObject config = args.getJSONObject(0);
    Intent intent = new Intent(context, CaptureActivity.class);
    intent.putExtra("BarcodeFormats", config.optInt("barcodeFormats", 1234));
    intent.putExtra("DetectorSize", config.optDouble("detectorSize", 0.5));
    intent.putExtra("RotateCamera", config.optBoolean("rotateCamera", false));
    intent.putExtra("ShowLogo", config.optBoolean("showLogo", true));
    intent.putExtra("LogoHeight", config.optInt("logoHeight", 40));

    _BeepOnSuccess = config.optBoolean("beepOnSuccess", false);
    _VibrateOnSuccess = config.optBoolean("vibrateOnSuccess", false);

    this.cordova.setActivityResultCallback(this);
    this.cordova.startActivityForResult(this, intent, RC_BARCODE_CAPTURE);
  }

  private void openContinuousScan(Context context, JSONArray args) throws JSONException {
    JSONObject config = args.getJSONObject(0);
    Intent intent = new Intent(context, CaptureActivity.class);
    intent.putExtra("BarcodeFormats", config.optInt("barcodeFormats", 1234));
    intent.putExtra("DetectorSize", config.optDouble("detectorSize", 0.5));
    intent.putExtra("RotateCamera", config.optBoolean("rotateCamera", false));
    intent.putExtra("ContinuousMode", true);
    intent.putExtra("Title", config.optString("title", ""));
    intent.putExtra("Subtitle", config.optString("subtitle", ""));
    intent.putExtra("ShowLogo", config.optBoolean("showLogo", true));
    intent.putExtra("LogoHeight", config.optInt("logoHeight", 40));

    _BeepOnSuccess = config.optBoolean("beepOnSuccess", false);
    _VibrateOnSuccess = config.optBoolean("vibrateOnSuccess", false);

    // Register broadcast receiver for continuous scan results
    registerBarcodeReceiver();

    this.cordova.setActivityResultCallback(this);
    this.cordova.startActivityForResult(this, intent, RC_BARCODE_CAPTURE);
  }

  private void registerBarcodeReceiver() {
    if (_BarcodeReceiver != null) {
      return; // Already registered
    }

    _BarcodeReceiver = new BroadcastReceiver() {
      @Override
      public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        if (action == null) return;

        if (CaptureActivity.ACTION_BARCODE_SCANNED.equals(action)) {
          Integer barcodeFormat = intent.getIntExtra(CaptureActivity.BarcodeFormat, 0);
          Integer barcodeType = intent.getIntExtra(CaptureActivity.BarcodeType, 0);
          String barcodeValue = intent.getStringExtra(CaptureActivity.BarcodeValue);

          Log.d(TAG, "Received barcode broadcast: " + barcodeValue);

          JSONArray result = new JSONArray();
          result.put(barcodeValue);
          result.put(barcodeFormat);
          result.put(barcodeType);

          // Send result but keep callback alive for continuous mode
          PluginResult pluginResult = new PluginResult(PluginResult.Status.OK, result);
          pluginResult.setKeepCallback(true);
          if (_ContinuousCallbackContext != null) {
            _ContinuousCallbackContext.sendPluginResult(pluginResult);
          }

          // Play feedback
          if (_BeepOnSuccess) {
            _MediaPlayer.start();
          }
          if (_VibrateOnSuccess) {
            Integer duration = 200;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
              _Vibrator.vibrate(VibrationEffect.createOneShot(duration, VibrationEffect.DEFAULT_AMPLITUDE));
            } else {
              _Vibrator.vibrate(duration);
            }
          }
        } else if (CaptureActivity.ACTION_SCANNER_READY.equals(action)) {
          // Scanner is ready - resend any pending stats
          Log.d(TAG, "Received SCANNER_READY, pending stats: " + _PendingStats);
          if (_PendingStats != null && !_PendingStats.isEmpty()) {
            Intent statsIntent = new Intent(CaptureActivity.ACTION_UPDATE_UI);
            statsIntent.setPackage(context.getPackageName());
            statsIntent.putExtra("stats", _PendingStats);
            Log.d(TAG, "Resending pending stats: " + _PendingStats);
            context.sendBroadcast(statsIntent);
          }
        }
      }
    };

    IntentFilter filter = new IntentFilter();
    filter.addAction(CaptureActivity.ACTION_BARCODE_SCANNED);
    filter.addAction(CaptureActivity.ACTION_SCANNER_READY);
    Context context = cordova.getContext();
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      context.registerReceiver(_BarcodeReceiver, filter, Context.RECEIVER_EXPORTED);
    } else {
      context.registerReceiver(_BarcodeReceiver, filter);
    }
  }

  private void unregisterBarcodeReceiver() {
    if (_BarcodeReceiver != null) {
      try {
        cordova.getContext().unregisterReceiver(_BarcodeReceiver);
      } catch (IllegalArgumentException e) {
        // Not registered
      }
      _BarcodeReceiver = null;
    }
  }

  private void flashOverlay(JSONArray args) throws JSONException {
    JSONObject config = args.getJSONObject(0);
    String colorStr = config.optString("color", "#22c55e");
    int duration = config.optInt("duration", 500);
    double opacity = config.optDouble("opacity", 0.4);

    int color;
    try {
      color = Color.parseColor(colorStr);
    } catch (IllegalArgumentException e) {
      color = Color.GREEN;
    }

    Intent intent = new Intent(CaptureActivity.ACTION_FLASH_OVERLAY);
    intent.setPackage(cordova.getContext().getPackageName());
    intent.putExtra("color", color);
    intent.putExtra("duration", duration);
    intent.putExtra("opacity", (float) opacity);
    cordova.getContext().sendBroadcast(intent);
  }

  private void closeScanner() {
    Intent intent = new Intent(CaptureActivity.ACTION_CLOSE_SCANNER);
    intent.setPackage(cordova.getContext().getPackageName());
    cordova.getContext().sendBroadcast(intent);
    unregisterBarcodeReceiver();
    _ContinuousMode = false;
    _PendingStats = null; // Clear pending stats when scanner closes
  }

  private void updateStats(JSONArray args) throws JSONException {
    JSONObject config = args.getJSONObject(0);
    String stats = config.optString("stats", "");
    Log.d(TAG, "updateStats called with: " + stats);

    // Store stats so they can be resent when scanner is ready
    _PendingStats = stats;

    Intent intent = new Intent(CaptureActivity.ACTION_UPDATE_UI);
    intent.setPackage(cordova.getContext().getPackageName());
    intent.putExtra("stats", stats);
    Log.d(TAG, "Sending UPDATE_UI broadcast to package: " + cordova.getContext().getPackageName());
    cordova.getContext().sendBroadcast(intent);
  }

  @Override
  public void onActivityResult(int requestCode, int resultCode, Intent data) {
    super.onActivityResult(requestCode, resultCode, data);

    if (requestCode == RC_BARCODE_CAPTURE) {
      // Cleanup continuous mode receiver
      unregisterBarcodeReceiver();

      if (_ContinuousMode) {
        // Continuous mode ended - send final callback
        _ContinuousMode = false;
        if (resultCode == CommonStatusCodes.CANCELED || resultCode != CommonStatusCodes.SUCCESS) {
          JSONArray result = new JSONArray();
          result.put("SCANNER_CLOSED");
          result.put("");
          result.put("");
          PluginResult pluginResult = new PluginResult(PluginResult.Status.ERROR, result);
          pluginResult.setKeepCallback(false);
          if (_ContinuousCallbackContext != null) {
            _ContinuousCallbackContext.sendPluginResult(pluginResult);
          }
        }
        return;
      }

      // Single scan mode
      if (resultCode == CommonStatusCodes.SUCCESS) {
        if (data != null) {
          Integer barcodeFormat = data.getIntExtra(CaptureActivity.BarcodeFormat, 0);
          Integer barcodeType = data.getIntExtra(CaptureActivity.BarcodeType, 0);
          String barcodeValue = data.getStringExtra(CaptureActivity.BarcodeValue);
          JSONArray result = new JSONArray();
          result.put(barcodeValue);
          result.put(barcodeFormat);
          result.put(barcodeType);
          _CallbackContext.sendPluginResult(new PluginResult(PluginResult.Status.OK, result));

          if (_BeepOnSuccess) {
            _MediaPlayer.start();
          }

          if (_VibrateOnSuccess) {
            Integer duration = 200;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
              _Vibrator.vibrate(VibrationEffect.createOneShot(duration, VibrationEffect.DEFAULT_AMPLITUDE));
            } else {
              // deprecated in API 26 aka Oreo
              _Vibrator.vibrate(duration);
            }
          }

          Log.d("MLKitBarcodeScanner", "Barcode read: " + barcodeValue);
        }
      } else {
        String err = data.getStringExtra("err");
        JSONArray result = new JSONArray();
        result.put(err);
        result.put("");
        result.put("");
        _CallbackContext.sendPluginResult(new PluginResult(PluginResult.Status.ERROR, result));
      }
    }
  }

  @Override
  public void onRestoreStateForActivityResult(Bundle state, CallbackContext callbackContext) {
    _CallbackContext = callbackContext;
  }
}
