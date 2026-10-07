import { cn } from "./cn"
import React from "react"

interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
    variant?: "primary" | "ghost" | "glass" | "glass-icon"
    size?: "sm" | "md" | "lg" | "icon"
}

export function Button({ className, variant = "glass", size = "md", ...props }: ButtonProps) {
    const variants = {
        primary: "bg-accent hover:bg-accent-hover text-on-accent border-transparent shadow-lg shadow-accent/20",
        ghost: "bg-transparent hover:bg-fill-hover text-fg border-transparent",
        glass: "bg-fill hover:bg-fill-hover text-fg backdrop-blur-md border-line border shadow-xs",
        "glass-icon": "bg-overlay hover:bg-overlay-strong text-on-overlay backdrop-blur-md border-overlay-line border shadow-xs",
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
                "inline-flex items-center justify-center rounded-ui-md transition-all duration-200 active:scale-95",
                "disabled:opacity-50 disabled:pointer-events-none",
                "focus:outline-hidden focus:ring-2 focus:ring-line-strong",
                variants[variant],
                sizes[size],
                className
            )}
            {...props}
        />
    )
}
