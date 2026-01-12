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
            <div className="relative h-2 w-full grow overflow-hidden rounded-full bg-white/10">
                <div
                    className="h-full bg-white/50 transition-all"
                    style={{ width: `${percentage}%` }}
                />
            </div>
            <div
                className="block h-5 w-5 rounded-full border-2 border-white/50 bg-white ring-offset-black transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50"
                style={{
                    position: 'absolute',
                    left: `calc(${percentage}% - 10px)`
                }}
            />
        </div>
    )
}
