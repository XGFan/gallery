import { cn } from "./cn"
import React from "react"

interface GlassPanelProps extends React.HTMLAttributes<HTMLDivElement> {
    intensity?: "low" | "medium" | "high"
}

export function GlassPanel({ className, intensity = "medium", ...props }: GlassPanelProps) {
    const intensityClasses = {
        low: "bg-surface",
        medium: "bg-surface",
        high: "bg-surface-strong",
    }

    return (
        <div
            className={cn(
                "rounded-ui-lg border border-line backdrop-ui shadow-ui transition-all duration-300",
                intensityClasses[intensity],
                className
            )}
            {...props}
        />
    )
}
