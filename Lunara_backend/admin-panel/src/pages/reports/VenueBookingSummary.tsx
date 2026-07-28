import { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { BiSearch, BiRefresh, BiFilterAlt, BiDownload, BiBuildingHouse, BiCalendar, BiMoney, BiCheckCircle } from 'react-icons/bi';
import toast from 'react-hot-toast';
import bookingsApi from '../../api/bookings';
import venuesApi from '../../api/venues';
import { useThemeMode } from '../../context/ThemeContext';

export const VenueBookingSummary = () => {
    const { mode } = useThemeMode();
    const isDark = mode === 'dark';
    const navigate = useNavigate();

    const [summary, setSummary] = useState<any>(null);
    const [venuesData, setVenuesData] = useState<any[]>([]);
    const [loading, setLoading] = useState(true);

    // Filters
    const [fromDate, setFromDate] = useState('');
    const [toDate, setToDate] = useState('');
    const [venueIdFilter, setVenueIdFilter] = useState('all');
    const [bookingStatus, setBookingStatus] = useState('all');
    const [paymentStatus, setPaymentStatus] = useState('all');
    const [searchQuery, setSearchQuery] = useState('');
    const [searchInput, setSearchInput] = useState('');
    
    // Pagination
    const [page, setPage] = useState(1);
    const [totalPages, setTotalPages] = useState(1);
    const [totalRecords, setTotalRecords] = useState(0);

    // Reference data for dropdown
    const [allVenues, setAllVenues] = useState<any[]>([]);

    useEffect(() => {
        // Fetch venues for filter dropdown
        venuesApi.getVenues().then(res => {
            if (res.venues) setAllVenues(res.venues);
        }).catch(() => {});
    }, []);

    const fetchSummary = useCallback(async () => {
        setLoading(true);
        try {
            const params = {
                page,
                limit: 15,
                fromDate: fromDate || undefined,
                toDate: toDate || undefined,
                venueId: venueIdFilter === 'all' ? undefined : venueIdFilter,
                bookingStatus: bookingStatus === 'all' ? undefined : bookingStatus,
                paymentStatus: paymentStatus === 'all' ? undefined : paymentStatus,
                search: searchQuery || undefined
            };
            const res = await bookingsApi.getVenueWiseSummary(params);
            if (res.success) {
                setSummary(res.data.summary);
                setVenuesData(res.data.venues);
                setTotalPages(res.data.pagination.totalPages);
                setTotalRecords(res.data.pagination.total);
            }
        } catch (error) {
            toast.error('Failed to load venue summary');
        } finally {
            setLoading(false);
        }
    }, [page, fromDate, toDate, venueIdFilter, bookingStatus, paymentStatus, searchQuery]);

    useEffect(() => {
        fetchSummary();
    }, [fetchSummary]);

    const handleSearchSubmit = (e: React.FormEvent) => {
        e.preventDefault();
        setSearchQuery(searchInput);
        setPage(1);
    };

    const handleClearFilters = () => {
        setFromDate('');
        setToDate('');
        setVenueIdFilter('all');
        setBookingStatus('all');
        setPaymentStatus('all');
        setSearchInput('');
        setSearchQuery('');
        setPage(1);
    };

    const formatCurrency = (amount: number | string) => {
        return `₹${Number(amount || 0).toLocaleString('en-IN', { minimumFractionDigits: 0, maximumFractionDigits: 2 })}`;
    };

    const handleExportCSV = () => {
        if (!venuesData || venuesData.length === 0) {
            toast.error('No data to export');
            return;
        }

        // CSV Header
        const headers = [
            'Sr. No.',
            'Venue Name',
            'Total Bookings',
            'Confirmed Bookings',
            'Pending Bookings',
            'Cancelled Bookings',
            'Completed Bookings',
            'Total Booking Amount',
            'Paid Amount',
            'Pending Amount',
            'Refund Amount'
        ];

        // CSV Rows
        const rows = venuesData.map((v, index) => [
            ((page - 1) * 15) + index + 1,
            `"${v.venueName}"`, // wrap in quotes to handle commas
            v.totalBookings,
            v.confirmedBookings,
            v.pendingBookings,
            v.cancelledBookings,
            v.completedBookings,
            v.totalBookingAmount,
            v.paidAmount,
            v.pendingAmount,
            v.refundAmount
        ]);

        const csvContent = [
            headers.join(','),
            ...rows.map(e => e.join(','))
        ].join('\n');

        const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
        const url = URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.setAttribute('href', url);
        link.setAttribute('download', `Venue_Booking_Summary_${new Date().toISOString().split('T')[0]}.csv`);
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
    };

    return (
        <div style={{ paddingBottom: '80px' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1.5rem' }}>
                <h4 style={{ margin: 0, fontWeight: 700 }}>Venue-Wise Booking Summary</h4>
                <button className="btn btn-outline-primary btn-sm" onClick={handleExportCSV} disabled={venuesData.length === 0 || loading}>
                    <BiDownload style={{ marginRight: 6 }} /> Export CSV
                </button>
            </div>

            {/* KPI Cards */}
            <div className="row g-3 mb-4">
                {/* 1. All Bookings */}
                <div className="col-sm-6 col-md-3">
                    <div className="stat-card">
                        <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                            <div>
                                <div className="stat-card-label">All Bookings</div>
                                <div className="stat-card-value">{loading ? '...' : summary?.totalBookings || 0}</div>
                                <div style={{ fontSize: '0.85rem', color: 'var(--vz-text-muted)', marginTop: '4px' }}>
                                    Amount: {loading ? '...' : formatCurrency(summary?.totalAmount)}
                                </div>
                            </div>
                            <div className="stat-card-icon primary"><BiCalendar /></div>
                        </div>
                    </div>
                </div>
                {/* 2. Today's Bookings */}
                <div className="col-sm-6 col-md-3">
                    <div className="stat-card">
                        <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                            <div>
                                <div className="stat-card-label">Today's Bookings</div>
                                <div className="stat-card-value">{loading ? '...' : summary?.todaysBookingCount || 0}</div>
                                <div style={{ fontSize: '0.85rem', color: 'var(--vz-text-muted)', marginTop: '4px' }}>
                                    Amount: {loading ? '...' : formatCurrency(summary?.todaysBookingAmount)}
                                </div>
                            </div>
                            <div className="stat-card-icon info"><BiCalendar /></div>
                        </div>
                    </div>
                </div>
                {/* 3. Solo Bookings */}
                <div className="col-sm-6 col-md-3">
                    <div className="stat-card">
                        <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                            <div>
                                <div className="stat-card-label">Solo Bookings</div>
                                <div className="stat-card-value">{loading ? '...' : summary?.soloBookingCount || 0}</div>
                                <div style={{ fontSize: '0.85rem', color: 'var(--vz-text-muted)', marginTop: '4px' }}>
                                    Amount: {loading ? '...' : formatCurrency(summary?.soloBookingAmount)}
                                </div>
                            </div>
                            <div className="stat-card-icon success"><BiCheckCircle /></div>
                        </div>
                    </div>
                </div>
                {/* 4. Party Plans */}
                <div className="col-sm-6 col-md-3">
                    <div className="stat-card">
                        <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                            <div>
                                <div className="stat-card-label">Party Plans</div>
                                <div className="stat-card-value">{loading ? '...' : summary?.partyPlansCount || 0}</div>
                                <div style={{ fontSize: '0.85rem', color: 'var(--vz-text-muted)', marginTop: '4px' }}>
                                    Amount: {loading ? '...' : formatCurrency(summary?.partyPlansAmount)}
                                </div>
                            </div>
                            <div className="stat-card-icon warning"><BiMoney /></div>
                        </div>
                    </div>
                </div>
                {/* 5. Party Requests */}
                <div className="col-sm-6 col-md-3">
                    <div className="stat-card">
                        <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                            <div>
                                <div className="stat-card-label">Party Requests</div>
                                <div className="stat-card-value">{loading ? '...' : summary?.partyRequestsCount || 0}</div>
                                <div style={{ fontSize: '0.85rem', color: 'var(--vz-text-muted)', marginTop: '4px' }}>
                                    Amount: {loading ? '...' : formatCurrency(summary?.partyRequestsAmount)}
                                </div>
                            </div>
                            <div className="stat-card-icon primary"><BiBuildingHouse /></div>
                        </div>
                    </div>
                </div>
                {/* 6. Group Party Bookings */}
                <div className="col-sm-6 col-md-3">
                    <div className="stat-card">
                        <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                            <div>
                                <div className="stat-card-label">Group Party</div>
                                <div className="stat-card-value">{loading ? '...' : summary?.groupPartyBookingCount || 0}</div>
                                <div style={{ fontSize: '0.85rem', color: 'var(--vz-text-muted)', marginTop: '4px' }}>
                                    Amount: {loading ? '...' : formatCurrency(summary?.groupPartyBookingAmount)}
                                </div>
                            </div>
                            <div className="stat-card-icon info"><BiCalendar /></div>
                        </div>
                    </div>
                </div>
                {/* 7. Large Parties */}
                <div className="col-sm-6 col-md-3">
                    <div className="stat-card">
                        <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                            <div>
                                <div className="stat-card-label">Large Parties</div>
                                <div className="stat-card-value">{loading ? '...' : summary?.largePartiesCount || 0}</div>
                                <div style={{ fontSize: '0.85rem', color: 'var(--vz-text-muted)', marginTop: '4px' }}>
                                    Amount: {loading ? '...' : formatCurrency(summary?.largePartiesAmount)}
                                </div>
                            </div>
                            <div className="stat-card-icon success"><BiCheckCircle /></div>
                        </div>
                    </div>
                </div>
                {/* 8. Upcoming Night Bookings */}
                <div className="col-sm-6 col-md-3">
                    <div className="stat-card">
                        <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                            <div>
                                <div className="stat-card-label">Upcoming Night</div>
                                <div className="stat-card-value">{loading ? '...' : summary?.upcomingNightBookingCount || 0}</div>
                                <div style={{ fontSize: '0.85rem', color: 'var(--vz-text-muted)', marginTop: '4px' }}>
                                    Amount: {loading ? '...' : formatCurrency(summary?.upcomingNightBookingAmount)}
                                </div>
                            </div>
                            <div className="stat-card-icon warning"><BiMoney /></div>
                        </div>
                    </div>
                </div>
            </div>

            {/* Filter Toolbar */}
            <div className="vz-card mb-4">
                <div className="vz-card-body" style={{ padding: '1rem' }}>
                    <form onSubmit={handleSearchSubmit} style={{ display: 'flex', flexWrap: 'wrap', gap: '0.75rem', alignItems: 'center' }}>
                        
                        {/* Search */}
                        <div style={{ position: 'relative', flex: '1 1 200px' }}>
                            <BiSearch style={{ position: 'absolute', left: '0.75rem', top: '50%', transform: 'translateY(-50%)', color: 'var(--vz-text-muted)' }} />
                            <input
                                className="vz-form-control"
                                placeholder="Search venue name..."
                                value={searchInput}
                                onChange={(e) => setSearchInput(e.target.value)}
                                style={{ paddingLeft: '2.25rem', width: '100%' }}
                            />
                        </div>

                        {/* Venue */}
                        <select
                            className="vz-form-control"
                            value={venueIdFilter}
                            onChange={(e) => { setVenueIdFilter(e.target.value); setPage(1); }}
                            style={{ flex: '1 1 150px' }}
                        >
                            <option value="all">🏢 All Venues</option>
                            {allVenues.map((v) => (
                                <option key={v.id} value={v.id}>{v.name}</option>
                            ))}
                        </select>

                        {/* Booking Status */}
                        <select
                            className="vz-form-control"
                            value={bookingStatus}
                            onChange={(e) => { setBookingStatus(e.target.value); setPage(1); }}
                            style={{ flex: '1 1 130px' }}
                        >
                            <option value="all">🎫 All Booking Statuses</option>
                            <option value="pending">Pending</option>
                            <option value="confirmed">Confirmed</option>
                            <option value="completed">Completed</option>
                            <option value="cancelled">Cancelled</option>
                        </select>

                        {/* Payment Status */}
                        <select
                            className="vz-form-control"
                            value={paymentStatus}
                            onChange={(e) => { setPaymentStatus(e.target.value); setPage(1); }}
                            style={{ flex: '1 1 130px' }}
                        >
                            <option value="all">💳 All Payment Statuses</option>
                            <option value="pending">Pending</option>
                            <option value="paid">Paid</option>
                            <option value="partially_paid">Partially Paid</option>
                            <option value="refunded">Refunded</option>
                        </select>

                        {/* Dates */}
                        <input
                            type="date"
                            className="vz-form-control"
                            value={fromDate}
                            onChange={(e) => { setFromDate(e.target.value); setPage(1); }}
                            style={{ flex: '1 1 130px' }}
                        />
                        <span style={{ color: 'var(--vz-text-muted)' }}>to</span>
                        <input
                            type="date"
                            className="vz-form-control"
                            value={toDate}
                            onChange={(e) => { setToDate(e.target.value); setPage(1); }}
                            style={{ flex: '1 1 130px' }}
                        />

                        {/* Actions */}
                        <button type="submit" className="btn btn-primary btn-sm" style={{ padding: '0.4rem 1rem' }}>
                            <BiFilterAlt style={{ marginRight: 4 }} /> Filter
                        </button>
                        
                        <button type="button" className="btn btn-outline-secondary btn-sm" onClick={handleClearFilters}>
                            Clear
                        </button>
                        <button type="button" className="btn btn-light btn-sm btn-icon" onClick={() => fetchSummary()} title="Refresh">
                            <BiRefresh size={18} />
                        </button>
                    </form>
                </div>
            </div>

            {/* Data Table */}
            <div className="vz-card">
                <div className="vz-card-body" style={{ padding: 0 }}>
                    {loading ? (
                        <div style={{ padding: '4rem', textAlign: 'center', color: 'var(--vz-text-muted)' }}>
                            <div className="spinner-border spinner-border-sm" style={{ marginRight: 8, color: '#7c3aed' }} />
                            Generating report...
                        </div>
                    ) : venuesData.length === 0 ? (
                        <div style={{ padding: '4rem', textAlign: 'center', color: 'var(--vz-text-muted)' }}>
                            <div style={{ fontSize: '3rem', marginBottom: '1rem' }}>📊</div>
                            <div style={{ fontWeight: 600 }}>No data found</div>
                            <div style={{ fontSize: '0.85rem' }}>Try adjusting your filters</div>
                        </div>
                    ) : (
                        <div className="table-responsive">
                            <table className="vz-table align-middle" style={{ whiteSpace: 'nowrap' }}>
                                <thead>
                                    <tr>
                                        <th style={{ width: 60 }}>Sr. No.</th>
                                        <th>Venue Name</th>
                                        <th style={{ textAlign: 'center' }}>Total<br/>Bookings</th>
                                        <th style={{ textAlign: 'center' }}>Confirmed</th>
                                        <th style={{ textAlign: 'center' }}>Pending</th>
                                        <th style={{ textAlign: 'center' }}>Cancelled</th>
                                        <th style={{ textAlign: 'center' }}>Completed</th>
                                        <th style={{ textAlign: 'right' }}>Total<br/>Booking Amt</th>
                                        <th style={{ textAlign: 'right' }}>Paid Amt</th>
                                        <th style={{ textAlign: 'right' }}>Pending Amt</th>
                                        <th style={{ textAlign: 'right' }}>Refund Amt</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    {venuesData.map((v, index) => (
                                        <tr key={v.venueId} onClick={() => navigate('/bookings', { state: { venueId: v.venueId, showVenueDetails: true } })} style={{ cursor: 'pointer', transition: 'background-color 0.2s' }} onMouseEnter={(e) => e.currentTarget.style.backgroundColor = isDark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.02)'} onMouseLeave={(e) => e.currentTarget.style.backgroundColor = 'transparent'}>
                                            <td>{((page - 1) * 15) + index + 1}</td>
                                            <td style={{ fontWeight: 600, color: 'var(--vz-primary)' }}>{v.venueName}</td>
                                            <td style={{ textAlign: 'center', fontWeight: 600 }}>{v.totalBookings}</td>
                                            <td style={{ textAlign: 'center', color: 'var(--vz-success)' }}>{v.confirmedBookings}</td>
                                            <td style={{ textAlign: 'center', color: 'var(--vz-warning)' }}>{v.pendingBookings}</td>
                                            <td style={{ textAlign: 'center', color: 'var(--vz-danger)' }}>{v.cancelledBookings}</td>
                                            <td style={{ textAlign: 'center', color: 'var(--vz-info)' }}>{v.completedBookings}</td>
                                            <td style={{ textAlign: 'right', fontWeight: 700 }}>{formatCurrency(v.totalBookingAmount)}</td>
                                            <td style={{ textAlign: 'right', color: 'var(--vz-success)', fontWeight: 600 }}>{formatCurrency(v.paidAmount)}</td>
                                            <td style={{ textAlign: 'right', color: 'var(--vz-warning)' }}>{formatCurrency(v.pendingAmount)}</td>
                                            <td style={{ textAlign: 'right', color: 'var(--vz-danger)' }}>{formatCurrency(v.refundAmount)}</td>
                                        </tr>
                                    ))}
                                    {/* Grand Totals Row */}
                                    <tr style={{ backgroundColor: isDark ? 'rgba(255,255,255,0.02)' : '#f8f9fa', borderTop: '2px solid var(--vz-border-color)' }}>
                                        <td colSpan={2} style={{ fontWeight: 700, textAlign: 'right' }}>PAGE TOTALS:</td>
                                        <td style={{ textAlign: 'center', fontWeight: 700 }}>{venuesData.reduce((acc, v) => acc + v.totalBookings, 0)}</td>
                                        <td style={{ textAlign: 'center', fontWeight: 700 }}>{venuesData.reduce((acc, v) => acc + v.confirmedBookings, 0)}</td>
                                        <td style={{ textAlign: 'center', fontWeight: 700 }}>{venuesData.reduce((acc, v) => acc + v.pendingBookings, 0)}</td>
                                        <td style={{ textAlign: 'center', fontWeight: 700 }}>{venuesData.reduce((acc, v) => acc + v.cancelledBookings, 0)}</td>
                                        <td style={{ textAlign: 'center', fontWeight: 700 }}>{venuesData.reduce((acc, v) => acc + v.completedBookings, 0)}</td>
                                        <td style={{ textAlign: 'right', fontWeight: 700 }}>{formatCurrency(venuesData.reduce((acc, v) => acc + v.totalBookingAmount, 0))}</td>
                                        <td style={{ textAlign: 'right', fontWeight: 700 }}>{formatCurrency(venuesData.reduce((acc, v) => acc + v.paidAmount, 0))}</td>
                                        <td style={{ textAlign: 'right', fontWeight: 700 }}>{formatCurrency(venuesData.reduce((acc, v) => acc + v.pendingAmount, 0))}</td>
                                        <td style={{ textAlign: 'right', fontWeight: 700 }}>{formatCurrency(venuesData.reduce((acc, v) => acc + v.refundAmount, 0))}</td>
                                    </tr>
                                </tbody>
                            </table>
                        </div>
                    )}
                </div>

                {/* Pagination */}
                {!loading && totalPages > 1 && (
                    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '12px 20px', borderTop: '1px solid var(--vz-border-color)' }}>
                        <span style={{ fontSize: '0.8rem', color: 'var(--vz-text-muted)' }}>
                            Showing page {page} of {totalPages} ({totalRecords} venues)
                        </span>
                        <div style={{ display: 'flex', gap: 6 }}>
                            <button
                                className="btn btn-sm btn-outline-secondary"
                                disabled={page <= 1}
                                onClick={() => setPage(p => p - 1)}
                            >
                                ← Prev
                            </button>
                            <button
                                className="btn btn-sm btn-outline-secondary"
                                disabled={page >= totalPages}
                                onClick={() => setPage(p => p + 1)}
                            >
                                Next →
                            </button>
                        </div>
                    </div>
                )}
            </div>
        </div>
    );
};
