import { clsx, type ClassValue } from "clsx"
import { extendTailwindMerge } from "tailwind-merge"

// Teach tailwind-merge the token-backed radius/shadow names from index.css so
// e.g. a caller's rounded-ui-lg overrides a component's rounded-ui-md.
const twMerge = extendTailwindMerge({
    extend: {
        theme: {
            radius: ["ui-sm", "ui-md", "ui-lg", "ui-xl"],
            shadow: ["ui", "ui-lg"],
        },
    },
})

export function cn(...inputs: ClassValue[]) {
    return twMerge(clsx(inputs))
}
