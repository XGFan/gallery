import { createPortal } from "react-dom";
import { useEffect } from "react";
import { Check, Home } from "lucide-react";
import clsx from "clsx";
import type { Crumb } from "../../hooks/useGalleryNav";

interface PathSheetProps {
  isOpen: boolean;
  breadcrumbs: Crumb[];
  onClose: () => void;
  onNavigate: (path: string) => void;
}

// Bottom sheet that replaces the horizontal breadcrumb on mobile. The ancestry
// is rendered as a vertical, indented list — one tap jumps to any level, with
// zero horizontal scrolling. Deep paths simply scroll vertically inside.
export default function PathSheet({ isOpen, breadcrumbs, onClose, onNavigate }: PathSheetProps) {
  useEffect(() => {
    const handleEsc = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", handleEsc);
    return () => window.removeEventListener("keydown", handleEsc);
  }, [onClose]);

  if (!isOpen) return null;

  const lastIndex = breadcrumbs.length - 1;

  return createPortal(
    <div
      className="fixed inset-0 z-50 flex flex-col justify-end"
      role="dialog"
      aria-modal="true"
      aria-label="Path navigation"
    >
      <div
        className="absolute inset-0 bg-black/60 backdrop-blur-xs animate-fade-in"
        onClick={onClose}
        aria-hidden="true"
      />

      <div
        className="relative bg-glass-heavy backdrop-blur-lg border-t border-white/20 rounded-t-3xl shadow-[0_-8px_32px_rgba(0,0,0,0.4)] ring-1 ring-white/10 pb-[calc(env(safe-area-inset-bottom,0px)+1rem)] pt-3 px-3 max-h-[70vh] overflow-y-auto custom-scrollbar animate-sheet-up"
      >
        {/* Grabber */}
        <div className="mx-auto mb-3 h-1.5 w-10 rounded-full bg-white/25" />

        <div className="px-1 pb-1 text-[11px] font-bold uppercase tracking-[0.2em] text-white/40">
          Path
        </div>

        <ul className="flex flex-col">
          {breadcrumbs.map((crumb, idx) => {
            const isCurrent = idx === lastIndex;
            const isHome = idx === 0;
            return (
              <li key={crumb.path || "home"}>
                <button
                  type="button"
                  onClick={() => {
                    if (!isCurrent) onNavigate(crumb.path);
                    onClose();
                  }}
                  aria-current={isCurrent ? "page" : undefined}
                  className={clsx(
                    "flex w-full items-center gap-3 rounded-2xl py-3 text-left transition-colors",
                    isCurrent ? "text-white font-semibold bg-white/10" : "text-white/70 hover:bg-white/5 active:bg-white/10"
                  )}
                  style={{ paddingLeft: `${idx * 18 + 12}px`, paddingRight: "12px" }}
                >
                  {idx > 0 && (
                    <span className="text-white/25 select-none" aria-hidden="true">
                      └
                    </span>
                  )}
                  {isHome ? (
                    <Home className="w-5 h-5 shrink-0" strokeWidth={2} />
                  ) : null}
                  <span className="truncate flex-1">{isHome ? "Home" : crumb.name}</span>
                  {isCurrent && <Check className="w-4 h-4 shrink-0 text-white/70" strokeWidth={2.5} />}
                </button>
              </li>
            );
          })}
        </ul>
      </div>
    </div>,
    document.body,
  );
}
