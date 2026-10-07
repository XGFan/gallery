import clsx from "clsx";
import FileTree from "../FileTree";
import { Library, Settings } from "lucide-react";

interface SidebarProps {
    className?: string;
    onOpenShuffleSettings?: () => void;
}

export default function NavigationSidebar({ className, onOpenShuffleSettings }: SidebarProps) {
    return (
        <aside
            className={clsx(
                "h-full flex flex-col bg-surface-strong backdrop-ui transition-all duration-500 ease-[cubic-bezier(0.32,0.72,0,1)] border-r border-line shadow-ui-lg relative overflow-hidden translate-z-0 will-change-transform",
                className
            )}
        >
            <div className="p-6 pb-4 flex items-center gap-4 relative z-10">
                <div className="p-2.5 bg-fill rounded-ui-md border border-line">
                    <Library className="w-6 h-6 text-fg" strokeWidth={2} />
                </div>
                <span className="font-bold text-lg tracking-tight text-fg font-sans">Library</span>
            </div>

            <div className="flex-1 overflow-y-auto px-4 py-4 custom-scrollbar relative z-10">
                {/* We use the existing FileTree logic but wrap it to fit our theme */}
                <div className="text-sm font-medium text-fg selection:bg-fill-active">
                    <FileTree />
                </div>
            </div>

            <div className="p-6 border-t border-line text-[10px] tracking-[0.25em] font-bold text-fg-3 uppercase select-none relative z-10 drop-shadow-xs flex items-center justify-center gap-3">
                <button
                    onClick={onOpenShuffleSettings}
                    className="flex items-center justify-center w-7 h-7 rounded-full bg-fill hover:bg-fill-hover text-fg-2 hover:text-fg transition-all duration-300"
                    aria-label="Shuffle Settings"
                    type="button"
                >
                    <Settings className="w-3.5 h-3.5" strokeWidth={2} />
                </button>
                <span className="text-center">Gallery Joy</span>
            </div>
        </aside>
    );
}
