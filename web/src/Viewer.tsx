import { useEffect, useState, useMemo, useRef, useCallback } from "react";
import { Album, AppCtx, DEFAULT_PAGE_SIZE, ImgData, getMimeType } from "./dto";
import "./Viewer.css"
import { Gallery } from "react-gallery-grid";
import InfiniteScroll from "react-infinite-scroll-component";
import Lightbox, { createIcon, IconButton, useLightboxState } from "yet-another-react-lightbox";
import { Fullscreen, Slideshow, Zoom } from "yet-another-react-lightbox/plugins";
import Video from "yet-another-react-lightbox/plugins/video";
import "yet-another-react-lightbox/styles.css";
import { useLoaderData, useNavigate } from "react-router-dom";
import { Modal } from "./components/ui/Modal";
import { Slider } from "./components/ui/Slider";
import { GalleryItem } from "./components/GalleryItem";
import VerticalPlayer from "./components/VerticalPlayer";
import { buildSwipeSequence, getMixedMode } from "./utils";
import { usePinchZoom, clamp } from "./hooks/usePinchZoom";
import { useIsMobile } from "./hooks/useIsMobile";
import { useScrollIntent } from "./hooks/useScrollIntent";
import { averageAspect, calColumns, columnsToRowHeight, getColumnLimits } from "./gridLayout";

const DEFAULT_PLUGINS = [
  Fullscreen,
  Slideshow,
  Zoom,
  Video
]
const RANDOM_PLUGINS = [Fullscreen, Slideshow, Zoom, Video]

const DEFAULT_VIEWPORT_WIDTH = 1280

const GoIcon = createIcon("Go", <path
  d="M 17.92 4.288 a 2.312 2.312 90 0 0 -2.4 -0.568 L 4.2 7.504 a 2.32 2.32 90 0 0 -0.096 4.376 l 4.192 1.6 h 0 a 0.744 0.744 90 0 1 0.424 0.416 l 1.6 4.2 A 2.296 2.296 90 0 0 12.488 19.6 h 0.056 a 2.304 2.304 90 0 0 2.152 -1.6 L 18.48 6.664 A 2.312 2.312 90 0 0 17.92 4.288 Z M 17 6.16 L 13.176 17.504 a 0.704 0.704 90 0 1 -0.672 0.496 a 0.736 0.736 90 0 1 -0.696 -0.464 l -1.6 -4.2 a 2.328 2.328 90 0 0 -1.336 -1.344 l -4.2 -1.6 A 0.72 0.72 90 0 1 4.2 9.696 a 0.704 0.704 90 0 1 0.496 -0.672 L 16.04 5.24 A 0.728 0.728 90 0 1 17 6.16 Z" />);



export default function Viewer() {
  const fullAlbum = (useLoaderData() as AppCtx<Album>).data;
  const [index, setIndex] = useState(-1);
  const [activePlayer, setActivePlayer] = useState<'vertical' | 'lightbox' | null>(null);
  const [entryKey, setEntryKey] = useState<string | null>(null);
  const [columns, setColumns] = useState(() => {
    const saved = Number(localStorage.getItem("gallery-columns"));
    const fallback = calColumns(typeof window !== "undefined" ? window.innerWidth : DEFAULT_VIEWPORT_WIDTH);
    // Cap at a sane upper bound so a corrupted value can't persist absurd counts;
    // the real per-viewport limit is applied via effectiveColumns below.
    return Number.isFinite(saved) && saved >= 1 ? Math.min(Math.round(saved), 64) : fallback;
  });
  const [containerWidth, setContainerWidth] = useState(() =>
    typeof window !== "undefined" ? window.innerWidth : DEFAULT_VIEWPORT_WIDTH
  );
  const galleryRef = useRef<HTMLDivElement>(null);
  const [album, setAlbum] = useState(fullAlbum.subAlbum(DEFAULT_PAGE_SIZE))
  const [showConfig, setShowConfig] = useState(false)
  const [showCounter, setShowCounter] = useState(true)
  const isMobile = useIsMobile();
  const scroll = useScrollIntent();
  // Mobile: the counter is mutually exclusive with the bottom nav bar — it only
  // shows while actively scrolling down through the wall (loading progress), and
  // hides on scroll-up / idle / at-top. Desktop keeps the legacy behaviour
  // (show on any scroll, hide after 3s).
  const counterVisible = isMobile ? (!scroll.atTop && scroll.direction === "down") : showCounter;
  const navigate = useNavigate();

  const slides = useMemo(() => {
    const source = album.mode === 'random' ? fullAlbum.images : album.images;
    return source.map(item => {
      if (item.imageType === 'video' && item.playable !== false) {
        return {
          type: "video" as const,
          poster: item.src,
          width: item.width,
          height: item.height,
          sources: [
            {
              src: item.videoSrc!,
              type: getMimeType(item.videoSrc!) || ""
            }
          ]
        }
      }
      return item;
    })
  }, [album.mode, fullAlbum.images, album.images]);

  const verticalPlayerData = useMemo(() => {
    if (activePlayer === 'vertical' && entryKey) {
      const mediaItems = album.images.filter(item => item.imageType !== 'directory');
      if (!mediaItems.length) {
        return null;
      }
      return buildSwipeSequence(mediaItems, entryKey, getMixedMode());
    }
    return null;
  }, [activePlayer, entryKey, album.images]);

  // Column-driven sizing (avp-style): `columns` is the source of truth; the
  // justified grid gets a target row height derived from columns + container
  // width + the items' average aspect ratio, so each step is a clean change.
  const avgAspect = useMemo(() => averageAspect(album.images), [album.images]);
  const columnLimits = useMemo(() => getColumnLimits(containerWidth), [containerWidth]);
  const effectiveColumns = clamp(columns, columnLimits.min, columnLimits.max);
  const rowHeight = useMemo(
    () => columnsToRowHeight(containerWidth, effectiveColumns, avgAspect),
    [containerWidth, effectiveColumns, avgAspect]
  );

  useEffect(() => {
    localStorage.setItem("gallery-columns", String(columns));
  }, [columns])

  // Track the gallery container width so the column count maps to real pixels.
  // The measured wrapper and react-gallery-grid's own root both span 100% with
  // no padding/border, so this width equals the width the grid packs against;
  // keep them in sync if either gains spacing.
  useEffect(() => {
    const el = galleryRef.current;
    if (!el) return;
    const update = () => setContainerWidth(el.clientWidth || window.innerWidth);
    update();
    if (typeof ResizeObserver === "undefined") {
      window.addEventListener("resize", update);
      return () => window.removeEventListener("resize", update);
    }
    const observer = new ResizeObserver(update);
    observer.observe(el);
    return () => observer.disconnect();
  }, [fullAlbum]);

  // Keep the latest column limits reachable from the stable zoom handler.
  const columnLimitsRef = useRef(columnLimits);
  useEffect(() => { columnLimitsRef.current = columnLimits; }, [columnLimits]);

  // Pinch (touch) or ctrl/⌘ + wheel (trackpad) steps the column count.
  // Zoom in (spread / wheel up) => fewer columns => bigger images.
  const handleZoom = useCallback((direction: 1 | -1) => {
    setColumns((current) => {
      const { min, max } = columnLimitsRef.current;
      return clamp(direction > 0 ? current - 1 : current + 1, min, max);
    });
  }, []);

  // Disabled while an overlay is open so the lightbox/player owns its own zoom
  // gestures instead of resizing the wall behind it.
  const overlayOpen = activePlayer !== null || (album.mode === 'random' && index >= 0);
  usePinchZoom({ onZoom: handleZoom, enabled: !overlayOpen });
  useEffect(() => {
    console.log("full album has changed", fullAlbum)
    window.scrollTo(0, 0)
    setActivePlayer(null)
    setEntryKey(null)
    if (fullAlbum.mode == "random") {
      setAlbum(fullAlbum.subAlbum(0))
      setIndex(0)
    } else {
      setAlbum(fullAlbum.subAlbum(DEFAULT_PAGE_SIZE))
    }
  }, [fullAlbum]);

  // Auto-hide counter after 3 seconds of no scrolling
  useEffect(() => {
    let timer: ReturnType<typeof setTimeout>;
    const handleScroll = () => {
      setShowCounter(true);
      clearTimeout(timer);
      timer = setTimeout(() => setShowCounter(false), 3000);
    };

    // Show initially, then hide after 3 seconds
    timer = setTimeout(() => setShowCounter(false), 3000);

    window.addEventListener('scroll', handleScroll);
    return () => {
      window.removeEventListener('scroll', handleScroll);
      clearTimeout(timer);
    };
  }, [fullAlbum]);

  function fetchNew() {
    console.log("concat new data")
    setAlbum(fullAlbum.subAlbum(album.images.length + DEFAULT_PAGE_SIZE))
  }

  function GoToDirectory() {
    const { currentSlide } = useLightboxState();
    return (
      <IconButton label="Photo gallery" icon={GoIcon} onClick={() => {
        if (currentSlide) {
          // eslint-disable-next-line
          const key: string = (currentSlide as any).key
          const index = key.lastIndexOf('/');
          setIndex(-1)
          navigate(`/${key.substring(0, index)}?mode=explore`)
        }
      }
      } />
    );
  }



  return <>
    {verticalPlayerData && (
      <VerticalPlayer
        items={verticalPlayerData.sequence}
        initialIndex={verticalPlayerData.initialIndex}
        onClose={() => {
          setIndex(-1)
          setActivePlayer(null)
          setEntryKey(null)
        }}
      />
    )}
    <Lightbox
      slides={slides}
      index={index}
      open={album.mode === 'random' ? index >= 0 : index >= 0 && activePlayer === 'lightbox'}
      close={() => {
        setIndex(-1)
        setActivePlayer(null)
        setEntryKey(null)
      }}
      plugins={album.mode === 'random' ? RANDOM_PLUGINS : DEFAULT_PLUGINS}
      video={{ controls: true, playsInline: true, autoPlay: false }}
      toolbar={{
        buttons: [<GoToDirectory key="link2album" />, "close"],
      }}
      render={{
        buttonZoom: () => null,
      }}
      on={{
        exiting: album.mode !== 'random' ? undefined : function () {
          if (document.fullscreenElement) {
            document.exitFullscreen?.().catch(() => { });
          }
          navigate(-1)
        }
      }}
      slideshow={{ delay: 1500 }}
      controller={{ closeOnBackdropClick: album.mode !== 'random' }}
    />
    {/* Mode switcher removed - moved to TopBar */}
    <InfiniteScroll dataLength={album.images.length}
      hasMore={fullAlbum.images.length > album.images.length}
      loader={<div className="text-white/50 text-center py-4">Loading more...</div>}
      scrollThreshold={0.9}
      className="w-full"
      next={fetchNew}>
      <div ref={galleryRef} className="w-full">
      <Gallery
        items={album.images}
        itemRenderer={({ item, size, index }) => {
          const handleClick = () => {
            const photo = item as ImgData;
            const realIndex = album.images.findIndex(img => img.key === photo.key);
            console.log(`Click item: ${photo.name}, Render Index: ${index}, Real Index: ${realIndex}`);

            switch (album.mode) {
              case 'album':
                navigate(`/${photo.key}?mode=image`)
                break;
              case 'image':
                if (photo.imageType === 'video') {
                  setActivePlayer('vertical')
                  setEntryKey(photo.key)
                } else {
                  setActivePlayer('lightbox')
                  setEntryKey(null)
                }
                setIndex(realIndex !== -1 ? realIndex : index);
                break;
              case 'explore':
                if (photo.imageType === 'image') {
                  setActivePlayer('lightbox')
                  setEntryKey(null)
                  setIndex(realIndex !== -1 ? realIndex : index);
                } else if (photo.imageType === 'video' && photo.playable !== false) {
                  setActivePlayer('vertical')
                  setEntryKey(photo.key)
                  setIndex(realIndex !== -1 ? realIndex : index);
                } else {
                  setActivePlayer(null)
                  setEntryKey(null)
                  navigate(`/${photo.key}?mode=explore`)
                }
                break;
              default:
                console.log("unknown operation", album.mode, photo, index)
                break;
            }
          };

          return (
            <GalleryItem
              item={item as ImgData}
              size={size}
              onClick={handleClick}
            />
          );
        }}
        rowHeightRange={{ min: rowHeight * 0.7, max: rowHeight * 1.3 }}
        maxColumns={effectiveColumns}
        gap={4}
      />
      </div>
    </InfiniteScroll>
    <button
      type="button"
      onClick={() => setShowConfig(true)}
      className={`fixed counter-safe z-50 transition-opacity duration-300 ${counterVisible ? 'opacity-100' : 'opacity-0 pointer-events-none'}`}
      aria-label="Open settings"
    >
      <div className="px-3 py-1.5 bg-black/40 backdrop-blur-md rounded-full border border-white/10 text-white/80 text-sm shadow-lg hover:bg-black/50">
        {album.images.length} / {fullAlbum.images.length}
      </div>
    </button>
    <Modal
      onClose={() => setShowConfig(false)}
      isOpen={showConfig}
      title="Settings"
    >
      <div className="grid grid-cols-[auto_1fr_auto] gap-4 items-center">
        <div className="text-sm font-medium text-white/80">
          Columns
        </div>
        <div>
          <Slider
            min={columnLimits.min}
            max={columnLimits.max}
            onChange={setColumns}
            value={effectiveColumns}
            step={1}
          />
        </div>
        <div className="text-sm font-mono text-white/60 w-10 text-right">
          {effectiveColumns}
        </div>
      </div>
    </Modal>
  </>
}
