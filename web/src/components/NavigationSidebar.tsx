import clsx from "clsx";
import FileTree from "../FileTree";
import { Library } from "lucide-react";

interface SidebarProps {
    className?: string;
}

export default function NavigationSidebar({ className }: SidebarProps) {
    return (
        <aside
            className={clsx(
                "h-full flex flex-col bg-glass-liquid backdrop-blur-lg transition-all duration-500 ease-[cubic-bezier(0.32,0.72,0,1)] border-r border-white/20 shadow-[4px_0_24px_-4px_rgba(0,0,0,0.2)] relative overflow-hidden translate-z-0 will-change-transform",
                className
            )}
        >
            {/* Gloss gradient overlay for liquid feel */}
            <div className="absolute inset-0 bg-gradient-to-b from-white/10 to-transparent pointer-events-none" />

            {/* Ambient light glow */}
            <div className="absolute top-0 left-0 w-full h-[500px] bg-gradient-to-b from-white/10 via-transparent to-transparent pointer-events-none opacity-50" />

            <div className="p-6 pb-4 flex items-center gap-4 relative z-10">
                <div className="p-2.5 bg-gradient-to-br from-white/20 to-white/5 rounded-xl shadow-inner border border-white/20 ring-1 ring-white/10 backdrop-blur-md">
                    <Library className="w-6 h-6 text-white" strokeWidth={2} />
                </div>
                <span className="font-bold text-lg tracking-tight text-white drop-shadow-glow font-sans">Library</span>
            </div>

            <div className="flex-1 overflow-y-auto px-4 py-4 custom-scrollbar relative z-10">
                {/* We use the existing FileTree logic but wrap it to fit our theme */}
                <div className="text-sm font-medium text-white/80 selection:bg-white/30">
                    <FileTree />
                </div>
            </div>

            <div className="p-6 border-t border-white/10 text-[10px] tracking-[0.25em] font-bold text-center text-white/40 uppercase select-none relative z-10 drop-shadow-sm">
                Gallery Joy
            </div>
        </aside>
    );
}
