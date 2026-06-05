import { useEffect, useState } from "react";
import { useLoaderData } from "react-router-dom";
import { Album, AppCtx, Mode } from "../../dto";
import { useGalleryNav } from "../../hooks/useGalleryNav";
import { useScrollIntent } from "../../hooks/useScrollIntent";
import MobileTopBar from "./MobileTopBar";
import BottomTabBar from "./BottomTabBar";
import PathSheet from "./PathSheet";

interface MobileNavProps {
  isSidebarOpen?: boolean;
  onSidebarToggle: () => void;
}

// Composes the mobile navigation: a minimal top bar (drawer + path title), a
// bottom Path Sheet for ancestry jumps, and a bottom tab bar for mode switching.
//
// Chrome visibility is mutually exclusive with the gallery's loading counter
// (which shows while scrolling *down*): the nav appears on scroll-up or at the
// top of the page, and hides while scrolling down or sitting idle in the content
// — so the counter and the tab bar never share the bottom edge.
export default function MobileNav({ isSidebarOpen, onSidebarToggle }: MobileNavProps) {
  const { data: album } = useLoaderData() as AppCtx<Album>;
  const { breadcrumbs, availableModes, currentMode, isLeaf, changeMode, navigateToPath } = useGalleryNav(album);
  const [isPathOpen, setPathOpen] = useState(false);
  const { direction, atTop } = useScrollIntent();
  const chromeVisible = atTop || direction === "up";

  // Safety net mirroring the desktop TopBar: landing on a leaf folder in a
  // directory-oriented mode falls back to the photo view.
  useEffect(() => {
    if (isLeaf && (currentMode === "album" || currentMode === "explore")) {
      changeMode("image");
    }
  }, [isLeaf, currentMode, changeMode]);

  // Any real scroll dismisses the path sheet.
  useEffect(() => {
    if (direction === "up" || direction === "down") setPathOpen(false);
  }, [direction]);

  const handleSelect = (mode: Mode) => {
    if (mode !== currentMode) changeMode(mode);
  };

  return (
    <>
      <MobileTopBar
        breadcrumbs={breadcrumbs}
        isVisible={chromeVisible}
        isSidebarOpen={isSidebarOpen}
        onSidebarToggle={onSidebarToggle}
        onOpenPath={() => setPathOpen(true)}
      />

      <PathSheet
        isOpen={isPathOpen}
        breadcrumbs={breadcrumbs}
        onClose={() => setPathOpen(false)}
        onNavigate={navigateToPath}
      />

      <BottomTabBar
        modes={availableModes}
        currentMode={currentMode}
        isVisible={chromeVisible}
        onSelect={handleSelect}
      />
    </>
  );
}
