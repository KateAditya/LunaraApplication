import React from 'react';
import Chart from 'react-apexcharts';
import { useQuery } from '@tanstack/react-query';
import {
    BiBarChartAlt2, BiTrendingUp, BiWallet, BiShieldQuarter,
    BiTime, BiXCircle, BiCheckCircle, BiFlag,
} from 'react-icons/bi';
import { MdOutlineCancel } from 'react-icons/md';
import { useThemeMode } from '../context/ThemeContext';
import cancellationsApi, { type CancellationAnalytics as CancellationAnalyticsData } from '../api/cancellations';
import { getImageUrl } from '../utils/imageUrl';

// ── Helpers ────────────────────────────────────────────────────────────────

function Avatar({ user, size = 32 }: { user?: any; size?: number }) {
    const name = `${user?.firstName || ''} ${user?.lastName || ''}`.trim() || '?';
    const initials = name.split(' ').map((w: string) => w[0]).join('').slice(0, 2).toUpperCase();
    const url = user?.photo ? getImageUrl(user.photo) : null;
    return url
        ? <img src={url} alt={name} className="rounded-circle object-fit-cover" style={{ width: size, height: size }} />
        : <div className="rounded-circle d-flex align-items-center justify-content-center fw-bold text-white" style={{ width: size, height: size, background: 'linear-gradient(135deg,#e6533c,#c4422e)', fontSize: size * 0.38 }}>{initials}</div>;
}

const COLORS = ['#e6533c', '#845adf', '#26bf94', '#ffaa00', '#3dc2ff', '#f97f51', '#6c5ce7'];

// ── KPI Card ──────────────────────────────────────────────────────────────

function KpiCard({ label, value, sub, icon, color }: { label: string; value: React.ReactNode; sub?: string; icon: React.ReactNode; color: string }) {
    return (
        <div className="col-sm-6 col-xl-3">
            <div className="card border-0 shadow-sm h-100">
                <div className="card-body d-flex gap-3 align-items-center">
                    <div className="rounded-3 d-flex align-items-center justify-content-center flex-shrink-0"
                        style={{ width: 48, height: 48, background: `${color}18` }}>
                        <span style={{ color, fontSize: 22 }}>{icon}</span>
                    </div>
                    <div>
                        <div className="text-muted small mb-1">{label}</div>
                        <div className="fw-bold fs-5 lh-1">{value}</div>
                        {sub && <div className="text-muted" style={{ fontSize: '0.72rem', marginTop: 2 }}>{sub}</div>}
                    </div>
                </div>
            </div>
        </div>
    );
}

// ── Main Component ─────────────────────────────────────────────────────────

export const CancellationAnalytics: React.FC = () => {
    const { mode } = useThemeMode();
    const isDark = mode === 'dark';
    const textColor = isDark ? '#8c9097' : '#6c757d';
    const gridColor = isDark ? 'rgba(255,255,255,0.06)' : '#e9edf4';

    const { data, isLoading, refetch } = useQuery({
        queryKey: ['cancellation-analytics'],
        queryFn: cancellationsApi.getAnalytics,
        refetchInterval: 5 * 60 * 1000,
    } as any);

    const rawData: any = data;
    const analytics: CancellationAnalyticsData | undefined = (rawData?.kpis ? rawData : rawData?.data) || rawData;
    const kpis = analytics?.kpis;
    const charts = analytics?.charts;

    // ── Chart options ──────────────────────────────────────────────────────

    const commonOptions: Partial<ApexCharts.ApexOptions> = {
        chart: { toolbar: { show: false }, fontFamily: "'Space Grotesk', sans-serif", background: 'transparent' },
        theme: { mode: mode as 'dark' | 'light' },
        grid: { borderColor: gridColor, strokeDashArray: 3 },
        xaxis: { labels: { style: { colors: textColor, fontSize: '10px' } }, axisBorder: { show: false }, axisTicks: { show: false } },
        yaxis: { labels: { style: { colors: textColor, fontSize: '10px' } } },
        legend: { labels: { colors: textColor } },
        tooltip: { theme: mode },
    };

    const dailyOptions: ApexCharts.ApexOptions = {
        ...commonOptions,
        chart: { ...commonOptions.chart, type: 'area', height: 240 },
        colors: ['#e6533c'],
        stroke: { curve: 'smooth', width: 2.5 },
        fill: { type: 'gradient', gradient: { shadeIntensity: 1, opacityFrom: 0.35, opacityTo: 0.02 } },
        xaxis: {
            ...commonOptions.xaxis,
            categories: charts?.dailyTrend.map(d => d.date.slice(5)) || [],
        },
        dataLabels: { enabled: false },
    };

    const monthlyOptions: ApexCharts.ApexOptions = {
        ...commonOptions,
        chart: { ...commonOptions.chart, type: 'bar', height: 240 },
        colors: ['#845adf'],
        plotOptions: { bar: { borderRadius: 6, columnWidth: '50%' } },
        xaxis: {
            ...commonOptions.xaxis,
            categories: charts?.monthlyTrend.map(d => d.month) || [],
        },
        dataLabels: { enabled: false },
    };

    const reasonOptions: ApexCharts.ApexOptions = {
        chart: { type: 'donut', fontFamily: "'Space Grotesk', sans-serif", background: 'transparent', toolbar: { show: false } },
        colors: COLORS,
        labels: charts?.reasonDistribution.map(r => r.reason) || [],
        legend: { position: 'bottom', labels: { colors: textColor }, fontSize: '11px' },
        plotOptions: { pie: { donut: { size: '60%', labels: { show: true, total: { show: true, label: 'Total', color: textColor, formatter: (w) => String(w.globals.seriesTotals.reduce((a: number, b: number) => a + b, 0)) } } } } },
        theme: { mode: mode as 'dark' | 'light' },
        tooltip: { theme: mode },
        dataLabels: { enabled: false },
    };

    const hostVsParticipantOptions: ApexCharts.ApexOptions = {
        chart: { type: 'donut', fontFamily: "'Space Grotesk', sans-serif", background: 'transparent', toolbar: { show: false } },
        colors: ['#e6533c', '#26bf94'],
        labels: ['Host Requested', 'Participant Requested'],
        legend: { position: 'bottom', labels: { colors: textColor }, fontSize: '11px' },
        theme: { mode: mode as 'dark' | 'light' },
        tooltip: { theme: mode },
        dataLabels: { enabled: false },
        plotOptions: { pie: { donut: { size: '60%', labels: { show: true, total: { show: true, label: 'Ratio', color: textColor } } } } },
    };

    if (isLoading) return (
        <div className="text-center py-5">
            <div className="spinner-border text-danger mb-3" />
            <div className="text-muted">Loading analytics data…</div>
        </div>
    );

    return (
        <div>
            {/* ─── Header ──────────────────────────────────────────────────── */}
            <div className="d-flex align-items-center justify-content-between mb-4 flex-wrap gap-3">
                <div>
                    <h4 className="mb-1 fw-bold d-flex align-items-center gap-2">
                        <BiBarChartAlt2 className="text-danger" size={26} /> Cancellation Analytics
                    </h4>
                    <p className="text-muted small mb-0">Real-time insights into Party Plan cancellation trends, patterns, and fraud detection.</p>
                </div>
                <button className="btn btn-outline-secondary btn-sm" onClick={() => refetch()}>↺ Refresh</button>
            </div>

            {/* ─── KPI Cards Row 1 ─────────────────────────────────────────── */}
            <div className="row g-3 mb-4">
                <KpiCard label="Total Cancelled" value={kpis?.totalCancelled ?? '—'} icon={<MdOutlineCancel />} color="#e6533c" />
                <KpiCard label="Today" value={kpis?.today ?? '—'} icon={<BiTime />} color="#ffaa00" />
                <KpiCard label="This Week" value={kpis?.thisWeek ?? '—'} icon={<BiBarChartAlt2 />} color="#845adf" />
                <KpiCard label="This Month" value={kpis?.thisMonth ?? '—'} icon={<BiTrendingUp />} color="#26bf94" />
            </div>

            {/* ─── KPI Cards Row 2 ─────────────────────────────────────────── */}
            <div className="row g-3 mb-4">
                <KpiCard label="Pending Approval" value={kpis?.pending ?? '—'} icon={<BiTime />} color="#ffaa00"
                    sub="Awaiting response from other party" />
                <KpiCard label="Approved" value={kpis?.approved ?? '—'} icon={<BiCheckCircle />} color="#26bf94"
                    sub="Mutual cancellations completed" />
                <KpiCard label="Rejected" value={kpis?.rejected ?? '—'} icon={<BiXCircle />} color="#e6533c"
                    sub="Recipient declined" />
                <KpiCard label="Expired" value={kpis?.expired ?? '—'} icon={<BiXCircle />} color="#6c757d"
                    sub="24h window passed" />
            </div>

            {/* ─── KPI Cards Row 3 ─────────────────────────────────────────── */}
            <div className="row g-3 mb-4">
                <KpiCard label="Avg Approval Time" value={kpis?.avgApprovalTimeMinutes !== undefined ? `${kpis.avgApprovalTimeMinutes} min` : '—'} icon={<BiTime />} color="#3dc2ff"
                    sub="From request to response" />
                <KpiCard label="Total Wallet Credits" value={kpis?.totalWalletCredits !== undefined ? `₹${kpis.totalWalletCredits.toLocaleString('en-IN')}` : '—'} icon={<BiWallet />} color="#26bf94"
                    sub="Commitment deposits refunded" />
                <KpiCard label="Avg Reliability Impact" value={kpis?.avgReliabilityReduction !== undefined ? `-${kpis.avgReliabilityReduction} pts` : '—'} icon={<BiShieldQuarter />} color="#e6533c"
                    sub="Per approved cancellation" />
                <KpiCard label="Avg Hours Before Event" value={kpis?.avgHoursBeforeCancellation !== undefined ? `${kpis.avgHoursBeforeCancellation}h` : '—'} icon={<BiTime />} color="#845adf"
                    sub="When cancellation was requested" />
            </div>

            {/* ─── Charts Row 1 ────────────────────────────────────────────── */}
            <div className="row g-3 mb-4">
                <div className="col-xl-8">
                    <div className="card border-0 shadow-sm h-100">
                        <div className="card-header bg-transparent border-0 fw-semibold pt-3">
                            📈 Daily Cancellation Trend (Last 30 Days)
                        </div>
                        <div className="card-body pt-0">
                            {charts?.dailyTrend.length ? (
                                <Chart type="area" height={240} options={dailyOptions}
                                    series={[{ name: 'Cancellations', data: charts.dailyTrend.map(d => d.count) }]} />
                            ) : <div className="text-center text-muted py-5 small">No data yet</div>}
                        </div>
                    </div>
                </div>
                <div className="col-xl-4">
                    <div className="card border-0 shadow-sm h-100">
                        <div className="card-header bg-transparent border-0 fw-semibold pt-3">
                            🔄 Host vs. Participant
                        </div>
                        <div className="card-body pt-0 d-flex align-items-center justify-content-center">
                            {kpis && (kpis.hostRequested > 0 || kpis.participantRequested > 0) ? (
                                <Chart type="donut" height={240} options={hostVsParticipantOptions}
                                    series={[kpis.hostRequested, kpis.participantRequested]} />
                            ) : <div className="text-center text-muted py-5 small">No data yet</div>}
                        </div>
                    </div>
                </div>
            </div>

            {/* ─── Charts Row 2 ────────────────────────────────────────────── */}
            <div className="row g-3 mb-4">
                <div className="col-xl-6">
                    <div className="card border-0 shadow-sm">
                        <div className="card-header bg-transparent border-0 fw-semibold pt-3">
                            📅 Monthly Trend (Last 12 Months)
                        </div>
                        <div className="card-body pt-0">
                            {charts?.monthlyTrend.length ? (
                                <Chart type="bar" height={240} options={monthlyOptions}
                                    series={[{ name: 'Cancellations', data: charts.monthlyTrend.map(d => d.count) }]} />
                            ) : <div className="text-center text-muted py-4 small">No data yet</div>}
                        </div>
                    </div>
                </div>
                <div className="col-xl-6">
                    <div className="card border-0 shadow-sm">
                        <div className="card-header bg-transparent border-0 fw-semibold pt-3">
                            🎯 Cancellation Reason Distribution
                        </div>
                        <div className="card-body pt-0 d-flex justify-content-center">
                            {charts?.reasonDistribution.length ? (
                                <Chart type="donut" height={270} options={reasonOptions}
                                    series={charts.reasonDistribution.map(r => r.count)} />
                            ) : <div className="text-center text-muted py-4 small">No data yet</div>}
                        </div>
                    </div>
                </div>
            </div>

            {/* ─── Top Reasons Table ───────────────────────────────────────── */}
            <div className="row g-3 mb-4">
                <div className="col-xl-5">
                    <div className="card border-0 shadow-sm h-100">
                        <div className="card-header bg-transparent border-0 fw-semibold pt-3">
                            🏆 Top Cancellation Reasons
                        </div>
                        <div className="card-body p-0">
                            <table className="table table-hover mb-0 small">
                                <thead className="table-light">
                                    <tr>
                                        <th className="px-3 py-2">#</th>
                                        <th>Reason</th>
                                        <th className="text-end px-3">Count</th>
                                        <th className="text-end px-3">Share</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    {(analytics?.topReasons || []).map((r, i) => {
                                        const total = analytics?.topReasons.reduce((a, b) => a + b.count, 0) || 1;
                                        return (
                                            <tr key={i}>
                                                <td className="px-3 text-muted">{i + 1}</td>
                                                <td>
                                                    <div className="d-flex align-items-center gap-2">
                                                        <span className="rounded" style={{ width: 10, height: 10, background: COLORS[i % COLORS.length], flexShrink: 0 }} />
                                                        {r.reason}
                                                    </div>
                                                </td>
                                                <td className="text-end px-3 fw-bold">{r.count}</td>
                                                <td className="text-end px-3 text-muted">{((r.count / total) * 100).toFixed(1)}%</td>
                                            </tr>
                                        );
                                    })}
                                    {!analytics?.topReasons?.length && (
                                        <tr><td colSpan={4} className="text-center text-muted py-4">No data yet</td></tr>
                                    )}
                                </tbody>
                            </table>
                        </div>
                    </div>
                </div>

                {/* ─── Status Summary ──────────────────────────────────────── */}
                <div className="col-xl-7">
                    <div className="card border-0 shadow-sm h-100">
                        <div className="card-header bg-transparent border-0 fw-semibold pt-3">
                            📊 Status Summary
                        </div>
                        <div className="card-body">
                            {kpis && (
                                <div className="d-flex flex-column gap-3">
                                    {[
                                        { label: 'Approved', count: kpis.approved, color: '#26bf94' },
                                        { label: 'Pending', count: kpis.pending, color: '#ffaa00' },
                                        { label: 'Rejected', count: kpis.rejected, color: '#e6533c' },
                                        { label: 'Expired', count: kpis.expired, color: '#6c757d' },
                                    ].map(item => {
                                        const total = Math.max(kpis.approved + kpis.pending + kpis.rejected + kpis.expired, 1);
                                        const pct = Math.round((item.count / total) * 100);
                                        return (
                                            <div key={item.label}>
                                                <div className="d-flex justify-content-between mb-1 small">
                                                    <span className="fw-semibold">{item.label}</span>
                                                    <span className="text-muted">{item.count} ({pct}%)</span>
                                                </div>
                                                <div className="progress" style={{ height: 8, borderRadius: 4 }}>
                                                    <div className="progress-bar" style={{ width: `${pct}%`, background: item.color, borderRadius: 4 }} />
                                                </div>
                                            </div>
                                        );
                                    })}
                                </div>
                            )}
                        </div>
                    </div>
                </div>
            </div>

            {/* ─── Fraud Detection ─────────────────────────────────────────── */}
            <div className="card border-0 shadow-sm mb-4">
                <div className="card-header bg-transparent border-0 pt-3 d-flex align-items-center gap-2">
                    <BiFlag className="text-danger" size={18} />
                    <span className="fw-semibold">Fraud Detection Alerts</span>
                    <span className="badge bg-danger-subtle text-danger rounded-pill">{analytics?.fraudFlags?.length || 0} Flags</span>
                </div>
                <div className="card-body p-0">
                    {!analytics?.fraudFlags?.length ? (
                        <div className="text-center text-muted py-4 small">
                            <BiCheckCircle size={32} className="text-success mb-2 opacity-50" />
                            <div>No fraud flags detected in the last 30 days.</div>
                        </div>
                    ) : (
                        <div className="table-responsive">
                            <table className="table table-hover align-middle mb-0 small">
                                <thead className="table-light">
                                    <tr>
                                        <th className="px-3 py-2">User</th>
                                        <th>Flag Type</th>
                                        <th>Details</th>
                                        <th className="px-3">Last Activity</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    {analytics.fraudFlags.map((f, i) => (
                                        <tr key={i}>
                                            <td className="px-3">
                                                <div className="d-flex align-items-center gap-2">
                                                    <Avatar user={f.user} size={32} />
                                                    <div>
                                                        <div className="fw-semibold">{f.user?.firstName} {f.user?.lastName}</div>
                                                        <div className="text-muted" style={{ fontSize: '0.72rem' }}>{f.user?.email}</div>
                                                    </div>
                                                </div>
                                            </td>
                                            <td>
                                                <span className={`badge rounded-pill px-3 py-1 ${f.flagType === 'Frequent Canceller' ? 'bg-danger-subtle text-danger' : 'bg-warning-subtle text-warning'}`}>
                                                    {f.flagType === 'Frequent Canceller' ? '🔁' : '⏰'} {f.flagType}
                                                </span>
                                            </td>
                                            <td>
                                                {f.flagType === 'Frequent Canceller'
                                                    ? <span>{f.cancellations} cancellations in last 30 days</span>
                                                    : <span>{f.hoursRemaining}h before event</span>}
                                            </td>
                                            <td className="px-3 text-muted">
                                                {f.lastRequest ? new Date(f.lastRequest).toLocaleDateString('en-IN') : '—'}
                                            </td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        </div>
                    )}
                </div>
            </div>

            {/* ─── Quick Stats Grid ─────────────────────────────────────────── */}
            <div className="row g-3">
                <div className="col-md-4">
                    <div className="card border-0 shadow-sm text-center py-4">
                        <div className="text-muted small mb-1">Total Wallet Credits Issued</div>
                        <div className="fw-bold fs-3 text-success">₹{kpis?.totalWalletCredits?.toLocaleString('en-IN') ?? '0'}</div>
                        <div className="text-muted" style={{ fontSize: '0.72rem' }}>Across all approved cancellations</div>
                    </div>
                </div>
                <div className="col-md-4">
                    <div className="card border-0 shadow-sm text-center py-4">
                        <div className="text-muted small mb-1">Avg Response Time</div>
                        <div className="fw-bold fs-3 text-primary">{kpis?.avgApprovalTimeMinutes ?? '0'} min</div>
                        <div className="text-muted" style={{ fontSize: '0.72rem' }}>From request to approval</div>
                    </div>
                </div>
                <div className="col-md-4">
                    <div className="card border-0 shadow-sm text-center py-4">
                        <div className="text-muted small mb-1">Avg Hours Before Event</div>
                        <div className="fw-bold fs-3 text-warning">{kpis?.avgHoursBeforeCancellation ?? '0'}h</div>
                        <div className="text-muted" style={{ fontSize: '0.72rem' }}>When request was made</div>
                    </div>
                </div>
            </div>
        </div>
    );
};
