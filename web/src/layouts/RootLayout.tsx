import { useState, ReactNode } from "react";
import clsx from "clsx";
import NavigationSidebar from "../components/NavigationSidebar";
import TopBar from "../components/TopBar";
import { Modal } from "../components/ui/Modal";
import { Button } from "../components/ui/Button";
import { getShuffleOpenMode, setShuffleOpenMode, ShuffleOpenMode, getMixedMode, setMixedMode } from "../utils";

interface RootLayoutProps {
    children: ReactNode;
}

export default function RootLayout({ children }: RootLayoutProps) {
    const [isSidebarOpen, setSidebarOpen] = useState(false);
    const [isShuffleModalOpen, setShuffleModalOpen] = useState(false);
    const [shuffleOpenMode, setShuffleOpenModeState] = useState<ShuffleOpenMode>(() => getShuffleOpenMode());
    const [isMixedMode, setIsMixedMode] = useState(() => getMixedMode());

    const handleOpenShuffleSettings = () => {
        setSidebarOpen(false);
        setShuffleModalOpen(true);
    };

    const handleSelectShuffleMode = (mode: ShuffleOpenMode) => {
        setShuffleOpenMode(mode);
        setShuffleOpenModeState(mode);
        setShuffleModalOpen(false);
    };

    const handleToggleMixedMode = () => {
        const newValue = !isMixedMode;
        setIsMixedMode(newValue);
        setMixedMode(newValue);
    };

    return (
        <div className="flex w-full overflow-auto text-white/90 font-sans selection:bg-accent selection:text-white">
            {/* Sidebar Overlay Backdrop */}
            {isSidebarOpen && (
                <div
                    className="fixed inset-0 bg-black/60 backdrop-blur-sm z-40 transition-opacity"
                    onClick={() => setSidebarOpen(false)}
                />
            )}

            {/* Sidebar - Fixed Overlay */}
            <div className={clsx(
                "fixed inset-y-0 left-0 z-50 w-64 transition-transform duration-300 ease-in-out",
                isSidebarOpen ? "translate-x-0" : "-translate-x-full"
            )}>
                <NavigationSidebar
                    className="w-full h-full border-none"
                    onOpenShuffleSettings={handleOpenShuffleSettings}
                />
            </div>

            {/* Main Content Area */}
            <main className="flex-1 flex flex-col relative w-full h-full min-w-0 bg-transparent">
                {/* Top Navigation Bar */}
                <TopBar
                    onSidebarToggle={() => setSidebarOpen(!isSidebarOpen)}
                    isSidebarOpen={isSidebarOpen}
                />

                {children}
            </main>

            <Modal
                isOpen={isShuffleModalOpen}
                onClose={() => setShuffleModalOpen(false)}
                title="Shuffle Mode"
            >
                <div className="space-y-6">
                    <div className="space-y-3">
                        <p className="text-sm text-white/70">
                            Choose how Shuffle opens on this device.
                        </p>
                        <div className="grid grid-cols-2 gap-3">
                            <Button
                                onClick={() => handleSelectShuffleMode("web")}
                                variant="glass"
                                className={clsx(
                                    "w-full justify-center rounded-2xl",
                                    shuffleOpenMode === "web" && "bg-white/20 border-white/30"
                                )}
                            >
                                Web
                            </Button>
                            <Button
                                onClick={() => handleSelectShuffleMode("app")}
                                variant="glass"
                                className={clsx(
                                    "w-full justify-center rounded-2xl",
                                    shuffleOpenMode === "app" && "bg-white/20 border-white/30"
                                )}
                            >
                                App
                            </Button>
                        </div>
                    </div>

                    <div className="pt-4 border-t border-white/10 flex items-center justify-between">
                        <span className="text-sm text-white/70">Mixed Mode (Images + Videos)</span>
                        <button
                            type="button"
                            role="switch"
                            aria-checked={isMixedMode}
                            data-testid="mixed-mode-toggle"
                            onClick={handleToggleMixedMode}
                            className={clsx(
                                "relative inline-flex h-6 w-11 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus-visible:ring-2 focus-visible:ring-white/75",
                                isMixedMode ? "bg-white/90" : "bg-white/10"
                            )}
                        >
                            <span className="sr-only">Toggle mixed mode</span>
                            <span
                                aria-hidden="true"
                                className={clsx(
                                    "pointer-events-none inline-block h-5 w-5 transform rounded-full shadow-lg ring-0 transition duration-200 ease-in-out",
                                    isMixedMode ? "translate-x-5 bg-black/80" : "translate-x-0 bg-white"
                                )}
                            />
                        </button>
                    </div>
                </div>
            </Modal>
        </div>
    );
}
