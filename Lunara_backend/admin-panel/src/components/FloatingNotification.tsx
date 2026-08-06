import React, { useEffect, useState, useRef } from 'react';
import { BiCalendarEvent, BiGroup, BiUserPin, BiX, BiChevronRight, BiBell } from 'react-icons/bi';

export interface FloatingNotificationItem {
    id: string;
    type: 'booking' | 'party_request' | 'group_party' | 'strangers_meet' | string;
    title: string;
    subtitle: string;
    path: string;
    createdAt?: string;
}

interface FloatingNotificationProps {
    notifications: FloatingNotificationItem[];
    onDismiss: (id: string) => void;
    onNavigate: (path: string, id: string) => void;
}

// Synthesize a soft, non-intrusive notification sound using Web Audio API
export const playNotificationChime = () => {
    try {
        const AudioCtx = window.AudioContext || (window as any).webkitAudioContext;
        if (!AudioCtx) return;
        const ctx = new AudioCtx();
        if (ctx.state === 'suspended') {
            ctx.resume();
        }
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();

        osc.type = 'sine';
        // Gentle double-ping chime
        const now = ctx.currentTime;
        osc.frequency.setValueAtTime(587.33, now); // D5
        osc.frequency.setValueAtTime(880, now + 0.1); // A5

        gain.gain.setValueAtTime(0.08, now);
        gain.gain.exponentialRampToValueAtTime(0.001, now + 0.4);

        osc.connect(gain);
        gain.connect(ctx.destination);

        osc.start(now);
        osc.stop(now + 0.4);
    } catch (e) {
        // Ignored if browser blocks autoplay audio before user gesture
    }
};

const SingleToast: React.FC<{
    item: FloatingNotificationItem;
    onDismiss: (id: string) => void;
    onNavigate: (path: string, id: string) => void;
}> = ({ item, onDismiss, onNavigate }) => {
    const [progress, setProgress] = useState(100);
    const [isHovered, setIsHovered] = useState(false);
    const duration = 8000; // 8 seconds
    const intervalRef = useRef<any>(null);

    useEffect(() => {
        playNotificationChime();
    }, []);

    useEffect(() => {
        if (isHovered) {
            if (intervalRef.current) clearInterval(intervalRef.current);
            return;
        }

        const step = 100 / (duration / 100);
        intervalRef.current = setInterval(() => {
            setProgress((prev) => {
                if (prev <= step) {
                    clearInterval(intervalRef.current);
                    onDismiss(item.id);
                    return 0;
                }
                return prev - step;
            });
        }, 100);

        return () => {
            if (intervalRef.current) clearInterval(intervalRef.current);
        };
    }, [isHovered, duration, item.id, onDismiss]);

    const getIcon = () => {
        switch (item.type) {
            case 'booking':
                return <BiCalendarEvent size={20} />;
            case 'party_request':
                return <BiGroup size={20} />;
            case 'group_party':
                return <BiGroup size={20} />;
            case 'strangers_meet':
                return <BiUserPin size={20} />;
            default:
                return <BiBell size={20} />;
        }
    };

    const getTypeColor = () => {
        switch (item.type) {
            case 'booking':
                return { bg: 'rgba(59,130,246,0.18)', border: '#3b82f6', text: '#60a5fa', badge: 'BOOKING' };
            case 'party_request':
                return { bg: 'rgba(245,158,11,0.18)', border: '#f59e0b', text: '#fbbf24', badge: 'PARTY REQUEST' };
            case 'group_party':
                return { bg: 'rgba(16,185,129,0.18)', border: '#10b981', text: '#34d399', badge: 'GROUP PARTY' };
            case 'strangers_meet':
                return { bg: 'rgba(139,92,246,0.18)', border: '#8b5cf6', text: '#a78bfa', badge: 'STRANGERS MEET' };
            default:
                return { bg: 'rgba(99,102,241,0.18)', border: '#6366f1', text: '#818cf8', badge: 'NOTIFICATION' };
        }
    };

    const colors = getTypeColor();

    return (
        <div
            onMouseEnter={() => setIsHovered(true)}
            onMouseLeave={() => setIsHovered(false)}
            style={{
                pointerEvents: 'auto',
                position: 'relative',
                background: 'rgba(15, 23, 42, 0.94)',
                backdropFilter: 'blur(16px)',
                WebkitBackdropFilter: 'blur(16px)',
                borderRadius: '16px',
                padding: '16px 18px',
                border: `1px solid ${colors.border}44`,
                boxShadow: '0 20px 40px rgba(0, 0, 0, 0.45), 0 0 20px rgba(139, 92, 246, 0.15)',
                color: '#ffffff',
                overflow: 'hidden',
                animation: 'slideInRight 0.35s cubic-bezier(0.16, 1, 0.3, 1)',
                display: 'flex',
                flexDirection: 'column',
                gap: '10px',
                transition: 'transform 0.2s ease, box-shadow 0.2s ease',
                transform: isHovered ? 'translateY(-2px)' : 'translateY(0)',
            }}
        >
            {/* Header / Category Badge */}
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                <div
                    style={{
                        display: 'inline-flex',
                        alignItems: 'center',
                        gap: '6px',
                        backgroundColor: colors.bg,
                        color: colors.text,
                        fontSize: '0.6875rem',
                        fontWeight: 800,
                        letterSpacing: '0.8px',
                        padding: '4px 10px',
                        borderRadius: '20px',
                        border: `1px solid ${colors.border}66`,
                        textTransform: 'uppercase',
                    }}
                >
                    {getIcon()}
                    <span>NEW {colors.badge}</span>
                </div>
                <button
                    onClick={() => onDismiss(item.id)}
                    style={{
                        background: 'none',
                        border: 'none',
                        color: '#94a3b8',
                        cursor: 'pointer',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        padding: '4px',
                        borderRadius: '50%',
                        transition: 'color 0.15s, background 0.15s',
                    }}
                    title="Dismiss"
                    onMouseOver={(e) => {
                        e.currentTarget.style.color = '#ffffff';
                        e.currentTarget.style.background = 'rgba(255,255,255,0.1)';
                    }}
                    onMouseOut={(e) => {
                        e.currentTarget.style.color = '#94a3b8';
                        e.currentTarget.style.background = 'none';
                    }}
                >
                    <BiX size={18} />
                </button>
            </div>

            {/* Title & Body */}
            <div>
                <div
                    style={{
                        fontSize: '0.9375rem',
                        fontWeight: 700,
                        color: '#f8fafc',
                        lineHeight: 1.35,
                        marginBottom: '4px',
                    }}
                >
                    {item.title}
                </div>
                <div
                    style={{
                        fontSize: '0.8125rem',
                        color: '#94a3b8',
                        lineHeight: 1.4,
                    }}
                >
                    {item.subtitle}
                </div>
            </div>

            {/* CTA Button */}
            <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: '2px' }}>
                <button
                    onClick={() => onNavigate(item.path, item.id)}
                    style={{
                        background: `linear-gradient(135deg, ${colors.border}, #7c3aed)`,
                        color: '#ffffff',
                        border: 'none',
                        borderRadius: '10px',
                        padding: '7px 14px',
                        fontSize: '0.78125rem',
                        fontWeight: 700,
                        cursor: 'pointer',
                        display: 'inline-flex',
                        alignItems: 'center',
                        gap: '4px',
                        boxShadow: `0 4px 12px ${colors.border}55`,
                        transition: 'transform 0.15s ease, opacity 0.15s ease',
                    }}
                    onMouseOver={(e) => {
                        e.currentTarget.style.transform = 'scale(1.03)';
                    }}
                    onMouseOut={(e) => {
                        e.currentTarget.style.transform = 'scale(1)';
                    }}
                >
                    View Details <BiChevronRight size={16} />
                </button>
            </div>

            {/* Auto-Dismiss Progress Bar */}
            <div
                style={{
                    position: 'absolute',
                    bottom: 0,
                    left: 0,
                    height: '3px',
                    width: `${progress}%`,
                    backgroundColor: colors.border,
                    transition: 'width 0.1s linear',
                    borderBottomLeftRadius: '16px',
                }}
            />
        </div>
    );
};

export const FloatingNotificationContainer: React.FC<FloatingNotificationProps> = ({
    notifications,
    onDismiss,
    onNavigate,
}) => {
    if (notifications.length === 0) return null;

    return (
        <>
            <style>
                {`
                @keyframes slideInRight {
                    from {
                        opacity: 0;
                        transform: translateX(60px) scale(0.95);
                    }
                    to {
                        opacity: 1;
                        transform: translateX(0) scale(1);
                    }
                }
                `}
            </style>
            <div
                style={{
                    position: 'fixed',
                    bottom: '24px',
                    right: '24px',
                    zIndex: 99999,
                    display: 'flex',
                    flexDirection: 'column',
                    gap: '12px',
                    maxWidth: '380px',
                    width: 'calc(100vw - 48px)',
                    pointerEvents: 'none',
                }}
            >
                {notifications.slice(0, 3).map((item) => (
                    <SingleToast
                        key={item.id}
                        item={item}
                        onDismiss={onDismiss}
                        onNavigate={onNavigate}
                    />
                ))}
            </div>
        </>
    );
};

export default FloatingNotificationContainer;
