import React, { useEffect, useState } from 'react';
import { BiSearch, BiMap, BiTime, BiGroup, BiStar, BiUser, BiCalendarEvent, BiStore, BiPulse } from 'react-icons/bi';
import { useThemeMode } from '../context/ThemeContext';
import {
    dashboardApi,
    type FeaturedVenue,
    type PartyTonight,
    type PartyPartner,
    type NearbyVenue
} from '../api/dashboard';

export const Dashboard: React.FC = () => {
    const { mode } = useThemeMode();
    const isDark = mode === 'dark';

    const [featuredVenues, setFeaturedVenues] = useState<FeaturedVenue[]>([]);
    const [partyTonight, setPartyTonight] = useState<PartyTonight[]>([]);
    const [partyPartners, setPartyPartners] = useState<PartyPartner[]>([]);
    const [nearbyVenues, setNearbyVenues] = useState<NearbyVenue[]>([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        const fetchDashboardData = async () => {
            try {
                const [featured, tonight, partners, nearby] = await Promise.all([
                    dashboardApi.getFeaturedVenues(),
                    dashboardApi.getPartyTonight(),
                    dashboardApi.getPartyPartners(),
                    dashboardApi.getNearbyVenues()
                ]);

                if (featured.success) setFeaturedVenues(featured.data);
                if (tonight.success) setPartyTonight(tonight.data);
                if (partners.success) setPartyPartners(partners.data);
                if (nearby.success) setNearbyVenues(nearby.data);
            } catch (error) {
                console.error('Error fetching dashboard data:', error);
            } finally {
                setLoading(false);
            }
        };

        fetchDashboardData();
    }, []);

    // Theme Colors matching Lunara Mobile App
    const colors = {
        bg: isDark ? '#000000' : '#f8f9fa',
        cardBg: isDark ? 'rgba(255, 255, 255, 0.05)' : '#ffffff',
        border: isDark ? 'rgba(255, 255, 255, 0.1)' : '#e9edf4',
        text: isDark ? '#ffffff' : '#212529',
        textMuted: isDark ? 'rgba(255, 255, 255, 0.7)' : '#6c757d',
        electricViolet: '#7F00FF',
        cyberCyan: '#00E5FF',
        hotPink: '#E100FF',
        deepBlue: '#00A9FF'
    };

    if (loading) {
        return (
            <div className="d-flex justify-content-center align-items-center" style={{ minHeight: '60vh' }}>
                <div className="spinner-border" style={{ color: colors.electricViolet }} role="status">
                    <span className="visually-hidden">Loading...</span>
                </div>
            </div>
        );
    }

    return (
        <div style={{ paddingBottom: '2rem' }}>
            {/* Header Greeting */}
            <div className="mb-4 d-flex justify-content-between align-items-center animate-in animate-in-1">
                <div>
                    <p className="mb-0 text-uppercase" style={{ fontSize: '0.75rem', letterSpacing: '2px', color: colors.textMuted, fontWeight: 600 }}>
                        Good Evening,
                    </p>
                    <h2 className="mb-0" style={{ color: colors.text, fontWeight: 800, fontFamily: "'Outfit', sans-serif" }}>
                        EXPLORER
                    </h2>
                </div>
                <div className="d-flex gap-3 align-items-center">
                    <button className="btn btn-icon rounded-circle" style={{ background: colors.cardBg, color: colors.text, border: `1px solid ${colors.border}` }}>
                        <BiPulse size={20} />
                    </button>
                    <div style={{
                        width: '48px',
                        height: '48px',
                        borderRadius: '50%',
                        padding: '2px',
                        background: `linear-gradient(45deg, ${colors.electricViolet}, ${colors.hotPink})`
                    }}>
                        <img
                            src="https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&w=200&q=80"
                            alt="Profile"
                            style={{ width: '100%', height: '100%', borderRadius: '50%', border: '2px solid black', objectFit: 'cover' }}
                        />
                    </div>
                </div>
            </div>

            {/* Quick Actions Menu */}
            <div className="row g-3 mb-5 animate-in animate-in-2">
                {[
                    { icon: <BiStore />, label: 'Explore', color: colors.electricViolet },
                    { icon: <BiUser />, label: 'Find Partner', color: colors.hotPink },
                    { icon: <BiCalendarEvent />, label: 'Book Party', color: colors.cyberCyan },
                    { icon: <BiStar />, label: 'VIP', color: '#ffb703' },
                    { icon: <BiGroup />, label: 'Group', color: colors.deepBlue }
                ].map((action, idx) => (
                    <div key={idx} className="col">
                        <div className="d-flex flex-column align-items-center gap-2" style={{ cursor: 'pointer' }}>
                            <div
                                className="d-flex justify-content-center align-items-center rounded-circle"
                                style={{
                                    width: '64px', height: '64px',
                                    background: `${action.color}15`,
                                    border: `1px solid ${action.color}50`,
                                    boxShadow: `0 0 15px ${action.color}20`,
                                    color: action.color,
                                    transition: 'all 0.3s ease'
                                }}
                                onMouseEnter={(e) => e.currentTarget.style.boxShadow = `0 0 25px ${action.color}40`}
                                onMouseLeave={(e) => e.currentTarget.style.boxShadow = `0 0 15px ${action.color}20`}
                            >
                                {React.cloneElement(action.icon as React.ReactElement<any>, { size: 28 })}
                            </div>
                            <span style={{ fontSize: '0.75rem', fontWeight: 600, color: colors.text }}>{action.label}</span>
                        </div>
                    </div>
                ))}
            </div>

            {/* Featured Venues (Promoted) */}
            <div className="mb-5 animate-in animate-in-3">
                <div className="d-flex justify-content-between align-items-center mb-3">
                    <h6 className="mb-0 text-uppercase" style={{ letterSpacing: '1px', fontWeight: 700, color: colors.text }}>Featured Experiences</h6>
                    <span style={{ fontSize: '0.75rem', fontWeight: 600, color: colors.cyberCyan, cursor: 'pointer' }}>SEE ALL</span>
                </div>
                <div className="d-flex gap-3 overflow-auto" style={{ paddingBottom: '1rem', msOverflowStyle: 'none', scrollbarWidth: 'none' }}>
                    {featuredVenues.map(venue => (
                        <div key={venue.id} style={{
                            minWidth: '320px',
                            height: '240px',
                            borderRadius: '24px',
                            position: 'relative',
                            overflow: 'hidden',
                            border: `2px solid ${colors.electricViolet}50`,
                            boxShadow: `0 10px 30px ${colors.electricViolet}20`
                        }}>
                            <img src={venue.image} alt={venue.name} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                            <div style={{
                                position: 'absolute',
                                inset: 0,
                                background: 'linear-gradient(to top, rgba(0,0,0,0.9), transparent)'
                            }} />
                            <div style={{ position: 'absolute', top: '16px', right: '16px' }}>
                                <div style={{
                                    background: 'rgba(255,255,255,0.1)',
                                    backdropFilter: 'blur(10px)',
                                    padding: '4px 12px',
                                    borderRadius: '20px',
                                    border: `1px solid ${colors.hotPink}50`,
                                    color: colors.hotPink,
                                    fontSize: '0.65rem',
                                    fontWeight: 'bold',
                                    letterSpacing: '1px'
                                }}>
                                    PROMOTED
                                </div>
                            </div>
                            <div style={{ position: 'absolute', bottom: '20px', left: '20px', right: '20px' }}>
                                <h4 className="mb-1" style={{ color: '#fff', fontWeight: 700 }}>{venue.name}</h4>
                                <p className="mb-0" style={{ color: colors.cyberCyan, fontSize: '0.8rem', fontWeight: 600 }}>{venue.type}</p>
                            </div>
                        </div>
                    ))}
                </div>
            </div>

            {/* Party Tonight Section */}
            <div className="mb-5 animate-in animate-in-4">
                <div className="d-flex justify-content-between align-items-center mb-3">
                    <h6 className="mb-0 text-uppercase" style={{ letterSpacing: '1px', fontWeight: 700, color: colors.text }}>Party Tonight</h6>
                    <span style={{ fontSize: '0.75rem', fontWeight: 600, color: colors.cyberCyan, cursor: 'pointer' }}>SEE ALL</span>
                </div>

                {/* Search Bar */}
                <div className="mb-3" style={{
                    background: colors.cardBg,
                    borderRadius: '24px',
                    padding: '8px 20px',
                    border: `1px solid ${colors.border}`,
                    display: 'flex',
                    alignItems: 'center',
                    gap: '12px'
                }}>
                    <BiSearch color={colors.cyberCyan} size={20} />
                    <input
                        type="text"
                        placeholder="Search venue or location..."
                        style={{
                            background: 'transparent',
                            border: 'none',
                            color: colors.text,
                            outline: 'none',
                            width: '100%',
                            fontSize: '0.9rem'
                        }}
                    />
                </div>

                <div className="d-flex flex-column gap-3">
                    {partyTonight.map(party => (
                        <div key={party.id} style={{
                            background: colors.cardBg,
                            borderRadius: '20px',
                            border: `1px solid ${colors.border}`,
                            display: 'flex',
                            overflow: 'hidden',
                            height: '110px'
                        }}>
                            <img src={party.image} alt={party.title} style={{ width: '100px', height: '100%', objectFit: 'cover' }} />
                            <div className="p-3 d-flex flex-column justify-content-center w-100">
                                <h6 className="mb-1 text-truncate" style={{ color: colors.text, fontWeight: 700 }}>{party.title}</h6>
                                <div className="d-flex align-items-center gap-1 mb-2">
                                    <BiMap size={14} color={colors.textMuted} />
                                    <span style={{ color: colors.textMuted, fontSize: '0.75rem' }}>{party.location}</span>
                                </div>
                                <div className="d-flex justify-content-between align-items-center mt-auto">
                                    <div className="d-flex align-items-center gap-1">
                                        <BiTime size={14} color={colors.electricViolet} />
                                        <span style={{ color: colors.electricViolet, fontSize: '0.75rem', fontWeight: 700 }}>{party.time}</span>
                                    </div>
                                    <div className="d-flex align-items-center gap-1">
                                        <BiGroup size={14} color={colors.cyberCyan} />
                                        <span style={{ color: colors.cyberCyan, fontSize: '0.75rem', fontWeight: 600 }}>{party.attendees}</span>
                                    </div>
                                </div>
                            </div>
                        </div>
                    ))}
                </div>
            </div>

            {/* Find Party Partner & Exlore Nearby (Row for Desktop) */}
            <div className="row g-4 animate-in animate-in-5">
                <div className="col-12 col-xl-6">
                    <div className="d-flex justify-content-between align-items-center mb-3">
                        <h6 className="mb-0 text-uppercase" style={{ letterSpacing: '1px', fontWeight: 700, color: colors.text }}>Find Party Partner</h6>
                    </div>
                    <div className="d-flex gap-3 overflow-auto" style={{ paddingBottom: '1rem', msOverflowStyle: 'none', scrollbarWidth: 'none' }}>

                        {/* Post Plan Card */}
                        <div style={{
                            minWidth: '140px',
                            height: '180px',
                            borderRadius: '20px',
                            background: `linear-gradient(135deg, ${colors.electricViolet}, ${colors.hotPink})`,
                            boxShadow: `0 10px 20px ${colors.hotPink}40`,
                            display: 'flex',
                            flexDirection: 'column',
                            alignItems: 'center',
                            justifyContent: 'center',
                            cursor: 'pointer',
                            color: '#fff'
                        }}>
                            <div style={{ background: 'rgba(255,255,255,0.2)', padding: '12px', borderRadius: '50%', marginBottom: '12px' }}>
                                <BiPulse size={24} />
                            </div>
                            <span style={{ fontWeight: 700, textAlign: 'center', fontSize: '0.9rem' }}>Post Your<br />Plan</span>
                        </div>

                        {/* Partner Cards */}
                        {partyPartners.map(partner => (
                            <div key={partner.id} style={{
                                minWidth: '140px',
                                height: '180px',
                                borderRadius: '20px',
                                position: 'relative',
                                overflow: 'hidden',
                                border: `1px solid ${colors.border}`
                            }}>
                                <img src={partner.image} alt={partner.name} style={{ width: '100%', height: '100%', objectFit: 'cover', opacity: 0.6 }} />
                                <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(to top, rgba(0,0,0,0.9), transparent)' }} />
                                <div style={{ position: 'absolute', bottom: '16px', left: '16px', right: '16px' }}>
                                    <h6 className="mb-1" style={{ color: '#fff', fontWeight: 700 }}>{partner.name}</h6>
                                    <p className="mb-0 text-truncate" style={{ color: colors.cyberCyan, fontSize: '0.7rem' }}>{partner.vibe}</p>
                                </div>
                            </div>
                        ))}
                    </div>
                </div>

                <div className="col-12 col-xl-6">
                    <div className="d-flex justify-content-between align-items-center mb-3">
                        <h6 className="mb-0 text-uppercase" style={{ letterSpacing: '1px', fontWeight: 700, color: colors.text }}>Explore Nearby</h6>
                    </div>
                    <div className="d-flex gap-3 overflow-auto" style={{ paddingBottom: '1rem', msOverflowStyle: 'none', scrollbarWidth: 'none' }}>
                        {nearbyVenues.map(venue => (
                            <div key={venue.id} style={{
                                minWidth: '180px',
                                height: '180px',
                                borderRadius: '24px',
                                position: 'relative',
                                overflow: 'hidden',
                                border: `1px solid ${colors.border}`
                            }}>
                                <img src={venue.image} alt={venue.name} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                                <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(to top, rgba(0,0,0,0.8), transparent)' }} />
                                <div style={{ position: 'absolute', bottom: '16px', left: '16px', right: '16px' }}>
                                    <h6 className="mb-1" style={{ color: '#fff', fontWeight: 700 }}>{venue.name}</h6>
                                    <div className="d-flex align-items-center gap-1">
                                        <BiMap size={12} color={colors.hotPink} />
                                        <span style={{ color: 'rgba(255,255,255,0.7)', fontSize: '0.7rem' }}>{venue.distance}</span>
                                    </div>
                                </div>
                            </div>
                        ))}
                    </div>
                </div>
            </div>

            {/* Vibe Categories */}
            <div className="mt-4 mb-3 d-flex gap-2 overflow-auto" style={{ msOverflowStyle: 'none', scrollbarWidth: 'none' }}>
                {['ROOFTOP', 'BARS', 'PUBS', 'FINE DINING', 'LOUNGES'].map((vibe, idx) => (
                    <div key={vibe} style={{
                        padding: '10px 24px',
                        background: idx === 0 ? colors.electricViolet : colors.cardBg,
                        border: `1px solid ${idx === 0 ? 'transparent' : colors.border}`,
                        borderRadius: '30px',
                        color: idx === 0 ? '#fff' : colors.text,
                        fontWeight: 700,
                        fontSize: '0.75rem',
                        letterSpacing: '1px',
                        cursor: 'pointer'
                    }}>
                        {vibe}
                    </div>
                ))}
            </div>

        </div>
    );
};

export default Dashboard;
