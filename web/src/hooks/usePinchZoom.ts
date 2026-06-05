import { useEffect, useRef } from "react";

/** Clamp a number into the inclusive [min, max] range. */
export function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

/** Euclidean distance between two active touch points. */
export function touchDistance(a: Touch, b: Touch): number {
  return Math.hypot(b.clientX - a.clientX, b.clientY - a.clientY);
}

/** Direction of a pinch step: +1 = zoom in (bigger), -1 = zoom out (smaller). */
export type ZoomDirection = 1 | -1;

interface UsePinchZoomOptions {
  /** Called once per discrete zoom step. +1 = zoom in (bigger), -1 = zoom out. */
  onZoom: (direction: ZoomDirection) => void;
  /**
   * When false the gesture is fully disabled: no listeners are attached and the
   * page's native pinch-zoom is left untouched. Use this to yield to overlays
   * that own their own zoom (e.g. an open lightbox).
   */
  enabled?: boolean;
  /** Finger-spread delta (px) that triggers one step. Smaller = more sensitive. */
  threshold?: number;
  /** Minimum time (ms) between steps, so one gesture doesn't fire a burst. */
  cooldownMs?: number;
}

/**
 * Resize an image wall by pinching, avp-style: each gesture emits discrete
 * zoom steps (one column at a time) instead of a continuous value, which keeps
 * the change crisp and always visible.
 *
 * - Touch screens: spreading two fingers past `threshold` zooms in; pinching
 *   them together zooms out. The baseline re-arms after each step so a sustained
 *   spread keeps stepping.
 * - Trackpads: a pinch arrives as `wheel` + ctrlKey, handled the same way.
 *
 * Native page pinch-zoom is suppressed while enabled so the gesture drives the
 * wall instead of the page.
 */
export function usePinchZoom({
  onZoom,
  enabled = true,
  threshold = 30,
  cooldownMs = 250,
}: UsePinchZoomOptions): void {
  // Keep the latest callback reachable from the long-lived listeners without
  // re-subscribing on every render.
  const onZoomRef = useRef(onZoom);
  useEffect(() => {
    onZoomRef.current = onZoom;
  }, [onZoom]);

  useEffect(() => {
    if (!enabled) return;

    const html = document.documentElement;
    const prevTouchAction = html.style.touchAction;
    // Allow normal scrolling but disable the browser's own pinch-zoom.
    html.style.touchAction = "pan-x pan-y";

    let baseDistance = 0; // 0 means "no two-finger gesture in flight"
    let lastStepAt = 0;

    const step = (direction: ZoomDirection) => {
      lastStepAt = Date.now();
      onZoomRef.current(direction);
    };

    const onTouchStart = (e: TouchEvent) => {
      baseDistance = e.touches.length === 2 ? touchDistance(e.touches[0], e.touches[1]) : 0;
    };

    const onTouchMove = (e: TouchEvent) => {
      if (e.touches.length !== 2) {
        // Single finger (scroll) or 3+ fingers: not a pinch — never preventDefault.
        baseDistance = 0;
        return;
      }
      e.preventDefault(); // block native pinch-zoom
      const current = touchDistance(e.touches[0], e.touches[1]);
      if (baseDistance === 0) {
        baseDistance = current; // (re)arm baseline for a fresh two-finger gesture
        return;
      }
      const delta = current - baseDistance;
      if (Math.abs(delta) > threshold && Date.now() - lastStepAt > cooldownMs) {
        step(delta > 0 ? 1 : -1); // spread -> zoom in (bigger); pinch -> zoom out
        baseDistance = current; // re-arm so a sustained gesture keeps stepping
      }
    };

    const onTouchEnd = (e: TouchEvent) => {
      if (e.touches.length < 2) baseDistance = 0;
    };

    // Trackpad pinch is reported as a wheel event with ctrlKey set.
    const onWheel = (e: WheelEvent) => {
      if (!e.ctrlKey && !e.metaKey) return;
      e.preventDefault();
      if (Date.now() - lastStepAt <= cooldownMs) return;
      if (e.deltaY < 0) step(1); // wheel up -> zoom in
      else if (e.deltaY > 0) step(-1); // wheel down -> zoom out
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
  }, [enabled, threshold, cooldownMs]);
}
