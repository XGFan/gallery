import { cn } from "./cn"
import React from "react"

interface GlassPanelProps extends React.HTMLAttributes<HTMLDivElement> {
    intensity?: "low" | "medium" | "high"
}

export function GlassPanel({ className, intensity = "medium", ...props }: GlassPanelProps) {
    const intensityClasses = {
        low: "bg-black/20 backdrop-blur-sm border-white/5",
        medium: "bg-black/40 backdrop-blur-md border-white/10",
        high: "bg-black/60 backdrop-blur-lg border-white/15",
    }

    return (
        <div
            className={cn(
                "rounded-2xl border shadow-2xl transition-all duration-300",
                intensityClasses[intensity],
                className
            )}
            {...props}
        />
    )
}
