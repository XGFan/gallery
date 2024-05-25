import {useState} from "react";
import {Button, Drawer} from "antd";
import {ControlOutlined} from "@ant-design/icons";
import './sidebar.css'
import FileTree from "./file-tree.tsx";

export default function Sidebar() {
  const [isDrawerVisible, setIsDrawerVisible] = useState(false);
  const showDrawer = () => {
    setIsDrawerVisible(true);
  };
  const onClose = () => {
    setIsDrawerVisible(false);
  };

  return (
    <div>
      <div className="fixed-widgets-lt" hidden={isDrawerVisible} onClick={showDrawer}>
        <Button type="text" size="large">
          <ControlOutlined style={{fontSize: '1.5rem'}}/>
        </Button>
      </div>
      <Drawer
        rootClassName={'saio-sidebar'}
        forceRender={true}
        placement="left"
        closable={false}
        onClose={onClose}
        open={isDrawerVisible}
      >
        <FileTree/>
      </Drawer>
    </div>
  );
}