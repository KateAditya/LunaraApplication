import React, { useState, useEffect, useCallback } from 'react';
import Chart from 'react-apexcharts';
import type { ApexOptions } from 'apexcharts';
import {
    BiX,
    BiTrendingUp,
    BiRefresh,
    BiDownload,
    BiSearch,
    BiArrowBack,
    BiBarChartAlt2,
} from 'react-icons/bi';
import toast from 'react-hot-toast';
import bookingsApi from '../api/bookings';
import { useThemeMode } from '../context/ThemeContext';

interface Props {
    venueId: string;
    venueName?: string;
    onClose: () => void;
}

export const VenueRevenueDetailsModal: React.FC<Props> = ({ venueId, venueName, onClose }) => {
    const { mode } = useThemeMode();
    const isDark = mode === 'dark';

    const [loading, setLoading] = useState(true);
    const [data, setData] = useState<any>(null);

    // Filter controls
    const [period, setPeriod] = useState<'daily' | 'weekly' | 'monthly' | 'yearly' | 'custom'>('monthly');
    const [fromDate, setFromDate] = useState('');
    const [toDate, setToDate] = useState('');
    const [statusFilter, setStatusFilter] = useState('all');
    const [searchQuery, setSearchQuery] = useState('');
    const [searchInput, setSearchInput] = useState('');

    // Pagination for records
    const [page, setPage] = useState(1);

    const fetchRevenueDetails = useCallback(async () => {
        if (!venueId) return;
        setLoading(true);
        try {
            const res = await bookingsApi.getVenueRevenueDetails({
                venueId,
                period,
                fromDate: period === 'custom' || fromDate ? fromDate : undefined,
                toDate: period === 'custom' || toDate ? toDate : undefined,
                status: statusFilter === 'all' ? undefined : statusFilter,
                search: searchQuery || undefined,
                page,
                limit: 10
            });

            if (res.success) {
                setData(res.data);
            } else {
                toast.error('Failed to load venue revenue details');
            }
        } catch (err: any) {
            console.error('fetchRevenueDetails error:', err);
            toast.error('Failed to load venue revenue details');
        } finally {
            setLoading(false);
        }
    }, [venueId, period, fromDate, toDate, statusFilter, searchQuery, page]);

    useEffect(() => {
        fetchRevenueDetails();
    }, [fetchRevenueDetails]);

    const formatCurrency = (val: number | string) => {
        return `₹${Number(val || 0).toLocaleString('en-IN', { minimumFractionDigits: 0, maximumFractionDigits: 2 })}`;
    };

    const handleSearch = (e: React.FormEvent) => {
        e.preventDefault();
        setSearchQuery(searchInput);
        setPage(1);
    };

    const handlePeriodChange = (newPeriod: 'daily' | 'weekly' | 'monthly' | 'yearly' | 'custom') => {
        setPeriod(newPeriod);
        setPage(1);
    };

    const handleExportCSV = () => {
        if (!data || !data.records || data.records.length === 0) {
            toast.error('No booking records to export');
            return;
        }

        const headers = [
            'Booking ID',
            'Date',
            'Customer Name',
            'Mobile',
            'Type / Mode',
            'Guests',
            'Total Amount',
            'Paid Amount',
            'Pending Amount',
            'Booking Status',
            'Payment Status'
        ];

        const rows = data.records.map((r: any) => [
            `"${r.id}"`,
            `"${r.bookingDate || ''}"`,
            `"${r.userName}"`,
            `"${r.userMobile}"`,
            `"${r.goingMode || 'solo'}"`,
            r.numberOfGuests,
            r.totalAmount,
            r.paidAmount,
            r.pendingAmount,
            `"${r.status}"`,
            `"${r.paymentStatus}"`
        ]);

        const csvContent = [headers.join(','), ...rows.map((row: any) => row.join(','))].join('\n');
        const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
        const url = URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.setAttribute('href', url);
        link.setAttribute('download', `${data.venue?.name || 'Venue'}_Revenue_${period}_${new Date().toISOString().split('T')[0]}.csv`);
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
    };

    // ── Chart Configurations ───────────────────────────────────────────────────

    // 1. Revenue & Payment Trend Line / Area Chart
    const trendLabels = data?.trend?.map((t: any) => t.label) || [];
    const paidSeries = data?.trend?.map((t: any) => t.paidAmount) || [];
    const totalSeries = data?.trend?.map((t: any) => t.totalAmount) || [];
    const pendingSeries = data?.trend?.map((t: any) => t.pendingAmount) || [];

    const trendChartOptions: ApexOptions = {
        chart: {
            type: 'area',
            height: 320,
            toolbar: { show: false },
            fontFamily: "'Space Grotesk', sans-serif",
            background: 'transparent',
            zoom: { enabled: false }
        },
        colors: ['#10b981', '#7c3aed', '#f59e0b'],
        stroke: { curve: 'smooth', width: [3, 2, 2] },
        fill: {
            type: 'gradient',
            gradient: {
                shadeIntensity: 1,
                opacityFrom: 0.45,
                opacityTo: 0.05,
                stops: [0, 90, 100]
            }
        },
        dataLabels: { enabled: false },
        xaxis: {
            categories: trendLabels,
            labels: { style: { colors: isDark ? '#94a3b8' : '#64748b', fontSize: '11px' } },
            axisBorder: { show: false }
        },
        yaxis: {
            labels: {
                style: { colors: isDark ? '#94a3b8' : '#64748b', fontSize: '11px' },
                formatter: (val) => `₹${val >= 1000 ? (val / 1000).toFixed(0) + 'k' : val}`
            }
        },
        grid: { borderColor: isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)' },
        legend: { labels: { colors: isDark ? '#f8fafc' : '#0f172a' }, position: 'top', horizontalAlign: 'right' },
        tooltip: { theme: isDark ? 'dark' : 'light', y: { formatter: (val) => `₹${val.toLocaleString()}` } }
    };

    const trendChartSeries = [
        { name: 'Paid Revenue', data: paidSeries },
        { name: 'Total Booking Value', data: totalSeries },
        { name: 'Pending Amount', data: pendingSeries }
    ];

    // 2. Booking Type Breakdown Donut Chart
    const modeData = data?.modeBreakdown || {};
    const donutLabels = ['Solo Bookings', 'Party Requests', 'Group Parties', 'Large Parties', 'Upcoming Night'];
    const donutSeries = [
        modeData.solo?.paidAmount || 0,
        modeData.party_request?.paidAmount || 0,
        modeData.group_party?.paidAmount || 0,
        modeData.large_party?.paidAmount || 0,
        modeData.upcoming_night?.paidAmount || 0
    ];

    const donutChartOptions: ApexOptions = {
        chart: { type: 'donut', height: 300, fontFamily: "'Space Grotesk', sans-serif" },
        colors: ['#3b82f6', '#8b5cf6', '#ec4899', '#f59e0b', '#10b981'],
        labels: donutLabels,
        legend: { position: 'bottom', labels: { colors: isDark ? '#f8fafc' : '#0f172a' } },
        dataLabels: { enabled: true, formatter: (val: number) => `${val.toFixed(0)}%` },
        plotOptions: {
            pie: {
                donut: {
                    size: '68%',
                    labels: {
                        show: true,
                        total: {
                            show: true,
                            label: 'Total Paid',
                            color: isDark ? '#f8fafc' : '#0f172a',
                            formatter: () => formatCurrency(data?.summary?.paidAmount || 0)
                        }
                    }
                }
            }
        },
        tooltip: { theme: isDark ? 'dark' : 'light', y: { formatter: (val) => `₹${val.toLocaleString()}` } }
    };

    return (
        <div style={{
            position: 'fixed',
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            backgroundColor: 'rgba(0,0,0,0.7)',
            backdropFilter: 'blur(8px)',
            zIndex: 1050,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            padding: '1.5rem',
            overflowY: 'auto'
        }}>
            <div style={{
                backgroundColor: isDark ? '#111827' : '#ffffff',
                color: isDark ? '#f8fafc' : '#0f172a',
                borderRadius: '20px',
                width: '100%',
                maxWidth: '1200px',
                maxHeight: '90vh',
                display: 'flex',
                flexDirection: 'column',
                boxShadow: '0 25px 50px -12px rgba(0, 0, 0, 0.5)',
                border: `1px solid ${isDark ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.1)'}`,
                overflow: 'hidden'
            }}>
                {/* Modal Header */}
                <div style={{
                    padding: '1.25rem 1.75rem',
                    borderBottom: `1px solid ${isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'}`,
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'space-between',
                    backgroundColor: isDark ? '#1e293b' : '#f8fafc'
                }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
                        <button
                            onClick={onClose}
                            className="btn btn-outline-secondary btn-sm btn-icon"
                            style={{ borderRadius: '50%', padding: '6px' }}
                            title="Back"
                        >
                            <BiArrowBack size={18} />
                        </button>
                        <div>
                            <h5 style={{ margin: 0, fontWeight: 800, fontSize: '1.25rem', display: 'flex', alignItems: 'center', gap: '8px' }}>
                                🏢 {data?.venue?.name || venueName || 'Venue Revenue Analytics'}
                            </h5>
                            <span style={{ fontSize: '0.82rem', color: isDark ? '#94a3b8' : '#64748b' }}>
                                {data?.venue?.city ? `${data.venue.city} • ` : ''}Detailed Revenue & Booking Records ({period.toUpperCase()} BREAKDOWN)
                            </span>
                        </div>
                    </div>

                    <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                        <button className="btn btn-outline-primary btn-sm" onClick={handleExportCSV} disabled={loading || !data}>
                            <BiDownload style={{ marginRight: 4 }} /> Export Revenue Report
                        </button>
                        <button onClick={onClose} className="btn btn-light btn-sm btn-icon" style={{ borderRadius: '50%' }}>
                            <BiX size={22} />
                        </button>
                    </div>
                </div>

                {/* Modal Body */}
                <div style={{ padding: '1.5rem', overflowY: 'auto', flex: 1 }}>

                    {/* Period Toolbar & Filters */}
                    <div style={{
                        display: 'flex',
                        flexWrap: 'wrap',
                        alignItems: 'center',
                        justifyContent: 'space-between',
                        gap: '1rem',
                        marginBottom: '1.5rem',
                        backgroundColor: isDark ? 'rgba(255,255,255,0.03)' : '#f1f5f9',
                        padding: '1rem',
                        borderRadius: '16px'
                    }}>
                        {/* Period Selector Buttons */}
                        <div style={{ display: 'flex', gap: '6px', flexWrap: 'wrap' }}>
                            {[
                                { id: 'daily', label: '📅 Day Wise' },
                                { id: 'weekly', label: '🗓️ Weekly' },
                                { id: 'monthly', label: '📆 Monthly' },
                                { id: 'yearly', label: '📊 Yearly' },
                                { id: 'custom', label: '⚙️ Custom Range' },
                            ].map((p) => {
                                const active = period === p.id;
                                return (
                                    <button
                                        key={p.id}
                                        type="button"
                                        onClick={() => handlePeriodChange(p.id as any)}
                                        style={{
                                            padding: '0.45rem 1rem',
                                            borderRadius: '12px',
                                            border: 'none',
                                            fontWeight: active ? 700 : 500,
                                            fontSize: '0.85rem',
                                            backgroundColor: active ? '#7c3aed' : isDark ? 'rgba(255,255,255,0.06)' : '#ffffff',
                                            color: active ? '#ffffff' : isDark ? '#cbd5e1' : '#334155',
                                            cursor: 'pointer',
                                            transition: 'all 0.2s ease',
                                            boxShadow: active ? '0 4px 12px rgba(124, 58, 237, 0.3)' : 'none'
                                        }}
                                    >
                                        {p.label}
                                    </button>
                                );
                            })}
                        </div>

                        {/* Custom Date Filter Inputs */}
                        {period === 'custom' && (
                            <div style={{ display: 'flex', alignItems: 'center', gap: '8px', flexWrap: 'wrap' }}>
                                <input
                                    type="date"
                                    className="vz-form-control"
                                    value={fromDate}
                                    onChange={(e) => setFromDate(e.target.value)}
                                    style={{ width: '140px', fontSize: '0.85rem' }}
                                />
                                <span style={{ fontSize: '0.85rem', color: '#94a3b8' }}>to</span>
                                <input
                                    type="date"
                                    className="vz-form-control"
                                    value={toDate}
                                    onChange={(e) => setToDate(e.target.value)}
                                    style={{ width: '140px', fontSize: '0.85rem' }}
                                />
                                <button type="button" className="btn btn-primary btn-sm" onClick={() => fetchRevenueDetails()}>
                                    Apply Range
                                </button>
                            </div>
                        )}

                        <button type="button" className="btn btn-light btn-sm btn-icon" onClick={() => fetchRevenueDetails()} title="Refresh">
                            <BiRefresh size={18} />
                        </button>
                    </div>

                    {loading ? (
                        <div style={{ padding: '5rem', textAlign: 'center' }}>
                            <div className="spinner-border text-primary mb-3" style={{ width: '3rem', height: '3rem', color: '#7c3aed' }} />
                            <div style={{ fontWeight: 600 }}>Loading Revenue Analytics & Records...</div>
                        </div>
                    ) : (
                        <>
                            {/* KPI Stat Cards */}
                            <div className="row g-3 mb-4">
                                <div className="col-6 col-md-3">
                                    <div style={{
                                        backgroundColor: isDark ? 'rgba(16, 185, 129, 0.1)' : '#ecfdf5',
                                        border: `1px solid ${isDark ? 'rgba(16, 185, 129, 0.2)' : '#a7f3d0'}`,
                                        borderRadius: '16px',
                                        padding: '1.25rem'
                                    }}>
                                        <div style={{ fontSize: '0.8rem', fontWeight: 600, color: '#059669', marginBottom: '4px' }}>Paid Revenue</div>
                                        <div style={{ fontSize: '1.5rem', fontWeight: 800, color: isDark ? '#34d399' : '#047857' }}>
                                            {formatCurrency(data?.summary?.paidAmount)}
                                        </div>
                                        <div style={{ fontSize: '0.75rem', color: isDark ? '#a7f3d0' : '#059669', marginTop: '4px' }}>
                                            Actual Collected Amount
                                        </div>
                                    </div>
                                </div>

                                <div className="col-6 col-md-3">
                                    <div style={{
                                        backgroundColor: isDark ? 'rgba(124, 58, 237, 0.1)' : '#f3e8ff',
                                        border: `1px solid ${isDark ? 'rgba(124, 58, 237, 0.2)' : '#ddd6fe'}`,
                                        borderRadius: '16px',
                                        padding: '1.25rem'
                                    }}>
                                        <div style={{ fontSize: '0.8rem', fontWeight: 600, color: '#7c3aed', marginBottom: '4px' }}>Total Booking Value</div>
                                        <div style={{ fontSize: '1.5rem', fontWeight: 800, color: isDark ? '#c084fc' : '#6b21a8' }}>
                                            {formatCurrency(data?.summary?.totalBookingAmount)}
                                        </div>
                                        <div style={{ fontSize: '0.75rem', color: isDark ? '#e9d5ff' : '#7e22ce', marginTop: '4px' }}>
                                            Total Gross Bookings
                                        </div>
                                    </div>
                                </div>

                                <div className="col-6 col-md-3">
                                    <div style={{
                                        backgroundColor: isDark ? 'rgba(245, 158, 11, 0.1)' : '#fffbeb',
                                        border: `1px solid ${isDark ? 'rgba(245, 158, 11, 0.2)' : '#fde68a'}`,
                                        borderRadius: '16px',
                                        padding: '1.25rem'
                                    }}>
                                        <div style={{ fontSize: '0.8rem', fontWeight: 600, color: '#d97706', marginBottom: '4px' }}>Pending Revenue</div>
                                        <div style={{ fontSize: '1.5rem', fontWeight: 800, color: isDark ? '#fbbf24' : '#b45309' }}>
                                            {formatCurrency(data?.summary?.pendingAmount)}
                                        </div>
                                        <div style={{ fontSize: '0.75rem', color: isDark ? '#fde68a' : '#d97706', marginTop: '4px' }}>
                                            To Be Collected
                                        </div>
                                    </div>
                                </div>

                                <div className="col-6 col-md-3">
                                    <div style={{
                                        backgroundColor: isDark ? 'rgba(59, 130, 246, 0.1)' : '#eff6ff',
                                        border: `1px solid ${isDark ? 'rgba(59, 130, 246, 0.2)' : '#bfdbfe'}`,
                                        borderRadius: '16px',
                                        padding: '1.25rem'
                                    }}>
                                        <div style={{ fontSize: '0.8rem', fontWeight: 600, color: '#2563eb', marginBottom: '4px' }}>Total Bookings</div>
                                        <div style={{ fontSize: '1.5rem', fontWeight: 800, color: isDark ? '#60a5fa' : '#1d4ed8' }}>
                                            {data?.summary?.totalBookings || 0}
                                        </div>
                                        <div style={{ fontSize: '0.75rem', color: isDark ? '#bfdbfe' : '#2563eb', marginTop: '4px' }}>
                                            Avg: {formatCurrency(data?.summary?.avgBookingValue)}
                                        </div>
                                    </div>
                                </div>
                            </div>

                            {/* Graphics / Charts Row */}
                            <div className="row g-3 mb-4">
                                {/* Revenue Trend Graphic */}
                                <div className="col-lg-8">
                                    <div style={{
                                        backgroundColor: isDark ? '#1e293b' : '#ffffff',
                                        borderRadius: '16px',
                                        padding: '1.25rem',
                                        border: `1px solid ${isDark ? 'rgba(255,255,255,0.08)' : '#e2e8f0'}`
                                    }}>
                                        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem' }}>
                                            <h6 style={{ margin: 0, fontWeight: 700, display: 'flex', alignItems: 'center', gap: '6px' }}>
                                                <BiTrendingUp style={{ color: '#7c3aed' }} /> Revenue & Booking Value Trend ({period.toUpperCase()})
                                            </h6>
                                        </div>
                                        <Chart options={trendChartOptions} series={trendChartSeries} type="area" height={310} />
                                    </div>
                                </div>

                                {/* Revenue by Booking Mode Donut */}
                                <div className="col-lg-4">
                                    <div style={{
                                        backgroundColor: isDark ? '#1e293b' : '#ffffff',
                                        borderRadius: '16px',
                                        padding: '1.25rem',
                                        border: `1px solid ${isDark ? 'rgba(255,255,255,0.08)' : '#e2e8f0'}`,
                                        height: '100%'
                                    }}>
                                        <h6 style={{ margin: '0 0 1rem 0', fontWeight: 700, display: 'flex', alignItems: 'center', gap: '6px' }}>
                                            <BiBarChartAlt2 style={{ color: '#3b82f6' }} /> Revenue by Booking Mode
                                        </h6>
                                        <Chart options={donutChartOptions} series={donutSeries} type="donut" height={290} />
                                    </div>
                                </div>
                            </div>

                            {/* Records Table Section */}
                            <div style={{
                                backgroundColor: isDark ? '#1e293b' : '#ffffff',
                                borderRadius: '16px',
                                border: `1px solid ${isDark ? 'rgba(255,255,255,0.08)' : '#e2e8f0'}`,
                                overflow: 'hidden'
                            }}>
                                <div style={{
                                    padding: '1rem 1.25rem',
                                    borderBottom: `1px solid ${isDark ? 'rgba(255,255,255,0.08)' : '#e2e8f0'}`,
                                    display: 'flex',
                                    flexWrap: 'wrap',
                                    justifyContent: 'space-between',
                                    alignItems: 'center',
                                    gap: '0.75rem'
                                }}>
                                    <h6 style={{ margin: 0, fontWeight: 700 }}>Venue Booking Records ({data?.pagination?.total || 0})</h6>

                                    <div style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap', alignItems: 'center' }}>
                                        {/* Status Filter */}
                                        <select
                                            className="vz-form-control"
                                            value={statusFilter}
                                            onChange={(e) => { setStatusFilter(e.target.value); setPage(1); }}
                                            style={{ width: '130px', fontSize: '0.82rem' }}
                                        >
                                            <option value="all">All Statuses</option>
                                            <option value="confirmed">Confirmed</option>
                                            <option value="completed">Completed</option>
                                            <option value="pending">Pending</option>
                                            <option value="cancelled">Cancelled</option>
                                        </select>

                                        {/* Search Form */}
                                        <form onSubmit={handleSearch} style={{ display: 'flex', gap: '4px' }}>
                                            <input
                                                type="text"
                                                className="vz-form-control"
                                                placeholder="Search user name/mobile..."
                                                value={searchInput}
                                                onChange={(e) => setSearchInput(e.target.value)}
                                                style={{ width: '180px', fontSize: '0.82rem' }}
                                            />
                                            <button type="submit" className="btn btn-primary btn-sm">
                                                <BiSearch />
                                            </button>
                                        </form>
                                    </div>
                                </div>

                                <div className="table-responsive">
                                    <table className="vz-table align-middle" style={{ whiteSpace: 'nowrap', fontSize: '0.85rem' }}>
                                        <thead>
                                            <tr>
                                                <th style={{ width: 50 }}>#</th>
                                                <th>Booking Date</th>
                                                <th>Customer</th>
                                                <th>Contact</th>
                                                <th>Booking Mode</th>
                                                <th style={{ textAlign: 'center' }}>Guests</th>
                                                <th style={{ textAlign: 'right' }}>Total Amt</th>
                                                <th style={{ textAlign: 'right' }}>Paid Amt</th>
                                                <th style={{ textAlign: 'center' }}>Status</th>
                                            </tr>
                                        </thead>
                                        <tbody>
                                            {!data?.records || data.records.length === 0 ? (
                                                <tr>
                                                    <td colSpan={9} style={{ textAlign: 'center', padding: '3rem', color: '#94a3b8' }}>
                                                        No booking records found for this period filter.
                                                    </td>
                                                </tr>
                                            ) : (
                                                data.records.map((r: any, idx: number) => (
                                                    <tr key={r.id}>
                                                        <td>{((page - 1) * 10) + idx + 1}</td>
                                                        <td>{r.bookingDate || new Date(r.createdAt).toLocaleDateString('en-IN')}</td>
                                                        <td style={{ fontWeight: 600 }}>{r.userName}</td>
                                                        <td>{r.userMobile}</td>
                                                        <td>
                                                            <span className={`badge bg-${r.isLargePartyRequest ? 'purple' : r.isGroupBooking ? 'info' : r.goingMode === 'party_request' ? 'warning' : 'primary'}-subtle text-${r.isLargePartyRequest ? 'purple' : r.isGroupBooking ? 'info' : r.goingMode === 'party_request' ? 'warning' : 'primary'}`} style={{ textTransform: 'uppercase', fontSize: '0.7rem' }}>
                                                                {r.isLargePartyRequest ? 'Large Party' : r.isGroupBooking ? 'Group Party' : r.goingMode === 'party_request' ? 'Party Request' : (r.goingMode || 'Solo')}
                                                            </span>
                                                        </td>
                                                        <td style={{ textAlign: 'center' }}>{r.numberOfGuests}</td>
                                                        <td style={{ textAlign: 'right', fontWeight: 700 }}>{formatCurrency(r.totalAmount)}</td>
                                                        <td style={{ textAlign: 'right', color: '#10b981', fontWeight: 600 }}>{formatCurrency(r.paidAmount)}</td>
                                                        <td style={{ textAlign: 'center' }}>
                                                            <span className={`badge bg-${r.status === 'confirmed' || r.status === 'completed' ? 'success' : r.status === 'pending' ? 'warning' : 'danger'}`} style={{ textTransform: 'capitalize', fontSize: '0.72rem' }}>
                                                                {r.status}
                                                            </span>
                                                        </td>
                                                    </tr>
                                                ))
                                            )}
                                        </tbody>
                                    </table>
                                </div>

                                {/* Table Pagination */}
                                {data?.pagination && data.pagination.totalPages > 1 && (
                                    <div style={{
                                        display: 'flex',
                                        alignItems: 'center',
                                        justifyContent: 'space-between',
                                        padding: '10px 16px',
                                        borderTop: `1px solid ${isDark ? 'rgba(255,255,255,0.08)' : '#e2e8f0'}`
                                    }}>
                                        <span style={{ fontSize: '0.8rem', color: '#94a3b8' }}>
                                            Showing page {page} of {data.pagination.totalPages} ({data.pagination.total} records)
                                        </span>
                                        <div style={{ display: 'flex', gap: '6px' }}>
                                            <button
                                                className="btn btn-sm btn-outline-secondary"
                                                disabled={page <= 1}
                                                onClick={() => setPage(p => p - 1)}
                                            >
                                                ← Prev
                                            </button>
                                            <button
                                                className="btn btn-sm btn-outline-secondary"
                                                disabled={page >= data.pagination.totalPages}
                                                onClick={() => setPage(p => p + 1)}
                                            >
                                                Next →
                                            </button>
                                        </div>
                                    </div>
                                )}
                            </div>
                        </>
                    )}
                </div>
            </div>
        </div>
    );
};
