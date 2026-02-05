import React, { useState, useRef, useEffect, useCallback } from 'react';
import { motion, AnimatePresence, PanInfo } from 'framer-motion';
import { ImgData } from '../dto';
import { X, Volume2, VolumeX, Play, Pause } from 'lucide-react';

export interface VerticalPlayerProps {
  items: ImgData[];
  initialIndex: number;
  onClose: () => void;
}

const SWIPE_THRESHOLD = 100;
const SWIPE_VELOCITY_THRESHOLD = 500;
const WHEEL_THRESHOLD = 30; // Sensitive enough for trackpads
const WHEEL_COOLDOWN = 500; // ms

export default function VerticalPlayer({ items, initialIndex, onClose }: VerticalPlayerProps) {
  const [index, setIndex] = useState(initialIndex);
  const [direction, setDirection] = useState(0); // 1 for next (swipe up), -1 for prev (swipe down)
  const [isMuted, setIsMuted] = useState(false);
  const [isPlaying, setIsPlaying] = useState(true);
  const [showControls, setShowControls] = useState(false);
  const [showMuteHint, setShowMuteHint] = useState(false);
  const [videoError, setVideoError] = useState(false);
  const videoRef = useRef<HTMLVideoElement>(null);
  const lastWheelTime = useRef(0);

  const currentItem = items[index];

  // Lock body scroll
  useEffect(() => {
    const originalStyle = window.getComputedStyle(document.body).overflow;
    document.body.style.overflow = 'hidden';
    return () => {
      document.body.style.overflow = originalStyle;
    };
  }, []);

  // Reset mute hint and error when changing slides
  // autoplay logic
  useEffect(() => {
    // Reset state for new slide
    setShowMuteHint(false);
    setVideoError(false);
    setIsPlaying(true);
    
    // Logic handles in the render/video component usually, but let's do it here via ref
    if (currentItem.imageType === 'video' && videoRef.current) {
        const video = videoRef.current;
        video.muted = isMuted;
        video.currentTime = 0; // Restart
        
        const playPromise = video.play();
        if (playPromise !== undefined) {
            playPromise.catch(error => {
                console.warn("Autoplay failed", error);
                // Fallback to muted
                if (!isMuted) {
                    setIsMuted(true);
                    video.muted = true;
                    video.play().then(() => {
                         setShowMuteHint(true);
                    }).catch(e => console.error("Muted autoplay also failed", e));
                }
            });
        }
    }
  }, [index]); // Dependencies: index changed.

  // Also sync mute state if user toggles it
  useEffect(() => {
      if (videoRef.current) {
          videoRef.current.muted = isMuted;
      }
  }, [isMuted]);

  // Sync play state
  useEffect(() => {
      if (videoRef.current) {
          if (isPlaying) videoRef.current.play().catch(() => {});
          else videoRef.current.pause();
      }
  }, [isPlaying]);


  const paginate = useCallback((newDirection: number) => {
    setDirection(newDirection);
    setIndex((prevIndex) => {
      let nextIndex = prevIndex + newDirection;
      if (nextIndex < 0) nextIndex = items.length - 1;
      if (nextIndex >= items.length) nextIndex = 0;
      return nextIndex;
    });
  }, [items.length]);

  const handleDragEnd = (_: MouseEvent | TouchEvent | PointerEvent, { offset, velocity }: PanInfo) => {
    const swipe = offset.y;
    const swipeVelocity = velocity.y;

    if (swipe < -SWIPE_THRESHOLD || swipeVelocity < -SWIPE_VELOCITY_THRESHOLD) {
      paginate(1); // Swipe up -> Next
    } else if (swipe > SWIPE_THRESHOLD || swipeVelocity > SWIPE_VELOCITY_THRESHOLD) {
      paginate(-1); // Swipe down -> Prev
    }
  };

  const toggleMute = (e: React.MouseEvent) => {
      e.stopPropagation();
      setIsMuted(!isMuted);
      setShowMuteHint(false);
  };
  
  const togglePlay = (e: React.MouseEvent) => {
      e.stopPropagation();
      setIsPlaying(!isPlaying);
  }

  const handleContentClick = () => {
      setShowControls(!showControls);
  };

  const handleWheel = useCallback((e: React.WheelEvent) => {
    // Prevent background scrolling propagation (though overscroll-behavior handles most)
    // e.stopPropagation(); 

    const now = Date.now();
    if (now - lastWheelTime.current < WHEEL_COOLDOWN) return;

    const deltaY = e.deltaY;

    if (Math.abs(deltaY) > WHEEL_THRESHOLD) {
        if (deltaY > 0) {
            paginate(1); // Scroll down -> Next
        } else {
            paginate(-1); // Scroll up -> Prev
        }
        lastWheelTime.current = now;
    }
  }, [paginate]);

  // Variants for slide animation
  const variants = {
    enter: (direction: number) => ({
      y: direction > 0 ? '100%' : '-100%',
      zIndex: 0,
      opacity: 1
    }),
    center: {
      zIndex: 1,
      y: 0,
      opacity: 1
    },
    exit: (direction: number) => ({
      zIndex: 0,
      y: direction < 0 ? '100%' : '-100%',
      opacity: 1 // Keep opacity to avoid seeing background
    })
  };

  return (
    <div 
      className="fixed inset-0 bg-black z-50 overflow-hidden overscroll-contain" 
      data-testid="vertical-player"
      onClick={handleContentClick}
      onWheel={handleWheel}
    >
      <button 
        className="absolute top-4 right-4 z-50 p-2 text-white/80 hover:text-white bg-black/20 rounded-full"
        onClick={(e) => { e.stopPropagation(); onClose(); }}
      >
        <X size={24} />
      </button>

      <AnimatePresence initial={false} custom={direction}>
        <motion.div
          key={index}
          custom={direction}
          variants={variants}
          initial="enter"
          animate="center"
          exit="exit"
          transition={{
            y: { type: "spring", stiffness: 300, damping: 30 },
            opacity: { duration: 0.2 }
          }}
          drag="y"
          dragConstraints={{ top: 0, bottom: 0 }}
          dragElastic={0.2} // Resistance
          onDragEnd={handleDragEnd}
          className="absolute inset-0 flex items-center justify-center w-full h-full"
          data-testid={`slide-${index}`}
          data-key={currentItem.key}
        >
          {currentItem.imageType === 'video' ? (
            videoError ? (
              <div className="w-full h-full flex flex-col items-center justify-center text-white" data-testid="video-fallback">
                 {/* Fallback with poster if available */}
                 {currentItem.src && (
                    <img 
                      src={currentItem.src} 
                      alt={currentItem.name} 
                      className="absolute inset-0 w-full h-full object-contain -z-10 opacity-50"
                    />
                 )}
                 <div className="z-10 bg-black/50 p-4 rounded-lg flex flex-col items-center gap-2">
                    <span className="text-lg font-medium">视频加载失败</span>
                    <span className="text-sm opacity-70">无法播放此视频</span>
                 </div>
              </div>
            ) : (
            <video
              ref={videoRef}
              src={currentItem.videoSrc || currentItem.src} // videoSrc is usually the video file
              poster={currentItem.src} // src is usually the poster/thumbnail in ImgData for videos? Wait, check utils.ts
              className="w-full h-full object-contain max-h-[100dvh]"
              playsInline
              loop
              preload="metadata"
              onError={() => {
                console.error("Video load error", currentItem.videoSrc);
                setVideoError(true);
              }}
              // Muted/Autoplay handled in effect
            />
            )
          ) : (
            <img
              src={currentItem.src}
              alt={currentItem.name}
              className="w-full h-full object-contain max-h-[100dvh]"
              draggable={false} // Prevent native drag
            />
          )}
        </motion.div>
      </AnimatePresence>

      {/* Controls Overlay */}
      {showControls && (
        <div className="absolute bottom-10 left-0 right-0 flex justify-center items-center gap-8 z-40 p-4 bg-gradient-to-t from-black/50 to-transparent">
             <button onClick={toggleMute} className="p-3 bg-white/10 rounded-full backdrop-blur-sm text-white hover:bg-white/20 transition-colors">
                 {isMuted ? <VolumeX /> : <Volume2 />}
             </button>
             <button onClick={togglePlay} className="p-3 bg-white/10 rounded-full backdrop-blur-sm text-white hover:bg-white/20 transition-colors">
                 {isPlaying ? <Pause /> : <Play />}
             </button>
        </div>
      )}

      {/* Mute Hint Toast */}
      {showMuteHint && (
          <div 
            className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 z-50 px-4 py-2 bg-black/60 text-white rounded-lg pointer-events-auto cursor-pointer flex items-center gap-2"
            onClick={toggleMute}
          >
              <VolumeX size={16} />
              <span>点击开声</span>
          </div>
      )}
      
      {/* Index Indicator (optional, useful for debugging/tests) */}
      <div className="absolute top-4 left-4 z-40 text-white/50 text-xs">
          {index + 1} / {items.length}
      </div>
    </div>
  );
}
