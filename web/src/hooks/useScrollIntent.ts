import { useEffect, useRef, useState } from "react";

export interface ScrollIntent {
  // Last meaningful scroll direction, or "idle" after the user stops.
  direction: "up" | "down" | "idle";
  // Near the very top of the page (where you can't scroll up to reveal chrome,
  // and short albums never scroll at all).
  atTop: boolean;
}

const TOP_THRESHOLD = 12; // px from top still counted as "at top"
const MICRO = 2; // ignore sub-pixel / jitter scrolls
const IDLE_MS = 1500; // settle to idle this long after the last scroll

// Drives the mobile chrome's mutually-exclusive show/hide:
//   scroll down  → counter (loading progress), nav hidden
//   scroll up    → nav, counter hidden
//   idle in body → both hidden (clean wall)
//   at top       → nav stays reachable (counter hidden)
// Shared, independent instances in MobileNav and Viewer stay in sync because they
// read the same window scroll with the same algorithm.
export function useScrollIntent(idleMs = IDLE_MS): ScrollIntent {
  const [intent, setIntent] = useState<ScrollIntent>({ direction: "idle", atTop: true });
  const lastY = useRef(0);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    const onScroll = () => {
      const y = window.scrollY;
      const atTop = y < TOP_THRESHOLD;
      const dy = y - lastY.current;
      lastY.current = y;

      // Tiny moves only update the at-top flag, never the direction.
      if (Math.abs(dy) < MICRO) {
        setIntent((prev) => (prev.atTop === atTop ? prev : { ...prev, atTop }));
        return;
      }

      setIntent({ direction: dy > 0 ? "down" : "up", atTop });
      if (timer.current) clearTimeout(timer.current);
      timer.current = setTimeout(
        () => setIntent((prev) => ({ ...prev, direction: "idle" })),
        idleMs,
      );
    };

    window.addEventListener("scroll", onScroll, { passive: true });
    return () => {
      window.removeEventListener("scroll", onScroll);
      if (timer.current) clearTimeout(timer.current);
    };
  }, [idleMs]);

  return intent;
}
