import { useState, ReactNode } from "react";
import clsx from "clsx";
import NavigationSidebar from "../components/NavigationSidebar";
import TopBar from "../components/TopBar";
import { Modal } from "../components/ui/Modal";
import { Button } from "../components/ui/Button";
import { getShuffleOpenMode, setShuffleOpenMode, ShuffleOpenMode } from "../utils";

interface RootLayoutProps {
    children: ReactNode;
}

export default function RootLayout({ children }: RootLayoutProps) {
    const [isSidebarOpen, setSidebarOpen] = useState(false);
    const [isShuffleModalOpen, setShuffleModalOpen] = useState(false);
    const [shuffleOpenMode, setShuffleOpenModeState] = useState<ShuffleOpenMode>(() => getShuffleOpenMode());

    const handleOpenShuffleSettings = () => {
        setSidebarOpen(false);
        setShuffleModalOpen(true);
    };

    const handleSelectShuffleMode = (mode: ShuffleOpenMode) => {
        setShuffleOpenMode(mode);
        setShuffleOpenModeState(mode);
        setShuffleModalOpen(false);
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
                <div className="space-y-4">
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
            </Modal>
        </div>
    );
}
