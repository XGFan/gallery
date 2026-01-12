import axios from "axios";
import { useEffect, useState, useMemo } from "react";
import { useLoaderData, useNavigate } from "react-router-dom";
import { Album, AppCtx } from "./dto";
import { Tree, TreeNode } from "./components/ui/Tree";

function data2Tree(obj: object, parent: { title: string, key: string } | null): TreeNode {
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
  const [tree, setTree] = useState({ key: "", title: "" } as TreeNode);
  const [expanded, setExpanded] = useState<string[]>([]);

  // Compute required keys synchronously based on current album path
  const requiredKeys = useMemo(() => {
    return album.path.parents().map(it => it.path).reverse().concat(album.path.path)
  }, [album.path]);

  // Effective expanded keys = user expanded + required keys (computed synchronously)
  const effectiveExpanded = useMemo(() => {
    const combined = new Set([...expanded, ...requiredKeys])
    return Array.from(combined)
  }, [expanded, requiredKeys]);

  const selected = album.path.path;

  useEffect(() => {
    console.log("fetch tree")
    axios.get(`/api/tree`)
      .then(res => {
        const dataTree = data2Tree(res.data, null);
        setTree(dataTree)
      })
  }, [])

  const navigate = useNavigate();
  if (!tree.title) {
    return <div className="p-4 text-center text-xs text-white/30">Loading...</div>
  }

  return <Tree
    expandedKeys={effectiveExpanded}
    selectedKeys={[selected]}
    onSelect={(k, node) => {
      console.log(k, node);
      if (node.isLeaf) {
        navigate(`/${node.key}?mode=image`)
      } else {
        // If clicking on the currently selected node, just toggle expand/collapse
        if (node.key === selected) {
          if (expanded.includes(node.key)) {
            setExpanded(expanded.filter(key => key !== node.key))
          } else {
            setExpanded([...expanded, node.key])
          }
          return
        }

        // For other non-leaf nodes: ensure it's expanded, then navigate
        if (!expanded.includes(node.key)) {
          setExpanded([...expanded, node.key])
        }
        navigate(`/${node.key}?mode=album`)
      }
    }}
    onExpand={function (e) {
      setExpanded(e.map(k => String(k)))
    }}
    treeData={tree.children || []}
  />
}
