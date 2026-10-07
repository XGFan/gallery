import { cn } from "./cn"

interface SliderProps {
    min: number
    max: number
    value: number
    step?: number
    onChange: (value: number) => void
    className?: string
}

export function Slider({ min, max, value, step = 1, onChange, className }: SliderProps) {
    const percentage = ((value - min) / (max - min)) * 100

    return (
        <div className={cn("relative flex w-full touch-none select-none items-center", className)}>
            <input
                type="range"
                min={min}
                max={max}
                step={step}
                value={value}
                onChange={(e) => onChange(Number(e.target.value))}
                className="absolute h-full w-full opacity-0 cursor-pointer z-10"
            />
            <div className="relative h-2 w-full grow overflow-hidden rounded-full bg-fill-hover">
                <div
                    className="h-full bg-fg-2 transition-all"
                    style={{ width: `${percentage}%` }}
                />
            </div>
            <div
                className="block h-5 w-5 rounded-full border border-line-strong bg-white shadow-sm transition-colors focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-accent focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50"
                style={{
                    position: 'absolute',
                    left: `calc(${percentage}% - 10px)`
                }}
            />
        </div>
    )
}
