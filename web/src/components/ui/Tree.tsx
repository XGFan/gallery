import React from "react"
import { cn } from "./cn"
import { Folder, File, FolderOpen } from "lucide-react"

export interface TreeNode {
    title: React.ReactNode
    key: string
    children?: TreeNode[]
    isLeaf?: boolean
}

interface TreeProps {
    treeData: TreeNode[]
    expandedKeys?: React.Key[]
    selectedKeys?: React.Key[]
    onExpand?: (expandedKeys: React.Key[]) => void
    onSelect?: (key: React.Key, node: TreeNode) => void
    className?: string
}

export function Tree({ treeData, expandedKeys = [], selectedKeys = [], onExpand, onSelect, className }: TreeProps) {
    // Convert keys to string for easier comparison
    const expKeys = expandedKeys.map(String)
    const selKeys = selectedKeys.map(String)

    const handleToggle = (key: string) => {
        const newExpanded = expKeys.includes(key)
            ? expKeys.filter((k) => k !== key)
            : [...expKeys, key]
        onExpand?.(newExpanded)
    }

    const renderNode = (node: TreeNode, level: number = 0) => {
        const isExpanded = expKeys.includes(node.key)
        const isSelected = selKeys.includes(node.key)
        const hasChildren = node.children && node.children.length > 0

        return (
            <div key={node.key} className="select-none text-sm text-white/80">
                <div
                    className={cn(
                        "flex items-center py-2 px-2 rounded-lg cursor-pointer transition-colors duration-200",
                        isSelected ? "bg-white/20 text-white font-medium backdrop-blur-sm" : "hover:bg-white/10",
                        "active:scale-[0.98]"
                    )}
                    style={{ paddingLeft: `${level * 1.5 + 0.5}rem` }}
                    onClick={(e) => {
                        e.stopPropagation()
                        // If it's a folder, toggle expand
                        if (!node.isLeaf) {
                            handleToggle(node.key)
                        }
                        // Always fire select
                        onSelect?.(node.key, node)
                    }}
                >
                    <span className="mr-2 shrink-0 opacity-90 drop-shadow-sm">
                        {node.isLeaf ? (
                            <File className="w-5 h-5 text-white/80" strokeWidth={2} />
                        ) : isExpanded ? (
                            <FolderOpen className="w-5 h-5 text-accent" strokeWidth={2} />
                        ) : (
                            <Folder className="w-5 h-5 text-accent/80" strokeWidth={2} />
                        )}

                    </span>
                    <span className="truncate">{node.title}</span>
                </div>
                {hasChildren && isExpanded && (
                    <div className="transform transition-all">
                        {node.children!.map((child) => renderNode(child, level + 1))}
                    </div>
                )}
            </div>
        )
    }

    return (
        <div className={cn("flex flex-col gap-[1px]", className)}>
            {treeData.map(node => renderNode(node))}
        </div>
    )
}
