import React, { useState, useRef, useEffect } from 'react';
import { Outlet, useNavigate, useLocation } from 'react-router-dom';
import {
    BiHomeAlt,
    BiGroup,
    BiStore,
    BiCalendarEvent,
    BiBarChartAlt2,
    BiShieldQuarter,
    BiMenu,
    BiSearch,
    BiBell,
    BiSun,
    BiMoon,
    BiUser,
    BiLogOut,
    BiChevronRight,
    BiHelpCircle,
    BiBook,
    BiFile,
    BiImage,
    BiUserPin,
    BiChat,
    BiBlock,
    BiCrown,
    BiTrashAlt,
} from 'react-icons/bi';
import { useAuthStore } from '../store/authStore';
import { useThemeMode } from '../context/ThemeContext';
import { ThemeSwitcher } from './ThemeSwitcher';

interface NavItem {
    text: string;
    icon: React.ReactNode;
    path: string;
}

interface NavGroup {
    category: string;
    items: NavItem[];
}

const navGroups: NavGroup[] = [
    {
        category: 'Main',
        items: [
            { text: 'Dashboard', icon: <BiHomeAlt />, path: '/' },
        ],
    },
    {
        category: 'Management',
        items: [
            { text: 'Users', icon: <BiGroup />, path: '/users' },
            { text: 'Autoblocked Users', icon: <BiBlock />, path: '/autoblocked-users' },
            { text: 'Deleted Accounts', icon: <BiTrashAlt />, path: '/deleted-accounts' },
            { text: 'Venues', icon: <BiStore />, path: '/venues' },
            { text: 'Ads Management', icon: <BiImage />, path: '/ads' },
            { text: 'Bookings', icon: <BiCalendarEvent />, path: '/bookings' },
            { text: 'Party Requests', icon: <BiGroup />, path: '/party-requests' },
            { text: 'Group Parties', icon: <BiGroup />, path: '/group-parties' },
            { text: 'Strangers Meet', icon: <BiUserPin />, path: '/strangers-meet' },
            { text: 'Safety Checks', icon: <BiShieldQuarter />, path: '/safety-checks' },
            { text: 'Chat Settings', icon: <BiChat />, path: '/chat-settings' },
            { text: 'Subscription Manage', icon: <BiCrown />, path: '/subscriptions' },
        ],
    },
    {
        category: 'Insights',
        items: [
            { text: 'Analytics', icon: <BiBarChartAlt2 />, path: '/analytics' },
            { text: 'Compliance', icon: <BiShieldQuarter />, path: '/compliance' },
        ],
    },
    {
        category: 'Support & Legal',
        items: [
            { text: 'Help Center', icon: <BiHelpCircle />, path: '/help-center' },
            { text: 'Community Guidelines', icon: <BiBook />, path: '/community-guidelines' },
            { text: 'Legal & Terms', icon: <BiFile />, path: '/legal-terms' },
        ],
    },
];

export const DashboardLayout: React.FC = () => {
    const navigate = useNavigate();
    const location = useLocation();
    const { user, clearAuth } = useAuthStore();
    const { settings, mode, toggleTheme } = useThemeMode();
    const { navLayout } = settings;
    const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
    const [mobileOpen, setMobileOpen] = useState(false);
    // ThemeSwitcher is rendered at the bottom of the layout
    const [profileOpen, setProfileOpen] = useState(false);
    const profileRef = useRef<HTMLDivElement>(null);

    const isActive = (path: string) => {
        if (path === '/') return location.pathname === '/';
        return location.pathname.startsWith(path);
    };

    const handleNavClick = (path: string) => {
        navigate(path);
        setMobileOpen(false);
    };

    const handleLogout = () => {
        clearAuth();
        navigate('/login');
    };

    // Close profile dropdown on outside click
    useEffect(() => {
        const handleClick = (e: MouseEvent) => {
            if (profileRef.current && !profileRef.current.contains(e.target as Node)) {
                setProfileOpen(false);
            }
        };
        document.addEventListener('mousedown', handleClick);
        return () => document.removeEventListener('mousedown', handleClick);
    }, []);

    // Get page title from current path
    const getPageTitle = () => {
        for (const group of navGroups) {
            for (const item of group.items) {
                if (isActive(item.path)) return item.text;
            }
        }
        return 'Dashboard';
    };

    return (
        <div className="app-wrapper" data-toggled={sidebarCollapsed ? 'collapsed' : ''}>
            {/* Sidebar Overlay (mobile only) */}
            <div
                className={`sidebar-overlay ${mobileOpen ? 'show' : ''}`}
                onClick={() => setMobileOpen(false)}
            />

            {/* Sidebar */}
            <aside
                className={`app-sidebar ${mobileOpen ? 'show' : ''}`}
                data-nav-layout={settings.navLayout}
                data-nav-style={settings.navStyle}
            >
                <div className="sidebar-header" style={{ justifyContent: 'center' }}>
                    <div className="sidebar-brand" onClick={() => navigate('/')} style={{ cursor: 'pointer', width: '100%', justifyContent: 'center' }}>
                        {/* Favicon icon — shown only when sidebar is collapsed (CSS controls visibility) */}
                        <div className="sidebar-brand-icon" style={{ margin: '0 auto' }}>
                            <img
                                src="/favicon.png"
                                alt="Lunara"
                                style={{ width: 32, height: 32, objectFit: 'contain' }}
                            />
                        </div>
                        {/* Logo V4 — shown when sidebar is expanded (hidden by CSS when collapsed) */}
                        <span className="sidebar-brand-text" style={{ padding: 0, display: 'flex', justifyContent: 'center', width: '100%' }}>
                            <img
                                src="/logo-v4.png"
                                alt="Lunara"
                                style={{ height: 38, maxWidth: 155, objectFit: 'contain', display: 'block' }}
                            />
                        </span>
                    </div>
                </div>

                <div className="sidebar-body">
                    {navLayout === 'horizontal' ? (
                        <ul className="sidebar-nav">
                            {navGroups.flatMap(g => g.items).map((item) => (
                                <li className="nav-item" key={item.path}>
                                    <button
                                        className={`nav-link ${isActive(item.path) ? 'active' : ''}`}
                                        onClick={() => handleNavClick(item.path)}
                                    >
                                        <span className="nav-icon">{item.icon}</span>
                                        <span>{item.text}</span>
                                    </button>
                                </li>
                            ))}
                        </ul>
                    ) : (
                        navGroups.map((group) => (
                            <div key={group.category}>
                                <div className="nav-category">{group.category}</div>
                                <ul className="sidebar-nav">
                                    {group.items.map((item) => (
                                        <li className="nav-item" key={item.path}>
                                            <button
                                                className={`nav-link ${isActive(item.path) ? 'active' : ''}`}
                                                onClick={() => handleNavClick(item.path)}
                                            >
                                                <span className="nav-icon">{item.icon}</span>
                                                <span>{item.text}</span>
                                            </button>
                                        </li>
                                    ))}
                                </ul>
                            </div>
                        ))
                    )}
                </div>

                <div className="sidebar-footer">
                    <div className="sidebar-user-card">
                        <div className="sidebar-avatar">
                            {user?.firstName?.charAt(0) || 'A'}
                        </div>
                        <div className="sidebar-user-info">
                            <div className="sidebar-user-name">
                                {user?.firstName} {user?.lastName}
                            </div>
                            <div className="sidebar-user-role">Administrator</div>
                        </div>
                    </div>
                </div>
            </aside>

            {/* Header */}
            <header className="app-header" data-header-styles={settings.headerStyle}>
                <div className="header-left">
                    {/* Hamburger: collapses sidebar on desktop, opens overlay on mobile */}
                    <button className="header-toggle" onClick={() => {
                        if (window.innerWidth < 768) {
                            setMobileOpen(o => !o);
                        } else {
                            setSidebarCollapsed(c => !c);
                        }
                    }}>
                        <BiMenu />
                    </button>
                    <div className="header-search" style={{ display: undefined }}>
                        <BiSearch className="header-search-icon" />
                        <span className="header-search-text">Search anything...</span>
                        <span className="header-search-kbd">⌘K</span>
                    </div>
                </div>

                <div className="header-right">
                    {/* Theme Toggle */}
                    <button className="header-btn" onClick={toggleTheme} title={mode === 'dark' ? 'Switch to Light' : 'Switch to Dark'}>
                        {mode === 'dark' ? <BiSun /> : <BiMoon />}
                    </button>

                    {/* Notifications */}
                    <button className="header-btn">
                        <BiBell />
                        <span className="badge-dot"></span>
                    </button>

                    {/* Profile Dropdown */}
                    <div className="vz-dropdown" ref={profileRef}>
                        <button
                            className="header-profile"
                            onClick={() => setProfileOpen(!profileOpen)}
                        >
                            <div className="header-profile-avatar">
                                {user?.firstName?.charAt(0) || 'A'}
                            </div>
                            <div className="header-profile-info">
                                <div className="header-profile-name">
                                    {user?.firstName || 'Admin'}
                                </div>
                                <div className="header-profile-role">Admin</div>
                            </div>
                        </button>

                        <div className={`vz-dropdown-menu ${profileOpen ? 'show' : ''}`}>
                            <div style={{ padding: '0.5rem 0.75rem' }}>
                                <div style={{ fontWeight: 600, fontSize: '0.8125rem', color: 'var(--vz-text-primary)' }}>
                                    {user?.firstName} {user?.lastName}
                                </div>
                                <div style={{ fontSize: '0.75rem', color: 'var(--vz-text-muted)' }}>
                                    {user?.email}
                                </div>
                            </div>
                            <div className="vz-dropdown-divider" />
                            <button className="vz-dropdown-item">
                                <BiUser /> Profile Settings
                            </button>
                            <button className="vz-dropdown-item danger" onClick={handleLogout}>
                                <BiLogOut /> Sign Out
                            </button>
                        </div>
                    </div>
                </div>
            </header>

            {/* Main Content */}
            <main className="app-content">
                {/* Breadcrumb */}
                <div className="page-header">
                    <h4 className="page-title">{getPageTitle()}</h4>
                    <div className="page-breadcrumb">
                        <a href="#" onClick={(e) => { e.preventDefault(); navigate('/'); }}>Home</a>
                        <BiChevronRight className="breadcrumb-separator" />
                        <span>{getPageTitle()}</span>
                    </div>
                </div>

                <Outlet />
            </main>

            {/* Theme Switcher Panel */}
            <ThemeSwitcher />
        </div>
    );
};

export default DashboardLayout;
