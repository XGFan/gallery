import { useCallback, useMemo } from "react";
import { useNavigate } from "react-router-dom";
import { Compass, Image as ImageIcon, LayoutGrid, Shuffle } from "lucide-react";
import type { ComponentType, SVGProps } from "react";
import { Album, Mode } from "../dto";
import { getShuffleOpenMode } from "../utils";

export type NavIcon = ComponentType<SVGProps<SVGSVGElement> & { strokeWidth?: number | string }>;

export interface Crumb {
  name: string;
  path: string;
}

export interface ModeItem {
  id: Mode;
  icon: NavIcon;
  label: string;
}

// Pure navigation derivations shared by the mobile nav components. This mirrors
// the breadcrumb / mode / isLeaf logic that lives inline in the desktop TopBar;
// the desktop TopBar is intentionally left untouched (scope: mobile-first), so a
// little duplication is accepted during the migration rather than risk a
// desktop regression. When the new UI graduates to large screens, TopBar can be
// retired in favour of this hook.
export function useGalleryNav(album: Album) {
  const navigate = useNavigate();
  const currentPath = album.path.path;
  const currentMode = album.mode;

  // Home → … → current. Home has an empty name (icon-only); intermediate empty
  // (root) parents are filtered out, matching the desktop breadcrumb.
  const breadcrumbs = useMemo<Crumb[]>(() => [
    { name: "", path: "" },
    ...album.path.parents().reverse().filter((p) => p.name).map((p) => ({ name: p.name, path: p.path })),
    ...(album.path.name ? [{ name: album.path.name, path: album.path.path }] : []),
  ], [album.path]);

  const changeMode = useCallback((newMode: Mode) => {
    if (newMode === "random" && getShuffleOpenMode() === "app") {
      // Direct navigation is the most reliable app handoff to tiny-viewer.
      window.location.href = `tinyviewer://${currentPath || ""}`;
      return;
    }
    navigate(`${currentPath ? "/" + currentPath : "/"}?mode=${newMode}`);
  }, [navigate, currentPath]);

  // Jump to an ancestor folder. Matches the desktop breadcrumb click target.
  const navigateToPath = useCallback((path: string) => {
    navigate(`/${path}?mode=album`);
  }, [navigate]);

  const isLeaf = useMemo(() => {
    if (album.images.some((img) => img.imageType === "directory")) return false;
    if (currentMode === "album" || currentMode === "explore") return true;
    if (currentMode === "image" || currentMode === "random") {
      const threshold = currentPath ? 1 : 0;
      return !album.images.some((img) => {
        const key = decodeURIComponent(img.key);
        if (currentPath && !key.startsWith(currentPath)) return false;
        const relative = currentPath ? key.substring(currentPath.length) : key;
        const slashCount = (relative.match(/\//g) || []).length;
        return slashCount > threshold;
      });
    }
    return false;
  }, [album.images, currentMode, currentPath]);

  // Stable order (no current-last reorder): a tab bar highlights the active tab
  // in place rather than collapsing to a single icon.
  const availableModes = useMemo<ModeItem[]>(() => ([
    { id: "album" as Mode, icon: LayoutGrid, label: "Albums", hidden: isLeaf },
    { id: "image" as Mode, icon: ImageIcon, label: "Photos", hidden: false },
    { id: "explore" as Mode, icon: Compass, label: "Explore", hidden: isLeaf },
    { id: "random" as Mode, icon: Shuffle, label: "Shuffle", hidden: false },
  ].filter((m) => !m.hidden).map(({ id, icon, label }) => ({ id, icon, label }))), [isLeaf]);

  return { breadcrumbs, changeMode, navigateToPath, isLeaf, availableModes, currentMode, currentPath };
}
