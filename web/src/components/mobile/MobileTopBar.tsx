import { ChevronDown, Home, Menu } from "lucide-react";
import clsx from "clsx";
import type { Crumb } from "../../hooks/useGalleryNav";

interface MobileTopBarProps {
  breadcrumbs: Crumb[];
  isVisible: boolean;
  isSidebarOpen?: boolean;
  onSidebarToggle: () => void;
  onOpenPath: () => void;
}

// Minimal, navigation-only top bar for mobile: a drawer toggle + the current
// folder name. No mode switcher lives here any more, so the breadcrumb gets the
// whole top axis and never collides with mode switching. Tapping the title opens
// the Path Sheet.
export default function MobileTopBar({
  breadcrumbs,
  isVisible,
  isSidebarOpen,
  onSidebarToggle,
  onOpenPath,
}: MobileTopBarProps) {
  const current = breadcrumbs[breadcrumbs.length - 1];
  const isRoot = breadcrumbs.length <= 1;
  const title = isRoot || !current?.name ? "Home" : current.name;

  return (
    <header
      className={clsx(
        "fixed left-0 right-0 h-12 flex items-center gap-2 px-4 z-30 pointer-events-none transition-transform duration-300 topbar-safe",
        !isVisible && "topbar-hidden",
      )}
    >
      <div className="flex items-center gap-1 bg-surface backdrop-ui border border-line rounded-full h-12 pl-1 pr-2 shadow-ui pointer-events-auto max-w-[calc(100vw-2rem)] min-w-0">
        <button
          type="button"
          onClick={onSidebarToggle}
          aria-label={isSidebarOpen ? "Close Sidebar" : "Open Sidebar"}
          className="flex items-center justify-center w-10 h-10 rounded-full text-fg-2 hover:text-fg hover:bg-fill-hover active:bg-fill-active transition-all shrink-0"
        >
          <Menu className="w-5 h-5" strokeWidth={1.75} />
        </button>

        <div className="w-px h-5 bg-line shrink-0" />

        <button
          type="button"
          onClick={onOpenPath}
          aria-label="Show path"
          className="flex items-center gap-1.5 min-w-0 pl-2 pr-1 h-10 rounded-full text-fg hover:bg-fill-hover active:bg-fill-active transition-all"
        >
          {isRoot && <Home className="w-4 h-4 shrink-0" strokeWidth={2} />}
          <span className="truncate font-semibold text-sm">{title}</span>
          <ChevronDown className="w-4 h-4 shrink-0 text-fg-3" strokeWidth={2.5} />
        </button>
      </div>
    </header>
  );
}
