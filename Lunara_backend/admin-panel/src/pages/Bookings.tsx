import React, { useState, useEffect, useCallback } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import toast from 'react-hot-toast';
import {
    BiSearch, BiCalendar, BiGroup, BiCheckCircle,
    BiTimeFive, BiRefresh, BiFilterAlt, BiDetail, BiX,
    BiUser, BiBuilding, BiMoney, BiSend, BiCreditCard
} from 'react-icons/bi';
import bookingsApi, { type Booking } from '../api/bookings';
import venuesApi from '../api/venues';

const getStatusBadgeClass = (status: string) => {
    const map: Record<string, string> = {
        pending: 'bg-warning-subtle text-warning',
        confirmed: 'bg-success-subtle text-success',
        completed: 'bg-info-subtle text-info',
        cancelled: 'bg-danger-subtle text-danger',
        no_show: 'bg-secondary-subtle text-secondary'
    };
    return map[status] || 'bg-light text-dark';
};

const getPaymentStatusBadgeClass = (status: string) => {
    const map: Record<string, string> = {
        pending: 'bg-warning-subtle text-warning',
        partial: 'bg-info-subtle text-info',
        paid: 'bg-success-subtle text-success',
        refunded: 'bg-danger-subtle text-danger'
    };
    return map[status] || 'bg-light text-dark';
};

const formatCurrency = (amount?: number | string) => {
    const num = Number(amount || 0);
    return `₹${num.toLocaleString('en-IN', { minimumFractionDigits: 0, maximumFractionDigits: 2 })}`;
};

const formatDate = (dateStr?: string) => {
    if (!dateStr) return '—';
    return new Date(dateStr).toLocaleDateString('en-IN', {
        day: 'numeric',
        month: 'short',
        year: 'numeric'
    });
};

export const Bookings: React.FC = () => {
    const queryClient = useQueryClient();
    
    // Filter states
    const [activeTab, setActiveTab] = useState<'all' | 'today' | 'solo' | 'plan' | 'party_request' | 'group' | 'large'>('all');
    const [venueIdFilter, setVenueIdFilter] = useState<string>('all');
    const [statusFilter, setStatusFilter] = useState<string>('all');
    const [searchInput, setSearchInput] = useState<string>('');
    const [searchQuery, setSearchQuery] = useState<string>('');
    const [currentPage, setCurrentPage] = useState<number>(1);
    const [autoRefresh, setAutoRefresh] = useState<boolean>(true);
    
    // Modal states
    const [selectedBooking, setSelectedBooking] = useState<Booking | null>(null);
    const [cancelReason, setCancelReason] = useState<string>('');
    const [showCancelConfirm, setShowCancelConfirm] = useState<boolean>(false);
    
    // Large party inputs
    const [paymentLink, setPaymentLink] = useState<string>('');
    const [paymentAmount, setPaymentAmount] = useState<string>('');
    const [showPaymentLinkModal, setShowPaymentLinkModal] = useState<boolean>(false);

    // Fetch venues list for dropdown
    const { data: venuesData } = useQuery({
        queryKey: ['venues-list'],
        queryFn: () => venuesApi.getVenues(),
        staleTime: 60000
    });

    // Build API query parameters
    const getParams = useCallback(() => {
        const params: any = {
            page: currentPage,
            limit: 15,
            search: searchQuery || undefined,
            status: statusFilter === 'all' ? undefined : statusFilter,
            venueId: venueIdFilter === 'all' ? undefined : venueIdFilter
        };

        if (activeTab === 'today') {
            params.date = 'today';
        } else if (activeTab === 'solo') {
            params.goingMode = 'solo';
        } else if (activeTab === 'plan') {
            params.goingMode = 'plan';
        } else if (activeTab === 'party_request') {
            params.goingMode = 'party_request';
        } else if (activeTab === 'group') {
            params.isGroupBooking = true;
        } else if (activeTab === 'large') {
            params.isLargePartyRequest = true;
        }

        return params;
    }, [currentPage, searchQuery, statusFilter, venueIdFilter, activeTab]);

    // Fetch Bookings list with React Query
    const { data: bookingsData, isLoading, isRefetching, refetch } = useQuery({
        queryKey: ['bookings-list', getParams()],
        queryFn: () => bookingsApi.getBookings(getParams()),
        refetchInterval: autoRefresh ? 10000 : false, // Auto refresh every 10 seconds if enabled
        placeholderData: (prev) => prev
    });

    // Fetch Stats
    const { data: statsData, refetch: refetchStats } = useQuery({
        queryKey: ['bookings-stats'],
        queryFn: () => bookingsApi.getBookingStats(),
        refetchInterval: autoRefresh ? 15000 : false
    });

    // Action Mutations
    const confirmMutation = useMutation({
        mutationFn: (id: string) => bookingsApi.confirmBooking(id),
        onSuccess: (res) => {
            if (res.success) {
                toast.success('Booking confirmed successfully!');
                queryClient.invalidateQueries({ queryKey: ['bookings-list'] });
                queryClient.invalidateQueries({ queryKey: ['bookings-stats'] });
                if (selectedBooking) {
                    setSelectedBooking(prev => prev ? { ...prev, status: 'confirmed' } : null);
                }
            } else {
                toast.error('Failed to confirm booking');
            }
        },
        onError: (err: any) => {
            toast.error(err.response?.data?.message || 'Error confirming booking');
        }
    });

    const cancelMutation = useMutation({
        mutationFn: ({ id, reason }: { id: string; reason: string }) => bookingsApi.cancelBooking(id, reason),
        onSuccess: (res) => {
            if (res.success) {
                toast.success('Booking cancelled successfully!');
                setShowCancelConfirm(false);
                setCancelReason('');
                queryClient.invalidateQueries({ queryKey: ['bookings-list'] });
                queryClient.invalidateQueries({ queryKey: ['bookings-stats'] });
                if (selectedBooking) {
                    setSelectedBooking(prev => prev ? { ...prev, status: 'cancelled' } : null);
                }
            } else {
                toast.error('Failed to cancel booking');
            }
        },
        onError: (err: any) => {
            toast.error(err.response?.data?.message || 'Error cancelling booking');
        }
    });

    const completeMutation = useMutation({
        mutationFn: (id: string) => bookingsApi.markCompleted(id),
        onSuccess: (res) => {
            if (res.success) {
                toast.success('Booking marked as completed!');
                queryClient.invalidateQueries({ queryKey: ['bookings-list'] });
                if (selectedBooking) {
                    setSelectedBooking(prev => prev ? { ...prev, status: 'completed' } : null);
                }
            } else {
                toast.error('Failed to mark completed');
            }
        },
        onError: (err: any) => {
            toast.error(err.response?.data?.message || 'Error updating status');
        }
    });

    const noShowMutation = useMutation({
        mutationFn: (id: string) => bookingsApi.markNoShow(id),
        onSuccess: (res) => {
            if (res.success) {
                toast.success('Booking marked as No Show!');
                queryClient.invalidateQueries({ queryKey: ['bookings-list'] });
                queryClient.invalidateQueries({ queryKey: ['bookings-stats'] });
                if (selectedBooking) {
                    setSelectedBooking(prev => prev ? { ...prev, status: 'no_show' } : null);
                }
            } else {
                toast.error('Failed to mark No Show');
            }
        },
        onError: (err: any) => {
            toast.error(err.response?.data?.message || 'Error updating status');
        }
    });

    // Large party payment mutations
    const sendPaymentLinkMutation = useMutation({
        mutationFn: ({ id, link, amt }: { id: string; link: string; amt: number }) =>
            bookingsApi.sendPaymentLink(id, link, amt),
        onSuccess: (res) => {
            if (res.success) {
                toast.success('Payment link sent to customer!');
                setShowPaymentLinkModal(false);
                setPaymentLink('');
                setPaymentAmount('');
                queryClient.invalidateQueries({ queryKey: ['bookings-list'] });
                if (selectedBooking) {
                    setSelectedBooking(res.data);
                }
            } else {
                toast.error('Failed to send payment link');
            }
        },
        onError: (err: any) => {
            toast.error(err.response?.data?.message || 'Error sending payment link');
        }
    });

    const markPaidMutation = useMutation({
        mutationFn: (id: string) => bookingsApi.markPaymentDone(id),
        onSuccess: (res) => {
            if (res.success) {
                toast.success('Payment marked as done successfully!');
                queryClient.invalidateQueries({ queryKey: ['bookings-list'] });
                queryClient.invalidateQueries({ queryKey: ['bookings-stats'] });
                if (selectedBooking) {
                    setSelectedBooking(res.data);
                }
            } else {
                toast.error('Failed to mark payment done');
            }
        },
        onError: (err: any) => {
            toast.error(err.response?.data?.message || 'Error marking payment done');
        }
    });

    // Reset pagination when filter changes
    useEffect(() => {
        setCurrentPage(1);
    }, [activeTab, venueIdFilter, statusFilter, searchQuery]);

    const handleSearchSubmit = (e: React.FormEvent) => {
        e.preventDefault();
        setSearchQuery(searchInput);
    };

    const handleClearFilters = () => {
        setSearchInput('');
        setSearchQuery('');
        setVenueIdFilter('all');
        setStatusFilter('all');
        setActiveTab('all');
    };

    const bookings: Booking[] = bookingsData?.data?.bookings || [];
    const pagination = bookingsData?.data?.pagination || { page: 1, limit: 15, total: 0, totalPages: 1 };
    const stats = statsData?.data || { totalBookings: 0, pendingBookings: 0, confirmedBookings: 0, totalRevenue: 0 };
    const venues = venuesData?.venues || [];

    const handleManualRefresh = () => {
        refetch();
        refetchStats();
        toast.success('Data refreshed');
    };

    return (
        <div>
            {/* Header / Stats Summary */}
            <div className="row g-3 mb-4">
                {[
                    { label: 'Total Bookings', value: stats.totalBookings, icon: <BiCalendar />, cls: 'primary' },
                    { label: 'Confirmed Bookings', value: stats.confirmedBookings, icon: <BiCheckCircle />, cls: 'success' },
                    { label: 'Pending Approval', value: stats.pendingBookings, icon: <BiTimeFive />, cls: 'warning' },
                    { label: 'Total Revenue', value: formatCurrency(stats.totalRevenue), icon: <BiCreditCard />, cls: 'info' }
                ].map((s, i) => (
                    <div className="col-sm-6 col-xl-3" key={s.label}>
                        <div className={`stat-card animate-in animate-in-${i + 1}`}>
                            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                                <div>
                                    <div className="stat-card-label">{s.label}</div>
                                    <div className="stat-card-value">{s.value}</div>
                                </div>
                                <div className={`stat-card-icon ${s.cls}`}>{s.icon}</div>
                            </div>
                        </div>
                    </div>
                ))}
            </div>

            {/* Filter Toolbar */}
            <div className="vz-card mb-4 animate-in animate-in-5">
                <div className="vz-card-body" style={{ padding: '1rem 1.25rem' }}>
                    <form onSubmit={handleSearchSubmit} style={{ display: 'flex', flexWrap: 'wrap', gap: '0.75rem', alignItems: 'center', justifyContent: 'space-between' }}>
                        <div style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap', alignItems: 'center', flex: 1 }}>
                            {/* Search */}
                            <div style={{ position: 'relative', minWidth: 200, flex: '1 1 200px' }}>
                                <BiSearch style={{ position: 'absolute', left: '0.75rem', top: '50%', transform: 'translateY(-50%)', color: 'var(--vz-text-muted)' }} />
                                <input
                                    className="vz-form-control"
                                    placeholder="Search bk-number, user name, email..."
                                    value={searchInput}
                                    onChange={(e) => setSearchInput(e.target.value)}
                                    style={{ paddingLeft: '2.25rem', width: '100%' }}
                                />
                            </div>

                            {/* Venue filter */}
                            <select
                                className="vz-form-control"
                                value={venueIdFilter}
                                onChange={(e) => setVenueIdFilter(e.target.value)}
                                style={{ minWidth: 160 }}
                            >
                                <option value="all">🏢 All Venues</option>
                                {venues.map((v) => (
                                    <option key={v.id} value={v.id}>{v.name} ({v.city})</option>
                                ))}
                            </select>

                            {/* Status filter */}
                            <select
                                className="vz-form-control"
                                value={statusFilter}
                                onChange={(e) => setStatusFilter(e.target.value)}
                                style={{ minWidth: 130 }}
                            >
                                <option value="all">⚡ All Statuses</option>
                                <option value="pending">Pending</option>
                                <option value="confirmed">Confirmed</option>
                                <option value="completed">Completed</option>
                                <option value="cancelled">Cancelled</option>
                                <option value="no_show">No Show</option>
                            </select>

                            <button type="submit" className="btn btn-primary btn-sm">
                                <BiFilterAlt style={{ marginRight: 4 }} /> Filter
                            </button>

                            {(searchQuery || venueIdFilter !== 'all' || statusFilter !== 'all' || activeTab !== 'all') && (
                                <button type="button" className="btn btn-outline-secondary btn-sm" onClick={handleClearFilters}>
                                    Clear
                                </button>
                            )}
                        </div>

                        {/* Live Auto Refresh Control */}
                        <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
                            <div style={{ display: 'flex', alignItems: 'center', gap: '0.4rem', fontSize: '0.8rem', color: 'var(--vz-text-muted)' }}>
                                <span style={{
                                    display: 'inline-block',
                                    width: 8,
                                    height: 8,
                                    borderRadius: '50%',
                                    background: autoRefresh ? '#10b981' : '#cbd5e1',
                                    animation: autoRefresh ? 'pulse 1.5s infinite' : 'none'
                                }} />
                                <label style={{ userSelect: 'none', cursor: 'pointer' }}>
                                    <input
                                        type="checkbox"
                                        checked={autoRefresh}
                                        onChange={(e) => setAutoRefresh(e.target.checked)}
                                        style={{ marginRight: 4, verticalAlign: 'middle' }}
                                    />
                                    Live Updates
                                </label>
                            </div>
                            <button
                                type="button"
                                onClick={handleManualRefresh}
                                className={`btn-icon ${isRefetching ? 'spin' : ''}`}
                                style={{ padding: 6, borderRadius: '50%', border: '1px solid var(--vz-border-color)', background: 'transparent' }}
                                title="Force Refresh"
                            >
                                <BiRefresh size={18} />
                            </button>
                        </div>
                    </form>
                </div>
            </div>

            {/* Tabs Row */}
            <div style={{ display: 'flex', gap: '0.5rem', marginBottom: '1.25rem', borderBottom: '2px solid var(--vz-border-color)', overflowX: 'auto', WebkitOverflowScrolling: 'touch' }}>
                {[
                    { key: 'all', label: 'All Bookings' },
                    { key: 'today', label: '📅 Today' },
                    { key: 'solo', label: '👤 Solo' },
                    { key: 'plan', label: '⚡ Party Plans' },
                    { key: 'party_request', label: '🤝 Party Requests' },
                    { key: 'group', label: '👥 Group Bookings' },
                    { key: 'large', label: '⭐ Large Parties' }
                ].map(t => (
                    <button
                        key={t.key}
                        onClick={() => setActiveTab(t.key as any)}
                        style={{
                            padding: '0.6rem 1.1rem',
                            border: 'none',
                            background: 'none',
                            cursor: 'pointer',
                            fontWeight: activeTab === t.key ? 700 : 400,
                            color: activeTab === t.key ? '#7c3aed' : 'var(--vz-text-muted)',
                            borderBottom: activeTab === t.key ? '3px solid #7c3aed' : '3px solid transparent',
                            marginBottom: '-2px',
                            fontSize: '0.875rem',
                            whiteSpace: 'nowrap',
                            transition: 'all 0.15s'
                        }}
                    >
                        {t.label}
                    </button>
                ))}
            </div>

            {/* Bookings Table / Content */}
            <div className="vz-card animate-in animate-in-6" style={{ minHeight: 300 }}>
                <div className="vz-card-body" style={{ padding: 0 }}>
                    {isLoading ? (
                        <div style={{ padding: '4rem', textAlign: 'center', color: 'var(--vz-text-muted)' }}>
                            <div className="spinner-border spinner-border-sm" style={{ marginRight: 8, color: '#7c3aed' }} />
                            Fetching bookings data…
                        </div>
                    ) : bookings.length === 0 ? (
                        <div style={{ padding: '5rem', textAlign: 'center', color: 'var(--vz-text-muted)' }}>
                            <div style={{ fontSize: '3rem', marginBottom: '1rem' }}>📅</div>
                            <div style={{ fontWeight: 600 }}>No bookings found</div>
                            <div style={{ fontSize: '0.85rem' }}>No bookings matching your current filter criteria were found.</div>
                        </div>
                    ) : (
                        <div className="vz-table-wrapper">
                            <table className="vz-table">
                                <thead>
                                    <tr>
                                        <th>Booking ID</th>
                                        <th>Customer</th>
                                        <th>Venue</th>
                                        <th>Date & Slot</th>
                                        <th>Mode</th>
                                        <th>Guests</th>
                                        <th>Total Amt</th>
                                        <th>Status</th>
                                        <th>Payment</th>
                                        <th style={{ width: 80, textAlign: 'center' }}>Action</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    {bookings.map((booking) => (
                                        <tr key={booking.id}>
                                            <td style={{ fontWeight: 600, color: 'var(--vz-primary)' }}>
                                                {booking.bookingNumber || booking.id.substring(0, 8).toUpperCase()}
                                            </td>
                                            <td>
                                                <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                                                    {booking.customer?.profileImageUrl ? (
                                                        <img
                                                            src={booking.customer.profileImageUrl}
                                                            alt="avatar"
                                                            style={{ width: 28, height: 28, borderRadius: '50%', objectFit: 'cover' }}
                                                        />
                                                    ) : (
                                                        <div style={{ width: 28, height: 28, borderRadius: '50%', background: 'rgba(124,58,237,0.1)', color: '#7c3aed', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: '0.75rem', fontWeight: 700 }}>
                                                            {booking.customer?.firstName?.charAt(0) || 'U'}
                                                        </div>
                                                    )}
                                                    <div>
                                                        <div style={{ fontWeight: 500, fontSize: '0.85rem' }}>{booking.customer?.firstName} {booking.customer?.lastName}</div>
                                                        <div style={{ fontSize: '0.7rem', color: 'var(--vz-text-muted)' }}>{booking.customer?.phone}</div>
                                                    </div>
                                                </div>
                                            </td>
                                            <td>
                                                <div>
                                                    <div style={{ fontWeight: 500, fontSize: '0.82rem' }}>{booking.venue?.name || 'Unknown'}</div>
                                                    <div style={{ fontSize: '0.7rem', color: 'var(--vz-text-muted)' }}>{booking.venue?.city} · {booking.venue?.category}</div>
                                                </div>
                                            </td>
                                            <td>
                                                <div style={{ fontSize: '0.82rem' }}>
                                                    {formatDate(booking.bookingDate)}
                                                </div>
                                                <div style={{ fontSize: '0.72rem', color: 'var(--vz-text-muted)' }}>
                                                    🕒 {booking.timeSlot || booking.startTime}
                                                </div>
                                            </td>
                                            <td>
                                                {booking.isLargePartyRequest ? (
                                                    <span className="badge bg-danger-subtle text-danger" style={{ fontSize: '0.7rem' }}>⭐ Large Party</span>
                                                ) : booking.isGroupBooking ? (
                                                    <span className="badge bg-primary-subtle text-primary" style={{ fontSize: '0.7rem' }}>👥 Group</span>
                                                ) : (
                                                    <span className="badge bg-info-subtle text-info" style={{ fontSize: '0.7rem', textTransform: 'capitalize' }}>
                                                        {booking.goingMode || 'Solo'}
                                                    </span>
                                                )}
                                            </td>
                                            <td>
                                                <div style={{ display: 'flex', alignItems: 'center', gap: '0.25rem', fontSize: '0.82rem' }}>
                                                    <BiGroup style={{ color: 'var(--vz-text-muted)' }} /> {booking.partySize || booking.numberOfGuests}
                                                </div>
                                            </td>
                                            <td style={{ fontWeight: 600, fontSize: '0.82rem' }}>
                                                {formatCurrency(booking.totalAmount)}
                                            </td>
                                            <td>
                                                <span className={`badge ${getStatusBadgeClass(booking.status)}`} style={{ textTransform: 'capitalize' }}>
                                                    {booking.status.replace('_', ' ')}
                                                </span>
                                            </td>
                                            <td>
                                                <span className={`badge ${getPaymentStatusBadgeClass(booking.paymentStatus)}`} style={{ textTransform: 'capitalize' }}>
                                                    {booking.paymentStatus}
                                                </span>
                                            </td>
                                            <td style={{ textAlign: 'center' }}>
                                                <button
                                                    onClick={() => setSelectedBooking(booking)}
                                                    className="btn btn-sm btn-outline-primary"
                                                    style={{ padding: '0.25rem 0.5rem' }}
                                                >
                                                    <BiDetail size={16} />
                                                </button>
                                            </td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        </div>
                    )}
                </div>

                {/* Pagination */}
                {!isLoading && pagination.totalPages > 1 && (
                    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '12px 20px', borderTop: '1px solid var(--vz-border-color)' }}>
                        <span style={{ fontSize: '0.8rem', color: 'var(--vz-text-muted)' }}>
                            Showing page {pagination.page} of {pagination.totalPages} ({pagination.total} total bookings)
                        </span>
                        <div style={{ display: 'flex', gap: 6 }}>
                            <button
                                className="btn btn-sm btn-outline-secondary"
                                disabled={pagination.page <= 1}
                                onClick={() => setCurrentPage(p => p - 1)}
                            >
                                ← Previous
                            </button>
                            <button
                                className="btn btn-sm btn-outline-secondary"
                                disabled={pagination.page >= pagination.totalPages}
                                onClick={() => setCurrentPage(p => p + 1)}
                            >
                                Next →
                            </button>
                        </div>
                    </div>
                )}
            </div>

            {/* Details Modal */}
            {selectedBooking && (
                <div className="modal-overlay" onClick={() => setSelectedBooking(null)} style={{ zIndex: 9999 }}>
                    <div className="modal-container" onClick={e => e.stopPropagation()} style={{ maxWidth: 700, maxHeight: '90vh', overflowY: 'auto' }}>
                        {/* Header */}
                        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '1.25rem' }}>
                            <h3 style={{ margin: 0, fontSize: '1.2rem', fontWeight: 700, display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                                📋 Booking Details
                                <span style={{ fontSize: '0.8rem', padding: '0.15rem 0.6rem', borderRadius: 20 }} className={`badge ${getStatusBadgeClass(selectedBooking.status)}`}>
                                    {selectedBooking.status.replace('_', ' ').toUpperCase()}
                                </span>
                            </h3>
                            <button className="btn-icon" onClick={() => setSelectedBooking(null)}>
                                <BiX size={24} />
                            </button>
                        </div>

                        {/* Booking Code Banner */}
                        <div style={{ background: 'var(--vz-light)', borderRadius: 10, padding: '1rem', marginBottom: '1.25rem', display: 'flex', flexWrap: 'wrap', gap: '1.5rem', justifyContent: 'space-between' }}>
                            <div>
                                <span style={{ fontSize: '0.72rem', color: 'var(--vz-text-muted)', display: 'block' }}>BOOKING NUMBER</span>
                                <span style={{ fontWeight: 700, color: 'var(--vz-primary)', fontFamily: 'monospace', fontSize: '1rem' }}>
                                    {selectedBooking.bookingNumber || selectedBooking.id.toUpperCase()}
                                </span>
                            </div>
                            {selectedBooking.ticketCode && (
                                <div>
                                    <span style={{ fontSize: '0.72rem', color: 'var(--vz-text-muted)', display: 'block' }}>TICKET CODE</span>
                                    <span style={{ fontWeight: 700, color: 'var(--vz-success)', fontFamily: 'monospace', fontSize: '1rem' }}>
                                        {selectedBooking.ticketCode}
                                    </span>
                                </div>
                            )}
                            <div>
                                <span style={{ fontSize: '0.72rem', color: 'var(--vz-text-muted)', display: 'block' }}>BOOKING DATE & TIME</span>
                                <span style={{ fontWeight: 600, fontSize: '0.9rem' }}>
                                    {formatDate(selectedBooking.bookingDate)} · {selectedBooking.timeSlot || selectedBooking.startTime}
                                </span>
                            </div>
                        </div>

                        {/* Grid info */}
                        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))', gap: '1rem', marginBottom: '1.25rem' }}>
                            {/* Customer Profile */}
                            <div className="card" style={{ padding: '1rem', border: '1px solid var(--vz-border-color)' }}>
                                <h4 style={{ fontSize: '0.85rem', fontWeight: 700, color: 'var(--vz-text-muted)', textTransform: 'uppercase', marginBottom: '0.75rem', display: 'flex', alignItems: 'center', gap: '0.4rem' }}>
                                    <BiUser /> Customer Info
                                </h4>
                                <div style={{ display: 'flex', gap: '0.75rem', alignItems: 'center', marginBottom: '0.75rem' }}>
                                    {selectedBooking.customer?.profileImageUrl ? (
                                        <img
                                            src={selectedBooking.customer.profileImageUrl}
                                            alt="Customer"
                                            style={{ width: 44, height: 44, borderRadius: '50%', objectFit: 'cover' }}
                                        />
                                    ) : (
                                        <div style={{ width: 44, height: 44, borderRadius: '50%', background: 'rgba(124,58,237,0.1)', color: '#7c3aed', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: '1rem', fontWeight: 700 }}>
                                            {selectedBooking.customer?.firstName?.charAt(0) || 'U'}
                                        </div>
                                    )}
                                    <div>
                                        <div style={{ fontWeight: 600 }}>{selectedBooking.customer?.firstName} {selectedBooking.customer?.lastName}</div>
                                        <div style={{ fontSize: '0.78rem', color: 'var(--vz-text-muted)' }}>{selectedBooking.customer?.email}</div>
                                    </div>
                                </div>
                                <div style={{ fontSize: '0.82rem', color: 'var(--vz-text-muted)' }}>
                                    <div>📞 Phone: <b>{selectedBooking.customer?.phone || '—'}</b></div>
                                    {selectedBooking.mobileNumber && (
                                        <div>📱 Alternate Contact: <b>{selectedBooking.mobileNumber}</b></div>
                                    )}
                                </div>
                            </div>

                            {/* Venue details */}
                            <div className="card" style={{ padding: '1rem', border: '1px solid var(--vz-border-color)' }}>
                                <h4 style={{ fontSize: '0.85rem', fontWeight: 700, color: 'var(--vz-text-muted)', textTransform: 'uppercase', marginBottom: '0.75rem', display: 'flex', alignItems: 'center', gap: '0.4rem' }}>
                                    <BiBuilding /> Venue Info
                                </h4>
                                <div style={{ fontWeight: 600, fontSize: '0.9rem', marginBottom: '0.25rem' }}>
                                    {selectedBooking.venue?.name}
                                </div>
                                <div style={{ fontSize: '0.82rem', color: 'var(--vz-text-muted)', marginBottom: '0.5rem' }}>
                                    📍 Category: {selectedBooking.venue?.category} · City: {selectedBooking.venue?.city}
                                </div>
                                <div style={{ fontSize: '0.82rem' }}>
                                    👥 Party Size: <b>{selectedBooking.partySize || selectedBooking.numberOfGuests} guests</b>
                                    {selectedBooking.tablePackage && (
                                        <div style={{ marginTop: 2 }}>📦 Package: <span className="badge bg-secondary-subtle text-secondary">{selectedBooking.tablePackage}</span></div>
                                    )}
                                </div>
                            </div>
                        </div>

                        {/* Payment / Price breakdown */}
                        <div className="card" style={{ padding: '1rem', border: '1px solid var(--vz-border-color)', marginBottom: '1.25rem' }}>
                            <h4 style={{ fontSize: '0.85rem', fontWeight: 700, color: 'var(--vz-text-muted)', textTransform: 'uppercase', marginBottom: '0.75rem', display: 'flex', alignItems: 'center', gap: '0.4rem' }}>
                                <BiMoney /> Payment details
                            </h4>
                            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(130px, 1fr))', gap: '0.75rem', fontSize: '0.82rem' }}>
                                <div>
                                    <span style={{ color: 'var(--vz-text-muted)' }}>Payment Status:</span>
                                    <div style={{ marginTop: 2 }}>
                                        <span className={`badge ${getPaymentStatusBadgeClass(selectedBooking.paymentStatus)}`}>
                                            {selectedBooking.paymentStatus.toUpperCase()}
                                        </span>
                                    </div>
                                </div>
                                <div>
                                    <span style={{ color: 'var(--vz-text-muted)' }}>Payment Mode:</span>
                                    <div style={{ fontWeight: 600, marginTop: 2 }}>
                                        {selectedBooking.paymentMode ? selectedBooking.paymentMode.replace('_', ' ').toUpperCase() : 'STANDARD'}
                                    </div>
                                </div>
                                <div>
                                    <span style={{ color: 'var(--vz-text-muted)' }}>Total Bill Amount:</span>
                                    <div style={{ fontWeight: 700, fontSize: '0.95rem', color: 'var(--vz-text-primary)', marginTop: 2 }}>
                                        {formatCurrency(selectedBooking.totalAmount)}
                                    </div>
                                </div>
                                <div>
                                    <span style={{ color: 'var(--vz-text-muted)' }}>Deposit Paid:</span>
                                    <div style={{ fontWeight: 600, color: 'var(--vz-success)', marginTop: 2 }}>
                                        {formatCurrency(selectedBooking.depositAmount)}
                                    </div>
                                </div>
                                {selectedBooking.commissionAmount !== undefined && (
                                    <div>
                                        <span style={{ color: 'var(--vz-text-muted)' }}>Platform Commission:</span>
                                        <div style={{ fontWeight: 600, color: 'var(--vz-primary)', marginTop: 2 }}>
                                            {formatCurrency(selectedBooking.commissionAmount)}
                                        </div>
                                    </div>
                                )}
                            </div>

                            {/* Payment links for Large Parties */}
                            {selectedBooking.isLargePartyRequest && (
                                <div style={{ borderTop: '1px dashed var(--vz-border-color)', marginTop: '1rem', paddingTop: '1rem' }}>
                                    <span style={{ fontSize: '0.78rem', color: 'var(--vz-text-muted)', display: 'block' }}>Large Party Admin Status:</span>
                                    <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'center', marginTop: 4, flexWrap: 'wrap' }}>
                                        <span className="badge bg-light text-dark" style={{ textTransform: 'uppercase' }}>
                                            Approval status: {selectedBooking.adminApprovalStatus || 'pending'}
                                        </span>
                                        {selectedBooking.adminPaymentLink && (
                                            <a href={selectedBooking.adminPaymentLink} target="_blank" rel="noopener noreferrer" className="btn btn-link btn-sm" style={{ padding: 0 }}>
                                                🔗 User Payment Link (₹{selectedBooking.adminPaymentAmount})
                                            </a>
                                        )}
                                    </div>
                                </div>
                            )}
                        </div>

                        {/* Special Requests / Metadata */}
                        {selectedBooking.specialRequests && (
                            <div className="card" style={{ padding: '1rem', border: '1px solid var(--vz-border-color)', marginBottom: '1.25rem', background: 'var(--vz-light)' }}>
                                <span style={{ fontSize: '0.75rem', fontWeight: 700, color: 'var(--vz-text-muted)', display: 'block', marginBottom: '0.4rem' }}>SPECIAL REQUESTS / METADATA</span>
                                <div style={{ fontSize: '0.8rem', color: 'var(--vz-text-muted)', whiteSpace: 'pre-wrap' }}>
                                    {(() => {
                                        try {
                                            const obj = JSON.parse(selectedBooking.specialRequests || '{}');
                                            return (
                                                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: '0.5rem' }}>
                                                    {Object.entries(obj).map(([k, v]) => (
                                                        <div key={k}>
                                                            <b style={{ textTransform: 'capitalize' }}>{k.replace(/([A-Z])/g, ' $1')}: </b>
                                                            <span>{String(v)}</span>
                                                        </div>
                                                    ))}
                                                </div>
                                            );
                                        } catch (_) {
                                            return selectedBooking.specialRequests;
                                        }
                                    })()}
                                </div>
                            </div>
                        )}

                        {/* Large Party Action forms */}
                        {showPaymentLinkModal && (
                            <div style={{ border: '1px solid #7c3aed', borderRadius: 10, padding: '1rem', marginBottom: '1.25rem', background: 'rgba(124,58,237,0.03)' }}>
                                <h4 style={{ fontSize: '0.85rem', fontWeight: 700, color: '#7c3aed', marginBottom: '0.75rem' }}>Send Custom Payment Link</h4>
                                <div style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap', marginBottom: '0.5rem' }}>
                                    <div style={{ flex: 2 }}>
                                        <input
                                            className="vz-form-control"
                                            placeholder="https://rzp.io/i/..."
                                            value={paymentLink}
                                            onChange={e => setPaymentLink(e.target.value)}
                                        />
                                    </div>
                                    <div style={{ flex: 1 }}>
                                        <input
                                            type="number"
                                            className="vz-form-control"
                                            placeholder="Amount (₹)"
                                            value={paymentAmount}
                                            onChange={e => setPaymentAmount(e.target.value)}
                                        />
                                    </div>
                                    <button
                                        type="button"
                                        className="btn btn-primary"
                                        onClick={() => {
                                            if (!paymentLink || !paymentAmount) {
                                                toast.error('Both payment link and amount are required');
                                                return;
                                            }
                                            sendPaymentLinkMutation.mutate({
                                                id: selectedBooking.id,
                                                link: paymentLink,
                                                amt: Number(paymentAmount)
                                            });
                                        }}
                                        disabled={sendPaymentLinkMutation.isPending}
                                    >
                                        Send
                                    </button>
                                    <button type="button" className="btn btn-outline-secondary" onClick={() => setShowPaymentLinkModal(false)}>
                                        Cancel
                                    </button>
                                </div>
                            </div>
                        )}

                        {/* Cancel Confirmation input */}
                        {showCancelConfirm && (
                            <div style={{ border: '1px solid #ef4444', borderRadius: 10, padding: '1rem', marginBottom: '1.25rem', background: 'rgba(239,68,68,0.03)' }}>
                                <h4 style={{ fontSize: '0.85rem', fontWeight: 700, color: '#ef4444', marginBottom: '0.5rem' }}>Reason for cancellation</h4>
                                <textarea
                                    className="vz-form-control"
                                    rows={2}
                                    placeholder="Enter cancellation reason..."
                                    value={cancelReason}
                                    onChange={e => setCancelReason(e.target.value)}
                                    style={{ width: '100%', marginBottom: '0.5rem' }}
                                />
                                <div style={{ display: 'flex', gap: '0.5rem' }}>
                                    <button
                                        className="btn btn-danger btn-sm"
                                        onClick={() => {
                                            if (!cancelReason.trim()) {
                                                toast.error('Cancellation reason is required');
                                                return;
                                            }
                                            cancelMutation.mutate({ id: selectedBooking.id, reason: cancelReason });
                                        }}
                                        disabled={cancelMutation.isPending}
                                    >
                                        Confirm Cancellation
                                    </button>
                                    <button className="btn btn-outline-secondary btn-sm" onClick={() => setShowCancelConfirm(false)}>
                                        Cancel
                                    </button>
                                </div>
                            </div>
                        )}

                        {/* Modal Action Buttons */}
                        <div style={{ display: 'flex', gap: '0.5rem', justifyContent: 'flex-end', flexWrap: 'wrap' }}>
                            {/* Standard Confirm */}
                            {selectedBooking.status === 'pending' && !selectedBooking.isLargePartyRequest && (
                                <button
                                    className="btn btn-success"
                                    onClick={() => confirmMutation.mutate(selectedBooking.id)}
                                    disabled={confirmMutation.isPending}
                                >
                                    ✓ Confirm Booking
                                </button>
                            )}

                            {/* Large Party Approval/Rejection */}
                            {selectedBooking.isLargePartyRequest && selectedBooking.adminApprovalStatus === 'pending' && (
                                <>
                                    <button
                                        className="btn btn-success"
                                        onClick={() => {
                                            const amtStr = window.prompt('Enter total amount (₹) for approval:');
                                            if (amtStr === null) return;
                                            const amt = Number(amtStr);
                                            if (isNaN(amt) || amt <= 0) {
                                                toast.error('Please enter a valid amount');
                                                return;
                                            }
                                            bookingsApi.approveLargePartyRequest(selectedBooking.id, 'approved', amt)
                                                .then((res: any) => {
                                                    if (res.success) {
                                                        toast.success('Large party request approved!');
                                                        setSelectedBooking(res.data);
                                                        queryClient.invalidateQueries({ queryKey: ['bookings-list'] });
                                                    }
                                                });
                                        }}
                                    >
                                        ✓ Approve Request
                                    </button>
                                    <button
                                        className="btn btn-danger"
                                        onClick={() => {
                                            if (!window.confirm('Reject this request?')) return;
                                            bookingsApi.approveLargePartyRequest(selectedBooking.id, 'rejected')
                                                .then((res: any) => {
                                                    if (res.success) {
                                                        toast.success('Large party request rejected');
                                                        setSelectedBooking(res.data);
                                                        queryClient.invalidateQueries({ queryKey: ['bookings-list'] });
                                                    }
                                                });
                                        }}
                                    >
                                        Reject Request
                                    </button>
                                </>
                            )}

                            {/* Large Party Payment Send link action */}
                            {selectedBooking.isLargePartyRequest && selectedBooking.adminApprovalStatus === 'approved' && (
                                <button className="btn btn-primary" onClick={() => setShowPaymentLinkModal(true)}>
                                    <BiSend style={{ marginRight: 4 }} /> Send Payment Link
                                </button>
                            )}

                            {/* Large Party Mark Paid action */}
                            {selectedBooking.isLargePartyRequest && selectedBooking.adminApprovalStatus === 'payment_sent' && (
                                <button
                                    className="btn btn-warning"
                                    onClick={() => {
                                        if (window.confirm('Mark this large party request payment as PAID?')) {
                                            markPaidMutation.mutate(selectedBooking.id);
                                        }
                                    }}
                                    disabled={markPaidMutation.isPending}
                                >
                                    ✓ Mark Payment Done
                                </button>
                            )}

                            {/* Complete / No Show actions */}
                            {selectedBooking.status === 'confirmed' && (
                                <>
                                    <button
                                        className="btn btn-info"
                                        onClick={() => completeMutation.mutate(selectedBooking.id)}
                                        disabled={completeMutation.isPending}
                                    >
                                        ✓ Mark Completed
                                    </button>
                                    <button
                                        className="btn btn-warning"
                                        onClick={() => noShowMutation.mutate(selectedBooking.id)}
                                        disabled={noShowMutation.isPending}
                                    >
                                        ⚠ Mark No Show
                                    </button>
                                </>
                            )}

                            {/* Cancel trigger */}
                            {['pending', 'confirmed'].includes(selectedBooking.status) && !showCancelConfirm && (
                                <button className="btn btn-danger" onClick={() => setShowCancelConfirm(true)}>
                                    Cancel Booking
                                </button>
                            )}

                            <button className="btn btn-outline-secondary" onClick={() => setSelectedBooking(null)}>
                                Close
                             </button>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
};

export default Bookings;
