import React, { createContext, useContext, useState, useEffect, useMemo, useCallback } from 'react';

// ===== Types =====
export type ThemeMode = 'dark' | 'light';
export type PageStyle = 'regular' | 'classic' | 'modern' | 'flat';
export type LayoutWidth = 'fullwidth' | 'boxed';
export type NavLayout = 'vertical' | 'horizontal';
export type NavStyle = 'menu-click' | 'menu-hover' | 'icon-click' | 'icon-hover' | 'icon-overlay';
export type MenuStyle = 'light' | 'dark' | 'color' | 'gradient' | 'transparent';
export type HeaderStyle = 'light' | 'dark' | 'color' | 'gradient' | 'transparent';
export type MenuPosition = 'fixed' | 'scrollable';
export type HeaderPosition = 'fixed' | 'scrollable';

export interface ThemeColorPreset {
    name: string;
    label: string;
    primary: string;
    primaryRgb: string;
    primaryLight: string;
    gradient: string;
}

export const THEME_COLOR_PRESETS: ThemeColorPreset[] = [
    { name: 'purple', label: 'Purple', primary: '#845adf', primaryRgb: '132, 90, 223', primaryLight: '#a78bfa', gradient: 'linear-gradient(135deg, #845adf, #6d28d9)' },
    { name: 'blue', label: 'Blue', primary: '#3b82f6', primaryRgb: '59, 130, 246', primaryLight: '#60a5fa', gradient: 'linear-gradient(135deg, #3b82f6, #2563eb)' },
    { name: 'teal', label: 'Teal', primary: '#14b8a6', primaryRgb: '20, 184, 166', primaryLight: '#2dd4bf', gradient: 'linear-gradient(135deg, #14b8a6, #0d9488)' },
    { name: 'green', label: 'Green', primary: '#22c55e', primaryRgb: '34, 197, 94', primaryLight: '#4ade80', gradient: 'linear-gradient(135deg, #22c55e, #16a34a)' },
    { name: 'orange', label: 'Orange', primary: '#f97316', primaryRgb: '249, 115, 22', primaryLight: '#fb923c', gradient: 'linear-gradient(135deg, #f97316, #ea580c)' },
    { name: 'pink', label: 'Pink', primary: '#ec4899', primaryRgb: '236, 72, 153', primaryLight: '#f472b6', gradient: 'linear-gradient(135deg, #ec4899, #db2777)' },
];

export interface ThemeSettings {
    mode: ThemeMode;
    colorPreset: string;
    pageStyle: PageStyle;
    layoutWidth: LayoutWidth;
    navLayout: NavLayout;
    navStyle: NavStyle;
    menuStyle: MenuStyle;
    headerStyle: HeaderStyle;
    menuPosition: MenuPosition;
    headerPosition: HeaderPosition;
    bgImage: string | null;
}

const DEFAULT_SETTINGS: ThemeSettings = {
    mode: 'dark',
    colorPreset: 'purple',
    pageStyle: 'regular',
    layoutWidth: 'fullwidth',
    navLayout: 'vertical',
    navStyle: 'menu-click',
    menuStyle: 'dark',
    headerStyle: 'light',
    menuPosition: 'fixed',
    headerPosition: 'fixed',
    bgImage: null,
};

const STORAGE_KEY = 'lunara-theme-settings';

interface ThemeContextType {
    settings: ThemeSettings;
    mode: ThemeMode;             // backward compat
    toggleTheme: () => void;     // backward compat
    setMode: (mode: ThemeMode) => void;
    setColorPreset: (preset: string) => void;
    setPageStyle: (style: PageStyle) => void;
    setLayoutWidth: (width: LayoutWidth) => void;
    setNavLayout: (layout: NavLayout) => void;
    setNavStyle: (style: NavStyle) => void;
    setMenuStyle: (style: MenuStyle) => void;
    setHeaderStyle: (style: HeaderStyle) => void;
    setMenuPosition: (pos: MenuPosition) => void;
    setHeaderPosition: (pos: HeaderPosition) => void;
    setBgImage: (image: string | null) => void;
    resetSettings: () => void;
    getActiveColorPreset: () => ThemeColorPreset;
}

const ThemeContext = createContext<ThemeContextType | undefined>(undefined);

// Apply all settings to the DOM
function applySettings(s: ThemeSettings) {
    const html = document.documentElement;
    html.setAttribute('data-theme', s.mode);
    html.setAttribute('data-theme-mode', s.mode);
    html.setAttribute('data-page-style', s.pageStyle);
    html.setAttribute('data-width', s.layoutWidth);
    html.setAttribute('data-primary', s.colorPreset);
    html.setAttribute('data-nav-layout', s.navLayout);
    html.setAttribute('data-nav-style', s.navStyle);
    html.setAttribute('data-menu-styles', s.menuStyle);
    html.setAttribute('data-header-styles', s.headerStyle);
    html.setAttribute('data-menu-position', s.menuPosition);
    html.setAttribute('data-header-position', s.headerPosition);
    if (s.bgImage) {
        html.setAttribute('data-bg-img', s.bgImage);
    } else {
        html.removeAttribute('data-bg-img');
    }

    // Apply primary color CSS variables
    const preset = THEME_COLOR_PRESETS.find(p => p.name === s.colorPreset) || THEME_COLOR_PRESETS[0];
    html.style.setProperty('--vz-primary', preset.primary);
    html.style.setProperty('--vz-primary-rgb', preset.primaryRgb);
    html.style.setProperty('--vz-primary-light', preset.primaryLight);
}

function loadSettings(): ThemeSettings {
    try {
        const raw = localStorage.getItem(STORAGE_KEY);
        if (raw) {
            const parsed = JSON.parse(raw);
            return { ...DEFAULT_SETTINGS, ...parsed };
        }
    } catch { /* ignore */ }
    return { ...DEFAULT_SETTINGS };
}

function saveSettings(s: ThemeSettings) {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(s));
}

export const ThemeProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
    const [settings, setSettings] = useState<ThemeSettings>(loadSettings);

    // Apply on mount
    useEffect(() => {
        applySettings(settings);
    }, []);

    // Apply whenever settings change
    useEffect(() => {
        applySettings(settings);
        saveSettings(settings);
    }, [settings]);

    const update = useCallback((patch: Partial<ThemeSettings>) => {
        setSettings(prev => ({ ...prev, ...patch }));
    }, []);

    const toggleTheme = useCallback(() => {
        setSettings(prev => ({ ...prev, mode: prev.mode === 'dark' ? 'light' : 'dark' }));
    }, []);

    const setMode = useCallback((mode: ThemeMode) => update({ mode }), [update]);
    const setColorPreset = useCallback((colorPreset: string) => update({ colorPreset }), [update]);
    const setPageStyle = useCallback((pageStyle: PageStyle) => update({ pageStyle }), [update]);
    const setLayoutWidth = useCallback((layoutWidth: LayoutWidth) => update({ layoutWidth }), [update]);
    const setNavLayout = useCallback((navLayout: NavLayout) => update({ navLayout }), [update]);
    const setNavStyle = useCallback((navStyle: NavStyle) => update({ navStyle }), [update]);
    const setMenuStyle = useCallback((menuStyle: MenuStyle) => update({ menuStyle }), [update]);
    const setHeaderStyle = useCallback((headerStyle: HeaderStyle) => update({ headerStyle }), [update]);
    const setMenuPosition = useCallback((menuPosition: MenuPosition) => update({ menuPosition }), [update]);
    const setHeaderPosition = useCallback((headerPosition: HeaderPosition) => update({ headerPosition }), [update]);
    const setBgImage = useCallback((bgImage: string | null) => update({ bgImage }), [update]);
    const resetSettings = useCallback(() => setSettings({ ...DEFAULT_SETTINGS }), []);

    const getActiveColorPreset = useCallback(
        () => THEME_COLOR_PRESETS.find(p => p.name === settings.colorPreset) || THEME_COLOR_PRESETS[0],
        [settings.colorPreset]
    );

    const value = useMemo(() => ({
        settings,
        mode: settings.mode,
        toggleTheme,
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
        getActiveColorPreset,
    }), [settings, toggleTheme, setMode, setColorPreset, setPageStyle, setLayoutWidth, setNavLayout, setNavStyle, setMenuStyle, setHeaderStyle, setMenuPosition, setHeaderPosition, setBgImage, resetSettings, getActiveColorPreset]);

    return (
        <ThemeContext.Provider value={value}>
            {children}
        </ThemeContext.Provider>
    );
};

export const useThemeMode = () => {
    const context = useContext(ThemeContext);
    if (!context) {
        throw new Error('useThemeMode must be used within a ThemeProvider');
    }
    return context;
};
