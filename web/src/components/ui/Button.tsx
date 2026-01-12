import { cn } from "./cn"
import React from "react"

interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
    variant?: "primary" | "ghost" | "glass" | "glass-icon"
    size?: "sm" | "md" | "lg" | "icon"
}

export function Button({ className, variant = "glass", size = "md", ...props }: ButtonProps) {
    const variants = {
        primary: "bg-blue-500 hover:bg-blue-600 text-white border-transparent shadow-lg shadow-blue-500/20",
        ghost: "bg-transparent hover:bg-white/10 text-white/90 hover:text-white border-transparent",
        glass: "bg-white/10 hover:bg-white/20 text-white backdrop-blur-md border-white/10 border shadow-sm",
        "glass-icon": "bg-black/30 hover:bg-black/50 text-white backdrop-blur-md border-white/5 border shadow-sm",
    }

    const sizes = {
        sm: "px-3 py-1.5 text-sm",
        md: "px-4 py-2 text-base",
        lg: "px-6 py-3 text-lg",
        icon: "p-2 aspect-square flex items-center justify-center",
    }

    return (
        <button
            className={cn(
                "inline-flex items-center justify-center rounded-xl transition-all duration-200 active:scale-95",
                "disabled:opacity-50 disabled:pointer-events-none",
                "focus:outline-none focus:ring-2 focus:ring-white/20",
                variants[variant],
                sizes[size],
                className
            )}
            {...props}
        />
    )
}
