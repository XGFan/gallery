import { useNavigate, useLoaderData } from "react-router-dom";
import {useState, useMemo, useEffect, useRef, useCallback, ReactNode} from "react";
import { ChevronRight, Home, LayoutGrid, Image as ImageIcon, Compass, HardDrive, Shuffle } from "lucide-react";
import { Album, AppCtx, Mode } from "../dto";
import clsx from "clsx";
import { getShuffleOpenMode } from "../utils";

// Constants for layout calculations
const MARGIN_MOBILE = 16; // px-4
const MARGIN_DESKTOP = 24; // px-6
const SWITCHER_WIDTH = 56; // w-14
const SWITCHER_GAP = 16; // gap between breadcrumb and switcher

interface TopBarProps {
    onSidebarToggle?: () => void;
    isSidebarOpen?: boolean;
}

export default function TopBar({ onSidebarToggle, isSidebarOpen }: TopBarProps) {
    const { data: album } = useLoaderData() as AppCtx<Album>;
    const navigate = useNavigate();
    const [isSwitcherExpanded, setSwitcherExpanded] = useState(false);
    const [isBreadcrumbExpanded, setBreadcrumbExpanded] = useState(false);
    const [shouldHideSwitcher, setShouldHideSwitcher] = useState(false);
    const [visibleSegmentCount, setVisibleSegmentCount] = useState<number | null>(null); // null = show all
    const [canHover, setCanHover] = useState(true); // Whether device supports hover
    const [isVisible, setIsVisible] = useState(true); // Scroll-aware visibility
    const lastScrollY = useRef(0);
    const breadcrumbRef = useRef<HTMLDivElement>(null);
    const segmentRefs = useRef<(HTMLDivElement | null)[]>([]);

    const parents = album.path.parents();
    const currentPath = album.path.path;
    const currentMode = album.mode;

    // Breadcrumb Logic - Home item has empty name to show only icon
    const breadcrumbs = useMemo(() => [
        { name: "", path: "", icon: <Home className="w-5 h-5" /> },
        ...parents.reverse().filter(p => p.name).map(p => ({ name: p.name, path: p.path, icon: null })),
        ...(album.path.name ? [{ name: album.path.name, path: album.path.path, icon: null }] : [])
    ], [parents, album.path.name, album.path.path]);

    // Helper to change mode while keeping current path
    const changeMode = useCallback((newMode: Mode) => {
        if (newMode === 'random') {
            if (getShuffleOpenMode() === "app") {
                const tinyViewerUrl = `tinyviewer://${currentPath || ''}`;
                // Use direct navigation for the most reliable app handoff
                window.location.href = tinyViewerUrl;
                return;
            }
        }
        navigate(`${currentPath ? '/' + currentPath : '/'}?mode=${newMode}`);
    }, [navigate, currentPath]);

    // Leaf Node Detection
    const isLeaf = useMemo(() => {
        if (album.images.some(img => img.imageType === 'directory')) return false;
        if (currentMode === 'album' || currentMode === 'explore') return true;
        if (currentMode === 'image' || currentMode === 'random') {
            const threshold = currentPath ? 1 : 0;
            return !album.images.some(img => {
                const key = decodeURIComponent(img.key);
                if (currentPath && !key.startsWith(currentPath)) return false;
                const relative = currentPath ? key.substring(currentPath.length) : key;
                const slashCount = (relative.match(/\//g) || []).length;
                return slashCount > threshold;
            });
        }
        return false;
    }, [album, currentMode, currentPath]);

    useEffect(() => {
        if (isLeaf && (currentMode === 'album' || currentMode === 'explore')) {
            changeMode('image');
        }
    }, [isLeaf, currentMode, changeMode]);

    // Scroll awareness
    useEffect(() => {
        const container = window;

        const handleScroll = () => {
            const currentScrollY = container.scrollY;

            // Show when at top or scrolling up
            if (currentScrollY < 10 || currentScrollY < lastScrollY.current) {
                setIsVisible(true);
            } else if (currentScrollY > lastScrollY.current && currentScrollY > 50) {
                // Hide when scrolling down and past threshold
                setIsVisible(false);
            }

            lastScrollY.current = currentScrollY;
        };

        container.addEventListener('scroll', handleScroll, { passive: true });
        return () => container.removeEventListener('scroll', handleScroll);
    }, []);

    // Detect hover capability using matchMedia
    useEffect(() => {
        const mediaQuery = window.matchMedia('(hover: hover) and (pointer: fine)');
        setCanHover(mediaQuery.matches);

        const handleChange = (e: MediaQueryListEvent) => {
            setCanHover(e.matches);
        };

        mediaQuery.addEventListener('change', handleChange);
        return () => mediaQuery.removeEventListener('change', handleChange);
    }, []);

    // Get margin based on screen size
    const getMargin = useCallback(() => {
        return window.innerWidth >= 768 ? MARGIN_DESKTOP : MARGIN_MOBILE;
    }, []);

    // Calculate layout and determine what to show
    const calculateLayout = useCallback(() => {
        const windowWidth = window.innerWidth;
        const margin = getMargin();

        // Max breadcrumb width = windowWidth - 2 * margin
        const maxBreadcrumbWidth = windowWidth - 2 * margin;

        // Available width when switcher is visible
        const availableWithSwitcher = windowWidth - 2 * margin - SWITCHER_WIDTH - SWITCHER_GAP;

        if (!breadcrumbRef.current) return;

        const nav = breadcrumbRef.current.querySelector('nav');
        if (!nav) return;

        const contentWidth = nav.scrollWidth;

        // Measure individual segment widths
        const segmentWidths: number[] = [];
        segmentRefs.current.forEach((ref, idx) => {
            if (ref) {
                segmentWidths[idx] = ref.getBoundingClientRect().width;
            }
        });

        // Case 1: Content fits with switcher - show both
        if (contentWidth <= availableWithSwitcher) {
            setShouldHideSwitcher(false);
            setVisibleSegmentCount(null);
            return;
        }

        // Case 2: Content exceeds available space with switcher
        // Try progressive truncation while keeping switcher
        if (breadcrumbs.length > 2 && segmentWidths.length > 0) {
            const homeWidth = segmentWidths[0] || 60;
            const ellipsisWidth = 40; // approximate width of "..."

            // Try to fit Home + ... + N trailing segments
            for (let trailingCount = breadcrumbs.length - 1; trailingCount >= 1; trailingCount--) {
                let neededWidth = homeWidth + ellipsisWidth;
                for (let i = breadcrumbs.length - trailingCount; i < breadcrumbs.length; i++) {
                    neededWidth += segmentWidths[i] || 80;
                }

                if (neededWidth <= availableWithSwitcher) {
                    setShouldHideSwitcher(false);
                    setVisibleSegmentCount(trailingCount);
                    return;
                }
            }
        }

        // Case 3: Even minimal truncation doesn't fit with switcher - hide switcher
        // Now we have full maxBreadcrumbWidth available
        if (contentWidth <= maxBreadcrumbWidth) {
            setShouldHideSwitcher(true);
            setVisibleSegmentCount(null);
            return;
        }

        // Case 4: Content exceeds max width even without switcher
        // Apply progressive truncation
        if (breadcrumbs.length > 2 && segmentWidths.length > 0) {
            const homeWidth = segmentWidths[0] || 60;
            const ellipsisWidth = 40;

            for (let trailingCount = breadcrumbs.length - 1; trailingCount >= 1; trailingCount--) {
                let neededWidth = homeWidth + ellipsisWidth;
                for (let i = breadcrumbs.length - trailingCount; i < breadcrumbs.length; i++) {
                    neededWidth += segmentWidths[i] || 80;
                }

                if (neededWidth <= maxBreadcrumbWidth) {
                    setShouldHideSwitcher(true);
                    setVisibleSegmentCount(trailingCount);
                    return;
                }
            }
        }

        // Fallback: show Home + last segment only
        setShouldHideSwitcher(true);
        setVisibleSegmentCount(1);
    }, [breadcrumbs.length, getMargin]);

    // Reset and recalculate on path change or expand state change
    useEffect(() => {
        if (!isBreadcrumbExpanded) {
            setVisibleSegmentCount(null);
            setShouldHideSwitcher(false);
        }
    }, [isBreadcrumbExpanded, currentPath]);

    // Layout calculation effect
    useEffect(() => {
        if (isBreadcrumbExpanded) {
            // Delay to allow DOM to render fully
            const timer = setTimeout(calculateLayout, 50);
            return () => clearTimeout(timer);
        }
    }, [isBreadcrumbExpanded, currentPath, calculateLayout]);

    // Use ResizeObserver instead of resize event for better performance
    useEffect(() => {
        if (!isBreadcrumbExpanded) return;

        const observer = new ResizeObserver(() => {
            calculateLayout();
        });

        observer.observe(document.body);
        return () => observer.disconnect();
    }, [isBreadcrumbExpanded, calculateLayout]);

    const availableModes = [
        { id: 'album', icon: LayoutGrid, label: 'Albums', hidden: isLeaf },
        { id: 'image', icon: ImageIcon, label: 'Photos', hidden: false },
        { id: 'explore', icon: Compass, label: 'Explore', hidden: isLeaf },
        { id: 'random', icon: Shuffle, label: 'Shuffle', hidden: false }
    ].filter(m => !m.hidden);

    // Determine which segments to show when expanded
    const getVisibleBreadcrumbs = () => {
        if (visibleSegmentCount === null || visibleSegmentCount >= breadcrumbs.length - 1) {
            // Show all
            return { showAll: true, trailingCount: 0 };
        }
        return { showAll: false, trailingCount: visibleSegmentCount };
    };

    const { showAll, trailingCount } = getVisibleBreadcrumbs();

    // Handle click to toggle (for touch devices)
    const handleBreadcrumbClick = () => {
        if (!canHover) {
            setBreadcrumbExpanded(!isBreadcrumbExpanded);
        }
    };

    return (
        <header
            className={clsx(
                "fixed left-0 right-0 h-12 flex items-center justify-between gap-4 px-4 md:px-6 z-30 pointer-events-none transition-transform duration-300 topbar-safe",
                !isVisible && "topbar-hidden"
            )}
        >
            {/* Left Island: Breadcrumbs */}
            <div
                ref={breadcrumbRef}
                className={clsx(
                    "flex items-center bg-glass-liquid backdrop-blur-lg border border-white/20 rounded-full h-12 shadow-[0_4px_16px_rgba(0,0,0,0.2)] ring-1 ring-white/10 pointer-events-auto transition-all duration-500 ease-[cubic-bezier(0.32,0.72,0,1)] relative overflow-hidden translate-z-0 will-change-transform",
                    isBreadcrumbExpanded
                        ? "px-4 md:px-6 w-auto max-w-[calc(100vw-2rem)] md:max-w-[calc(100vw-3rem)]"
                        : "px-4 max-w-[240px] md:max-w-[480px] lg:max-w-[720px] xl:max-w-[1000px]",
                    // Hide breadcrumb when switcher is expanded
                    isSwitcherExpanded && "opacity-0 pointer-events-none -translate-x-10 scale-95 !w-0 p-0 border-0"
                )}

                onMouseEnter={() => canHover && !isSwitcherExpanded && breadcrumbs.length > 1 && setBreadcrumbExpanded(true)}
                onMouseLeave={() => canHover && setBreadcrumbExpanded(false)}
                onClick={handleBreadcrumbClick}
            >

                {/* Breadcrumbs */}
                <nav aria-label="Breadcrumb" className={clsx(
                    "flex items-center gap-1 text-sm font-medium text-white/80 overflow-hidden whitespace-nowrap min-w-0",
                    // Only add right padding when expanded or has multiple breadcrumbs
                    (isBreadcrumbExpanded || breadcrumbs.length > 1) && "pr-2"
                )}>
                    {/* Sidebar Toggle - Always visible */}
                    {onSidebarToggle && (
                        <>
                            <button
                                onClick={(e) => {
                                    e.stopPropagation();
                                    onSidebarToggle();
                                }}
                                className="flex items-center justify-center w-9 h-9 rounded-full text-white/60 hover:text-white hover:bg-white/10 transition-all duration-300 shrink-0 ml-1"
                                aria-label={isSidebarOpen ? "Close Sidebar" : "Open Sidebar"}
                            >
                                <HardDrive className="w-5 h-5" strokeWidth={1.5} />
                            </button>
                            {/* Divider */}
                            <div className="w-px h-5 bg-white/20 mx-1 shrink-0" />
                        </>
                    )}
                    {(():ReactNode => {
                        // Collapsed: Show Home (if root) or "Home > ... > Current"
                        if (!isBreadcrumbExpanded && breadcrumbs.length > 2) {
                            const current = breadcrumbs[breadcrumbs.length - 1];
                            const isHome = breadcrumbs.length === 1;

                            if (isHome) return (
                                <div className="flex items-center">
                                    <button className="flex items-center gap-1 px-2 py-1 rounded-md text-white cursor-default font-semibold">
                                        <Home className="w-5 h-5" />
                                    </button>
                                </div>
                            );

                            return (
                                <>
                                    <div className="flex items-center">
                                        <button onClick={(e) => { e.stopPropagation(); navigate(`/?mode=album`); }} className="flex items-center gap-1 px-1 py-1 rounded-md text-white/50 hover:text-white">
                                            <Home className="w-5 h-5" />
                                        </button>
                                        <ChevronRight className="w-3.5 h-3.5 text-white/20 mx-0.5" />
                                    </div>
                                    <div className="flex items-center">
                                        <span className="text-white/30 px-1">...</span>
                                        <ChevronRight className="w-3.5 h-3.5 text-white/20 mx-0.5" />
                                    </div>
                                    <div className="flex items-center min-w-0 flex-1">
                                        <button className="flex items-center gap-1 px-1 py-1 rounded-md text-white cursor-default font-semibold min-w-0">
                                            <span className="truncate">{current.name}</span>
                                        </button>
                                    </div>
                                </>
                            );
                        }

                        // Expanded with possible truncation
                        return breadcrumbs.map((item, idx) => {
                            const isLast = idx === breadcrumbs.length - 1;
                            const isFirst = idx === 0;

                            // Progressive truncation logic
                            if (!showAll && !isFirst && !isLast) {
                                const startOfTrailing = breadcrumbs.length - trailingCount;

                                // Show ellipsis only once at position 1
                                if (idx === 1) {
                                    return (
                                        <div key="ellipsis" className="flex items-center" ref={el => segmentRefs.current[idx] = el}>
                                            <span className="text-white/30 px-1">...</span>
                                            <ChevronRight className="w-3.5 h-3.5 text-white/20 mx-0.5" />
                                        </div>
                                    );
                                }

                                // Hide intermediate segments that are not in trailing
                                if (idx < startOfTrailing) {
                                    return null;
                                }
                            }

                            return (
                                <div
                                    key={idx}
                                    className={clsx(
                                        "flex items-center min-w-0",
                                        isLast ? "flex-1 overflow-hidden" : "shrink-0 max-w-[120px] md:max-w-[160px]"
                                    )}
                                    ref={el => segmentRefs.current[idx] = el}
                                >
                                    <button
                                        onClick={(e) => {
                                            e.stopPropagation();
                                            if (!isLast) navigate(`/${item.path}?mode=album`);
                                        }}
                                        className={clsx(
                                            "flex items-center transition-colors min-w-0",
                                            // Home icon button: circular like sidebar button
                                            item.icon && !item.name
                                                ? "justify-center w-9 h-9 rounded-full hover:bg-white/10"
                                                : "gap-1 px-2 py-1 rounded-md hover:bg-white/10",
                                            isLast ? "text-white cursor-default font-semibold overflow-hidden" : "text-white/60 hover:text-white"
                                        )}
                                        disabled={isLast}
                                    >
                                        {item.icon}
                                        {item.name && <span className="truncate">{item.name}</span>}
                                    </button>
                                    {!isLast && <ChevronRight className="w-3.5 h-3.5 text-white/20 mx-0.5 shrink-0" />}
                                </div>
                            );
                        });
                    })()}
                </nav>
            </div>

            {/* Right Island: View Switcher - Collapsible */}
            <div
                className={clsx(
                    "flex bg-glass-liquid backdrop-blur-lg border border-white/20 h-12 w-12 items-center shadow-[0_4px_16px_rgba(0,0,0,0.2)] ring-1 ring-white/10 pointer-events-auto transition-all duration-500 ease-[cubic-bezier(0.32,0.72,0,1)] relative overflow-hidden translate-z-0 will-change-transform shrink-0 rounded-3xl",
                    isSwitcherExpanded
                        ? "px-1 py-1 md:px-2 md:py-0 !w-auto flex-col md:flex-row h-auto md:h-12 items-stretch md:items-center self-start"
                        : "px-0 justify-center cursor-pointer hover:bg-white/10 hover:shadow-glow",
                    // Hide switcher when: breadcrumb expanded, should be hidden, or only one mode available
                    (shouldHideSwitcher || isBreadcrumbExpanded || availableModes.length <= 1) && "opacity-0 pointer-events-none translate-x-10 scale-95 !w-0 p-0 border-0"
                )}
                onMouseEnter={() => canHover && !isBreadcrumbExpanded && setSwitcherExpanded(true)}
                onMouseLeave={() => canHover && setSwitcherExpanded(false)}
                onClick={() => !canHover && !isSwitcherExpanded && !isBreadcrumbExpanded && setSwitcherExpanded(true)}
            >
                {availableModes.map((mode) => {
                    if (!isSwitcherExpanded && currentMode !== mode.id) return null;

                    return (
                        <button
                            key={mode.id}
                            onClick={(e) => {
                                e.stopPropagation();
                                if (isSwitcherExpanded) {
                                    if (currentMode !== mode.id) {
                                        changeMode(mode.id as Mode);
                                    }
                                    setSwitcherExpanded(false);
                                } else {
                                    setSwitcherExpanded(true);
                                }
                            }}
                            className={clsx(
                                "flex items-center gap-2 rounded-full text-xs font-medium transition-all duration-500 ease-[cubic-bezier(0.32,0.72,0,1)] whitespace-nowrap",
                                isSwitcherExpanded
                                    ? "px-4 py-3 md:px-5 md:py-2 w-full md:w-auto justify-start md:justify-center"
                                    : "w-full h-full justify-center p-0",
                                currentMode === mode.id && isSwitcherExpanded
                                    ? "bg-white/10 text-white shadow-inner border border-white/10 backdrop-blur-md"
                                    : "text-white/40 hover:text-white/80 hover:bg-white/5",
                                !isSwitcherExpanded && "text-white"
                            )}
                        >
                            <mode.icon className="w-5 h-5" strokeWidth={2} />
                            {isSwitcherExpanded && <span>{mode.label}</span>}
                        </button>
                    );
                })}
            </div>
        </header >
    );
}
