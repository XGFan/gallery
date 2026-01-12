import { memo } from "react";
import { FolderOpen } from "lucide-react";
import { ImgData } from "../dto";

interface GalleryItemProps {
    item: ImgData;
    size: { width: number; height: number };
    onClick: () => void;
}

export const GalleryItem = memo(function GalleryItem({ item, size, onClick }: GalleryItemProps) {
    return (
        <div
            style={{ ...size, position: "relative" }}
            className="group cursor-pointer"
            onClick={onClick}
            role="button"
            tabIndex={0}
            aria-label={item.imageType === 'directory' ? `Open folder ${item.name}` : `View image ${item.name}`}
            onKeyDown={(e) => {
                if (e.key === 'Enter' || e.key === ' ') {
                    e.preventDefault();
                    onClick();
                }
            }}
        >
            {/* Simple container with subtle interactions */}
            <div className="rounded-lg overflow-hidden bg-white/[0.02] hover:bg-white/[0.05] transition-colors duration-200 w-full h-full">
                <img
                    src={item.src}
                    alt={item.name}
                    className="w-full h-full object-cover"
                    loading="lazy"
                />
            </div>

            {/* Directory Overlay */}
            {item.imageType === 'directory' && (
                <div className="absolute inset-x-0 bottom-0 p-2 bg-black/60 backdrop-blur-sm pointer-events-none">
                    <div className="flex items-center gap-1.5 text-white/90">
                        <FolderOpen className="w-3.5 h-3.5" aria-hidden="true" />
                        <span className="text-xs font-medium truncate leading-tight">{item.name}</span>
                    </div>
                </div>
            )}
        </div>
    );
});
