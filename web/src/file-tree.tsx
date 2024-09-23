import axios from "axios";
import React, {useEffect, useState} from "react";
import {DataNode} from "rc-tree/lib/interface";
import {useLoaderData, useNavigate} from "react-router-dom";
import {Album, AppCtx} from "./dto.tsx";
import DirectoryTree from "antd/es/tree/DirectoryTree";

function data2Tree(obj: object, parent: { title: string, key: string } | null): DataNode {
  const p = parent ?? {
    title: '/',
    key: ''
  }
  return {
    title: p.title,
    key: p.key,
    children: Object.entries(obj)
      .map(([k, v]) => {
        if (v == null || Object.keys(v as object).length === 0) {
          return {
            title: k,
            key: p.key === '' ? encodeURIComponent(k) : (p.key + '/' + encodeURIComponent(k)),
            isLeaf: true
          }
        } else {
          return data2Tree(v, {
            title: k,
            key: p.key === '' ? encodeURIComponent(k) : (p.key + '/' + encodeURIComponent(k))
          })
        }
      })
  }
}

export default function FileTree() {
  const album = (useLoaderData() as AppCtx<Album>).data;
  const [tree, setTree] = useState({key: ""} as DataNode);
  const [expanded, setExpanded] = useState([] as React.Key[]);
  const [selected, setSelected] = useState('');

  function updateTree(a: Album) {
    setExpanded(a.path.parents().map(it => it.path).reverse().concat(a.path.path))
    setSelected(a.path.path)
  }

  useEffect(() => {
    console.log("fetch tree")
    axios.get(`/api/tree`)
      .then(res => {
        const dataTree = data2Tree(res.data, null);
        setTree(dataTree)
      })
  }, [])
  useEffect(() => {
    updateTree(album)
  }, [tree, album]);
  const navigate = useNavigate();
  return <DirectoryTree
    showLine
    autoExpandParent
    multiple={false}
    blockNode={true}
    expandedKeys={expanded}
    selectedKeys={[selected]}
    onSelect={(k, info) => {
      console.log(k, info);
      if (info.node.isLeaf) {
        navigate(`/${info.node.key}?mode=image`)
      } else {
        navigate(`/${info.node.key}?mode=explore`)
      }
    }}
    onExpand={function (e) {
      setExpanded(e)
    }}
    treeData={[tree]}
  />
}
