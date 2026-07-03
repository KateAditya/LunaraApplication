import React from 'react';
import { BiShieldQuarter, BiCheckCircle, BiError, BiFile, BiTime } from 'react-icons/bi';

const complianceMetrics = [
    { label: 'Verification Rate', value: '94.2%', icon: <BiCheckCircle />, cls: 'success', desc: 'Users with verified identity' },
    { label: 'DPDP Compliance', value: '98.7%', icon: <BiShieldQuarter />, cls: 'primary', desc: 'Data protection compliance' },
    { label: 'Active Reports', value: '12', icon: <BiError />, cls: 'warning', desc: 'Pending safety reports' },
    { label: 'Policy Adherence', value: '99.1%', icon: <BiFile />, cls: 'info', desc: 'Venue compliance score' },
];

const recentReports = [
    { id: 'RPT-001', type: 'Safety Concern', venue: 'Neon District', reportedBy: 'Anonymous', date: '2026-02-21', priority: 'High', status: 'Open' },
    { id: 'RPT-002', type: 'Harassment', venue: 'Club Infinity', reportedBy: 'Priya K.', date: '2026-02-20', priority: 'Critical', status: 'Under Review' },
    { id: 'RPT-003', type: 'License Violation', venue: 'Beach Cafe', reportedBy: 'System', date: '2026-02-19', priority: 'Medium', status: 'Resolved' },
    { id: 'RPT-004', type: 'Overcrowding', venue: 'Grand Terrace', reportedBy: 'Anonymous', date: '2026-02-18', priority: 'High', status: 'Open' },
    { id: 'RPT-005', type: 'Noise Complaint', venue: 'Skybar Lounge', reportedBy: 'Resident', date: '2026-02-17', priority: 'Low', status: 'Resolved' },
];

const activityLog = [
    { time: '2 min ago', action: 'Venue license verified', target: 'Club Infinity', user: 'System' },
    { time: '15 min ago', action: 'Report escalated', target: 'RPT-002', user: 'Admin' },
    { time: '1 hour ago', action: 'DPDP data audit completed', target: 'All Venues', user: 'System' },
    { time: '3 hours ago', action: 'User identity manually verified', target: 'Vikram P.', user: 'Admin' },
    { time: '5 hours ago', action: 'Safety report resolved', target: 'RPT-003', user: 'Admin' },
];

const getPriorityBadge = (p: string) => {
    const map: Record<string, string> = { Critical: 'danger', High: 'warning', Medium: 'info', Low: 'secondary' };
    return map[p] || 'secondary';
};

const getStatusBadge = (s: string) => {
    const map: Record<string, string> = { Open: 'warning', 'Under Review': 'info', Resolved: 'success' };
    return map[s] || 'secondary';
};

export const Compliance: React.FC = () => {
    return (
        <div>
            {/* Metric Cards */}
            <div className="row g-3 mb-4">
                {complianceMetrics.map((m, i) => (
                    <div className="col-sm-6 col-xl-3" key={m.label}>
                        <div className={`stat-card animate-in animate-in-${i + 1}`}>
                            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                                <div>
                                    <div className="stat-card-label">{m.label}</div>
                                    <div className="stat-card-value">{m.value}</div>
                                    <div style={{ fontSize: '0.6875rem', color: 'var(--vz-text-muted)', marginTop: '0.25rem' }}>
                                        {m.desc}
                                    </div>
                                </div>
                                <div className={`stat-card-icon ${m.cls}`}>{m.icon}</div>
                            </div>
                        </div>
                    </div>
                ))}
            </div>

            <div className="row g-3">
                {/* Reports Table */}
                <div className="col-xl-8">
                    <div className="vz-card animate-in animate-in-5">
                        <div className="vz-card-header">
                            <h6 className="vz-card-title">Recent Reports</h6>
                            <button className="vz-btn vz-btn-outline vz-btn-sm">View All</button>
                        </div>
                        <div className="vz-card-body" style={{ padding: 0 }}>
                            <div className="vz-table-wrapper">
                                <table className="vz-table">
                                    <thead>
                                        <tr>
                                            <th>ID</th>
                                            <th>Type</th>
                                            <th>Venue</th>
                                            <th>Reported By</th>
                                            <th>Priority</th>
                                            <th>Status</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        {recentReports.map((r) => (
                                            <tr key={r.id}>
                                                <td style={{ fontWeight: 600, color: 'var(--vz-primary)' }}>{r.id}</td>
                                                <td style={{ fontWeight: 500 }}>{r.type}</td>
                                                <td style={{ color: 'var(--vz-text-muted)' }}>{r.venue}</td>
                                                <td style={{ color: 'var(--vz-text-muted)' }}>{r.reportedBy}</td>
                                                <td><span className={`vz-badge ${getPriorityBadge(r.priority)}`}>{r.priority}</span></td>
                                                <td><span className={`vz-badge ${getStatusBadge(r.status)}`}>{r.status}</span></td>
                                            </tr>
                                        ))}
                                    </tbody>
                                </table>
                            </div>
                        </div>
                    </div>
                </div>

                {/* Activity Log */}
                <div className="col-xl-4">
                    <div className="vz-card animate-in animate-in-6">
                        <div className="vz-card-header">
                            <h6 className="vz-card-title">Activity Log</h6>
                        </div>
                        <div className="vz-card-body" style={{ padding: 0 }}>
                            {activityLog.map((a, i) => (
                                <div
                                    key={i}
                                    style={{
                                        display: 'flex',
                                        gap: '0.75rem',
                                        padding: '0.75rem 1.25rem',
                                        borderBottom: i < activityLog.length - 1 ? '1px solid var(--vz-border-color)' : 'none',
                                        alignItems: 'flex-start',
                                    }}
                                >
                                    <div style={{
                                        width: 32,
                                        height: 32,
                                        borderRadius: '50%',
                                        background: 'rgba(var(--vz-primary-rgb), 0.1)',
                                        display: 'flex',
                                        alignItems: 'center',
                                        justifyContent: 'center',
                                        flexShrink: 0,
                                        color: 'var(--vz-primary)',
                                        fontSize: '0.875rem',
                                    }}>
                                        <BiTime />
                                    </div>
                                    <div style={{ minWidth: 0 }}>
                                        <div style={{ fontSize: '0.8125rem', fontWeight: 500, color: 'var(--vz-text-primary)' }}>
                                            {a.action}
                                        </div>
                                        <div style={{ fontSize: '0.6875rem', color: 'var(--vz-text-muted)' }}>
                                            {a.target} · by {a.user}
                                        </div>
                                        <div style={{ fontSize: '0.625rem', color: 'var(--vz-text-muted)', marginTop: '0.125rem' }}>
                                            {a.time}
                                        </div>
                                    </div>
                                </div>
                            ))}
                        </div>
                    </div>
                </div>
            </div>
        </div>
    );
};

export default Compliance;
