import { useEffect, useRef, useState } from "react";

// Scroll-direction → chrome visibility, shared by the mobile top bar and bottom
// tab bar so both edges hide/show together (full-screen wall while browsing).
// Extracted from the desktop TopBar's scroll logic and kept behaviourally
// identical: visible at the top or when scrolling up, hidden when scrolling
// down past a small threshold. `onScroll` fires every scroll so callers can
// collapse transient UI (e.g. the path sheet).
export function useChromeVisibility(onScroll?: () => void): boolean {
  const [isVisible, setIsVisible] = useState(true);
  const lastScrollY = useRef(0);
  const onScrollRef = useRef(onScroll);
  onScrollRef.current = onScroll;

  useEffect(() => {
    const handleScroll = () => {
      const currentScrollY = window.scrollY;
      onScrollRef.current?.();

      if (currentScrollY < 10 || currentScrollY < lastScrollY.current) {
        setIsVisible(true);
      } else if (currentScrollY > lastScrollY.current && currentScrollY > 50) {
        setIsVisible(false);
      }

      lastScrollY.current = currentScrollY;
    };

    window.addEventListener("scroll", handleScroll, { passive: true });
    return () => window.removeEventListener("scroll", handleScroll);
  }, []);

  return isVisible;
}
