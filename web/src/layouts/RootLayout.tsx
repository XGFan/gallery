import { useState, ReactNode } from "react";
import clsx from "clsx";
import NavigationSidebar from "../components/NavigationSidebar";
import TopBar from "../components/TopBar";

interface RootLayoutProps {
    children: ReactNode;
}

export default function RootLayout({ children }: RootLayoutProps) {
    const [isSidebarOpen, setSidebarOpen] = useState(false);

    return (
        <div className="flex w-full h-screen overflow-hidden text-white/90 font-sans selection:bg-accent selection:text-white">
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
                <NavigationSidebar className="w-full h-full border-none" />
            </div>

            {/* Main Content Area */}
            <main className="flex-1 flex flex-col relative w-full h-full min-w-0 bg-transparent">
                {/* Top Navigation Bar */}
                <TopBar
                    onSidebarToggle={() => setSidebarOpen(!isSidebarOpen)}
                    isSidebarOpen={isSidebarOpen}
                />

                {/* Scrollable Grid Area */}
                <div id="main-scroll-container" className="flex-1 overflow-y-auto overflow-x-hidden custom-scrollbar relative z-0 p-1">
                    {children}
                </div>
            </main>

            {/* Mobile Drawer Overlay could go here if we implemented responsive drawer in RootLayout */}
        </div>
    );
}
