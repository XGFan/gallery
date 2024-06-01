import {useEffect, useState} from "react";
import {Album, AppCtx, calColumns, DEFAULT_PAGE_SIZE} from "./dto.tsx";
import "./viewer.css"
import PhotoAlbum from "react-photo-album";
import InfiniteScroll from "react-infinite-scroll-component";
import Lightbox, {createIcon, IconButton, useLightboxState} from "yet-another-react-lightbox";
import {Fullscreen, Slideshow, Zoom} from "yet-another-react-lightbox/plugins";
import "yet-another-react-lightbox/styles.css";
import {useLoaderData, useNavigate} from "react-router-dom";
import {Button, Col, Dropdown, Modal, Row, Slider} from "antd";
import {AppstoreOutlined, FolderOpenOutlined, PictureOutlined, SettingOutlined, SmileOutlined} from "@ant-design/icons";

const DEFAULT_PLUGINS = [
  Fullscreen,
  Slideshow,
  Zoom
]
const RANDOM_PLUGINS = [Zoom, Fullscreen, Slideshow]

const DEFAULT_ROW_HEIGHT = 500

const GoIcon = createIcon("Go", <path
  d="M 17.92 4.288 a 2.312 2.312 90 0 0 -2.4 -0.568 L 4.2 7.504 a 2.32 2.32 90 0 0 -0.096 4.376 l 4.192 1.6 h 0 a 0.744 0.744 90 0 1 0.424 0.416 l 1.6 4.2 A 2.296 2.296 90 0 0 12.488 19.6 h 0.056 a 2.304 2.304 90 0 0 2.152 -1.6 L 18.48 6.664 A 2.312 2.312 90 0 0 17.92 4.288 Z M 17 6.16 L 13.176 17.504 a 0.704 0.704 90 0 1 -0.672 0.496 a 0.736 0.736 90 0 1 -0.696 -0.464 l -1.6 -4.2 a 2.328 2.328 90 0 0 -1.336 -1.344 l -4.2 -1.6 A 0.72 0.72 90 0 1 4.2 9.696 a 0.704 0.704 90 0 1 0.496 -0.672 L 16.04 5.24 A 0.728 0.728 90 0 1 17 6.16 Z"/>);


const modes = [
  {
    key: 'image',
    icon: <PictureOutlined/>,
    label: "Image"
  },
  {
    key: 'explore',
    icon: <FolderOpenOutlined/>,
    label: "Explore"
  },
  {
    key: 'album',
    icon: <AppstoreOutlined/>,
    label: "Album"
  },
  {
    key: 'random',
    icon: <SmileOutlined/>,
    label: "Random"
  },
  {
    key: 'config',
    icon: <SettingOutlined/>,
    label: "Config"
  },
]

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
  const navigate = useNavigate();
  useEffect(() => {
    localStorage.setItem("row-height", String(rowHeight));
  }, [rowHeight])
  useEffect(() => {
    console.log("full album has changed", fullAlbum)
    window.scrollTo(0, 0)
    if (fullAlbum.mode == "random") {
      setAlbum(fullAlbum)
      setIndex(1)
    } else {
      setAlbum(fullAlbum.subAlbum(DEFAULT_PAGE_SIZE))
    }
  }, [fullAlbum]);

  function fetchNew() {
    console.log("concat new data")
    setAlbum(fullAlbum.subAlbum(album.images.length + DEFAULT_PAGE_SIZE))
  }

  function GoToDirectory() {
    const {currentSlide} = useLightboxState();
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
      }/>
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
        buttons: [<GoToDirectory key="link2album"/>, "close"],
      }}
      render={{
        // buttonPrev: album.mode !== 'random' ? undefined : () => null,
        // buttonNext: album.mode !== 'random' ? undefined : () => null,
        // iconClose: album.mode !== 'random' ? undefined : () => null,
      }}
      on={{
        // click: album.mode !== 'random' ? undefined : function () {
        // },
        exiting: album.mode !== 'random' ? undefined : function () {
          navigate(-1)
        }
      }}
      slideshow={{delay: 1500}}
      controller={{closeOnBackdropClick: album.mode !== 'random'}}
    />
    <div className={'fixed-widgets-rt'}>
      <Dropdown
        menu={{
          inlineIndent: 0,
          onClick: function (e) {
            if (e.key == 'config') {
              setShowConfig(true)
            } else {
              navigate(`/${album.path.path}?mode=${e.key}`)
            }
          },
          items:
            modes.filter(it => it.key != album.mode),
        }}
        trigger={['click']}>
        <Button
          type="text"
          size="large">
          {modes.filter(it => it.key === album.mode).map(it => it.icon)[0]}
        </Button>
      </Dropdown>
    </div>
    <InfiniteScroll dataLength={album.images.length}
                    hasMore={fullAlbum.images.length > album.images.length}
                    loader={<></>}
                    next={fetchNew}>
      <PhotoAlbum
        layout="rows"
        photos={album.mode === 'random' ? [] : album.images}
        targetRowHeight={() => rowHeight}
        spacing={() => 0}
        columns={calColumns}
        onClick={({photo, index}) => {
          switch (album.mode) {
            case 'album':
              navigate(`/${photo.key}?mode=image`)
              break;
            case 'image':
              console.log("open image")
              setIndex(index);
              break;
            case 'explore':
              if (photo.imageType === 'image') {
                setIndex(index);
              } else {
                navigate(`/${photo.key}?mode=explore`)
              }
              break;
            default:
              console.log("unknown operation", album.mode, photo, index)
              break;
          }
        }}

        renderPhoto={({photo, wrapperStyle, renderDefaultPhoto}) => {
          return <div style={{position: "relative", ...wrapperStyle}}>
            {renderDefaultPhoto({wrapped: true})}
            {photo.imageType === 'directory' ? <span className="jg-caption">{photo.name}</span> : <span></span>}
          </div>
        }}
      />
    </InfiniteScroll>
    <div className="fixed-widgets-rb">
      <Button type="text" size="small">{album.images.length}/{fullAlbum.images.length}</Button>
    </div>
    <Modal open={showConfig}
           footer={null}
           title={null}
           closeIcon={null}
           onCancel={() => {
             setShowConfig(false)
           }}
    >
      <Row style={{alignItems: 'center'}}>
        <Col span={4} style={{textAlign: "center"}}>
          Height
        </Col>
        <Col span={16}>
          <Slider
            min={250}
            max={1000}
            onChange={setRowHeight}
            value={rowHeight}
            step={50}
            tooltip={{
              open: false
            }}
          />
        </Col>
        <Col span={4} style={{textAlign: "center"}}>
          {rowHeight}
        </Col>
      </Row>
    </Modal>
  </>
}