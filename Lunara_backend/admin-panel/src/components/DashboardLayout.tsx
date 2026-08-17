import React, { useState, useRef, useEffect, useCallback } from 'react';
import { Outlet, useNavigate, useLocation } from 'react-router-dom';
import { io } from 'socket.io-client';
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
    BiCreditCard,
    BiXCircle,
    BiFlag,
    BiRefresh,
    BiTimeFive,
    BiWallet,
} from 'react-icons/bi';
import { useAuthStore } from '../store/authStore';
import { useThemeMode } from '../context/ThemeContext';
import { ThemeSwitcher } from './ThemeSwitcher';
import adminNotificationsApi, { type NotificationCounts, type ActivityItem } from '../api/adminNotifications';
import FloatingNotificationContainer, { type FloatingNotificationItem } from './FloatingNotification';

// Local storage helpers for last seen timestamps
const getLastSeenKey = (path: string) => `lunara_last_seen_${path}`;

const getStoredTimestamp = (path: string): string => {
    let stored = localStorage.getItem(getLastSeenKey(path));
    if (!stored) {
        stored = new Date().toISOString();
        localStorage.setItem(getLastSeenKey(path), stored);
    }
    return stored;
};

const markPathSeen = (path: string) => {
    localStorage.setItem(getLastSeenKey(path), new Date().toISOString());
};

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
            { text: 'Reported Users', icon: <BiBlock />, path: '/reported-users' },
            { text: 'Deleted Accounts', icon: <BiTrashAlt />, path: '/deleted-accounts' },
            { text: 'Venues', icon: <BiStore />, path: '/venues' },
            { text: 'Ads Management', icon: <BiImage />, path: '/ads' },
            { text: 'Bookings', icon: <BiCalendarEvent />, path: '/bookings' },
            { text: 'Event Bookings', icon: <BiCalendarEvent />, path: '/event-bookings' },
            { text: 'Party Requests', icon: <BiGroup />, path: '/party-requests' },
            { text: 'Group Parties', icon: <BiGroup />, path: '/group-parties' },
            { text: 'Strangers Meet', icon: <BiUserPin />, path: '/strangers-meet' },
            { text: 'Safety Checks', icon: <BiShieldQuarter />, path: '/safety-checks' },
            { text: 'Chat Settings', icon: <BiChat />, path: '/chat-settings' },
            { text: 'Subscription Manage', icon: <BiCrown />, path: '/subscriptions' },
            { text: 'Cancelled Plans', icon: <BiXCircle />, path: '/cancelled-plans' },
            { text: 'Cancellation Analytics', icon: <BiFlag />, path: '/cancellation-analytics' },
        ],
    },
    {
        category: 'Insights',
        items: [
            { text: 'Analytics', icon: <BiBarChartAlt2 />, path: '/analytics' },
            { text: 'Venue Summary', icon: <BiBarChartAlt2 />, path: '/reports/venue-summary' },
            { text: 'Payments', icon: <BiCreditCard />, path: '/payments' },
            { text: 'Smart Credit Wallet', icon: <BiWallet />, path: '/wallet' },
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
    const [profileOpen, setProfileOpen] = useState(false);
    const profileRef = useRef<HTMLDivElement>(null);

    const handleLogout = () => {
        clearAuth();
        navigate('/login');
    };

    const isActive = (path: string) => {
        if (path === '/') return location.pathname === '/';
        return location.pathname.startsWith(path);
    };

    const handleNavClick = (path: string) => {
        markPathSeen(path);
        navigate(path);
        setMobileOpen(false);
        fetchNotifications();
    };

    const [notifCounts, setNotifCounts] = useState<NotificationCounts>({
        bookings: 0,
        partyRequests: 0,
        groupParties: 0,
        strangersMeet: 0,
        totalPending: 0,
    });
    const [activityList, setActivityList] = useState<ActivityItem[]>([]);
    const [notifOpen, setNotifOpen] = useState(false);
    const notifRef = useRef<HTMLDivElement>(null);

    // Floating notifications state
    const [floatingNotifs, setFloatingNotifs] = useState<FloatingNotificationItem[]>([]);
    const seenNotifIds = useRef<Set<string>>(new Set());

    const dismissFloatingNotif = useCallback((id: string) => {
        setFloatingNotifs((prev) => prev.filter((item) => item.id !== id));
    }, []);

    const addFloatingNotification = useCallback((item: FloatingNotificationItem) => {
        setFloatingNotifs((prev) => {
            if (prev.some((p) => p.id === item.id)) return prev;
            return [item, ...prev].slice(0, 3);
        });
    }, []);

    const fetchNotifications = useCallback(async () => {
        try {
            const lastSeenBookings = getStoredTimestamp('/bookings');
            const lastSeenPartyRequests = getStoredTimestamp('/party-requests');
            const lastSeenGroupParties = getStoredTimestamp('/group-parties');
            const lastSeenStrangersMeet = getStoredTimestamp('/strangers-meet');

            const [sumRes, actRes] = await Promise.all([
                adminNotificationsApi.getSummary({
                    lastSeenBookings,
                    lastSeenPartyRequests,
                    lastSeenGroupParties,
                    lastSeenStrangersMeet,
                }).catch(() => ({ success: false, data: null })),
                adminNotificationsApi.getActivity().catch(() => ({ success: false, data: [] })),
            ]);

            if (sumRes.success && sumRes.data) {
                setNotifCounts(sumRes.data);
            }
            if (actRes.success && Array.isArray(actRes.data)) {
                setActivityList(actRes.data);

                // Diff activity items to trigger floating toasts for new posts
                actRes.data.forEach((item: ActivityItem) => {
                    const itemTime = new Date(item.createdAt).getTime();
                    const isRecent = (Date.now() - itemTime) < 5 * 60 * 1000; // created in last 5 min
                    if (isRecent && !seenNotifIds.current.has(item.id)) {
                        seenNotifIds.current.add(item.id);
                        const routeLastSeen = new Date(getStoredTimestamp(item.path)).getTime();
                        if (itemTime > routeLastSeen) {
                            addFloatingNotification({
                                id: item.id,
                                type: item.type,
                                title: item.title,
                                subtitle: item.subtitle,
                                path: item.path,
                                createdAt: item.createdAt,
                            });
                        }
                    }
                });
            }
        } catch (err) {
            console.error('Error fetching admin notifications:', err);
        }
    }, [addFloatingNotification]);

    // Handle route navigation: mark current section as seen & refresh counts
    useEffect(() => {
        const matchingPath = ['/bookings', '/party-requests', '/group-parties', '/strangers-meet'].find((p) =>
            location.pathname.startsWith(p)
        );
        if (matchingPath) {
            markPathSeen(matchingPath);
        }
        fetchNotifications();
        const interval = setInterval(fetchNotifications, 10000);
        return () => clearInterval(interval);
    }, [location.pathname, fetchNotifications]);

    // Socket.IO for real-time notifications across the admin panel
    useEffect(() => {
        const socketUrl = import.meta.env.VITE_API_URL || 'http://localhost:9076';
        const socket = io(socketUrl, { transports: ['websocket', 'polling'] });

        socket.on('connect', () => {
            socket.emit('join_admin_room');
        });

        const handleRealtimeNotification = (data: any) => {
            const notifId = data.id || data.entityId ? `${data.type || 'notif'}_${data.id || data.entityId}` : `realtime_${Date.now()}`;
            if (!seenNotifIds.current.has(notifId)) {
                seenNotifIds.current.add(notifId);
                addFloatingNotification({
                    id: notifId,
                    type: data.type || 'party_request',
                    title: data.title || '🎉 New Plan Posted!',
                    subtitle: data.body || data.subtitle || data.message || 'A new plan has been created.',
                    path: data.path || '/party-requests',
                    createdAt: data.createdAt || new Date().toISOString(),
                });
            }
            fetchNotifications();
        };

        socket.on('admin_notification_created', handleRealtimeNotification);
        socket.on('admin_notification', handleRealtimeNotification);

        return () => {
            socket.disconnect();
        };
    }, [addFloatingNotification, fetchNotifications]);

    // Close profile & notification dropdowns on outside click
    useEffect(() => {
        const handleClick = (e: MouseEvent) => {
            if (profileRef.current && !profileRef.current.contains(e.target as Node)) {
                setProfileOpen(false);
            }
            if (notifRef.current && !notifRef.current.contains(e.target as Node)) {
                setNotifOpen(false);
            }
        };
        document.addEventListener('mousedown', handleClick);
        return () => document.removeEventListener('mousedown', handleClick);
    }, []);

    const getItemBadge = (path: string) => {
        let count = 0;
        if (path === '/bookings') count = notifCounts.bookings;
        else if (path === '/party-requests') count = notifCounts.partyRequests;
        else if (path === '/group-parties') count = notifCounts.groupParties;
        else if (path === '/strangers-meet') count = notifCounts.strangersMeet;

        if (count <= 0) return null;

        return (
            <span
                style={{
                    marginLeft: 'auto',
                    backgroundColor: '#ef4444',
                    color: '#ffffff',
                    fontSize: '0.65rem',
                    fontWeight: 800,
                    borderRadius: '12px',
                    padding: '2px 7px',
                    lineHeight: '1.2',
                    boxShadow: '0 0 10px rgba(239, 68, 68, 0.6)',
                    display: 'inline-flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    gap: '4px',
                }}
            >
                <span style={{ width: 5, height: 5, borderRadius: '50%', backgroundColor: '#ffffff' }} />
                {count} NEW
            </span>
        );
    };

    const formatTimeAgo = (dateStr: string) => {
        if (!dateStr) return '';
        const diff = Math.floor((new Date().getTime() - new Date(dateStr).getTime()) / 1000);
        if (diff < 60) return 'Just now';
        if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
        if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
        return `${Math.floor(diff / 86400)}d ago`;
    };

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
                                                <span style={{ display: 'flex', alignItems: 'center', width: '100%', justifyContent: 'space-between' }}>
                                                    <span>{item.text}</span>
                                                    {getItemBadge(item.path)}
                                                </span>
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

                    {/* Notifications Dropdown */}
                    <div className="vz-dropdown" ref={notifRef} style={{ position: 'relative' }}>
                        <button
                            className="header-btn"
                            onClick={() => setNotifOpen(!notifOpen)}
                            title="Notifications"
                            style={{ position: 'relative' }}
                        >
                            <BiBell size={20} />
                            {notifCounts.totalPending > 0 && (
                                <span
                                    style={{
                                        position: 'absolute',
                                        top: '2px',
                                        right: '2px',
                                        backgroundColor: '#ef4444',
                                        color: '#ffffff',
                                        fontSize: '0.625rem',
                                        fontWeight: 700,
                                        borderRadius: '10px',
                                        minWidth: '16px',
                                        height: '16px',
                                        display: 'flex',
                                        alignItems: 'center',
                                        justifyContent: 'center',
                                        padding: '0 4px',
                                        boxShadow: '0 0 0 2px var(--vz-header-bg, #fff)',
                                    }}
                                >
                                    {notifCounts.totalPending}
                                </span>
                            )}
                        </button>

                        <div
                            className={`vz-dropdown-menu ${notifOpen ? 'show' : ''}`}
                            style={{
                                width: '360px',
                                maxHeight: '480px',
                                right: 0,
                                left: 'auto',
                                padding: 0,
                                overflow: 'hidden',
                                boxShadow: '0 12px 32px rgba(0,0,0,0.2)',
                                borderRadius: '12px',
                            }}
                        >
                            <div style={{ padding: '0.875rem 1rem', background: 'var(--vz-card-bg)', borderBottom: '1px solid var(--vz-border-color)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                                <div style={{ fontWeight: 700, fontSize: '0.9375rem', color: 'var(--vz-text-primary)', display: 'flex', alignItems: 'center', gap: '6px' }}>
                                    <BiBell size={18} color="var(--vz-primary)" /> Notifications
                                    {notifCounts.totalPending > 0 && (
                                        <span style={{ backgroundColor: 'rgba(239,68,68,0.12)', color: '#ef4444', fontSize: '0.75rem', fontWeight: 600, padding: '2px 8px', borderRadius: '12px' }}>
                                            {notifCounts.totalPending} Pending
                                        </span>
                                    )}
                                </div>
                                <button
                                    type="button"
                                    onClick={fetchNotifications}
                                    style={{ background: 'none', border: 'none', color: 'var(--vz-text-muted)', cursor: 'pointer', display: 'flex', alignItems: 'center', fontSize: '1.1rem' }}
                                    title="Refresh"
                                >
                                    <BiRefresh />
                                </button>
                            </div>
                            <div style={{ maxHeight: '380px', overflowY: 'auto' }}>
                                {activityList.length === 0 ? (
                                    <div style={{ padding: '2rem 1rem', textAlign: 'center', color: 'var(--vz-text-muted)', fontSize: '0.875rem' }}>
                                        No recent activity or notifications
                                    </div>
                                ) : (
                                    activityList.map((item) => (
                                        <div
                                            key={item.id}
                                            onClick={() => {
                                                setNotifOpen(false);
                                                navigate(item.path);
                                            }}
                                            style={{
                                                padding: '0.75rem 1rem',
                                                borderBottom: '1px solid var(--vz-border-color)',
                                                cursor: 'pointer',
                                                transition: 'background 0.15s ease',
                                                display: 'flex',
                                                gap: '0.75rem',
                                                alignItems: 'flex-start',
                                                backgroundColor: item.isPending ? 'rgba(99,102,241,0.04)' : 'transparent',
                                            }}
                                        >
                                            <div style={{
                                                width: 32, height: 32, borderRadius: '50%',
                                                backgroundColor: item.type === 'booking' ? 'rgba(59,130,246,0.12)' :
                                                    item.type === 'party_request' ? 'rgba(245,158,11,0.12)' :
                                                    item.type === 'group_party' ? 'rgba(16,185,129,0.12)' : 'rgba(139,92,246,0.12)',
                                                color: item.type === 'booking' ? '#2563eb' :
                                                    item.type === 'party_request' ? '#d97706' :
                                                    item.type === 'group_party' ? '#059669' : '#7c3aed',
                                                display: 'flex', alignItems: 'center', justifyContent: 'center',
                                                flexShrink: 0, fontSize: '1rem'
                                            }}>
                                                {item.type === 'booking' ? <BiCalendarEvent /> :
                                                 item.type === 'party_request' ? <BiGroup /> :
                                                 item.type === 'group_party' ? <BiGroup /> : <BiUserPin />}
                                            </div>
                                            <div style={{ flex: 1, minWidth: 0 }}>
                                                <div style={{ fontSize: '0.8125rem', fontWeight: 600, color: 'var(--vz-text-primary)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                                                    {item.title}
                                                </div>
                                                <div style={{ fontSize: '0.75rem', color: 'var(--vz-text-muted)', margin: '2px 0 4px', lineHeight: 1.3 }}>
                                                    {item.subtitle}
                                                </div>
                                                <div style={{ fontSize: '0.6875rem', color: 'var(--vz-text-muted)', display: 'flex', alignItems: 'center', gap: '4px' }}>
                                                    <BiTimeFive size={12} /> {formatTimeAgo(item.createdAt)}
                                                </div>
                                            </div>
                                            {item.isPending && (
                                                <span style={{ width: 8, height: 8, borderRadius: '50%', backgroundColor: '#ef4444', flexShrink: 0, marginTop: 4 }} />
                                            )}
                                        </div>
                                    ))
                                )}
                            </div>
                        </div>
                    </div>

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

            {/* Floating Notification Toast Widget */}
            <FloatingNotificationContainer
                notifications={floatingNotifs}
                onDismiss={dismissFloatingNotif}
                onNavigate={(path) => {
                    markPathSeen(path);
                    navigate(path);
                    fetchNotifications();
                }}
            />

            {/* Theme Switcher Panel */}
            <ThemeSwitcher />
        </div>
    );
};

export default DashboardLayout;
