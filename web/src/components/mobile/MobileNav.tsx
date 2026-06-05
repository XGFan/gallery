import { useEffect, useState } from "react";
import { useLoaderData } from "react-router-dom";
import { Album, AppCtx, Mode } from "../../dto";
import { useGalleryNav } from "../../hooks/useGalleryNav";
import { useChromeVisibility } from "../../hooks/useChromeVisibility";
import MobileTopBar from "./MobileTopBar";
import BottomTabBar from "./BottomTabBar";
import PathSheet from "./PathSheet";

interface MobileNavProps {
  isSidebarOpen?: boolean;
  onSidebarToggle: () => void;
}

// Composes the mobile navigation: a minimal top bar (drawer + path title), a
// bottom Path Sheet for ancestry jumps, and an auto-hiding bottom tab bar for
// mode switching. Top and bottom chrome share one scroll-visibility signal so
// they hide/show together; scrolling also dismisses the path sheet.
export default function MobileNav({ isSidebarOpen, onSidebarToggle }: MobileNavProps) {
  const { data: album } = useLoaderData() as AppCtx<Album>;
  const { breadcrumbs, availableModes, currentMode, isLeaf, changeMode, navigateToPath } = useGalleryNav(album);
  const [isPathOpen, setPathOpen] = useState(false);
  const isVisible = useChromeVisibility(() => setPathOpen(false));

  // Safety net mirroring the desktop TopBar: landing on a leaf folder in a
  // directory-oriented mode falls back to the photo view.
  useEffect(() => {
    if (isLeaf && (currentMode === "album" || currentMode === "explore")) {
      changeMode("image");
    }
  }, [isLeaf, currentMode, changeMode]);

  const handleSelect = (mode: Mode) => {
    if (mode !== currentMode) changeMode(mode);
  };

  return (
    <>
      <MobileTopBar
        breadcrumbs={breadcrumbs}
        isVisible={isVisible}
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
        isVisible={isVisible}
        onSelect={handleSelect}
      />
    </>
  );
}
