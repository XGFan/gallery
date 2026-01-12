import React, { useEffect } from "react"
import { GlassPanel } from "./GlassPanel"
import { X } from "lucide-react"
import { Button } from "./Button"
import { createPortal } from "react-dom"

interface ModalProps {
    isOpen: boolean
    onClose: () => void
    children: React.ReactNode
    title?: React.ReactNode
}

export function Modal({ isOpen, onClose, children, title }: ModalProps) {
    useEffect(() => {
        const handleEsc = (e: KeyboardEvent) => {
            if (e.key === "Escape") onClose()
        }
        window.addEventListener("keydown", handleEsc)
        return () => window.removeEventListener("keydown", handleEsc)
    }, [onClose])

    if (!isOpen) return null

    return createPortal(
        <div
            className="fixed inset-0 z-50 flex items-center justify-center p-4 sm:p-6"
            role="dialog"
            aria-modal="true"
            aria-labelledby="modal-title"
        >
            <div
                className="fixed inset-0 bg-black/60 backdrop-blur-sm transition-opacity"
                onClick={onClose}
                aria-hidden="true"
            />

            <GlassPanel
                intensity="high"
                className="relative transform overflow-hidden w-full max-w-lg p-6 shadow-2xl transition-all animate-in fade-in zoom-in-95 duration-300"
            >
                <div className="flex items-center justify-between mb-4">
                    <div id="modal-title" className="text-lg font-semibold text-white/90">{title}</div>
                    <Button variant="ghost" size="icon" onClick={onClose} className="h-8 w-8 rounded-full" aria-label="Close">
                        <X className="h-4 w-4" aria-hidden="true" />
                    </Button>
                </div>
                <div className="text-white/80">
                    {children}
                </div>
            </GlassPanel>
        </div>,
        document.body
    )
}
