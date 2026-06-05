import clsx from "clsx";
import type { Mode } from "../../dto";
import type { ModeItem } from "../../hooks/useGalleryNav";

interface BottomTabBarProps {
  modes: ModeItem[];
  currentMode: Mode;
  isVisible: boolean;
  onSelect: (mode: Mode) => void;
}

// Mode switching lives on the bottom edge as a thumb-reachable tab bar: a single
// tap switches mode, and it shares the top bar's scroll-aware visibility so both
// slide away while browsing (full-screen wall) and return at rest / scroll-up.
//
// Layout follows iOS Photos' segmented switcher: each tab stacks its icon over a
// label, and the active tab gets a soft highlight pill in the accent colour.
// Stacking is also the most width-efficient way to label four tabs on a phone —
// the label width (not icon+label) sets the tab width, so all four fit a 375px
// viewport without truncation.
export default function BottomTabBar({ modes, currentMode, isVisible, onSelect }: BottomTabBarProps) {
  // Nothing to switch between → don't occupy the bottom edge at all.
  if (modes.length <= 1) return null;

  return (
    <nav
      aria-label="View mode"
      className={clsx(
        "fixed left-0 right-0 flex justify-center z-30 pointer-events-none bottombar-safe transition-[transform,opacity] duration-300 ease-[cubic-bezier(0.32,0.72,0,1)]",
        !isVisible && "bottombar-hidden",
      )}
    >
      <div className="flex items-center gap-2 bg-glass-liquid backdrop-blur-lg border border-white/20 rounded-full p-2 shadow-[0_4px_24px_rgba(0,0,0,0.35)] ring-1 ring-white/10 pointer-events-auto max-w-[calc(100vw-1rem)]">
        {modes.map((mode) => {
          const active = mode.id === currentMode;
          return (
            <button
              key={mode.id}
              type="button"
              onClick={() => onSelect(mode.id)}
              aria-label={mode.label}
              aria-current={active ? "true" : undefined}
              className={clsx(
                "flex flex-col items-center justify-center gap-1 rounded-full px-3 py-2 min-w-[76px] transition-colors duration-300",
                active
                  ? "bg-white/15 text-accent"
                  : "text-white/55 hover:text-white/90",
              )}
            >
              <mode.icon className="w-6 h-6" strokeWidth={2} />
              <span className="text-[11px] font-semibold leading-none">{mode.label}</span>
            </button>
          );
        })}
      </div>
    </nav>
  );
}
