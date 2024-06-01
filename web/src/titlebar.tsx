import {useLoaderData, useNavigate} from "react-router-dom";
import {Album, AppCtx, Mode, Path} from "./dto.tsx";
import {useEffect, useState} from "react";
import {Button, Dropdown, Typography} from "antd";
import {HomeOutlined} from "@ant-design/icons";
import {MenuItemType} from "antd/lib/menu/hooks/useItems";


class BarData {
  mode: Mode
  path: Path

  constructor(album: Album) {
    this.mode = album.mode
    this.path = album.path
  }
}

export default function TitleBar() {
  const initAlbum = (useLoaderData() as AppCtx<Album>).data;
  const [barData, setBarData] = useState(new BarData(initAlbum))
  const navigate = useNavigate();
  useEffect(() => {
    setBarData(new BarData(initAlbum))
  }, [initAlbum]);

  let items: MenuItemType[]
  let title: string
  const parents = barData.path.parents();
  if (parents.length == 0) {
    items = []
    title = 'Gallery'
  } else {
    title = barData.path.name
    items = parents
      .slice(0, parents.length - 1)
      .map((value: Path): MenuItemType => {
        return {
          label: value.name,
          key: value.path
        }
      })
      .concat({
        label: <HomeOutlined/>,
        key: '',
      })
  }


  return <div className={'fixed-widgets-mt'}>
    <Dropdown
      menu={{
        inlineIndent: 0,
        onClick: function (e) {
          navigate(`/${e.key}?mode=${barData.mode}`)
        },
        items: items
      }}
    >
      <Button
        style={{
          maxWidth: '100%'
        }}
        type="text"
        size="large">
        <Typography.Text ellipsis={true}>{title}</Typography.Text>
      </Button>
    </Dropdown>
  </div>
}