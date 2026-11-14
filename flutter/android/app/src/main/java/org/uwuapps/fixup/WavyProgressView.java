/*
 * The updater's progress bar (UpdateActivity, update_activity.xml), as Material 3 Expressive draws
 * one, the way Android's own updater and apps in Material You do: the part done as a wave in the
 * theme's primary colour, drifting, then a gap and the rest of the way flat in its secondary
 * container colour, with a dot at the end. With no telling how far it's got, a wavy stretch sweeps
 * across instead. Its colours are the theme's, so the wallpaper's on Android 12 and later.
 *
 * Material Components' LinearProgressIndicator has the gap and the dot, but no wave: that's only
 * in Jetpack Compose's Material 3, which this app doesn't use. So it's drawn here, to the same
 * measures: a 4 dp line, waves 40 dp long and 3 dp high (half as long while sweeping), flat near
 * the start and the end. With animations off (Settings, Accessibility, Remove animations) it
 * keeps still.
 */
package org.uwuapps.fixup;

import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import android.util.AttributeSet;
import android.view.View;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.animation.LinearInterpolator;
import android.widget.ProgressBar;

import com.google.android.material.color.MaterialColors;

public class WavyProgressView extends View {
    // How long a wave takes to drift by its own length, and the sweep to cross once.
    private static final long DRIFT_MS = 1000;
    private static final long SWEEP_MS = 1800;

    private final Paint mActive = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint mTrack = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint mStop = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Path mPath = new Path();
    private final float mThickness;
    private final float mAmplitude;
    private final float mWavelength;
    private final float mGap;

    // Shown from 0 to 1, chasing where it's been set (mTarget) a little each frame, so a download's
    // many small steps glide rather than each starting an animation of its own.
    private float mProgress;
    private float mTarget;
    private boolean mIndeterminate = true;
    private long mLastFrame;
    // Running while it's on screen: the wave's drift, and the sweep.
    private ValueAnimator mTicker;
    private float mPhase;
    private float mSweep;

    public WavyProgressView(Context context, AttributeSet attrs) {
        super(context, attrs);
        float dp = getResources().getDisplayMetrics().density;
        mThickness = 4 * dp;
        mAmplitude = 3 * dp;
        mWavelength = 40 * dp;
        mGap = 4 * dp;
        for (Paint paint : new Paint[] {mActive, mTrack}) {
            paint.setStyle(Paint.Style.STROKE);
            paint.setStrokeWidth(mThickness);
            paint.setStrokeCap(Paint.Cap.ROUND);
            paint.setStrokeJoin(Paint.Join.ROUND);
        }
        int primary = MaterialColors.getColor(this, androidx.appcompat.R.attr.colorPrimary);
        mActive.setColor(primary);
        mStop.setColor(primary);
        mTrack.setColor(MaterialColors.getColor(this, com.google.android.material.R.attr.colorSecondaryContainer));
        setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_YES);
    }

    public boolean isIndeterminate() {
        return mIndeterminate;
    }

    public void setIndeterminate(boolean indeterminate) {
        if (mIndeterminate == indeterminate) return;
        mIndeterminate = indeterminate;
        if (!indeterminate) mProgress = mTarget = 0;
        invalidate();
    }

    // From 0 to 100, eased there if `animate`.
    public void setProgress(int percent, boolean animate) {
        mTarget = Math.max(0, Math.min(100, percent)) / 100f;
        if (!animate || mTicker == null) mProgress = mTarget;
        invalidate();
        sendAccessibilityEvent(android.view.accessibility.AccessibilityEvent.TYPE_VIEW_SELECTED);
    }

    @Override
    protected void onMeasure(int widthSpec, int heightSpec) {
        int height = Math.round(mThickness + 2 * mAmplitude) + getPaddingTop() + getPaddingBottom();
        setMeasuredDimension(getDefaultSize(getSuggestedMinimumWidth(), widthSpec), resolveSize(height, heightSpec));
    }

    @Override
    protected void onAttachedToWindow() {
        super.onAttachedToWindow();
        tick();
    }

    @Override
    protected void onDetachedFromWindow() {
        super.onDetachedFromWindow();
        stopTicking();
    }

    @Override
    protected void onVisibilityChanged(View changed, int visibility) {
        super.onVisibilityChanged(changed, visibility);
        if (isShown()) tick();
        else stopTicking();
    }

    private boolean moving() {
        return android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.O || ValueAnimator.areAnimatorsEnabled();
    }

    private void tick() {
        if (mTicker != null || !isAttachedToWindow() || !isShown() || !moving()) return;
        mTicker = ValueAnimator.ofFloat(0, 1).setDuration(SWEEP_MS);
        mTicker.setRepeatCount(ValueAnimator.INFINITE);
        mTicker.setInterpolator(new LinearInterpolator());
        long start = System.currentTimeMillis();
        mLastFrame = start;
        mTicker.addUpdateListener(a -> {
            long now = System.currentTimeMillis();
            mPhase = (float) (2 * Math.PI * ((now - start) % DRIFT_MS) / DRIFT_MS);
            mSweep = (float) a.getAnimatedValue();
            // A fifth of the way there every 30 ms or so, whatever the frame rate.
            float step = 1 - (float) Math.pow(0.8, (now - mLastFrame) / 30.0);
            mProgress += (mTarget - mProgress) * Math.min(1, step);
            if (Math.abs(mTarget - mProgress) < 0.001f) mProgress = mTarget;
            mLastFrame = now;
            invalidate();
        });
        mTicker.start();
    }

    private void stopTicking() {
        if (mTicker != null) mTicker.cancel();
        mTicker = null;
        mProgress = mTarget;
    }

    @Override
    protected void onDraw(Canvas canvas) {
        float half = mThickness / 2;
        float left = getPaddingLeft() + half;
        float right = getWidth() - getPaddingRight() - half;
        float cy = getPaddingTop() + (getHeight() - getPaddingTop() - getPaddingBottom()) / 2f;
        if (right <= left) return;
        float width = right - left;

        if (mIndeterminate) {
            // A stretch 40% as long as the bar, its front easing in from the left and out past
            // the right, with the track either side of it.
            float eased = (float) (0.5 - Math.cos(Math.PI * mSweep) / 2);
            float head = left + (width * 1.4f) * eased;
            float tail = head - width * 0.4f;
            float from = Math.max(left, tail);
            float to = Math.min(right, head);
            if (to > from) wave(canvas, from, to, cy, mAmplitude, mWavelength / 2);
            if (from - mGap - mThickness > left) canvas.drawLine(left, cy, from - mGap - mThickness, cy, mTrack);
            if (to + mGap + mThickness < right) canvas.drawLine(to + mGap + mThickness, cy, right, cy, mTrack);
            return;
        }

        float end = left + width * mProgress;
        // Flat at the very start and as it finishes, as Material's does.
        float amplitude = mAmplitude * Math.max(0, Math.min(1, Math.min(mProgress / 0.1f, (1 - mProgress) / 0.05f)));
        if (end > left) wave(canvas, left, end, cy, amplitude, mWavelength);
        float trackFrom = mProgress > 0 ? end + mGap + mThickness : left;
        if (trackFrom < right) canvas.drawLine(trackFrom, cy, right, cy, mTrack);
        // The stop dot at the end, till the wave reaches it.
        if (mProgress < 1) canvas.drawCircle(right, cy, half, mStop);
    }

    // A wave from x `from` to `to`, its phase fixed to the bar so it drifts rather than slides.
    private void wave(Canvas canvas, float from, float to, float cy, float amplitude, float wavelength) {
        mPath.rewind();
        float step = Math.max(1f, wavelength / 24);
        for (float x = from; ; x = Math.min(to, x + step)) {
            float y = cy + amplitude * (float) Math.sin(2 * Math.PI * (x - getPaddingLeft()) / wavelength - mPhase);
            if (x == from) mPath.moveTo(x, y);
            else mPath.lineTo(x, y);
            if (x >= to) break;
        }
        canvas.drawPath(mPath, mActive);
    }

    // Read out as a progress bar, with how far it's got.
    @Override
    public void onInitializeAccessibilityNodeInfo(AccessibilityNodeInfo info) {
        super.onInitializeAccessibilityNodeInfo(info);
        info.setClassName(ProgressBar.class.getName());
        if (!mIndeterminate) {
            info.setRangeInfo(AccessibilityNodeInfo.RangeInfo.obtain(
                    AccessibilityNodeInfo.RangeInfo.RANGE_TYPE_PERCENT, 0, 100, Math.round(mProgress * 100)));
        }
    }
}
