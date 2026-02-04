package com.mobisys.cordova.plugins.mlkit.barcode.scanner;

import android.animation.Animator;
import android.animation.AnimatorListenerAdapter;
import android.animation.AnimatorSet;
import android.animation.ObjectAnimator;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.util.AttributeSet;
import android.view.View;
import android.view.animation.AccelerateDecelerateInterpolator;

/**
 * Custom view that draws rounded scanner brackets with breathing animation.
 * Similar to iOS CameraViewController's scanFrameView behavior.
 */
public class ScannerBracketsView extends View {
    
    private static final String TAG = "ScannerBracketsView";
    
    private Paint paint;
    private Path topLeftPath, topRightPath, bottomLeftPath, bottomRightPath;
    
    private float detectorSize = 0.5f;
    private int bracketColor = 0xFFFFFFFF; // White
    private float strokeWidth = 12f;
    private float cornerRadius = 50f;
    private float arcLength = 100f;
    
    private boolean isAnimating = false;
    private AnimatorSet breathingAnimator;
    
    public ScannerBracketsView(Context context) {
        super(context);
        init();
    }
    
    public ScannerBracketsView(Context context, AttributeSet attrs) {
        super(context, attrs);
        init();
    }
    
    public ScannerBracketsView(Context context, AttributeSet attrs, int defStyleAttr) {
        super(context, attrs, defStyleAttr);
        init();
    }
    
    private void init() {
        paint = new Paint();
        paint.setStyle(Paint.Style.STROKE);
        paint.setColor(bracketColor);
        paint.setStrokeWidth(strokeWidth);
        paint.setAntiAlias(true);
        paint.setStrokeCap(Paint.Cap.ROUND);
        
        topLeftPath = new Path();
        topRightPath = new Path();
        bottomLeftPath = new Path();
        bottomRightPath = new Path();
    }
    
    public void setDetectorSize(float size) {
        this.detectorSize = size;
        invalidate();
    }
    
    public void setBracketColor(int color) {
        this.bracketColor = color;
        paint.setColor(color);
        invalidate();
    }
    
    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        
        int width = getWidth();
        int height = getHeight();
        
        if (width == 0 || height == 0) return;
        
        int diameter = Math.min(width, height);
        int offset = (int) ((1 - detectorSize) * diameter);
        diameter -= offset;
        
        int left = width / 2 - diameter / 2;
        int top = height / 2 - diameter / 2;
        int right = width / 2 + diameter / 2;
        int bottom = height / 2 + diameter / 2;
        
        // Clear paths
        topLeftPath.reset();
        topRightPath.reset();
        bottomLeftPath.reset();
        bottomRightPath.reset();
        
        // Top-left corner arc
        topLeftPath.moveTo(left, top + arcLength);
        topLeftPath.lineTo(left, top + cornerRadius);
        topLeftPath.arcTo(new RectF(left, top, left + cornerRadius * 2, top + cornerRadius * 2), 
                          180, 90, false);
        topLeftPath.lineTo(left + arcLength, top);
        
        // Top-right corner arc
        topRightPath.moveTo(right - arcLength, top);
        topRightPath.lineTo(right - cornerRadius, top);
        topRightPath.arcTo(new RectF(right - cornerRadius * 2, top, right, top + cornerRadius * 2),
                           -90, 90, false);
        topRightPath.lineTo(right, top + arcLength);
        
        // Bottom-left corner arc
        bottomLeftPath.moveTo(left, bottom - arcLength);
        bottomLeftPath.lineTo(left, bottom - cornerRadius);
        bottomLeftPath.arcTo(new RectF(left, bottom - cornerRadius * 2, left + cornerRadius * 2, bottom),
                             180, -90, false);
        bottomLeftPath.lineTo(left + arcLength, bottom);
        
        // Bottom-right corner arc
        bottomRightPath.moveTo(right, bottom - arcLength);
        bottomRightPath.lineTo(right, bottom - cornerRadius);
        bottomRightPath.arcTo(new RectF(right - cornerRadius * 2, bottom - cornerRadius * 2, right, bottom),
                              0, 90, false);
        bottomRightPath.lineTo(right - arcLength, bottom);
        
        // Draw all paths
        canvas.drawPath(topLeftPath, paint);
        canvas.drawPath(topRightPath, paint);
        canvas.drawPath(bottomLeftPath, paint);
        canvas.drawPath(bottomRightPath, paint);
    }
    
    /**
     * Start the breathing/focus animation
     */
    public void startBreathingAnimation() {
        if (isAnimating) return;
        isAnimating = true;
        
        animateBreathingCycle();
    }
    
    private void animateBreathingCycle() {
        if (!isAnimating) return;
        
        // Scale down (inhale)
        ObjectAnimator scaleDownX = ObjectAnimator.ofFloat(this, "scaleX", 1.0f, 0.88f);
        ObjectAnimator scaleDownY = ObjectAnimator.ofFloat(this, "scaleY", 1.0f, 0.88f);
        scaleDownX.setDuration(900);
        scaleDownY.setDuration(900);
        
        // Scale up (exhale)
        ObjectAnimator scaleUpX = ObjectAnimator.ofFloat(this, "scaleX", 0.88f, 1.0f);
        ObjectAnimator scaleUpY = ObjectAnimator.ofFloat(this, "scaleY", 0.88f, 1.0f);
        scaleUpX.setDuration(900);
        scaleUpY.setDuration(900);
        
        AnimatorSet scaleDown = new AnimatorSet();
        scaleDown.playTogether(scaleDownX, scaleDownY);
        scaleDown.setInterpolator(new AccelerateDecelerateInterpolator());
        
        AnimatorSet scaleUp = new AnimatorSet();
        scaleUp.playTogether(scaleUpX, scaleUpY);
        scaleUp.setInterpolator(new AccelerateDecelerateInterpolator());
        
        breathingAnimator = new AnimatorSet();
        breathingAnimator.playSequentially(scaleDown, scaleUp);
        breathingAnimator.addListener(new AnimatorListenerAdapter() {
            @Override
            public void onAnimationEnd(Animator animation) {
                if (isAnimating) {
                    // Loop the animation
                    animateBreathingCycle();
                }
            }
        });
        
        breathingAnimator.start();
    }
    
    /**
     * Pause the breathing animation (e.g., when barcode detected)
     */
    public void pauseBreathingAnimation() {
        isAnimating = false;
        if (breathingAnimator != null) {
            breathingAnimator.cancel();
        }
        // Snap back to normal scale
        animate().scaleX(1.0f).scaleY(1.0f).setDuration(150).start();
    }
    
    /**
     * Resume breathing animation after a delay
     */
    public void resumeBreathingAnimationAfterDelay(long delayMs) {
        postDelayed(() -> startBreathingAnimation(), delayMs);
    }
    
    /**
     * Perform a quick focus effect (shrink then spring back)
     * Called when a barcode is detected
     */
    public void animateFocusEffect() {
        pauseBreathingAnimation();
        
        // Quick shrink
        animate()
            .scaleX(0.92f)
            .scaleY(0.92f)
            .setDuration(150)
            .withEndAction(() -> {
                // Spring back
                animate()
                    .scaleX(1.0f)
                    .scaleY(1.0f)
                    .setDuration(400)
                    .withEndAction(() -> {
                        // Resume breathing after hold
                        resumeBreathingAnimationAfterDelay(1000);
                    })
                    .start();
            })
            .start();
    }
    
    @Override
    protected void onDetachedFromWindow() {
        super.onDetachedFromWindow();
        pauseBreathingAnimation();
    }
}
