import React, { useEffect, useState, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { BiCalendar, BiCheckCircle, BiPulse, BiGroup, BiStar, BiCalendarEvent, BiParty, BiStoreAlt } from 'react-icons/bi';
import { useThemeMode } from '../context/ThemeContext';
import bookingsApi from '../api/bookings';
import ReactApexChart from 'react-apexcharts';
import { io } from 'socket.io-client';
import Swal from 'sweetalert2';
import 'sweetalert2/dist/sweetalert2.min.css';

export const Dashboard: React.FC = () => {
    const { mode } = useThemeMode();
    const isDark = mode === 'dark';
    const navigate = useNavigate();

    const [summary, setSummary] = useState<any>(null);
    const [venuesData, setVenuesData] = useState<any[]>([]);
    const [loading, setLoading] = useState(true);

    const fetchDashboardData = useCallback(async () => {
        setLoading(true);
        try {
            const res = await bookingsApi.getVenueWiseSummary({});
            if (res.success) {
                setSummary(res.data.summary);
                setVenuesData(res.data.venues);
            }
        } catch (error) {
            console.error('Error fetching dashboard data:', error);
        } finally {
            setLoading(false);
        }
    }, []);

    useEffect(() => {
        fetchDashboardData();

        // Socket.io for Real-time Admin Notifications
        const socket = io(import.meta.env.VITE_API_URL || 'http://localhost:5000');
        
        socket.on('connect', () => {
            socket.emit('join_admin_room');
        });

        socket.on('admin_notification', (data) => {
            Swal.fire({
                title: data.title || 'New Notification',
                text: data.message || 'Action required.',
                icon: 'info',
                toast: true,
                position: 'top-end',
                showConfirmButton: false,
                timer: 6000,
                timerProgressBar: true,
                background: isDark ? '#1a1d21' : '#ffffff',
                color: isDark ? '#ffffff' : '#000000',
                didOpen: (toast) => {
                    toast.addEventListener('mouseenter', Swal.stopTimer)
                    toast.addEventListener('mouseleave', Swal.resumeTimer)
                }
            });
        });

        return () => {
            socket.disconnect();
        };
    }, [fetchDashboardData, isDark]);

    const formatCurrency = (amount: number | string) => {
        return `₹${Number(amount || 0).toLocaleString('en-IN', { minimumFractionDigits: 0, maximumFractionDigits: 2 })}`;
    };

    // Theme Colors
    const colors = {
        bg: isDark ? '#000000' : '#f8f9fa',
        cardBg: isDark ? 'rgba(255, 255, 255, 0.05)' : '#ffffff',
        border: isDark ? 'rgba(255, 255, 255, 0.1)' : '#e9edf4',
        text: isDark ? '#ffffff' : '#212529',
        textMuted: isDark ? 'rgba(255, 255, 255, 0.7)' : '#6c757d',
        electricViolet: '#7F00FF',
        hotPink: '#E100FF',
    };

    // Chart Options
    const chartOptions: any = {
        chart: {
            type: 'bar',
            background: 'transparent',
            toolbar: { show: false }
        },
        theme: { mode: isDark ? 'dark' : 'light' },
        plotOptions: {
            bar: {
                borderRadius: 4,
                horizontal: false,
                columnWidth: '45%',
            }
        },
        dataLabels: { enabled: false },
        xaxis: {
            categories: venuesData.map(v => v.venueName?.substring(0, 15) + (v.venueName?.length > 15 ? '...' : '')),
            labels: {
                style: { colors: isDark ? '#fff' : '#000' }
            }
        },
        yaxis: {
            labels: {
                style: { colors: isDark ? '#fff' : '#000' }
            }
        },
        colors: [colors.electricViolet],
        tooltip: {
            theme: isDark ? 'dark' : 'light',
            y: {
                formatter: function (val: number) {
                    return val + " Bookings"
                }
            }
        }
    };

    const chartSeries = [{
        name: 'Total Bookings',
        data: venuesData.map(v => v.totalBookings || 0)
    }];

    if (loading) {
        return (
            <div className="d-flex justify-content-center align-items-center" style={{ minHeight: '60vh' }}>
                <div className="spinner-border" style={{ color: colors.electricViolet }} role="status">
                    <span className="visually-hidden">Loading...</span>
                </div>
            </div>
        );
    }

    const handleCardClick = (path: string, state?: any) => {
        navigate(path, { state });
    };

    return (
        <div style={{ paddingBottom: '2rem' }}>
            {/* Header */}
            <div className="mb-4 d-flex justify-content-between align-items-center">
                <div>
                    <p className="mb-0 text-uppercase" style={{ fontSize: '0.75rem', letterSpacing: '2px', color: colors.textMuted, fontWeight: 600 }}>
                        Admin Overview
                    </p>
                    <h2 className="mb-0" style={{ color: colors.text, fontWeight: 800, fontFamily: "'Outfit', sans-serif" }}>
                        DASHBOARD
                    </h2>
                </div>
                <div className="d-flex gap-3 align-items-center">
                    <button className="btn btn-icon rounded-circle" onClick={fetchDashboardData} style={{ background: colors.cardBg, color: colors.text, border: `1px solid ${colors.border}` }}>
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

            {/* KPI Cards */}
            <div className="row g-3 mb-4">
                {/* 1. All Bookings */}
                <div className="col-sm-6 col-md-3">
                    <div className="stat-card" onClick={() => handleCardClick('/bookings', { tab: 'all' })} style={{ cursor: 'pointer' }}>
                        <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                            <div>
                                <div className="stat-card-label">All Bookings</div>
                                <div className="stat-card-value">{summary?.totalBookings || 0}</div>
                                <div style={{ fontSize: '0.85rem', color: 'var(--vz-text-muted)', marginTop: '4px' }}>
                                    Amount: {formatCurrency(summary?.totalAmount)}
                                </div>
                            </div>
                            <div className="stat-card-icon primary"><BiCalendar /></div>
                        </div>
                    </div>
                </div>
                {/* 2. Today's Bookings & Revenue */}
                <div className="col-sm-6 col-md-3">
                    <div className="stat-card" onClick={() => handleCardClick('/bookings', { tab: 'today' })} style={{ cursor: 'pointer' }}>
                        <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                            <div>
                                <div className="stat-card-label">Today's Revenue</div>
                                <div className="stat-card-value">{formatCurrency(summary?.todaysBookingAmount)}</div>
                                <div style={{ fontSize: '0.85rem', color: 'var(--vz-text-muted)', marginTop: '4px' }}>
                                    Count: {summary?.todaysBookingCount || 0}
                                </div>
                            </div>
                            <div className="stat-card-icon info"><BiStoreAlt /></div>
                        </div>
                    </div>
                </div>
                {/* 3. Solo Bookings */}
                <div className="col-sm-6 col-md-3">
                    <div className="stat-card" onClick={() => handleCardClick('/bookings', { tab: 'solo' })} style={{ cursor: 'pointer' }}>
                        <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                            <div>
                                <div className="stat-card-label">Solo Bookings</div>
                                <div className="stat-card-value">{summary?.soloBookingCount || 0}</div>
                                <div style={{ fontSize: '0.85rem', color: 'var(--vz-text-muted)', marginTop: '4px' }}>
                                    Amount: {formatCurrency(summary?.soloBookingAmount)}
                                </div>
                            </div>
                            <div className="stat-card-icon success"><BiCheckCircle /></div>
                        </div>
                    </div>
                </div>
                {/* 4. Party Plans */}
                <div className="col-sm-6 col-md-3">
                    <div className="stat-card" onClick={() => handleCardClick('/bookings', { tab: 'plan' })} style={{ cursor: 'pointer' }}>
                        <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                            <div>
                                <div className="stat-card-label">Party Plans</div>
                                <div className="stat-card-value">{summary?.partyPlansCount || 0}</div>
                                <div style={{ fontSize: '0.85rem', color: 'var(--vz-text-muted)', marginTop: '4px' }}>
                                    Amount: {formatCurrency(summary?.partyPlansAmount)}
                                </div>
                            </div>
                            <div className="stat-card-icon warning"><BiCalendarEvent /></div>
                        </div>
                    </div>
                </div>
                {/* 5. Party Requests */}
                <div className="col-sm-6 col-md-3">
                    <div className="stat-card" onClick={() => handleCardClick('/party-requests')} style={{ cursor: 'pointer' }}>
                        <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                            <div>
                                <div className="stat-card-label">Party Requests</div>
                                <div className="stat-card-value">{summary?.partyRequestsCount || 0}</div>
                                <div style={{ fontSize: '0.85rem', color: 'var(--vz-text-muted)', marginTop: '4px' }}>
                                    Amount: {formatCurrency(summary?.partyRequestsAmount)}
                                </div>
                            </div>
                            <div className="stat-card-icon danger"><BiParty /></div>
                        </div>
                    </div>
                </div>
                {/* 6. Group Party Booking */}
                <div className="col-sm-6 col-md-3">
                    <div className="stat-card" onClick={() => handleCardClick('/group-parties')} style={{ cursor: 'pointer' }}>
                        <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                            <div>
                                <div className="stat-card-label">Group Party Booking</div>
                                <div className="stat-card-value">{summary?.groupPartyBookingCount || 0}</div>
                                <div style={{ fontSize: '0.85rem', color: 'var(--vz-text-muted)', marginTop: '4px' }}>
                                    Amount: {formatCurrency(summary?.groupPartyBookingAmount)}
                                </div>
                            </div>
                            <div className="stat-card-icon primary"><BiGroup /></div>
                        </div>
                    </div>
                </div>
                {/* 7. Large Parties */}
                <div className="col-sm-6 col-md-3">
                    <div className="stat-card" onClick={() => handleCardClick('/party-requests')} style={{ cursor: 'pointer' }}>
                        <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                            <div>
                                <div className="stat-card-label">Large Parties</div>
                                <div className="stat-card-value">{summary?.largePartiesCount || 0}</div>
                                <div style={{ fontSize: '0.85rem', color: 'var(--vz-text-muted)', marginTop: '4px' }}>
                                    Amount: {formatCurrency(summary?.largePartiesAmount)}
                                </div>
                            </div>
                            <div className="stat-card-icon info"><BiGroup /></div>
                        </div>
                    </div>
                </div>
                {/* 8. Upcoming Night Booking */}
                <div className="col-sm-6 col-md-3">
                    <div className="stat-card" onClick={() => handleCardClick('/bookings', { tab: 'upcoming' })} style={{ cursor: 'pointer' }}>
                        <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                            <div>
                                <div className="stat-card-label">Upcoming Night Booking</div>
                                <div className="stat-card-value">{summary?.upcomingNightBookingCount || 0}</div>
                                <div style={{ fontSize: '0.85rem', color: 'var(--vz-text-muted)', marginTop: '4px' }}>
                                    Amount: {formatCurrency(summary?.upcomingNightBookingAmount)}
                                </div>
                            </div>
                            <div className="stat-card-icon warning"><BiStar /></div>
                        </div>
                    </div>
                </div>
            </div>

            {/* Venue Wise Bookings Chart */}
            <div className="card border-0 shadow-sm" style={{ background: colors.cardBg, borderRadius: '12px' }}>
                <div className="card-header border-0 bg-transparent pt-4 pb-2 px-4">
                    <h5 className="mb-0" style={{ fontWeight: 700, color: colors.text }}>Venue Wise Bookings</h5>
                </div>
                <div className="card-body px-2 pb-4">
                    {venuesData.length > 0 ? (
                        <ReactApexChart 
                            options={chartOptions} 
                            series={chartSeries} 
                            type="bar" 
                            height={350} 
                        />
                    ) : (
                        <div className="text-center py-5 text-muted">
                            No venue booking data available
                        </div>
                    )}
                </div>
            </div>

        </div>
    );
};

export default Dashboard;
