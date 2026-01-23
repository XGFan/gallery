import { useEffect, useState } from "react";
import { Album, AppCtx, DEFAULT_PAGE_SIZE, ImgData } from "./dto";
import "./Viewer.css"
import { Gallery } from "react-gallery-grid";
import InfiniteScroll from "react-infinite-scroll-component";
import Lightbox, { createIcon, IconButton, useLightboxState } from "yet-another-react-lightbox";
import { Fullscreen, Slideshow, Zoom } from "yet-another-react-lightbox/plugins";
import "yet-another-react-lightbox/styles.css";
import { useLoaderData, useNavigate } from "react-router-dom";
import { Modal } from "./components/ui/Modal";
import { Slider } from "./components/ui/Slider";
import { GalleryItem } from "./components/GalleryItem";

const DEFAULT_PLUGINS = [
  Fullscreen,
  Slideshow,
  Zoom
]
const RANDOM_PLUGINS = [Fullscreen, Slideshow, Zoom]

const DEFAULT_ROW_HEIGHT = 500

const GoIcon = createIcon("Go", <path
  d="M 17.92 4.288 a 2.312 2.312 90 0 0 -2.4 -0.568 L 4.2 7.504 a 2.32 2.32 90 0 0 -0.096 4.376 l 4.192 1.6 h 0 a 0.744 0.744 90 0 1 0.424 0.416 l 1.6 4.2 A 2.296 2.296 90 0 0 12.488 19.6 h 0.056 a 2.304 2.304 90 0 0 2.152 -1.6 L 18.48 6.664 A 2.312 2.312 90 0 0 17.92 4.288 Z M 17 6.16 L 13.176 17.504 a 0.704 0.704 90 0 1 -0.672 0.496 a 0.736 0.736 90 0 1 -0.696 -0.464 l -1.6 -4.2 a 2.328 2.328 90 0 0 -1.336 -1.344 l -4.2 -1.6 A 0.72 0.72 90 0 1 4.2 9.696 a 0.704 0.704 90 0 1 0.496 -0.672 L 16.04 5.24 A 0.728 0.728 90 0 1 17 6.16 Z" />);



export default function Viewer() {
  const fullAlbum = (useLoaderData() as AppCtx<Album>).data;
  const [index, setIndex] = useState(-1);
  const [rowHeight, setRowHeight] = useState(() => {
    //parse string to number
    const height: number = Number(localStorage.getItem("row-height"));
    console.log(`localstorage: ${height}`)
    if (height == null || isNaN(height) || height < 200 || height > 1000) {
      return DEFAULT_ROW_HEIGHT
    } else {
      return height
    }
  });
  const [album, setAlbum] = useState(fullAlbum.subAlbum(DEFAULT_PAGE_SIZE))
  const [showConfig, setShowConfig] = useState(false)
  const [showCounter, setShowCounter] = useState(true)
  const navigate = useNavigate();
  useEffect(() => {
    localStorage.setItem("row-height", String(rowHeight));
  }, [rowHeight])
  useEffect(() => {
    console.log("full album has changed", fullAlbum)
    window.scrollTo(0, 0)
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
      <IconButton label="Location" icon={GoIcon} onClick={() => {
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
    <Lightbox
      slides={album.mode === 'random' ? fullAlbum.images : album.images}
      index={index}
      open={index >= 0}
      close={() => setIndex(-1)}
      plugins={album.mode === 'random' ? RANDOM_PLUGINS : DEFAULT_PLUGINS}
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
                console.log("open image")
                setIndex(realIndex !== -1 ? realIndex : index);
                break;
              case 'explore':
                if (photo.imageType === 'image') {
                  setIndex(realIndex !== -1 ? realIndex : index);
                } else {
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
        gap={4}
      />
    </InfiniteScroll>
    {/* Bottom center counter */}
    <div className={`fixed bottom-4 left-1/2 -translate-x-1/2 z-50 transition-opacity duration-300 ${showCounter ? 'opacity-100' : 'opacity-0 pointer-events-none'}`}>
      <div className="px-3 py-1.5 bg-black/40 backdrop-blur-md rounded-full border border-white/10 text-white/80 text-sm shadow-lg">
        {album.images.length} / {fullAlbum.images.length}
      </div>
    </div>
    <Modal
      onClose={() => setShowConfig(false)}
      isOpen={showConfig}
      title="Settings"
    >
      <div className="grid grid-cols-[auto_1fr_auto] gap-4 items-center">
        <div className="text-sm font-medium text-white/80">
          Height
        </div>
        <div>
          <Slider
            min={250}
            max={1000}
            onChange={setRowHeight}
            value={rowHeight}
            step={50}
          />
        </div>
        <div className="text-sm font-mono text-white/60 w-10 text-right">
          {rowHeight}
        </div>
      </div>
    </Modal>
  </>
}
