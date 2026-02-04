import { memo } from "react";
import { FolderOpen, Play, Video } from "lucide-react";
import { ImgData } from "../dto";

function formatDuration(seconds: number): string {
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    const s = Math.floor(seconds % 60);

    if (h > 0) {
        return `${h}:${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`;
    }
    return `${m}:${s.toString().padStart(2, '0')}`;
}

interface GalleryItemProps {
    item: ImgData;
    size: { width: number; height: number };
    onClick: () => void;
}

export const GalleryItem = memo(function GalleryItem({ item, size, onClick }: GalleryItemProps) {
    const isVideo = item.imageType === 'video';
    const isDisabled = isVideo && item.playable === false;

    const handleClick = () => {
        if (!isDisabled) {
            onClick();
        }
    };

    return (
        <div
            style={{ ...size, position: "relative" }}
            className={`group ${isDisabled ? 'cursor-not-allowed opacity-60' : 'cursor-pointer'}`}
            onClick={handleClick}
            role="button"
            tabIndex={isDisabled ? -1 : 0}
            data-testid={isVideo ? 'gallery-video-item' : undefined}
            aria-label={item.imageType === 'directory' ? `Open folder ${item.name}` : isVideo ? `Play video ${item.name}` : `View image ${item.name}`}
            onKeyDown={(e) => {
                if ((e.key === 'Enter' || e.key === ' ') && !isDisabled) {
                    e.preventDefault();
                    handleClick();
                }
            }}
        >
            {/* Simple container with subtle interactions */}
            <div className="rounded-lg overflow-hidden bg-white/[0.02] hover:bg-white/[0.05] transition-colors duration-200 w-full h-full relative">
                <img
                    src={item.src}
                    alt={item.name}
                    className="w-full h-full object-cover"
                    loading="lazy"
                />

                {/* Video Overlay */}
                {isVideo && (
                    <>
                        <div className="absolute inset-0 flex items-center justify-center bg-black/10 group-hover:bg-black/20 transition-colors">
                            <div className={`p-3 rounded-full bg-black/40 backdrop-blur-sm border border-white/20 text-white shadow-lg ${isDisabled ? 'opacity-50' : 'group-hover:scale-110 transition-transform'}`}>
                                <Play className="w-6 h-6 fill-white" aria-hidden="true" />
                            </div>
                        </div>
                        {item.durationSec && item.durationSec > 0 ? (
                            <div className="absolute bottom-2 right-2 px-1.5 py-0.5 rounded bg-black/50 backdrop-blur-md border border-white/10">
                                <span className="text-[10px] font-medium tracking-wide text-white/90">
                                    {formatDuration(item.durationSec)}
                                </span>
                            </div>
                        ) : (
                            <div className="absolute top-2 right-2 px-1.5 py-0.5 rounded bg-black/50 backdrop-blur-md border border-white/10">
                                <div className="flex items-center gap-1 text-white/90">
                                    <Video className="w-3 h-3" />
                                    <span className="text-[10px] font-medium tracking-wide uppercase">
                                        Video
                                    </span>
                                </div>
                            </div>
                        )}
                    </>
                )}
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
