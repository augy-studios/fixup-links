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
    private static final long DRIFT_MILLISECONDS = 1000;
    private static final long SWEEP_MILLISECONDS = 1800;

    private final Paint activePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint trackPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint stopPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Path wavePath = new Path();
    private final float thickness;
    private final float amplitude;
    private final float wavelength;
    private final float gap;

    // Shown from 0 to 1, chasing where it's been set (target) a little each frame, so a download's
    // many small steps glide rather than each starting an animation of its own.
    private float progress;
    private float target;
    private boolean indeterminate = true;
    private long lastFrame;
    // Running while it's on screen: the wave's drift, and the sweep.
    private ValueAnimator ticker;
    private float phase;
    private float sweep;

    public WavyProgressView(Context context, AttributeSet attributes) {
        super(context, attributes);
        float density = getResources().getDisplayMetrics().density;
        thickness = 4 * density;
        amplitude = 3 * density;
        wavelength = 40 * density;
        gap = 4 * density;
        for (Paint paint : new Paint[] {activePaint, trackPaint}) {
            paint.setStyle(Paint.Style.STROKE);
            paint.setStrokeWidth(thickness);
            paint.setStrokeCap(Paint.Cap.ROUND);
            paint.setStrokeJoin(Paint.Join.ROUND);
        }
        int primary = MaterialColors.getColor(this, androidx.appcompat.R.attr.colorPrimary);
        activePaint.setColor(primary);
        stopPaint.setColor(primary);
        trackPaint.setColor(MaterialColors.getColor(this, com.google.android.material.R.attr.colorSecondaryContainer));
        setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_YES);
    }

    public boolean isIndeterminate() {
        return indeterminate;
    }

    public void setIndeterminate(boolean indeterminate) {
        if (this.indeterminate == indeterminate) {
            return;
        }
        this.indeterminate = indeterminate;
        if (!indeterminate) {
            target = 0;
            progress = 0;
        }
        invalidate();
    }

    // From 0 to 100, eased there if `animate`.
    public void setProgress(int percent, boolean animate) {
        target = Math.max(0, Math.min(100, percent)) / 100f;
        if (!animate || ticker == null) {
            progress = target;
        }
        invalidate();
        sendAccessibilityEvent(android.view.accessibility.AccessibilityEvent.TYPE_VIEW_SELECTED);
    }

    @Override
    protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
        int height = Math.round(thickness + 2 * amplitude) + getPaddingTop() + getPaddingBottom();
        setMeasuredDimension(getDefaultSize(getSuggestedMinimumWidth(), widthMeasureSpec),
                resolveSize(height, heightMeasureSpec));
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
    protected void onVisibilityChanged(View changedView, int visibility) {
        super.onVisibilityChanged(changedView, visibility);
        if (isShown()) {
            tick();
        } else {
            stopTicking();
        }
    }

    private boolean moving() {
        return android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.O || ValueAnimator.areAnimatorsEnabled();
    }

    /**
     * Starts the animator that runs while the bar is on screen (unless animations are off): each
     * frame moves the wave's phase, the indeterminate sweep, and the shown progress a step nearer
     * its target.
     */
    private void tick() {
        if (ticker != null || !isAttachedToWindow() || !isShown() || !moving()) {
            return;
        }
        ticker = ValueAnimator.ofFloat(0, 1).setDuration(SWEEP_MILLISECONDS);
        ticker.setRepeatCount(ValueAnimator.INFINITE);
        ticker.setInterpolator(new LinearInterpolator());
        long start = System.currentTimeMillis();
        lastFrame = start;
        ticker.addUpdateListener((animation) -> {
            long now = System.currentTimeMillis();
            phase = (float) (2 * Math.PI * ((now - start) % DRIFT_MILLISECONDS) / DRIFT_MILLISECONDS);
            sweep = (float) animation.getAnimatedValue();
            // A fifth of the way there every 30 ms or so, whatever the frame rate.
            float step = 1 - (float) Math.pow(0.8, (now - lastFrame) / 30.0);
            progress += (target - progress) * Math.min(1, step);
            if (Math.abs(target - progress) < 0.001f) {
                progress = target;
            }
            lastFrame = now;
            invalidate();
        });
        ticker.start();
    }

    private void stopTicking() {
        if (ticker != null) {
            ticker.cancel();
        }
        ticker = null;
        progress = target;
    }

    /**
     * Draws the bar: while indeterminate, a wavy stretch sweeping across with the flat track
     * either side; otherwise the wave up to the progress, a gap, the flat track to the end, and
     * the stop dot.
     */
    @Override
    protected void onDraw(Canvas canvas) {
        float halfThickness = thickness / 2;
        float left = getPaddingLeft() + halfThickness;
        float right = getWidth() - getPaddingRight() - halfThickness;
        float centerLine = getPaddingTop() + (getHeight() - getPaddingTop() - getPaddingBottom()) / 2f;
        if (right <= left) {
            return;
        }
        float width = right - left;

        if (indeterminate) {
            // A stretch 40% as long as the bar, its front easing in from the left and out past
            // the right, with the track either side of it.
            float eased = (float) (0.5 - Math.cos(Math.PI * sweep) / 2);
            float head = left + (width * 1.4f) * eased;
            float tail = head - width * 0.4f;
            float from = Math.max(left, tail);
            float to = Math.min(right, head);
            if (to > from) {
                wave(canvas, from, to, centerLine, amplitude, wavelength / 2);
            }
            if (from - gap - thickness > left) {
                canvas.drawLine(left, centerLine, from - gap - thickness, centerLine, trackPaint);
            }
            if (to + gap + thickness < right) {
                canvas.drawLine(to + gap + thickness, centerLine, right, centerLine, trackPaint);
            }
            return;
        }

        float end = left + width * progress;
        // Flat at the very start and as it finishes, as Material's does.
        float shownAmplitude = amplitude * Math.max(0, Math.min(1, Math.min(progress / 0.1f, (1 - progress) / 0.05f)));
        if (end > left) {
            wave(canvas, left, end, centerLine, shownAmplitude, wavelength);
        }
        float trackFrom;
        if (progress > 0) {
            trackFrom = end + gap + thickness;
        } else {
            trackFrom = left;
        }
        if (trackFrom < right) {
            canvas.drawLine(trackFrom, centerLine, right, centerLine, trackPaint);
        }
        // The stop dot at the end, till the wave reaches it.
        if (progress < 1) {
            canvas.drawCircle(right, centerLine, halfThickness, stopPaint);
        }
    }

    // A wave from x `from` to `to`, its phase fixed to the bar so it drifts rather than slides.
    private void wave(Canvas canvas, float from, float to, float centerLine, float waveAmplitude, float waveLength) {
        wavePath.rewind();
        float step = Math.max(1f, waveLength / 24);
        for (float horizontal = from; ; horizontal = Math.min(to, horizontal + step)) {
            float vertical = centerLine + waveAmplitude
                    * (float) Math.sin(2 * Math.PI * (horizontal - getPaddingLeft()) / waveLength - phase);
            if (horizontal == from) {
                wavePath.moveTo(horizontal, vertical);
            } else {
                wavePath.lineTo(horizontal, vertical);
            }
            if (horizontal >= to) {
                break;
            }
        }
        canvas.drawPath(wavePath, activePaint);
    }

    // Read out as a progress bar, with how far it's got.
    @Override
    public void onInitializeAccessibilityNodeInfo(AccessibilityNodeInfo info) {
        super.onInitializeAccessibilityNodeInfo(info);
        info.setClassName(ProgressBar.class.getName());
        if (!indeterminate) {
            info.setRangeInfo(AccessibilityNodeInfo.RangeInfo.obtain(
                    AccessibilityNodeInfo.RangeInfo.RANGE_TYPE_PERCENT, 0, 100, Math.round(progress * 100)));
        }
    }
}
