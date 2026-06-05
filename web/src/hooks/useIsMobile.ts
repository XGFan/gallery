import { useEffect, useState } from "react";

// Narrow viewport / touch gate for the mobile navigation. Mirrors the existing
// `md:` breakpoint (Tailwind md = 768px) used throughout the desktop TopBar, so
// the two never render at the same time. SSR/jsdom (no matchMedia) resolves to
// false → desktop path, which keeps the existing TopBar/RootLayout tests valid.
const MOBILE_QUERY = "(max-width: 767px)";

export function useIsMobile(): boolean {
  const [isMobile, setIsMobile] = useState<boolean>(() => {
    if (typeof window === "undefined" || typeof window.matchMedia !== "function") {
      return false;
    }
    return window.matchMedia(MOBILE_QUERY).matches;
  });

  useEffect(() => {
    if (typeof window === "undefined" || typeof window.matchMedia !== "function") {
      return;
    }
    const mq = window.matchMedia(MOBILE_QUERY);
    const handleChange = (e: MediaQueryListEvent) => setIsMobile(e.matches);
    setIsMobile(mq.matches);
    mq.addEventListener("change", handleChange);
    return () => mq.removeEventListener("change", handleChange);
  }, []);

  return isMobile;
}
