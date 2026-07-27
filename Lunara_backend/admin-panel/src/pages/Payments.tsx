import { useState, useEffect } from 'react';
import Chart from 'react-apexcharts';
import { BiSearch, BiRefresh, BiDollarCircle, BiCheckCircle, BiXCircle, BiTimeFive } from 'react-icons/bi';
import toast from 'react-hot-toast';
import { paymentsApi, type PaymentSummary, type Payment } from '../api/payments';
import { format } from 'date-fns';
import { useThemeMode } from '../context/ThemeContext';

export const Payments = () => {
    const { mode } = useThemeMode();
    const isDark = mode === 'dark';
    const textColor = isDark ? '#8c9097' : '#6c757d';
    const gridColor = isDark ? 'rgba(255,255,255,0.06)' : '#e9edf4';

    const [summary, setSummary] = useState<PaymentSummary | null>(null);
    const [payments, setPayments] = useState<Payment[]>([]);
    const [loadingSummary, setLoadingSummary] = useState(true);
    const [loadingPayments, setLoadingPayments] = useState(true);

    // Filters & Pagination
    const [page, setPage] = useState(1);
    const [totalPages, setTotalPages] = useState(1);
    const [statusFilter, setStatusFilter] = useState('');
    const [searchQuery, setSearchQuery] = useState('');
    
    // Using a debounced search term for the actual API call
    const [debouncedSearch, setDebouncedSearch] = useState('');

    useEffect(() => {
        const handler = setTimeout(() => {
            setDebouncedSearch(searchQuery);
            setPage(1); // Reset page on new search
        }, 500);
        return () => clearTimeout(handler);
    }, [searchQuery]);

    const fetchSummary = async () => {
        setLoadingSummary(true);
        try {
            const res = await paymentsApi.getSummary();
            if (res.success) {
                setSummary(res.data);
            }
        } catch (error) {
            toast.error('Failed to load payment summary');
        } finally {
            setLoadingSummary(false);
        }
    };

    const fetchPayments = async () => {
        setLoadingPayments(true);
        try {
            const res = await paymentsApi.getPayments({
                page,
                limit: 10,
                status: statusFilter,
                search: debouncedSearch
            });
            if (res.success) {
                setPayments(res.data);
                setTotalPages(res.pagination.totalPages);
            }
        } catch (error) {
            toast.error('Failed to load payments list');
        } finally {
            setLoadingPayments(false);
        }
    };

    useEffect(() => {
        fetchSummary();
    }, []);

    useEffect(() => {
        fetchPayments();
    }, [page, statusFilter, debouncedSearch]);

    const formatCurrency = (amount: number | string) => {
        return `₹${Number(amount).toLocaleString('en-IN', { minimumFractionDigits: 0, maximumFractionDigits: 2 })}`;
    };

    // Chart configurations
    const lineOptions: ApexCharts.ApexOptions = {
        chart: { type: 'area', height: 320, toolbar: { show: false }, fontFamily: "'Space Grotesk', sans-serif", background: 'transparent' },
        colors: ['#26bf94'],
        fill: { type: 'gradient', gradient: { shadeIntensity: 1, opacityFrom: 0.4, opacityTo: 0.05, stops: [0, 90, 100] } },
        stroke: { curve: 'smooth', width: 2 },
        xaxis: {
            categories: summary?.revenueOverTime.map(item => format(new Date(item.date), 'dd MMM')) || [],
            labels: { style: { colors: textColor, fontSize: '11px' } },
            axisBorder: { show: false }, axisTicks: { show: false },
        },
        yaxis: { labels: { style: { colors: textColor, fontSize: '11px' }, formatter: (value) => `₹${value / 1000}k` } },
        grid: { borderColor: gridColor, strokeDashArray: 3 },
        dataLabels: { enabled: false },
        tooltip: { theme: isDark ? 'dark' : 'light' },
    };

    const lineSeries = [
        { name: 'Revenue', data: summary?.revenueOverTime.map(item => Number(item.revenue)) || [] }
    ];

    const pieOptions: ApexCharts.ApexOptions = {
        chart: { type: 'donut', height: 280, fontFamily: "'Space Grotesk', sans-serif" },
        colors: ['#845adf', '#23b7e5', '#f5b849', '#e34d8b'],
        labels: summary?.paymentMethods.map(item => item.paymentMethod.toUpperCase()) || [],
        legend: { position: 'bottom', labels: { colors: textColor } },
        stroke: { show: false },
        dataLabels: { enabled: false },
        plotOptions: { pie: { donut: { size: '70%', labels: { show: true, name: { color: textColor }, value: { color: isDark ? '#d4d5d9' : '#1a1d21' }, total: { show: true, label: 'Methods', color: textColor } } } } },
    };

    const pieSeries = summary?.paymentMethods.map(item => Number(item.count)) || [];

    const getStatusBadge = (status: string) => {
        switch (status.toLowerCase()) {
            case 'successful': return <span className="vz-badge success">Successful</span>;
            case 'failed': return <span className="vz-badge danger">Failed</span>;
            case 'processing': return <span className="vz-badge warning">Processing</span>;
            case 'initiated': return <span className="vz-badge info">Initiated</span>;
            case 'refunded': return <span className="vz-badge secondary">Refunded</span>;
            default: return <span className="vz-badge secondary">{status}</span>;
        }
    };

    return (
        <div style={{ paddingBottom: '80px' }}>
            {/* KPI Cards */}
            <div className="row g-3 mb-4">
                <div className="col-sm-6 col-xl-3">
                    <div className="stat-card animate-in animate-in-1">
                        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                            <div>
                                <div className="stat-card-label">Total Revenue</div>
                                <div className="stat-card-value">
                                    {loadingSummary ? '...' : formatCurrency(summary?.totalRevenue || 0)}
                                </div>
                            </div>
                            <div className="stat-card-icon success"><BiDollarCircle /></div>
                        </div>
                    </div>
                </div>
                <div className="col-sm-6 col-xl-3">
                    <div className="stat-card animate-in animate-in-2">
                        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                            <div>
                                <div className="stat-card-label">Successful Transactions</div>
                                <div className="stat-card-value">
                                    {loadingSummary ? '...' : summary?.successfulCount || 0}
                                </div>
                            </div>
                            <div className="stat-card-icon primary"><BiCheckCircle /></div>
                        </div>
                    </div>
                </div>
                <div className="col-sm-6 col-xl-3">
                    <div className="stat-card animate-in animate-in-3">
                        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                            <div>
                                <div className="stat-card-label">Failed Transactions</div>
                                <div className="stat-card-value">
                                    {loadingSummary ? '...' : summary?.failedCount || 0}
                                </div>
                            </div>
                            <div className="stat-card-icon danger"><BiXCircle /></div>
                        </div>
                    </div>
                </div>
                <div className="col-sm-6 col-xl-3">
                    <div className="stat-card animate-in animate-in-4">
                        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                            <div>
                                <div className="stat-card-label">Avg. Transaction Value</div>
                                <div className="stat-card-value">
                                    {loadingSummary ? '...' : formatCurrency(summary?.averageTransactionValue || 0)}
                                </div>
                            </div>
                            <div className="stat-card-icon info"><BiTimeFive /></div>
                        </div>
                    </div>
                </div>
            </div>

            {/* Charts Row */}
            <div className="row g-3 mb-4">
                <div className="col-xl-8">
                    <div className="vz-card animate-in animate-in-5" style={{ height: '100%' }}>
                        <div className="vz-card-header">
                            <h6 className="vz-card-title">Revenue Overview</h6>
                        </div>
                        <div className="vz-card-body">
                            {loadingSummary ? (
                                <div style={{ height: 320, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>Loading chart...</div>
                            ) : (
                                <Chart options={lineOptions} series={lineSeries} type="area" height={320} />
                            )}
                        </div>
                    </div>
                </div>
                <div className="col-xl-4">
                    <div className="vz-card animate-in animate-in-6" style={{ height: '100%' }}>
                        <div className="vz-card-header">
                            <h6 className="vz-card-title">Payment Methods</h6>
                        </div>
                        <div className="vz-card-body">
                            {loadingSummary ? (
                                <div style={{ height: 280, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>Loading chart...</div>
                            ) : (
                                <Chart options={pieOptions} series={pieSeries} type="donut" height={280} />
                            )}
                        </div>
                    </div>
                </div>
            </div>

            {/* Toolbar */}
            <div className="vz-card mb-3 animate-in animate-in-7">
                <div className="vz-card-body" style={{ padding: '0.75rem 1.25rem' }}>
                    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap', gap: '0.75rem' }}>
                        <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'center', flexWrap: 'wrap' }}>
                            <div style={{ position: 'relative' }}>
                                <BiSearch style={{ position: 'absolute', left: '0.75rem', top: '50%', transform: 'translateY(-50%)', color: 'var(--vz-text-muted)' }} />
                                <input
                                    className="vz-form-control"
                                    placeholder="Search user..."
                                    value={searchQuery}
                                    onChange={(e) => setSearchQuery(e.target.value)}
                                    style={{ paddingLeft: '2.25rem', width: 250 }}
                                />
                            </div>
                            <select
                                className="vz-form-control"
                                style={{ width: 140 }}
                                value={statusFilter}
                                onChange={(e) => { setStatusFilter(e.target.value); setPage(1); }}
                            >
                                <option value="">All Statuses</option>
                                <option value="successful">Successful</option>
                                <option value="failed">Failed</option>
                                <option value="processing">Processing</option>
                                <option value="initiated">Initiated</option>
                                <option value="refunded">Refunded</option>
                            </select>
                        </div>
                        <button className="vz-btn vz-btn-outline vz-btn-sm" onClick={() => { fetchSummary(); fetchPayments(); }} title="Refresh" disabled={loadingSummary || loadingPayments}>
                            <BiRefresh style={{ animation: (loadingSummary || loadingPayments) ? 'spin 1s linear infinite' : 'none' }} />
                        </button>
                    </div>
                </div>
            </div>

            {/* Transactions Table */}
            <div className="vz-card animate-in animate-in-8">
                <div className="vz-card-header">
                    <h6 className="vz-card-title">Recent Transactions</h6>
                </div>
                <div className="vz-card-body" style={{ padding: 0 }}>
                    {loadingPayments ? (
                        <div style={{ textAlign: 'center', padding: '3rem', color: 'var(--vz-text-muted)' }}>
                            <div className="spinner-border spinner-border-sm" role="status" style={{ marginRight: '0.5rem' }} />
                            Loading transactions...
                        </div>
                    ) : (
                        <div className="vz-table-wrapper">
                            <table className="vz-table">
                                <thead>
                                    <tr>
                                        <th>Transaction ID</th>
                                        <th>User</th>
                                        <th>Amount</th>
                                        <th>Method</th>
                                        <th>Date</th>
                                        <th>Status</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    {payments.length === 0 ? (
                                        <tr>
                                            <td colSpan={6} style={{ textAlign: 'center', padding: '2rem', color: 'var(--vz-text-muted)' }}>
                                                No transactions found.
                                            </td>
                                        </tr>
                                    ) : (
                                        payments.map((payment) => (
                                            <tr key={payment.id}>
                                                <td>
                                                    <div style={{ fontWeight: 600, fontSize: '0.8125rem' }}>{payment.transactionId}</div>
                                                    <div style={{ fontSize: '0.6875rem', color: 'var(--vz-text-muted)' }}>
                                                        {payment.id.substring(0, 8)}...
                                                    </div>
                                                </td>
                                                <td>
                                                    <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
                                                        <div style={{ width: 32, height: 32, borderRadius: '50%', backgroundColor: 'var(--vz-primary)', color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center', fontWeight: 600, fontSize: '0.75rem' }}>
                                                            {payment.payer?.firstName?.charAt(0) || 'U'}
                                                        </div>
                                                        <div>
                                                            <div style={{ fontWeight: 600, fontSize: '0.8125rem' }}>
                                                                {payment.payer ? `${payment.payer.firstName} ${payment.payer.lastName}` : 'Unknown User'}
                                                            </div>
                                                            <div style={{ fontSize: '0.75rem', color: 'var(--vz-text-muted)' }}>
                                                                {payment.payer?.email || 'N/A'}
                                                            </div>
                                                        </div>
                                                    </div>
                                                </td>
                                                <td style={{ fontWeight: 600 }}>{formatCurrency(payment.amount)}</td>
                                                <td>
                                                    <span style={{
                                                        display: 'inline-block',
                                                        padding: '0.2rem 0.5rem',
                                                        borderRadius: '4px',
                                                        fontSize: '0.6875rem',
                                                        fontWeight: 600,
                                                        color: 'var(--vz-primary)',
                                                        background: 'rgba(var(--vz-primary-rgb), 0.1)',
                                                        textTransform: 'uppercase'
                                                    }}>
                                                        {payment.paymentMethod}
                                                    </span>
                                                </td>
                                                <td>
                                                    <div style={{ fontSize: '0.8125rem' }}>{format(new Date(payment.createdAt), 'dd MMM yyyy')}</div>
                                                    <div style={{ fontSize: '0.75rem', color: 'var(--vz-text-muted)' }}>{format(new Date(payment.createdAt), 'hh:mm a')}</div>
                                                </td>
                                                <td>{getStatusBadge(payment.status)}</td>
                                            </tr>
                                        ))
                                    )}
                                </tbody>
                            </table>
                        </div>
                    )}
                </div>
                {/* Pagination */}
                {totalPages > 1 && (
                    <div className="vz-card-footer" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                        <div style={{ fontSize: '0.8125rem', color: 'var(--vz-text-muted)' }}>
                            Showing page {page} of {totalPages}
                        </div>
                        <div style={{ display: 'flex', gap: '0.25rem' }}>
                            <button
                                className="vz-btn vz-btn-outline vz-btn-sm"
                                disabled={page === 1}
                                onClick={() => setPage(p => Math.max(1, p - 1))}
                            >
                                Previous
                            </button>
                            <button
                                className="vz-btn vz-btn-outline vz-btn-sm"
                                disabled={page === totalPages}
                                onClick={() => setPage(p => Math.min(totalPages, p + 1))}
                            >
                                Next
                            </button>
                        </div>
                    </div>
                )}
            </div>
        </div>
    );
};
