import React, { useState, useEffect, useCallback, useMemo } from 'react';
import toast from 'react-hot-toast';
import {
    BiSearch,
    BiRefresh,
    BiCheckCircle,
    BiCopy,
    BiMoney,
    BiGroup,
    BiUserPin,
    BiParty,
    BiDetail,
    BiCheck,
} from 'react-icons/bi';
import cancellationRequestsApi, {
    type GroupPartyCancellationItem,
    type LargePartyCancellationItem,
    type StrangerMeetCancellationItem,
    type PayoutDetails,
} from '../api/cancellationRequests';
type TabType = 'group_party' | 'large_party' | 'stranger_meet';

export const CancellationRequests: React.FC = () => {

    const [activeTab, setActiveTab] = useState<TabType>('group_party');
    const [statusFilter, setStatusFilter] = useState<string>('all');
    const [search, setSearch] = useState<string>('');

    // Data States
    const [loading, setLoading] = useState<boolean>(false);
    const [groupParties, setGroupParties] = useState<GroupPartyCancellationItem[]>([]);
    const [largeParties, setLargeParties] = useState<LargePartyCancellationItem[]>([]);
    const [strangerMeets, setStrangerMeets] = useState<StrangerMeetCancellationItem[]>([]);

    // Selected item for details
    const [detailItem, setDetailItem] = useState<{
        tab: TabType;
        data: GroupPartyCancellationItem | LargePartyCancellationItem | StrangerMeetCancellationItem;
    } | null>(null);

    // Modals
    const [markPaidTarget, setMarkPaidTarget] = useState<{
        tab: TabType;
        id: string;
        memberRefundId?: string;
        recipientName: string;
        recipientPhone?: string;
        amount: number;
        payoutDetails?: PayoutDetails;
    } | null>(null);

    const [utrReference, setUtrReference] = useState<string>('');
    const [payoutNotes, setPayoutNotes] = useState<string>('');
    const [submittingAction, setSubmittingAction] = useState<boolean>(false);

    // Large Party / Stranger Meet Approve & Reject Modals
    const [approveTarget, setApproveTarget] = useState<{
        tab: 'large_party' | 'stranger_meet';
        id: string;
        title: string;
        amount: number;
        guests: number;
    } | null>(null);
    const [approveRefundPercentage, setApproveRefundPercentage] = useState<number>(100);
    const [approveNotes, setApproveNotes] = useState<string>('');
    const [approveRefundMethod, setApproveRefundMethod] = useState<'MANUAL_PAYOUT' | 'WALLET'>('MANUAL_PAYOUT');

    const [rejectTarget, setRejectTarget] = useState<{
        tab: 'large_party' | 'stranger_meet';
        id: string;
        title: string;
    } | null>(null);
    const [rejectionReason, setRejectionReason] = useState<string>('');

    // Fetch handlers
    const fetchData = useCallback(async () => {
        setLoading(true);
        try {
            if (activeTab === 'group_party') {
                const res = await cancellationRequestsApi.getGroupPartyCancellations({
                    status: statusFilter,
                    search: search.trim() || undefined,
                });
                if (res.success) {
                    setGroupParties(res.data || []);
                }
            } else if (activeTab === 'large_party') {
                const res = await cancellationRequestsApi.getLargePartyCancellations({
                    status: statusFilter,
                    search: search.trim() || undefined,
                });
                if (res.success) {
                    setLargeParties(res.items || []);
                }
            } else if (activeTab === 'stranger_meet') {
                const res = await cancellationRequestsApi.getStrangerMeetCancellations({
                    status: statusFilter,
                    search: search.trim() || undefined,
                });
                if (res.success && res.data) {
                    setStrangerMeets(res.data.cancellations || []);
                }
            }
        } catch (err: any) {
            toast.error(err.response?.data?.message || 'Failed to load cancellation requests');
        } finally {
            setLoading(false);
        }
    }, [activeTab, statusFilter, search]);

    useEffect(() => {
        fetchData();
    }, [fetchData]);

    // Helpers
    const copyToClipboard = (text: string, label: string) => {
        if (!text) return;
        navigator.clipboard.writeText(text);
        toast.success(`Copied ${label}: ${text}`);
    };

    const formatCurrency = (amt?: number) => {
        if (amt === undefined || amt === null) return '₹0';
        return `₹${Number(amt).toLocaleString('en-IN')}`;
    };

    const formatDate = (dateStr?: string) => {
        if (!dateStr) return '—';
        try {
            return new Date(dateStr).toLocaleDateString('en-IN', {
                day: '2-digit',
                month: 'short',
                year: 'numeric',
                hour: '2-digit',
                minute: '2-digit',
            });
        } catch {
            return dateStr;
        }
    };

    // KPI Calculations
    const kpis = useMemo(() => {
        const gpPending = groupParties.filter((g) => g.refundStatus === 'PENDING_PAYOUT').length;
        const gpPaid = groupParties.filter((g) => g.refundStatus === 'COMPLETED').length;
        const lpPending = largeParties.filter(
            (l) => l.status === 'PENDING_ADMIN_REVIEW' || l.status === 'REFUND_PROCESSING'
        ).length;
        const lpCompleted = largeParties.filter((l) => l.status === 'COMPLETED').length;
        const smPending = strangerMeets.filter(
            (s) => s.status === 'PENDING_ADMIN_REVIEW' || s.status === 'REFUND_PROCESSING'
        ).length;
        const smCompleted = strangerMeets.filter((s) => s.status === 'COMPLETED').length;

        const totalPending = gpPending + lpPending + smPending;
        const totalCompleted = gpPaid + lpCompleted + smCompleted;

        return {
            gpPending,
            gpPaid,
            lpPending,
            lpCompleted,
            smPending,
            smCompleted,
            totalPending,
            totalCompleted,
        };
    }, [groupParties, largeParties, strangerMeets]);

    // Action Handlers
    const handleMarkPaidSubmit = async () => {
        if (!markPaidTarget) return;
        if (!utrReference.trim()) {
            toast.error('Please enter the UTR or Bank Transaction Reference number');
            return;
        }

        setSubmittingAction(true);
        try {
            if (markPaidTarget.tab === 'group_party') {
                const res = await cancellationRequestsApi.markGroupPartyRefundPaid(markPaidTarget.id, {
                    paymentReference: utrReference.trim(),
                    notes: payoutNotes.trim() || undefined,
                });
                if (res.success) {
                    toast.success('Group Party refund marked as PAID! Notification sent to user.');
                }
            } else if (markPaidTarget.tab === 'large_party') {
                const res = await cancellationRequestsApi.markLargePartyRefundPaid(markPaidTarget.id, {
                    paymentReference: utrReference.trim(),
                    paymentNotes: payoutNotes.trim() || undefined,
                });
                if (res.success) {
                    toast.success('Large Party refund marked as PAID! Notification sent to user.');
                }
            } else if (markPaidTarget.tab === 'stranger_meet') {
                if (markPaidTarget.memberRefundId) {
                    // Member refund settlement
                    const res = await cancellationRequestsApi.markStrangerMeetMemberRefundPaid(
                        markPaidTarget.memberRefundId,
                        {
                            paymentReference: utrReference.trim(),
                            paymentMethod: 'MANUAL_PAYOUT',
                        }
                    );
                    if (res.success) {
                        toast.success('Member refund marked as PAID!');
                    }
                } else {
                    // Host refund settlement
                    const res = await cancellationRequestsApi.settleStrangerMeetHostRefund(markPaidTarget.id, {
                        paymentReference: utrReference.trim(),
                        notes: payoutNotes.trim() || undefined,
                    });
                    if (res.success) {
                        toast.success('Host refund settled and marked as PAID!');
                    }
                }
            }

            setMarkPaidTarget(null);
            setUtrReference('');
            setPayoutNotes('');
            fetchData();
        } catch (err: any) {
            toast.error(err.response?.data?.message || 'Failed to mark as paid');
        } finally {
            setSubmittingAction(false);
        }
    };

    const handleApproveSubmit = async () => {
        if (!approveTarget) return;
        if (approveRefundPercentage < 0 || approveRefundPercentage > 100) {
            toast.error('Refund percentage must be between 0% and 100%');
            return;
        }

        setSubmittingAction(true);
        try {
            if (approveTarget.tab === 'large_party') {
                const res = await cancellationRequestsApi.approveLargePartyCancellation(approveTarget.id, {
                    refundPercentage: approveRefundPercentage,
                    refundMethod: approveRefundMethod,
                    adminNotes: approveNotes.trim() || undefined,
                });
                if (res.success) {
                    toast.success('Large Party cancellation approved! User notified.');
                }
            } else if (approveTarget.tab === 'stranger_meet') {
                const res = await cancellationRequestsApi.approveStrangerMeetCancellation(approveTarget.id, {
                    refundPercentage: approveRefundPercentage,
                    refundMethod: approveRefundMethod,
                    adminNotes: approveNotes.trim() || undefined,
                    hostRefundDecision: approveRefundPercentage === 100 ? 'FULL' : 'PARTIAL',
                    hostRefundPercentage: approveRefundPercentage,
                    hostRefundDestination: approveRefundMethod === 'WALLET' ? 'WALLET' : 'UPI',
                });
                if (res.success) {
                    toast.success('Stranger Meet cancellation approved! Users notified.');
                }
            }
            setApproveTarget(null);
            setApproveNotes('');
            fetchData();
        } catch (err: any) {
            toast.error(err.response?.data?.message || 'Failed to approve request');
        } finally {
            setSubmittingAction(false);
        }
    };

    const handleRejectSubmit = async () => {
        if (!rejectTarget) return;
        if (!rejectionReason.trim()) {
            toast.error('Please specify the reason for rejecting this cancellation');
            return;
        }

        setSubmittingAction(true);
        try {
            if (rejectTarget.tab === 'large_party') {
                const res = await cancellationRequestsApi.rejectLargePartyCancellation(rejectTarget.id, {
                    rejectionReason: rejectionReason.trim(),
                });
                if (res.success) {
                    toast.success('Large Party cancellation rejected. User notified.');
                }
            } else if (rejectTarget.tab === 'stranger_meet') {
                const res = await cancellationRequestsApi.rejectStrangerMeetCancellation(rejectTarget.id, {
                    reason: rejectionReason.trim(),
                });
                if (res.success) {
                    toast.success('Stranger Meet cancellation rejected. User notified.');
                }
            }
            setRejectTarget(null);
            setRejectionReason('');
            fetchData();
        } catch (err: any) {
            toast.error(err.response?.data?.message || 'Failed to reject cancellation');
        } finally {
            setSubmittingAction(false);
        }
    };

    // Payout details badge renderer
    const renderPayoutBadge = (p?: PayoutDetails) => {
        if (!p) {
            return <span className="text-muted small">No payout info</span>;
        }
        if (p.upiId || p.upiPhoneNumber) {
            const val = p.upiId || p.upiPhoneNumber || '';
            return (
                <div className="d-flex align-items-center gap-1">
                    <span className="badge bg-primary-subtle text-primary border border-primary-subtle px-2 py-1">
                        UPI: {val}
                    </span>
                    <button
                        type="button"
                        className="btn btn-sm btn-link p-0 text-muted"
                        title="Copy UPI ID"
                        onClick={() => copyToClipboard(val, 'UPI ID')}
                    >
                        <BiCopy size={15} />
                    </button>
                </div>
            );
        }
        if (p.accountNumber) {
            return (
                <div className="d-flex flex-column gap-1">
                    <div className="d-flex align-items-center gap-1">
                        <span className="badge bg-info-subtle text-info border border-info-subtle px-2 py-1">
                            A/C: {p.accountNumber} ({p.ifscCode || 'IFSC'})
                        </span>
                        <button
                            type="button"
                            className="btn btn-sm btn-link p-0 text-muted"
                            title="Copy Account Number"
                            onClick={() => copyToClipboard(p.accountNumber!, 'Account Number')}
                        >
                            <BiCopy size={15} />
                        </button>
                    </div>
                    {p.accountHolderName && (
                        <span className="text-muted" style={{ fontSize: '11px' }}>
                            {p.accountHolderName} • {p.bankName || ''}
                        </span>
                    )}
                </div>
            );
        }
        return <span className="badge bg-secondary-subtle text-secondary px-2 py-1">Wallet / None</span>;
    };

    return (
        <div className="container-fluid px-4 py-3">
            {/* Header */}
            <div className="d-flex flex-wrap justify-content-between align-items-center mb-4 gap-3">
                <div>
                    <h3 className="fw-bold mb-1 d-flex align-items-center gap-2">
                        <BiMoney className="text-primary" /> Cancellation & Refund Requests
                    </h3>
                    <p className="text-muted mb-0 small">
                        Manage refund requests for Group Parties (&gt; ₹1,500), Large Parties (&gt; 20 guests), and Stranger Meets with payout settlement.
                    </p>
                </div>

                <div className="d-flex align-items-center gap-2">
                    <button
                        className="btn btn-outline-secondary d-flex align-items-center gap-1"
                        onClick={fetchData}
                        disabled={loading}
                    >
                        <BiRefresh className={loading ? 'spin' : ''} size={18} />
                        Refresh
                    </button>
                </div>
            </div>

            {/* KPI Metric Summary Cards */}
            <div className="row g-3 mb-4">
                <div className="col-sm-6 col-xl-3">
                    <div className="vz-card p-3 d-flex align-items-center justify-content-between shadow-sm">
                        <div>
                            <span className="text-muted small fw-semibold d-block">GROUP PARTY PENDING</span>
                            <h4 className="fw-bold mb-0 text-warning mt-1">{kpis.gpPending}</h4>
                            <span className="text-muted" style={{ fontSize: '11px' }}>
                                &gt; ₹1,500 External Payouts
                            </span>
                        </div>
                        <div
                            className="rounded-3 p-3 d-flex align-items-center justify-content-center"
                            style={{ background: 'rgba(245, 158, 11, 0.12)', color: '#f59e0b' }}
                        >
                            <BiParty size={26} />
                        </div>
                    </div>
                </div>

                <div className="col-sm-6 col-xl-3">
                    <div className="vz-card p-3 d-flex align-items-center justify-content-between shadow-sm">
                        <div>
                            <span className="text-muted small fw-semibold d-block">LARGE PARTY PENDING</span>
                            <h4 className="fw-bold mb-0 text-primary mt-1">{kpis.lpPending}</h4>
                            <span className="text-muted" style={{ fontSize: '11px' }}>
                                &gt; 20 Guests Reviews
                            </span>
                        </div>
                        <div
                            className="rounded-3 p-3 d-flex align-items-center justify-content-center"
                            style={{ background: 'rgba(59, 130, 246, 0.12)', color: '#3b82f6' }}
                        >
                            <BiGroup size={26} />
                        </div>
                    </div>
                </div>

                <div className="col-sm-6 col-xl-3">
                    <div className="vz-card p-3 d-flex align-items-center justify-content-between shadow-sm">
                        <div>
                            <span className="text-muted small fw-semibold d-block">STRANGER MEET PENDING</span>
                            <h4 className="fw-bold mb-0 text-info mt-1">{kpis.smPending}</h4>
                            <span className="text-muted" style={{ fontSize: '11px' }}>
                                Host & Members Refunds
                            </span>
                        </div>
                        <div
                            className="rounded-3 p-3 d-flex align-items-center justify-content-center"
                            style={{ background: 'rgba(14, 165, 233, 0.12)', color: '#0ea5e9' }}
                        >
                            <BiUserPin size={26} />
                        </div>
                    </div>
                </div>

                <div className="col-sm-6 col-xl-3">
                    <div className="vz-card p-3 d-flex align-items-center justify-content-between shadow-sm">
                        <div>
                            <span className="text-muted small fw-semibold d-block">TOTAL SETTLED / PAID</span>
                            <h4 className="fw-bold mb-0 text-success mt-1">{kpis.totalCompleted}</h4>
                            <span className="text-muted" style={{ fontSize: '11px' }}>
                                Fully Processed Requests
                            </span>
                        </div>
                        <div
                            className="rounded-3 p-3 d-flex align-items-center justify-content-center"
                            style={{ background: 'rgba(16, 185, 129, 0.12)', color: '#10b981' }}
                        >
                            <BiCheckCircle size={26} />
                        </div>
                    </div>
                </div>
            </div>

            {/* Navigation Tabs */}
            <div className="vz-card mb-4">
                <div className="border-bottom px-3 pt-3">
                    <ul className="nav nav-tabs border-0 gap-2">
                        <li className="nav-item">
                            <button
                                className={`nav-link pb-3 px-3 fw-semibold ${activeTab === 'group_party' ? 'active text-primary border-bottom border-primary border-3' : 'text-muted'}`}
                                onClick={() => {
                                    setActiveTab('group_party');
                                    setStatusFilter('all');
                                }}
                            >
                                <BiParty className="me-1" size={18} />
                                Group Party (&gt; ₹1,500)
                                {kpis.gpPending > 0 && (
                                    <span className="badge bg-warning text-dark ms-2 rounded-pill">
                                        {kpis.gpPending}
                                    </span>
                                )}
                            </button>
                        </li>
                        <li className="nav-item">
                            <button
                                className={`nav-link pb-3 px-3 fw-semibold ${activeTab === 'large_party' ? 'active text-primary border-bottom border-primary border-3' : 'text-muted'}`}
                                onClick={() => {
                                    setActiveTab('large_party');
                                    setStatusFilter('all');
                                }}
                            >
                                <BiGroup className="me-1" size={18} />
                                Large Party (&gt; 20 Guests)
                                {kpis.lpPending > 0 && (
                                    <span className="badge bg-primary ms-2 rounded-pill">
                                        {kpis.lpPending}
                                    </span>
                                )}
                            </button>
                        </li>
                        <li className="nav-item">
                            <button
                                className={`nav-link pb-3 px-3 fw-semibold ${activeTab === 'stranger_meet' ? 'active text-primary border-bottom border-primary border-3' : 'text-muted'}`}
                                onClick={() => {
                                    setActiveTab('stranger_meet');
                                    setStatusFilter('all');
                                }}
                            >
                                <BiUserPin className="me-1" size={18} />
                                Stranger Meet
                                {kpis.smPending > 0 && (
                                    <span className="badge bg-info ms-2 rounded-pill">
                                        {kpis.smPending}
                                    </span>
                                )}
                            </button>
                        </li>
                    </ul>
                </div>

                {/* Filter and Search Bar */}
                <div className="p-3 d-flex flex-wrap align-items-center justify-content-between gap-3">
                    <div className="d-flex align-items-center gap-2 flex-grow-1" style={{ maxWidth: 360 }}>
                        <div className="position-relative w-100">
                            <BiSearch
                                className="position-absolute"
                                style={{ left: 12, top: '50%', transform: 'translateY(-50%)', color: '#9ca3af' }}
                            />
                            <input
                                type="text"
                                className="form-control ps-5"
                                placeholder="Search by name, phone, venue..."
                                value={search}
                                onChange={(e) => setSearch(e.target.value)}
                            />
                        </div>
                    </div>

                    <div className="d-flex align-items-center gap-2">
                        <label className="text-muted small fw-semibold text-nowrap">Status:</label>
                        <select
                            className="form-select form-select-sm"
                            style={{ minWidth: 170 }}
                            value={statusFilter}
                            onChange={(e) => setStatusFilter(e.target.value)}
                        >
                            <option value="all">All Statuses</option>
                            <option value="pending">Pending Payout / Review</option>
                            <option value="completed">Paid / Completed</option>
                            <option value="rejected">Rejected</option>
                        </select>
                    </div>
                </div>
            </div>

            {/* TAB CONTENT */}

            {/* TAB 1: GROUP PARTY CANCELLATIONS (> ₹1,500) */}
            {activeTab === 'group_party' && (
                <div className="vz-card shadow-sm">
                    <div className="table-responsive">
                        <table className="vz-table align-middle">
                            <thead>
                                <tr>
                                    <th>User / Host</th>
                                    <th>Party & Venue</th>
                                    <th>Guests</th>
                                    <th>Total Paid</th>
                                    <th>Refund Amount</th>
                                    <th>Payout Details</th>
                                    <th>Status</th>
                                    <th>UTR / Reference</th>
                                    <th className="text-end">Actions</th>
                                </tr>
                            </thead>
                            <tbody>
                                {loading ? (
                                    <tr>
                                        <td colSpan={9} className="text-center py-5">
                                            <div className="spinner-border text-primary spinner-border-sm me-2" role="status"></div>
                                            Loading Group Party cancellations...
                                        </td>
                                    </tr>
                                ) : groupParties.length === 0 ? (
                                    <tr>
                                        <td colSpan={9} className="text-center py-5 text-muted">
                                            No Group Party cancellations found exceeding ₹1,500.
                                        </td>
                                    </tr>
                                ) : (
                                    groupParties.map((item) => {
                                        const isPaid = item.refundStatus === 'COMPLETED';
                                        const isPending = item.refundStatus === 'PENDING_PAYOUT';
                                        const creatorName = item.creator
                                            ? `${item.creator.firstName || ''} ${item.creator.lastName || ''}`.trim()
                                            : 'User';

                                        return (
                                            <tr key={item.id}>
                                                <td>
                                                    <div className="d-flex align-items-center gap-2">
                                                        <div
                                                            className="rounded-circle d-flex align-items-center justify-content-center text-white fw-bold small"
                                                            style={{ width: 36, height: 36, background: '#6366f1' }}
                                                        >
                                                            {creatorName[0] || 'U'}
                                                        </div>
                                                        <div>
                                                            <div className="fw-semibold">{creatorName}</div>
                                                            <div className="text-muted" style={{ fontSize: '11px' }}>
                                                                {item.creator?.phone || 'No Phone'}
                                                            </div>
                                                        </div>
                                                    </div>
                                                </td>
                                                <td>
                                                    <div className="fw-semibold">{item.partyTitle}</div>
                                                    <div className="text-muted small">
                                                        {item.venue?.name || 'Venue'} • {formatDate(item.partyDate)}
                                                    </div>
                                                </td>
                                                <td>
                                                    <span className="badge bg-secondary-subtle text-secondary px-2 py-1">
                                                        {item.numberOfFriends} guests
                                                    </span>
                                                </td>
                                                <td className="fw-semibold">{formatCurrency(item.totalAmount)}</td>
                                                <td>
                                                    <span className="fw-bold text-danger">
                                                        {formatCurrency(item.refundAmount)}
                                                    </span>
                                                </td>
                                                <td>{renderPayoutBadge(item.refundPayoutDetails)}</td>
                                                <td>
                                                    {isPaid ? (
                                                        <span className="badge bg-success-subtle text-success border border-success-subtle px-2 py-1">
                                                            REFUND PAID
                                                        </span>
                                                    ) : isPending ? (
                                                        <span className="badge bg-warning-subtle text-warning border border-warning-subtle px-2 py-1">
                                                            PENDING PAYOUT
                                                        </span>
                                                    ) : (
                                                        <span className="badge bg-secondary-subtle text-secondary px-2 py-1">
                                                            {item.refundStatus || 'CANCELLED'}
                                                        </span>
                                                    )}
                                                </td>
                                                <td>
                                                    {item.refundTransactionReference ? (
                                                        <span className="badge bg-light text-dark border px-2 py-1 font-monospace">
                                                            {item.refundTransactionReference}
                                                        </span>
                                                    ) : (
                                                        <span className="text-muted small">—</span>
                                                    )}
                                                </td>
                                                <td className="text-end">
                                                    <div className="d-flex align-items-center justify-content-end gap-2">
                                                        {isPending && (
                                                            <button
                                                                className="btn btn-sm btn-success d-flex align-items-center gap-1 text-nowrap"
                                                                onClick={() => {
                                                                    setMarkPaidTarget({
                                                                        tab: 'group_party',
                                                                        id: item.id,
                                                                        recipientName: creatorName,
                                                                        recipientPhone: item.creator?.phone,
                                                                        amount: item.refundAmount,
                                                                        payoutDetails: item.refundPayoutDetails,
                                                                    });
                                                                    setUtrReference('');
                                                                    setPayoutNotes('');
                                                                }}
                                                            >
                                                                <BiCheckCircle size={15} /> Mark as Paid
                                                            </button>
                                                        )}
                                                        <button
                                                            className="btn btn-sm btn-outline-secondary"
                                                            title="View Details"
                                                            onClick={() => setDetailItem({ tab: 'group_party', data: item })}
                                                        >
                                                            <BiDetail size={15} />
                                                        </button>
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
            )}

            {/* TAB 2: LARGE PARTY CANCELLATIONS (> 20 GUESTS) */}
            {activeTab === 'large_party' && (
                <div className="vz-card shadow-sm">
                    <div className="table-responsive">
                        <table className="vz-table align-middle">
                            <thead>
                                <tr>
                                    <th>User / Host</th>
                                    <th>Booking & Venue</th>
                                    <th>Guests</th>
                                    <th>Booking Amt</th>
                                    <th>Refund Eligible</th>
                                    <th>Payout Details</th>
                                    <th>Status</th>
                                    <th>UTR / Ref</th>
                                    <th className="text-end">Actions</th>
                                </tr>
                            </thead>
                            <tbody>
                                {loading ? (
                                    <tr>
                                        <td colSpan={9} className="text-center py-5">
                                            <div className="spinner-border text-primary spinner-border-sm me-2" role="status"></div>
                                            Loading Large Party cancellations...
                                        </td>
                                    </tr>
                                ) : largeParties.length === 0 ? (
                                    <tr>
                                        <td colSpan={9} className="text-center py-5 text-muted">
                                            No Large Party cancellation requests found.
                                        </td>
                                    </tr>
                                ) : (
                                    largeParties.map((item) => {
                                        const isPendingReview = item.status === 'PENDING_ADMIN_REVIEW';
                                        const isApprovedOrProcessing =
                                            item.status === 'APPROVED' || item.status === 'REFUND_PROCESSING';
                                        const isCompleted = item.status === 'COMPLETED';
                                        const isRejected = item.status === 'REJECTED';
                                        const userName = item.user
                                            ? `${item.user.firstName || ''} ${item.user.lastName || ''}`.trim()
                                            : 'User';

                                        return (
                                            <tr key={item.id}>
                                                <td>
                                                    <div className="d-flex align-items-center gap-2">
                                                        <div
                                                            className="rounded-circle d-flex align-items-center justify-content-center text-white fw-bold small"
                                                            style={{ width: 36, height: 36, background: '#3b82f6' }}
                                                        >
                                                            {userName[0] || 'U'}
                                                        </div>
                                                        <div>
                                                            <div className="fw-semibold">{userName}</div>
                                                            <div className="text-muted" style={{ fontSize: '11px' }}>
                                                                {item.user?.phone || 'No Phone'}
                                                            </div>
                                                        </div>
                                                    </div>
                                                </td>
                                                <td>
                                                    <div className="fw-semibold">
                                                        {item.booking?.venue?.name || 'Venue'}
                                                    </div>
                                                    <div className="text-muted small">
                                                        {item.booking?.bookingNumber ? `#${item.booking.bookingNumber} • ` : ''}
                                                        {formatDate(item.booking?.eventDate)}
                                                    </div>
                                                </td>
                                                <td>
                                                    <span className="badge bg-primary-subtle text-primary border border-primary-subtle px-2 py-1">
                                                        {item.totalGuests} guests
                                                    </span>
                                                </td>
                                                <td className="fw-semibold">{formatCurrency(item.bookingAmount)}</td>
                                                <td>
                                                    <div className="d-flex flex-column">
                                                        <span className="fw-bold text-danger">
                                                            {formatCurrency(item.refundAmount)}
                                                        </span>
                                                        <span className="text-muted" style={{ fontSize: '11px' }}>
                                                            {item.approvedRefundPercentage ?? item.eligibleRefundPercentage ?? 0}% Refund
                                                        </span>
                                                    </div>
                                                </td>
                                                <td>{renderPayoutBadge(item.payoutDetails)}</td>
                                                <td>
                                                    {isCompleted ? (
                                                        <span className="badge bg-success-subtle text-success border border-success-subtle px-2 py-1">
                                                            REFUND PAID
                                                        </span>
                                                    ) : isApprovedOrProcessing ? (
                                                        <span className="badge bg-warning-subtle text-warning border border-warning-subtle px-2 py-1">
                                                            REFUND PROCESSING
                                                        </span>
                                                    ) : isPendingReview ? (
                                                        <span className="badge bg-info-subtle text-info border border-info-subtle px-2 py-1">
                                                            PENDING REVIEW
                                                        </span>
                                                    ) : isRejected ? (
                                                        <span className="badge bg-danger-subtle text-danger border border-danger-subtle px-2 py-1">
                                                            REJECTED
                                                        </span>
                                                    ) : (
                                                        <span className="badge bg-secondary-subtle text-secondary px-2 py-1">
                                                            {item.status}
                                                        </span>
                                                    )}
                                                </td>
                                                <td>
                                                    {item.paymentReference ? (
                                                        <span className="badge bg-light text-dark border px-2 py-1 font-monospace">
                                                            {item.paymentReference}
                                                        </span>
                                                    ) : (
                                                        <span className="text-muted small">—</span>
                                                    )}
                                                </td>
                                                <td className="text-end">
                                                    <div className="d-flex align-items-center justify-content-end gap-2">
                                                        {isPendingReview && (
                                                            <>
                                                                <button
                                                                    className="btn btn-sm btn-primary"
                                                                    onClick={() => {
                                                                        setApproveTarget({
                                                                            tab: 'large_party',
                                                                            id: item.id,
                                                                            title: `${item.booking?.venue?.name || 'Large Party'} (${item.totalGuests} guests)`,
                                                                            amount: item.bookingAmount,
                                                                            guests: item.totalGuests,
                                                                        });
                                                                        setApproveRefundPercentage(item.eligibleRefundPercentage || 100);
                                                                    }}
                                                                >
                                                                    Approve
                                                                </button>
                                                                <button
                                                                    className="btn btn-sm btn-danger"
                                                                    onClick={() => {
                                                                        setRejectTarget({
                                                                            tab: 'large_party',
                                                                            id: item.id,
                                                                            title: `${item.booking?.venue?.name || 'Large Party'} (${item.totalGuests} guests)`,
                                                                        });
                                                                    }}
                                                                >
                                                                    Reject
                                                                </button>
                                                            </>
                                                        )}

                                                        {isApprovedOrProcessing && (
                                                            <button
                                                                className="btn btn-sm btn-success d-flex align-items-center gap-1 text-nowrap"
                                                                onClick={() => {
                                                                    setMarkPaidTarget({
                                                                        tab: 'large_party',
                                                                        id: item.id,
                                                                        recipientName: userName,
                                                                        recipientPhone: item.user?.phone,
                                                                        amount: item.refundAmount,
                                                                        payoutDetails: item.payoutDetails,
                                                                    });
                                                                    setUtrReference('');
                                                                    setPayoutNotes('');
                                                                }}
                                                            >
                                                                <BiCheckCircle size={15} /> Mark as Paid
                                                            </button>
                                                        )}

                                                        <button
                                                            className="btn btn-sm btn-outline-secondary"
                                                            title="View Details"
                                                            onClick={() => setDetailItem({ tab: 'large_party', data: item })}
                                                        >
                                                            <BiDetail size={15} />
                                                        </button>
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
            )}

            {/* TAB 3: STRANGER MEET CANCELLATIONS */}
            {activeTab === 'stranger_meet' && (
                <div className="vz-card shadow-sm">
                    <div className="table-responsive">
                        <table className="vz-table align-middle">
                            <thead>
                                <tr>
                                    <th>Host</th>
                                    <th>Meet Subject & Venue</th>
                                    <th>Members</th>
                                    <th>Collected Amt</th>
                                    <th>Host Refund</th>
                                    <th>Payout Details</th>
                                    <th>Status</th>
                                    <th>Host UTR</th>
                                    <th className="text-end">Actions</th>
                                </tr>
                            </thead>
                            <tbody>
                                {loading ? (
                                    <tr>
                                        <td colSpan={9} className="text-center py-5">
                                            <div className="spinner-border text-primary spinner-border-sm me-2" role="status"></div>
                                            Loading Stranger Meet cancellations...
                                        </td>
                                    </tr>
                                ) : strangerMeets.length === 0 ? (
                                    <tr>
                                        <td colSpan={9} className="text-center py-5 text-muted">
                                            No Stranger Meet cancellation requests found.
                                        </td>
                                    </tr>
                                ) : (
                                    strangerMeets.map((item) => {
                                        const isPendingReview = item.status === 'PENDING_ADMIN_REVIEW';
                                        const isApprovedOrProcessing =
                                            item.status === 'APPROVED' || item.status === 'REFUND_PROCESSING';
                                        const isCompleted = item.status === 'COMPLETED';
                                        const isRejected = item.status === 'REJECTED';
                                        const hostName = item.host
                                            ? `${item.host.firstName || ''} ${item.host.lastName || ''}`.trim()
                                            : 'Host';

                                        const hostRefundPending =
                                            item.hostRefundStatus === 'HOST_REFUND_PENDING_SETTLEMENT' ||
                                            (isApprovedOrProcessing && (item.hostRefundAmount || 0) > 0 && item.hostRefundStatus !== 'PAID');

                                        return (
                                            <tr key={item.id}>
                                                <td>
                                                    <div className="d-flex align-items-center gap-2">
                                                        <div
                                                            className="rounded-circle d-flex align-items-center justify-content-center text-white fw-bold small"
                                                            style={{ width: 36, height: 36, background: '#0ea5e9' }}
                                                        >
                                                            {hostName[0] || 'H'}
                                                        </div>
                                                        <div>
                                                            <div className="fw-semibold">{hostName}</div>
                                                            <div className="text-muted" style={{ fontSize: '11px' }}>
                                                                {item.host?.phone || 'No Phone'}
                                                            </div>
                                                        </div>
                                                    </div>
                                                </td>
                                                <td>
                                                    <div className="fw-semibold">{item.meet?.subject || 'Stranger Meet'}</div>
                                                    <div className="text-muted small">
                                                        {item.meet?.venue?.name || 'Venue'} • {formatDate(item.meet?.eventDateTime)}
                                                    </div>
                                                </td>
                                                <td>
                                                    <span className="badge bg-info-subtle text-info border border-info-subtle px-2 py-1">
                                                        {item.totalMembersCount} members
                                                    </span>
                                                </td>
                                                <td className="fw-semibold">
                                                    {formatCurrency(item.totalCollectedAmount)}
                                                </td>
                                                <td>
                                                    <div className="d-flex flex-column">
                                                        <span className="fw-bold text-danger">
                                                            {formatCurrency(item.hostRefundAmount || item.totalRefundAmount || 0)}
                                                        </span>
                                                        <span className="text-muted" style={{ fontSize: '11px' }}>
                                                            {item.refundPolicyPercentage || 100}% Policy
                                                        </span>
                                                    </div>
                                                </td>
                                                <td>{renderPayoutBadge(item.hostPayoutDetails)}</td>
                                                <td>
                                                    {isCompleted ? (
                                                        <span className="badge bg-success-subtle text-success border border-success-subtle px-2 py-1">
                                                            COMPLETED
                                                        </span>
                                                    ) : isApprovedOrProcessing ? (
                                                        <span className="badge bg-warning-subtle text-warning border border-warning-subtle px-2 py-1">
                                                            PROCESSING
                                                        </span>
                                                    ) : isPendingReview ? (
                                                        <span className="badge bg-info-subtle text-info border border-info-subtle px-2 py-1">
                                                            PENDING REVIEW
                                                        </span>
                                                    ) : isRejected ? (
                                                        <span className="badge bg-danger-subtle text-danger border border-danger-subtle px-2 py-1">
                                                            REJECTED
                                                        </span>
                                                    ) : (
                                                        <span className="badge bg-secondary-subtle text-secondary px-2 py-1">
                                                            {item.status}
                                                        </span>
                                                    )}
                                                </td>
                                                <td>
                                                    {item.hostSettlementTransactionId ? (
                                                        <span className="badge bg-light text-dark border px-2 py-1 font-monospace">
                                                            {item.hostSettlementTransactionId}
                                                        </span>
                                                    ) : (
                                                        <span className="text-muted small">—</span>
                                                    )}
                                                </td>
                                                <td className="text-end">
                                                    <div className="d-flex align-items-center justify-content-end gap-2">
                                                        {isPendingReview && (
                                                            <>
                                                                <button
                                                                    className="btn btn-sm btn-primary"
                                                                    onClick={() => {
                                                                        setApproveTarget({
                                                                            tab: 'stranger_meet',
                                                                            id: item.id,
                                                                            title: `${item.meet?.subject || 'Stranger Meet'} (${item.totalMembersCount} members)`,
                                                                            amount: item.totalCollectedAmount,
                                                                            guests: item.totalMembersCount,
                                                                        });
                                                                        setApproveRefundPercentage(item.refundPolicyPercentage || 100);
                                                                    }}
                                                                >
                                                                    Approve
                                                                </button>
                                                                <button
                                                                    className="btn btn-sm btn-danger"
                                                                    onClick={() => {
                                                                        setRejectTarget({
                                                                            tab: 'stranger_meet',
                                                                            id: item.id,
                                                                            title: `${item.meet?.subject || 'Stranger Meet'}`,
                                                                        });
                                                                    }}
                                                                >
                                                                    Reject
                                                                </button>
                                                            </>
                                                        )}

                                                        {hostRefundPending && (
                                                            <button
                                                                className="btn btn-sm btn-success d-flex align-items-center gap-1 text-nowrap"
                                                                onClick={() => {
                                                                    setMarkPaidTarget({
                                                                        tab: 'stranger_meet',
                                                                        id: item.id,
                                                                        recipientName: `${hostName} (Host)`,
                                                                        recipientPhone: item.host?.phone,
                                                                        amount: item.hostRefundAmount || item.totalRefundAmount || 0,
                                                                        payoutDetails: item.hostPayoutDetails,
                                                                    });
                                                                    setUtrReference('');
                                                                    setPayoutNotes('');
                                                                }}
                                                            >
                                                                <BiCheckCircle size={15} /> Settle Host Refund
                                                            </button>
                                                        )}

                                                        <button
                                                            className="btn btn-sm btn-outline-secondary"
                                                            title="View Details & Member Refunds"
                                                            onClick={() => setDetailItem({ tab: 'stranger_meet', data: item })}
                                                        >
                                                            <BiDetail size={15} />
                                                        </button>
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
            )}

            {/* MODAL 1: MARK AS PAID / SETTLE PAYOUT (UTR INPUT) */}
            {markPaidTarget && (
                <div className="modal show d-block" style={{ background: 'rgba(0,0,0,0.6)' }} tabIndex={-1}>
                    <div className="modal-dialog modal-dialog-centered">
                        <div className="modal-content shadow-lg border-0">
                            <div className="modal-header bg-success text-white py-3">
                                <h5 className="modal-title fw-bold d-flex align-items-center gap-2">
                                    <BiCheckCircle size={22} /> Mark Refund as Paid
                                </h5>
                                <button
                                    type="button"
                                    className="btn-close btn-close-white"
                                    onClick={() => setMarkPaidTarget(null)}
                                    disabled={submittingAction}
                                ></button>
                            </div>
                            <div className="modal-body p-4">
                                <div className="alert alert-info py-2 px-3 small mb-3">
                                    Marking as paid will update the database status to <strong>REFUND COMPLETED</strong>, dispatch an in-app notification to the user, and immediately update their card in the live feed.
                                </div>

                                <div className="p-3 bg-light rounded mb-3 border">
                                    <div className="row g-2">
                                        <div className="col-6">
                                            <span className="text-muted small d-block">Recipient</span>
                                            <strong className="text-dark">{markPaidTarget.recipientName}</strong>
                                            {markPaidTarget.recipientPhone && (
                                                <div className="text-muted small">{markPaidTarget.recipientPhone}</div>
                                            )}
                                        </div>
                                        <div className="col-6 text-end">
                                            <span className="text-muted small d-block">Payout Amount</span>
                                            <strong className="fs-5 text-success">
                                                {formatCurrency(markPaidTarget.amount)}
                                            </strong>
                                        </div>
                                    </div>

                                    {markPaidTarget.payoutDetails && (
                                        <div className="mt-2 pt-2 border-top">
                                            <span className="text-muted small d-block mb-1">Destination Details:</span>
                                            {markPaidTarget.payoutDetails.upiId && (
                                                <div className="d-flex align-items-center gap-1">
                                                    <span className="badge bg-primary">UPI</span>
                                                    <span className="fw-semibold text-dark">
                                                        {markPaidTarget.payoutDetails.upiId}
                                                    </span>
                                                    <button
                                                        type="button"
                                                        className="btn btn-sm btn-link p-0 text-muted ms-1"
                                                        onClick={() => copyToClipboard(markPaidTarget.payoutDetails!.upiId!, 'UPI ID')}
                                                    >
                                                        <BiCopy size={15} />
                                                    </button>
                                                </div>
                                            )}
                                            {markPaidTarget.payoutDetails.accountNumber && (
                                                <div className="small text-dark mt-1">
                                                    <div>A/C: {markPaidTarget.payoutDetails.accountNumber}</div>
                                                    <div>IFSC: {markPaidTarget.payoutDetails.ifscCode}</div>
                                                    <div>Holder: {markPaidTarget.payoutDetails.accountHolderName}</div>
                                                    <div>Bank: {markPaidTarget.payoutDetails.bankName}</div>
                                                </div>
                                            )}
                                        </div>
                                    )}
                                </div>

                                <div className="mb-3">
                                    <label className="form-label fw-bold small text-dark">
                                        Bank UTR / UPI Transaction Reference <span className="text-danger">*</span>
                                    </label>
                                    <input
                                        type="text"
                                        className="form-control"
                                        placeholder="e.g. UTR1234567890 or UPI REF ID"
                                        value={utrReference}
                                        onChange={(e) => setUtrReference(e.target.value)}
                                        autoFocus
                                    />
                                    <span className="text-muted" style={{ fontSize: '11px' }}>
                                        Enter the transaction ID generated from your banking or UPI app.
                                    </span>
                                </div>

                                <div className="mb-3">
                                    <label className="form-label fw-bold small text-dark">Admin Notes (Optional)</label>
                                    <textarea
                                        className="form-control"
                                        rows={2}
                                        placeholder="Add any internal transaction or verification note..."
                                        value={payoutNotes}
                                        onChange={(e) => setPayoutNotes(e.target.value)}
                                    />
                                </div>
                            </div>
                            <div className="modal-footer bg-light">
                                <button
                                    type="button"
                                    className="btn btn-secondary"
                                    onClick={() => setMarkPaidTarget(null)}
                                    disabled={submittingAction}
                                >
                                    Cancel
                                </button>
                                <button
                                    type="button"
                                    className="btn btn-success d-flex align-items-center gap-2 fw-semibold"
                                    onClick={handleMarkPaidSubmit}
                                    disabled={submittingAction}
                                >
                                    {submittingAction ? (
                                        <>
                                            <div className="spinner-border spinner-border-sm" role="status"></div>
                                            Processing...
                                        </>
                                    ) : (
                                        <>
                                            <BiCheck size={18} /> Confirm & Mark as Paid
                                        </>
                                    )}
                                </button>
                            </div>
                        </div>
                    </div>
                </div>
            )}

            {/* MODAL 2: APPROVE CANCELLATION REQUEST */}
            {approveTarget && (
                <div className="modal show d-block" style={{ background: 'rgba(0,0,0,0.6)' }} tabIndex={-1}>
                    <div className="modal-dialog modal-dialog-centered">
                        <div className="modal-content shadow-lg border-0">
                            <div className="modal-header bg-primary text-white py-3">
                                <h5 className="modal-title fw-bold">Approve Cancellation Request</h5>
                                <button
                                    type="button"
                                    className="btn-close btn-close-white"
                                    onClick={() => setApproveTarget(null)}
                                    disabled={submittingAction}
                                ></button>
                            </div>
                            <div className="modal-body p-4">
                                <div className="mb-3">
                                    <label className="form-label text-muted small d-block">Target Party</label>
                                    <strong className="text-dark fs-6">{approveTarget.title}</strong>
                                </div>

                                <div className="row mb-3 g-2">
                                    <div className="col-6">
                                        <label className="form-label text-muted small d-block">Total Booking Amount</label>
                                        <strong className="text-dark">{formatCurrency(approveTarget.amount)}</strong>
                                    </div>
                                    <div className="col-6">
                                        <label className="form-label text-muted small d-block">Calculated Refund</label>
                                        <strong className="text-danger fs-6">
                                            {formatCurrency((approveTarget.amount * approveRefundPercentage) / 100)}
                                        </strong>
                                    </div>
                                </div>

                                <div className="mb-3">
                                    <label className="form-label fw-bold small text-dark">Approved Refund Percentage (%)</label>
                                    <input
                                        type="number"
                                        className="form-control"
                                        min={0}
                                        max={100}
                                        value={approveRefundPercentage}
                                        onChange={(e) => setApproveRefundPercentage(Number(e.target.value))}
                                    />
                                    <span className="text-muted" style={{ fontSize: '11px' }}>
                                        Default is policy percentage (100%). Adjust if partial refund applies.
                                    </span>
                                </div>

                                <div className="mb-3">
                                    <label className="form-label fw-bold small text-dark">Refund Method</label>
                                    <select
                                        className="form-select"
                                        value={approveRefundMethod}
                                        onChange={(e: any) => setApproveRefundMethod(e.target.value)}
                                    >
                                        <option value="MANUAL_PAYOUT">Manual Bank / UPI Payout</option>
                                        <option value="WALLET">Lunara Smart Credit Wallet</option>
                                    </select>
                                </div>

                                <div className="mb-3">
                                    <label className="form-label fw-bold small text-dark">Admin Notes</label>
                                    <textarea
                                        className="form-control"
                                        rows={2}
                                        placeholder="Reason or notes for approval..."
                                        value={approveNotes}
                                        onChange={(e) => setApproveNotes(e.target.value)}
                                    />
                                </div>
                            </div>
                            <div className="modal-footer bg-light">
                                <button
                                    type="button"
                                    className="btn btn-secondary"
                                    onClick={() => setApproveTarget(null)}
                                    disabled={submittingAction}
                                >
                                    Cancel
                                </button>
                                <button
                                    type="button"
                                    className="btn btn-primary d-flex align-items-center gap-2 fw-semibold"
                                    onClick={handleApproveSubmit}
                                    disabled={submittingAction}
                                >
                                    {submittingAction ? (
                                        <>
                                            <div className="spinner-border spinner-border-sm" role="status"></div>
                                            Approving...
                                        </>
                                    ) : (
                                        'Confirm Approval'
                                    )}
                                </button>
                            </div>
                        </div>
                    </div>
                </div>
            )}

            {/* MODAL 3: REJECT CANCELLATION REQUEST */}
            {rejectTarget && (
                <div className="modal show d-block" style={{ background: 'rgba(0,0,0,0.6)' }} tabIndex={-1}>
                    <div className="modal-dialog modal-dialog-centered">
                        <div className="modal-content shadow-lg border-0">
                            <div className="modal-header bg-danger text-white py-3">
                                <h5 className="modal-title fw-bold">Reject Cancellation Request</h5>
                                <button
                                    type="button"
                                    className="btn-close btn-close-white"
                                    onClick={() => setRejectTarget(null)}
                                    disabled={submittingAction}
                                ></button>
                            </div>
                            <div className="modal-body p-4">
                                <div className="mb-3">
                                    <label className="form-label text-muted small d-block">Target Party</label>
                                    <strong className="text-dark fs-6">{rejectTarget.title}</strong>
                                </div>

                                <div className="mb-3">
                                    <label className="form-label fw-bold small text-dark">
                                        Rejection Reason <span className="text-danger">*</span>
                                    </label>
                                    <textarea
                                        className="form-control"
                                        rows={3}
                                        placeholder="Explain why this cancellation request is being rejected..."
                                        value={rejectionReason}
                                        onChange={(e) => setRejectionReason(e.target.value)}
                                        autoFocus
                                    />
                                    <span className="text-muted" style={{ fontSize: '11px' }}>
                                        This reason will be sent in a notification to the user.
                                    </span>
                                </div>
                            </div>
                            <div className="modal-footer bg-light">
                                <button
                                    type="button"
                                    className="btn btn-secondary"
                                    onClick={() => setRejectTarget(null)}
                                    disabled={submittingAction}
                                >
                                    Cancel
                                </button>
                                <button
                                    type="button"
                                    className="btn btn-danger d-flex align-items-center gap-2 fw-semibold"
                                    onClick={handleRejectSubmit}
                                    disabled={submittingAction}
                                >
                                    {submittingAction ? (
                                        <>
                                            <div className="spinner-border spinner-border-sm" role="status"></div>
                                            Rejecting...
                                        </>
                                    ) : (
                                        'Confirm Rejection'
                                    )}
                                </button>
                            </div>
                        </div>
                    </div>
                </div>
            )}

            {/* MODAL 4: DETAILS DRAWER / VIEW MODAL */}
            {detailItem && (
                <div className="modal show d-block" style={{ background: 'rgba(0,0,0,0.6)' }} tabIndex={-1}>
                    <div className="modal-dialog modal-dialog-centered modal-lg">
                        <div className="modal-content shadow-lg border-0">
                            <div className="modal-header py-3 border-bottom">
                                <h5 className="modal-title fw-bold d-flex align-items-center gap-2">
                                    <BiDetail className="text-primary" /> Cancellation Details
                                </h5>
                                <button
                                    type="button"
                                    className="btn-close"
                                    onClick={() => setDetailItem(null)}
                                ></button>
                            </div>
                            <div className="modal-body p-4" style={{ maxHeight: '75vh', overflowY: 'auto' }}>
                                <div className="card p-3 mb-3 bg-light border">
                                    <h6 className="fw-bold mb-2">Item Overview</h6>
                                    <div className="row g-2 small">
                                        <div className="col-sm-6">
                                            <strong>ID:</strong>{' '}
                                            <span className="font-monospace text-muted">{detailItem.data.id}</span>
                                        </div>
                                        <div className="col-sm-6">
                                            <strong>Type:</strong>{' '}
                                            <span className="badge bg-secondary">
                                                {detailItem.tab.replace('_', ' ').toUpperCase()}
                                            </span>
                                        </div>
                                    </div>
                                </div>

                                {/* Tab Specific Detail Sections */}
                                {detailItem.tab === 'stranger_meet' && (
                                    <>
                                        <h6 className="fw-bold mb-2 mt-4">Member Refunds Breakdown</h6>
                                        {((detailItem.data as StrangerMeetCancellationItem).memberRefunds || []).length ===
                                        0 ? (
                                            <p className="text-muted small">No member refunds recorded for this meet.</p>
                                        ) : (
                                            <div className="table-responsive">
                                                <table className="table table-sm table-bordered">
                                                    <thead className="table-light">
                                                        <tr>
                                                            <th>Member</th>
                                                            <th>Phone</th>
                                                            <th>Amount</th>
                                                            <th>Refund Status</th>
                                                            <th>Destination</th>
                                                            <th>Actions</th>
                                                        </tr>
                                                    </thead>
                                                    <tbody>
                                                        {(detailItem.data as StrangerMeetCancellationItem).memberRefunds!.map(
                                                            (mr) => (
                                                                <tr key={mr.id}>
                                                                    <td>
                                                                        {mr.user
                                                                            ? `${mr.user.firstName} ${mr.user.lastName}`
                                                                            : mr.userId}
                                                                    </td>
                                                                    <td>{mr.user?.phone || '—'}</td>
                                                                    <td className="fw-bold text-danger">
                                                                        {formatCurrency(mr.refundAmount)}
                                                                    </td>
                                                                    <td>
                                                                        <span className="badge bg-light text-dark border">
                                                                            {mr.refundStatus}
                                                                        </span>
                                                                    </td>
                                                                    <td>{mr.destinationType}</td>
                                                                    <td>
                                                                        {mr.refundStatus !== 'PAID' &&
                                                                            mr.refundStatus !== 'WALLET_CREDITED' && (
                                                                                <button
                                                                                    className="btn btn-xs btn-success py-0 px-2"
                                                                                    onClick={() => {
                                                                                        setMarkPaidTarget({
                                                                                            tab: 'stranger_meet',
                                                                                            id: detailItem.data.id,
                                                                                            memberRefundId: mr.id,
                                                                                            recipientName: mr.user
                                                                                                ? `${mr.user.firstName} ${mr.user.lastName}`
                                                                                                : 'Member',
                                                                                            recipientPhone: mr.user?.phone,
                                                                                            amount: mr.refundAmount,
                                                                                            payoutDetails: mr.payoutDetails,
                                                                                        });
                                                                                    }}
                                                                                >
                                                                                    Pay
                                                                                </button>
                                                                            )}
                                                                    </td>
                                                                </tr>
                                                            )
                                                        )}
                                                    </tbody>
                                                </table>
                                            </div>
                                        )}
                                    </>
                                )}
                            </div>
                            <div className="modal-footer bg-light">
                                <button
                                    type="button"
                                    className="btn btn-secondary"
                                    onClick={() => setDetailItem(null)}
                                >
                                    Close
                                </button>
                            </div>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
};

export default CancellationRequests;
