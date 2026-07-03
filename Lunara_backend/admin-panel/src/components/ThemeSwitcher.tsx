import React, { useState, useEffect, useRef, useCallback } from 'react';
import {
    BiCog,
    BiX,
    BiSun,
    BiMoon,
    BiReset,
    BiExpandAlt,
    BiCollapse,
    BiLayout,
    BiNavigation,
    BiWindow,
    BiImage,
    BiCheck,
} from 'react-icons/bi';
import {
    useThemeMode,
    THEME_COLOR_PRESETS,
    type ThemeMode,
    type PageStyle,
    type LayoutWidth,
    type NavLayout,
    type NavStyle,
    type MenuStyle,
    type HeaderStyle,
    type MenuPosition,
    type HeaderPosition,
} from '../context/ThemeContext';

type Tab = 'styles' | 'nav' | 'header_menu' | 'colors' | 'bg_images';

export const ThemeSwitcher: React.FC = () => {
    const {
        settings,
        setMode,
        setColorPreset,
        setPageStyle,
        setLayoutWidth,
        setNavLayout,
        setNavStyle,
        setMenuStyle,
        setHeaderStyle,
        setMenuPosition,
        setHeaderPosition,
        setBgImage,
        resetSettings,
    } = useThemeMode();

    const [isOpen, setIsOpen] = useState(false);
    const [activeTab, setActiveTab] = useState<Tab>('styles');
    const panelRef = useRef<HTMLDivElement>(null);

    // Close panel on Escape key
    useEffect(() => {
        const onKey = (e: KeyboardEvent) => {
            if (e.key === 'Escape') setIsOpen(false);
        };
        document.addEventListener('keydown', onKey);
        return () => document.removeEventListener('keydown', onKey);
    }, []);

    // Close on click outside
    useEffect(() => {
        if (!isOpen) return;
        const onClick = (e: MouseEvent) => {
            if (panelRef.current && !panelRef.current.contains(e.target as Node)) {
                setIsOpen(false);
            }
        };
        const timeout = setTimeout(() => {
            document.addEventListener('mousedown', onClick);
        }, 100);
        return () => {
            clearTimeout(timeout);
            document.removeEventListener('mousedown', onClick);
        };
    }, [isOpen]);

    const handleReset = useCallback(() => {
        resetSettings();
    }, [resetSettings]);

    // Prevent body scroll when panel is open
    useEffect(() => {
        if (isOpen) {
            document.body.style.overflow = 'hidden';
        } else {
            document.body.style.overflow = '';
        }
        return () => { document.body.style.overflow = ''; };
    }, [isOpen]);

    return (
        <>
            {/* Floating Gear Button */}
            <button
                className="theme-switcher-trigger"
                onClick={() => setIsOpen(true)}
                title="Theme Settings"
                aria-label="Open theme settings"
            >
                <BiCog className="trigger-icon" />
            </button>

            {/* Backdrop */}
            <div
                className={`theme-switcher-backdrop ${isOpen ? 'show' : ''}`}
                onClick={() => setIsOpen(false)}
                aria-hidden="true"
            />

            {/* Panel */}
            <div
                ref={panelRef}
                className={`theme-switcher-panel ${isOpen ? 'show' : ''}`}
                role="dialog"
                aria-label="Theme Switcher"
            >
                {/* Panel Header */}
                <div className="ts-header">
                    <div className="ts-header-title">
                        <span className="ts-header-icon">⚙️</span>
                        <span>Switcher</span>
                    </div>
                    <button
                        className="ts-close-btn"
                        onClick={() => setIsOpen(false)}
                        aria-label="Close switcher"
                    >
                        <BiX />
                    </button>
                </div>

                {/* Tabs */}
                <div className="ts-tabs-wrapper">
                    <div className="ts-tabs">
                        <button className={`ts-tab ${activeTab === 'styles' ? 'active' : ''}`} onClick={() => setActiveTab('styles')}>Styles</button>
                        <button className={`ts-tab ${activeTab === 'nav' ? 'active' : ''}`} onClick={() => setActiveTab('nav')}>Nav</button>
                        <button className={`ts-tab ${activeTab === 'header_menu' ? 'active' : ''}`} onClick={() => setActiveTab('header_menu')}>Header/Menu</button>
                        <button className={`ts-tab ${activeTab === 'colors' ? 'active' : ''}`} onClick={() => setActiveTab('colors')}>Colors</button>
                        <button className={`ts-tab ${activeTab === 'bg_images' ? 'active' : ''}`} onClick={() => setActiveTab('bg_images')}>Images</button>
                    </div>
                </div>

                {/* Tab Content */}
                <div className="ts-body">
                    {activeTab === 'styles' && (
                        <StylesTab
                            mode={settings.mode}
                            pageStyle={settings.pageStyle}
                            layoutWidth={settings.layoutWidth}
                            menuPosition={settings.menuPosition}
                            headerPosition={settings.headerPosition}
                            setMode={setMode}
                            setPageStyle={setPageStyle}
                            setLayoutWidth={setLayoutWidth}
                            setMenuPosition={setMenuPosition}
                            setHeaderPosition={setHeaderPosition}
                        />
                    )}
                    {activeTab === 'nav' && (
                        <NavStylesTab
                            navLayout={settings.navLayout}
                            navStyle={settings.navStyle}
                            setNavLayout={setNavLayout}
                            setNavStyle={setNavStyle}
                        />
                    )}
                    {activeTab === 'header_menu' && (
                        <HeaderMenuTab
                            menuStyle={settings.menuStyle}
                            headerStyle={settings.headerStyle}
                            setMenuStyle={setMenuStyle}
                            setHeaderStyle={setHeaderStyle}
                        />
                    )}
                    {activeTab === 'colors' && (
                        <ColorsTab
                            activePreset={settings.colorPreset}
                            setColorPreset={setColorPreset}
                        />
                    )}
                    {activeTab === 'bg_images' && (
                        <BgImagesTab
                            bgImage={settings.bgImage}
                            setBgImage={setBgImage}
                        />
                    )}
                </div>

                {/* Footer */}
                <div className="ts-footer">
                    <button className="ts-reset-btn" onClick={handleReset}>
                        <BiReset style={{ fontSize: '1rem' }} />
                        <span>Reset All</span>
                    </button>
                </div>
            </div>
        </>
    );
};

/* ==============================
   STYLES TAB
============================== */
interface StylesTabProps {
    mode: ThemeMode;
    pageStyle: PageStyle;
    layoutWidth: LayoutWidth;
    menuPosition: MenuPosition;
    headerPosition: HeaderPosition;
    setMode: (m: ThemeMode) => void;
    setPageStyle: (s: PageStyle) => void;
    setLayoutWidth: (w: LayoutWidth) => void;
    setMenuPosition: (p: MenuPosition) => void;
    setHeaderPosition: (p: HeaderPosition) => void;
}

const StylesTab: React.FC<StylesTabProps> = ({
    mode, pageStyle, layoutWidth, menuPosition, headerPosition,
    setMode, setPageStyle, setLayoutWidth, setMenuPosition, setHeaderPosition
}) => (
    <div className="ts-styles-content">
        <OptionSection title="Theme Color Mode:">
            <div className="ts-option-row">
                <OptionButton active={mode === 'light'} onClick={() => setMode('light')} icon={<BiSun />} label="Light" />
                <OptionButton active={mode === 'dark'} onClick={() => setMode('dark')} icon={<BiMoon />} label="Dark" />
            </div>
        </OptionSection>

        <OptionSection title="Page Styles:">
            <div className="ts-option-grid">
                {(['regular', 'classic', 'modern', 'flat'] as PageStyle[]).map((style) => (
                    <OptionChip key={style} active={pageStyle === style} onClick={() => setPageStyle(style)} label={style.charAt(0).toUpperCase() + style.slice(1)} />
                ))}
            </div>
        </OptionSection>

        <OptionSection title="Layout Width:">
            <div className="ts-option-row">
                <OptionButton active={layoutWidth === 'fullwidth'} onClick={() => setLayoutWidth('fullwidth')} icon={<BiExpandAlt />} label="Full" />
                <OptionButton active={layoutWidth === 'boxed'} onClick={() => setLayoutWidth('boxed')} icon={<BiCollapse />} label="Boxed" />
            </div>
        </OptionSection>

        <OptionSection title="Menu Position:">
            <div className="ts-option-row">
                <OptionButton active={menuPosition === 'fixed'} onClick={() => setMenuPosition('fixed')} icon={<BiWindow />} label="Fixed" />
                <OptionButton active={menuPosition === 'scrollable'} onClick={() => setMenuPosition('scrollable')} icon={<BiNavigation />} label="Scroll" />
            </div>
        </OptionSection>

        <OptionSection title="Header Position:">
            <div className="ts-option-row">
                <OptionButton active={headerPosition === 'fixed'} onClick={() => setHeaderPosition('fixed')} icon={<BiWindow />} label="Fixed" />
                <OptionButton active={headerPosition === 'scrollable'} onClick={() => setHeaderPosition('scrollable')} icon={<BiNavigation />} label="Scroll" />
            </div>
        </OptionSection>
    </div>
);

/* ==============================
   NAV STYLES TAB
============================== */
interface NavStylesTabProps {
    navLayout: NavLayout;
    navStyle: NavStyle;
    setNavLayout: (l: NavLayout) => void;
    setNavStyle: (s: NavStyle) => void;
}

const NavStylesTab: React.FC<NavStylesTabProps> = ({ navLayout, navStyle, setNavLayout, setNavStyle }) => (
    <div className="ts-styles-content">
        <OptionSection title="Navigation Layout:">
            <div className="ts-option-row">
                <OptionButton active={navLayout === 'vertical'} onClick={() => setNavLayout('vertical')} icon={<BiLayout />} label="Vertical" />
                <OptionButton active={navLayout === 'horizontal'} onClick={() => setNavLayout('horizontal')} icon={<BiLayout style={{ transform: 'rotate(90deg)' }} />} label="Horizontal" />
            </div>
        </OptionSection>

        <OptionSection title="Navigation Style:">
            <div className="ts-option-grid">
                {(['menu-click', 'menu-hover', 'icon-click', 'icon-hover', 'icon-overlay'] as NavStyle[]).map((style) => (
                    <OptionChip key={style} active={navStyle === style} onClick={() => setNavStyle(style)} label={style.split('-').map(s => s.charAt(0).toUpperCase() + s.slice(1)).join(' ')} />
                ))}
            </div>
        </OptionSection>
    </div>
);

/* ==============================
   HEADER & MENU TAB
============================== */
interface HeaderMenuTabProps {
    menuStyle: MenuStyle;
    headerStyle: HeaderStyle;
    setMenuStyle: (s: MenuStyle) => void;
    setHeaderStyle: (s: HeaderStyle) => void;
}

const HeaderMenuTab: React.FC<HeaderMenuTabProps> = ({ menuStyle, headerStyle, setMenuStyle, setHeaderStyle }) => (
    <div className="ts-styles-content">
        <OptionSection title="Menu Styles:">
            <div className="ts-option-grid">
                {(['light', 'dark', 'color', 'gradient', 'transparent'] as MenuStyle[]).map((style) => (
                    <OptionChip key={style} active={menuStyle === style} onClick={() => setMenuStyle(style)} label={style.charAt(0).toUpperCase() + style.slice(1)} />
                ))}
            </div>
        </OptionSection>

        <OptionSection title="Header Styles:">
            <div className="ts-option-grid">
                {(['light', 'dark', 'color', 'gradient', 'transparent'] as HeaderStyle[]).map((style) => (
                    <OptionChip key={style} active={headerStyle === style} onClick={() => setHeaderStyle(style)} label={style.charAt(0).toUpperCase() + style.slice(1)} />
                ))}
            </div>
        </OptionSection>
    </div>
);

/* ==============================
   COLORS TAB
============================== */
interface ColorsTabProps {
    activePreset: string;
    setColorPreset: (name: string) => void;
}

const ColorsTab: React.FC<ColorsTabProps> = ({ activePreset, setColorPreset }) => (
    <div className="ts-colors-content">
        <OptionSection title="Theme Primary Color:">
            <div className="ts-color-grid">
                {THEME_COLOR_PRESETS.map((preset) => (
                    <button
                        key={preset.name}
                        className={`ts-color-swatch ${activePreset === preset.name ? 'active' : ''}`}
                        onClick={() => setColorPreset(preset.name)}
                        title={preset.label}
                    >
                        <span className="ts-swatch-fill" style={{ background: preset.gradient }} />
                        {activePreset === preset.name && <span className="ts-swatch-check"><BiCheck /></span>}
                        <span className="ts-swatch-label">{preset.label}</span>
                    </button>
                ))}
            </div>
        </OptionSection>
    </div>
);

/* ==============================
   BACKGROUND IMAGES TAB
============================== */
interface BgImagesTabProps {
    bgImage: string | null;
    setBgImage: (image: string | null) => void;
}

const BgImagesTab: React.FC<BgImagesTabProps> = ({ bgImage, setBgImage }) => (
    <div className="ts-styles-content">
        <OptionSection title="Menu Background Image:">
            <div className="ts-bg-img-grid">
                <button
                    className={`ts-bg-img-btn ${bgImage === null ? 'active' : ''}`}
                    onClick={() => setBgImage(null)}
                >
                    None
                </button>
                {['bgimg1', 'bgimg2', 'bgimg3', 'bgimg4', 'bgimg5'].map((img) => (
                    <button
                        key={img}
                        className={`ts-bg-img-btn ${bgImage === img ? 'active' : ''}`}
                        onClick={() => setBgImage(img)}
                    >
                        <BiImage />
                        <span>{img.replace('bgimg', 'Image ')}</span>
                    </button>
                ))}
            </div>
        </OptionSection>
    </div>
);

/* ==============================
   SHARED SUB-COMPONENTS
============================== */
const OptionSection: React.FC<{ title: string; children: React.ReactNode }> = ({ title, children }) => (
    <div className="ts-section">
        <div className="ts-section-title">{title}</div>
        {children}
    </div>
);

const OptionButton: React.FC<{ active: boolean; onClick: () => void; icon: React.ReactNode; label: string }> = ({ active, onClick, icon, label }) => (
    <button className={`ts-option-btn ${active ? 'active' : ''}`} onClick={onClick}>
        <span className="ts-option-btn-icon">{icon}</span>
        <span>{label}</span>
    </button>
);

const OptionChip: React.FC<{ active: boolean; onClick: () => void; label: string }> = ({ active, onClick, label }) => (
    <button className={`ts-option-chip ${active ? 'active' : ''}`} onClick={onClick}>
        <span className="ts-chip-radio">{active && <span className="ts-chip-radio-dot" />}</span>
        <span>{label}</span>
    </button>
);

export default ThemeSwitcher;
