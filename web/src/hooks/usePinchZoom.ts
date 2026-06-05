import { useEffect, useRef } from "react";

/** Clamp a number into the inclusive [min, max] range. */
export function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

/** Euclidean distance between two active touch points. */
export function touchDistance(a: Touch, b: Touch): number {
  return Math.hypot(b.clientX - a.clientX, b.clientY - a.clientY);
}

/**
 * Map a pinch gesture to a new (rounded, clamped) value.
 *
 * Spreading the fingers apart (currentDistance > startDistance) scales the value
 * up; pinching them together scales it down — matching native pinch-to-zoom.
 */
export function computePinchValue(
  startValue: number,
  startDistance: number,
  currentDistance: number,
  min: number,
  max: number,
): number {
  if (startDistance <= 0) return clamp(startValue, min, max);
  const scaled = startValue * (currentDistance / startDistance);
  return clamp(Math.round(scaled), min, max);
}

interface UsePinchZoomOptions {
  /** Current value (e.g. gallery row height in px). */
  value: number;
  /** Setter for the value; only called when the rounded value actually changes. */
  setValue: (next: number) => void;
  /** Lower bound for the value. */
  min: number;
  /** Upper bound for the value. */
  max: number;
  /** Pixels of value change per unit of ctrl/meta + wheel delta (trackpad pinch). */
  wheelStep?: number;
  /**
   * When false the gesture is fully disabled: no listeners are attached and the
   * page's native pinch-zoom is left untouched. Use this to yield to overlays
   * that own their own zoom (e.g. an open lightbox) so the wall isn't resized
   * behind them.
   */
  enabled?: boolean;
}

/**
 * Resize an image wall by pinching.
 *
 * - Touch screens: two-finger pinch scales `value` continuously.
 * - Trackpads: browsers deliver a pinch as `wheel` + ctrlKey, handled here too.
 *
 * Ported from the avp gallery (which adjusts a discrete column count); this
 * variant scales gallery's continuous `rowHeight`. Native page pinch-zoom is
 * suppressed while mounted so the gesture drives the wall instead of the page.
 */
export function usePinchZoom({
  value,
  setValue,
  min,
  max,
  wheelStep = 1,
  enabled = true,
}: UsePinchZoomOptions): void {
  // Keep the latest value reachable from the long-lived listeners below without
  // re-subscribing on every change.
  const valueRef = useRef(value);
  useEffect(() => {
    valueRef.current = value;
  }, [value]);

  useEffect(() => {
    if (!enabled) return;

    const html = document.documentElement;
    const prevTouchAction = html.style.touchAction;
    // Allow normal scrolling but disable the browser's own pinch-zoom.
    html.style.touchAction = "pan-x pan-y";

    // Baseline for the active two-finger gesture; 0 means "no gesture in flight".
    let startDistance = 0;
    let startValue = 0;

    const apply = (next: number) => {
      if (next !== valueRef.current) setValue(next);
    };

    // Capture a fresh baseline from the two active fingers.
    const baseline = (e: TouchEvent) => {
      startDistance = touchDistance(e.touches[0], e.touches[1]);
      startValue = valueRef.current;
    };

    const onTouchStart = (e: TouchEvent) => {
      // Only an exact two-finger contact starts a pinch; any other count
      // (single-finger scroll, or a third finger) invalidates the baseline.
      if (e.touches.length === 2) baseline(e);
      else startDistance = 0;
    };

    const onTouchMove = (e: TouchEvent) => {
      if (e.touches.length !== 2) {
        // Single finger (scroll) or 3+ fingers: not a pinch — never preventDefault.
        startDistance = 0;
        return;
      }
      if (startDistance === 0) {
        // A clean two-finger gesture (re)started, e.g. after going 2->3->2
        // fingers; re-baseline from here instead of using stale fingers.
        baseline(e);
        return;
      }
      e.preventDefault(); // block native pinch-zoom
      const current = touchDistance(e.touches[0], e.touches[1]);
      apply(computePinchValue(startValue, startDistance, current, min, max));
    };

    const onTouchEnd = (e: TouchEvent) => {
      if (e.touches.length < 2) startDistance = 0;
    };

    // Trackpad pinch is reported as a wheel event with ctrlKey set.
    const onWheel = (e: WheelEvent) => {
      if (!e.ctrlKey && !e.metaKey) return;
      e.preventDefault();
      // Wheel up (deltaY < 0) zooms in -> larger value.
      apply(clamp(Math.round(valueRef.current - e.deltaY * wheelStep), min, max));
    };

    // Safari fires non-standard gesture events for trackpad pinch; block the
    // native page zoom so our wheel handler stays in control.
    const preventGesture = (e: Event) => e.preventDefault();

    document.addEventListener("touchstart", onTouchStart, { passive: false });
    document.addEventListener("touchmove", onTouchMove, { passive: false });
    document.addEventListener("touchend", onTouchEnd);
    document.addEventListener("touchcancel", onTouchEnd);
    window.addEventListener("wheel", onWheel, { passive: false });
    document.addEventListener("gesturestart", preventGesture, { passive: false });
    document.addEventListener("gesturechange", preventGesture, { passive: false });

    return () => {
      html.style.touchAction = prevTouchAction;
      document.removeEventListener("touchstart", onTouchStart);
      document.removeEventListener("touchmove", onTouchMove);
      document.removeEventListener("touchend", onTouchEnd);
      document.removeEventListener("touchcancel", onTouchEnd);
      window.removeEventListener("wheel", onWheel);
      document.removeEventListener("gesturestart", preventGesture);
      document.removeEventListener("gesturechange", preventGesture);
    };
  }, [enabled, setValue, min, max, wheelStep]);
}
