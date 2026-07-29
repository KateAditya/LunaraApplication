import React, { useState, useEffect } from 'react';
import { BiBlock, BiShow, BiLoaderAlt, BiUserCheck, BiMessageSquareDetail, BiUserX } from 'react-icons/bi';
import { usersApi } from '../api/users';
import type { User } from '../types/user';
import toast from 'react-hot-toast';

export const ReportedUsers: React.FC = () => {
    const [currentPage, setCurrentPage] = useState(1);
    const perPage = 10;

    // API Data state
    const [reports, setReports] = useState<any[]>([]);
    const [loading, setLoading] = useState(true);
    const [totalReports, setTotalReports] = useState(0);
    const [totalPages, setTotalPages] = useState(1);

    const loadReportedUsers = async () => {
        try {
            setLoading(true);
            const response = await usersApi.getReportedUsers({
                page: currentPage,
                limit: perPage,
            });

            if (response.success) {
                const resData = response as any;
                if (resData.reports) {
                    setReports(resData.reports);
                    setTotalReports(resData.count || 0);
                    setTotalPages(resData.totalPages || 1);
                } else if (resData.data?.reports) {
                    setReports(resData.data.reports);
                    setTotalReports(resData.data.pagination?.total || 0);
                    setTotalPages(resData.data.pagination?.totalPages || 1);
                }
            } else {
                toast.error('Failed to load reported users');
            }
        } catch (error) {
            console.error('Error loading reported users:', error);
            toast.error('Failed to load reported users');
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        loadReportedUsers();
    }, [currentPage]);

    const handleDeactivate = async (userId: string, userName: string) => {
        if (window.confirm(`Are you sure you want to deactivate "${userName}"? They will not be able to log in.`)) {
            try {
                const res = await usersApi.deactivateUser(userId);
                if (res.success) {
                    toast.success(`User "${userName}" has been deactivated!`);
                    loadReportedUsers();
                } else {
                    toast.error(res.message || 'Failed to deactivate user');
                }
            } catch (error) {
                console.error('Deactivate error:', error);
                toast.error('Failed to deactivate user');
            }
        }
    };

    return (
        <div>
            {/* Warning banner */}
            <div className="vz-card mb-3 animate-in animate-in-1" style={{ borderLeft: '4px solid #f59e0b' }}>
                <div className="vz-card-body" style={{ padding: '1rem 1.25rem' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
                        <div style={{
                            width: 38,
                            height: 38,
                            borderRadius: '50%',
                            background: 'rgba(245, 158, 11, 0.1)',
                            display: 'flex',
                            alignItems: 'center',
                            justifyContent: 'center',
                            color: '#f59e0b',
                            fontSize: '1.25rem',
                            flexShrink: 0
                        }}>
                            <BiMessageSquareDetail />
                        </div>
                        <div>
                            <h6 style={{ margin: 0, fontWeight: 700, color: 'var(--vz-text-primary)' }}>Reported Users Management</h6>
                            <p style={{ margin: 0, fontSize: '0.75rem', color: 'var(--vz-text-muted)', marginTop: '0.125rem' }}>
                                This section displays users who have been reported by others. You can view the report reasons and take necessary actions, such as deactivating their accounts.
                            </p>
                        </div>
                    </div>
                </div>
            </div>

            {/* Table */}
            <div className="vz-card animate-in animate-in-2">
                <div className="vz-card-body" style={{ padding: 0 }}>
                    <div className="vz-table-wrapper">
                        <table className="vz-table">
                            <thead>
                                <tr>
                                    <th style={{ width: 50 }}>#</th>
                                    <th>Reported User</th>
                                    <th>Email</th>
                                    <th>Total Blocks Received</th>
                                    <th>Report Reason</th>
                                    <th>Report Date</th>
                                    <th style={{ width: 120 }}>Actions</th>
                                </tr>
                            </thead>
                            <tbody>
                                {loading ? (
                                    <tr>
                                        <td colSpan={7} style={{ textAlign: 'center', padding: '3rem', color: 'var(--vz-text-muted)' }}>
                                            <BiLoaderAlt className="vz-spin" style={{ fontSize: '1.5rem', marginBottom: '0.5rem', color: 'var(--vz-primary)' }} />
                                            <div>Loading reported users...</div>
                                        </td>
                                    </tr>
                                ) : reports.length === 0 ? (
                                    <tr>
                                        <td colSpan={7} style={{ textAlign: 'center', padding: '2rem', color: 'var(--vz-text-muted)' }}>
                                            No reported users found.
                                        </td>
                                    </tr>
                                ) : (
                                    reports.map((report: any, idx: number) => {
                                        const user = report.user;
                                        if (!user) return null;
                                        return (
                                            <tr key={report.id || idx}>
                                                <td style={{ color: 'var(--vz-text-muted)' }}>
                                                    {(currentPage - 1) * perPage + idx + 1}
                                                </td>
                                                <td>
                                                    <div style={{ display: 'flex', alignItems: 'center', gap: '0.625rem' }}>
                                                        <div style={{
                                                            width: 32,
                                                            height: 32,
                                                            borderRadius: '50%',
                                                            background: `linear-gradient(135deg, #f59e0b, #e6533c)`,
                                                            display: 'flex',
                                                            alignItems: 'center',
                                                            justifyContent: 'center',
                                                            color: '#fff',
                                                            fontWeight: 600,
                                                            fontSize: '0.6875rem',
                                                            flexShrink: 0,
                                                        }}>
                                                            {user.firstName?.charAt(0)}{user.lastName?.charAt(0)}
                                                        </div>
                                                        <div>
                                                            <div style={{ fontWeight: 600, fontSize: '0.8125rem' }}>{user.firstName} {user.lastName}</div>
                                                            <div style={{ fontSize: '0.6875rem', color: 'var(--vz-text-muted)' }}>
                                                                Status: {user.isActive ? 'Active' : 'Inactive'}
                                                            </div>
                                                        </div>
                                                    </div>
                                                </td>
                                                <td>
                                                    <div style={{ fontSize: '0.8125rem', color: 'var(--vz-text-primary)' }}>{user.email}</div>
                                                </td>
                                                <td>
                                                    <span style={{
                                                        fontWeight: 700,
                                                        color: '#e6533c',
                                                        fontSize: '0.875rem',
                                                        background: 'rgba(230, 83, 60, 0.1)',
                                                        padding: '0.125rem 0.5rem',
                                                        borderRadius: '4px'
                                                    }}>
                                                        {user.blockCount ?? 0} blocks
                                                    </span>
                                                </td>
                                                <td>
                                                    <div style={{ display: 'flex', alignItems: 'center', gap: '0.25rem', fontSize: '0.75rem', color: 'var(--vz-text-secondary)' }}>
                                                        <BiMessageSquareDetail style={{ flexShrink: 0 }} />
                                                        <span style={{ maxWidth: 200, display: 'inline-block', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }} title={report.reason}>
                                                            {report.reason}
                                                        </span>
                                                    </div>
                                                </td>
                                                <td style={{ color: 'var(--vz-text-muted)', fontSize: '0.75rem' }}>
                                                    {report.createdAt ? new Date(report.createdAt).toLocaleString('en-IN', { dateStyle: 'medium', timeStyle: 'short' }) : 'N/A'}
                                                </td>
                                                <td>
                                                    <div style={{ display: 'flex', gap: '0.375rem' }}>
                                                        {user.isActive && (
                                                            <button
                                                                className="vz-btn vz-btn-danger vz-btn-xs"
                                                                style={{ display: 'flex', alignItems: 'center', gap: '4px', fontSize: '0.6875rem', padding: '0.25rem 0.5rem' }}
                                                                onClick={() => handleDeactivate(user.id, `${user.firstName} ${user.lastName}`)}
                                                            >
                                                                <BiUserX />
                                                                <span>Deactivate</span>
                                                            </button>
                                                        )}
                                                    </div>
                                                </td>
                                            </tr>
                                        );
                                    })
                                )}
                            </tbody>
                        </table>
                    </div>
                </div>

                {/* Pagination */}
                {totalPages > 1 && (
                    <div style={{
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'space-between',
                        padding: '0.75rem 1.25rem',
                        borderTop: '1px solid var(--vz-border-color)',
                    }}>
                        <span style={{ fontSize: '0.75rem', color: 'var(--vz-text-muted)' }}>
                            Showing {(currentPage - 1) * perPage + 1}–{Math.min(currentPage * perPage, totalReports)} of {totalReports}
                        </span>
                        <div style={{ display: 'flex', gap: '0.25rem' }}>
                            <button
                                className="vz-btn vz-btn-outline vz-btn-sm"
                                disabled={currentPage === 1}
                                onClick={() => setCurrentPage(p => p - 1)}
                            >Prev</button>
                            {Array.from({ length: Math.min(totalPages, 5) }, (_, i) => i + 1).map(p => (
                                <button
                                    key={p}
                                    className={`vz-btn vz-btn-sm ${currentPage === p ? 'vz-btn-primary' : 'vz-btn-outline'}`}
                                    onClick={() => setCurrentPage(p)}
                                >
                                    {p}
                                </button>
                            ))}
                            <button
                                className="vz-btn vz-btn-outline vz-btn-sm"
                                disabled={currentPage === totalPages}
                                onClick={() => setCurrentPage(p => p + 1)}
                            >Next</button>
                        </div>
                    </div>
                )}
            </div>
        </div>
    );
};
