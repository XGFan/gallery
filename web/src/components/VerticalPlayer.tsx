import React, { useState, useRef, useEffect, useCallback } from 'react';
import { motion, AnimatePresence, PanInfo } from 'framer-motion';
import { ImgData } from '../dto';
import { X, Volume2, VolumeX, Play, Pause } from 'lucide-react';

const formatTime = (time: number) => {
  if (!time || isNaN(time)) return "0:00";
  const m = Math.floor(time / 60);
  const s = Math.floor(time % 60);
  return `${m}:${s.toString().padStart(2, '0')}`;
};

interface VideoProgressBarProps {
  videoRef: React.RefObject<HTMLVideoElement>;
  progressCache: React.MutableRefObject<Record<string, number>>;
  videoKey: string;
}

function VideoProgressBar({ videoRef, progressCache, videoKey }: VideoProgressBarProps) {
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [isDragging, setIsDragging] = useState(false);
  const progressBarRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;

    if (video.readyState >= 1) {
      setDuration(video.duration);
    }

    const cachedTime = progressCache.current[videoKey] || 0;
    setCurrentTime(cachedTime);

    const handleTimeUpdate = () => {
      if (!isDragging) {
        setCurrentTime(video.currentTime);
        progressCache.current[videoKey] = video.currentTime;
      }
    };

    const handleLoadedMetadata = () => {
      setDuration(video.duration);
    };

    video.addEventListener('timeupdate', handleTimeUpdate);
    video.addEventListener('loadedmetadata', handleLoadedMetadata);
    return () => {
      video.removeEventListener('timeupdate', handleTimeUpdate);
      video.removeEventListener('loadedmetadata', handleLoadedMetadata);
    };
  }, [isDragging, videoRef, progressCache, videoKey]);

  const seekTo = (time: number) => {
    setCurrentTime(time);
    if (videoRef.current) {
      videoRef.current.currentTime = time;
      progressCache.current[videoKey] = time;
    }
  };

  const handlePointerSeek = (e: React.PointerEvent<HTMLDivElement> | React.MouseEvent<HTMLDivElement>) => {
    if (!progressBarRef.current) return;
    const rect = progressBarRef.current.getBoundingClientRect();
    const x = Math.max(0, Math.min(e.clientX - rect.left, rect.width));
    const percentage = x / rect.width;
    return percentage * duration;
  };

  if (duration <= 0) return null;

  return (
    <div className="w-full max-w-md pointer-events-auto flex flex-col items-center">
      <div className="flex justify-between w-full text-xs text-white/80 mb-2 font-mono drop-shadow-md">
         <span>{formatTime(currentTime)}</span>
         <span>{formatTime(duration)}</span>
      </div>
      <div
        ref={progressBarRef}
        className="w-full h-6 flex items-center cursor-pointer group"
        role="slider"
        tabIndex={0}
        aria-valuenow={duration > 0 ? (currentTime / duration) * 100 : 0}
        aria-valuemin={0}
        aria-valuemax={100}
        onKeyDown={(e) => {
          if (e.key === 'ArrowRight') {
            seekTo(Math.min(duration, currentTime + 5));
          } else if (e.key === 'ArrowLeft') {
            seekTo(Math.max(0, currentTime - 5));
          }
        }}
        onClick={(e) => {
          e.stopPropagation();
          const newTime = handlePointerSeek(e);
          if (newTime !== undefined) seekTo(newTime);
        }}
        onPointerDown={(e) => {
          e.stopPropagation();
          e.currentTarget.setPointerCapture(e.pointerId);
          setIsDragging(true);
          const newTime = handlePointerSeek(e);
          if (newTime !== undefined) setCurrentTime(newTime);
        }}
        onPointerMove={(e) => {
          if (isDragging) {
            e.stopPropagation();
            const newTime = handlePointerSeek(e);
            if (newTime !== undefined) setCurrentTime(newTime);
          }
        }}
        onPointerUp={(e) => {
          e.stopPropagation();
          e.currentTarget.releasePointerCapture(e.pointerId);
          setIsDragging(false);
          const newTime = handlePointerSeek(e);
          if (newTime !== undefined) seekTo(newTime);
        }}
        onPointerCancel={(e) => {
          e.stopPropagation();
          e.currentTarget.releasePointerCapture(e.pointerId);
          setIsDragging(false);
        }}
      >
        <div className="w-full h-1.5 bg-white/30 rounded-full relative group-hover:h-2 transition-all shadow-sm pointer-events-none">
          <div
            className="absolute left-0 top-0 bottom-0 bg-white rounded-full"
            style={{ width: `${(currentTime / duration) * 100}%` }}
          >
            <div className="absolute right-0 top-1/2 -translate-y-1/2 w-4 h-4 bg-white rounded-full opacity-0 group-hover:opacity-100 transition-opacity translate-x-1/2 shadow-md" />
          </div>
        </div>
      </div>
    </div>
  );
}

interface ThinProgressBarProps {
  videoRef: React.RefObject<HTMLVideoElement>;
}

function ThinProgressBar({ videoRef }: ThinProgressBarProps) {
  const [progress, setProgress] = useState(0);

  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;

    const handleTimeUpdate = () => {
      if (video.duration > 0) {
        setProgress((video.currentTime / video.duration) * 100);
      }
    };

    video.addEventListener('timeupdate', handleTimeUpdate);
    return () => {
      video.removeEventListener('timeupdate', handleTimeUpdate);
    };
  }, [videoRef]);

  if (progress <= 0) return null;

  return (
    <div className="absolute bottom-0 left-0 right-0 h-[2px] bg-white/20 z-40 pointer-events-none">
      <div
        className="h-full bg-white/70"
        style={{ width: `${progress}%` }}
      />
    </div>
  );
}

export interface VerticalPlayerProps {
  items: ImgData[];
  initialIndex: number;
  onClose: () => void;
}

const SWIPE_THRESHOLD = 100;
const SWIPE_VELOCITY_THRESHOLD = 500;
const WHEEL_THRESHOLD = 30;
const WHEEL_COOLDOWN = 500;

export default function VerticalPlayer({ items, initialIndex, onClose }: VerticalPlayerProps) {
  const [index, setIndex] = useState(initialIndex);
  const [direction, setDirection] = useState(0);
  const [isMuted, setIsMuted] = useState(false);
  const [isPlaying, setIsPlaying] = useState(true);
  const [showControls, setShowControls] = useState(false);
  const [showMuteHint, setShowMuteHint] = useState(false);
  const [videoError, setVideoError] = useState(false);
  const videoRef = useRef<HTMLVideoElement>(null);
  const lastWheelTime = useRef(0);
  const progressCache = useRef<Record<string, number>>({});
  const isMutedRef = useRef(isMuted);

  const currentItem = items[index];

  useEffect(() => {
    isMutedRef.current = isMuted;
  }, [isMuted]);

  useEffect(() => {
    const originalStyle = window.getComputedStyle(document.body).overflow;
    document.body.style.overflow = 'hidden';
    return () => {
      document.body.style.overflow = originalStyle;
    };
  }, []);

  useEffect(() => {
    setShowMuteHint(false);
    setVideoError(false);
    setIsPlaying(true);

    if (currentItem.imageType === 'video' && videoRef.current) {
        const video = videoRef.current;
        video.muted = isMutedRef.current;

        const cachedTime = progressCache.current[currentItem.key] || 0;
        video.currentTime = cachedTime;

        const playPromise = video.play();
        if (playPromise !== undefined) {
            playPromise.catch(error => {
                console.warn("Autoplay failed", error);
                if (!isMutedRef.current) {
                    setIsMuted(true);
                    video.muted = true;
                    video.play().then(() => {
                         setShowMuteHint(true);
                    }).catch(e => console.error("Muted autoplay also failed", e));
                }
            });
        }
    }
  }, [currentItem.imageType, currentItem.key]);

  useEffect(() => {
      if (videoRef.current) {
          videoRef.current.muted = isMuted;
      }
  }, [isMuted]);

  useEffect(() => {
      if (videoRef.current) {
          if (isPlaying) videoRef.current.play().catch(() => {});
          else videoRef.current.pause();
      }
  }, [isPlaying]);

  useEffect(() => {
      if (currentItem.imageType !== 'video') {
          videoRef.current = null;
      }
  }, [currentItem.imageType]);

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
      paginate(1);
    } else if (swipe > SWIPE_THRESHOLD || swipeVelocity > SWIPE_VELOCITY_THRESHOLD) {
      paginate(-1);
    }
  };

  const handleToggle = (e: React.MouseEvent | React.KeyboardEvent, action: 'mute' | 'play') => {
      e.stopPropagation();
      if (action === 'mute') {
          setIsMuted(prev => !prev);
          setShowMuteHint(false);
      } else {
          setIsPlaying(prev => !prev);
      }
  };

  const handleContentClick = () => {
      setShowControls(!showControls);
  };

  const handleWheel = useCallback((e: React.WheelEvent) => {
    const now = Date.now();
    if (now - lastWheelTime.current < WHEEL_COOLDOWN) return;

    const deltaY = e.deltaY;

    if (Math.abs(deltaY) > WHEEL_THRESHOLD) {
        if (deltaY > 0) {
            paginate(1);
        } else {
            paginate(-1);
        }
        lastWheelTime.current = now;
    }
  }, [paginate]);

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
      opacity: 1
    })
  };

  return (
    <div
      className="fixed inset-0 bg-black z-50 overflow-hidden overscroll-contain"
      data-testid="vertical-player"
      onClick={handleContentClick}
      onWheel={handleWheel}
      role="button"
      tabIndex={-1}
      onKeyDown={(e) => {
        if (e.key === 'Enter' || e.key === ' ') handleContentClick();
      }}
    >
      <button
        type="button"
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
          dragElastic={0.2}
          onDragEnd={handleDragEnd}
          className="absolute inset-0 flex items-center justify-center w-full h-full"
          data-testid={`slide-${index}`}
          data-key={currentItem.key}
        >
          {currentItem.imageType === 'video' ? (
            videoError ? (
              <div className="w-full h-full flex flex-col items-center justify-center text-white" data-testid="video-fallback">
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
              ref={(el) => {
                if (el) {
                  videoRef.current = el;
                }
              }}
              src={currentItem.videoSrc || currentItem.src}
              poster={currentItem.src}
              className="w-full h-full object-contain max-h-[100dvh]"
              playsInline
              loop
              preload="metadata"
              onError={() => {
                console.error("Video load error", currentItem.videoSrc);
                setVideoError(true);
              }}
            />
            )
          ) : (
            <img
              src={currentItem.src}
              alt={currentItem.name}
              className="w-full h-full object-contain max-h-[100dvh]"
              draggable={false}
            />
          )}
        </motion.div>
      </AnimatePresence>

      <AnimatePresence>
        {showControls && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="absolute bottom-0 left-0 right-0 flex flex-col items-center gap-6 z-40 p-6 pb-12 bg-gradient-to-t from-black/80 via-black/40 to-transparent pointer-events-none"
          >
            {currentItem.imageType === 'video' && (
              <VideoProgressBar
                 videoRef={videoRef}
                 progressCache={progressCache}
                 videoKey={currentItem.key}
              />
            )}

            <div className="flex justify-center items-center gap-12 pointer-events-auto mt-2">
                 <button type="button" onClick={(e) => handleToggle(e, 'mute')} className="p-4 bg-white/10 rounded-full backdrop-blur-md text-white hover:bg-white/20 transition-colors shadow-lg">
                     {isMuted ? <VolumeX size={28} /> : <Volume2 size={28} />}
                 </button>
                 <button type="button" onClick={(e) => handleToggle(e, 'play')} className="p-4 bg-white/10 rounded-full backdrop-blur-md text-white hover:bg-white/20 transition-colors shadow-lg">
                     {isPlaying ? <Pause size={28} /> : <Play size={28} />}
                 </button>
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      {!showControls && currentItem.imageType === 'video' && (
        <ThinProgressBar videoRef={videoRef} />
      )}

      {showMuteHint && (
          <div
            className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 z-50 px-4 py-2 bg-black/60 text-white rounded-lg pointer-events-auto cursor-pointer flex items-center gap-2"
            onClick={(e) => handleToggle(e, 'mute')}
            onKeyDown={(e) => e.key === 'Enter' && handleToggle(e, 'mute')}
            role="button"
            tabIndex={0}
          >
              <VolumeX size={16} />
              <span>点击开声</span>
          </div>
      )}

      <div className="absolute top-4 left-4 z-40 text-white/50 text-xs">
          {index + 1} / {items.length}
      </div>
    </div>
  );
}
