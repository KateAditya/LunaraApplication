import React, { useState, useCallback } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import toast from 'react-hot-toast';
import {
    BiSearch, BiFilterAlt, BiRefresh, BiDetail, BiX,
    BiUser, BiBuilding, BiMoney, BiCheckCircle, BiXCircle, BiTime,
    BiFlag, BiRedo, BiChevronDown, BiChevronUp, BiCalendar, BiWallet,
    BiShieldQuarter, BiChat, BiReceipt, BiAlarm, BiExport,
} from 'react-icons/bi';
import { MdOutlineCancel, MdOutlineHistory } from 'react-icons/md';
import cancellationsApi, { type CancellationRecord, type CancellationDetail } from '../api/cancellations';
import { getImageUrl } from '../utils/imageUrl';
import { useAuthStore } from '../store/authStore';

// ── Helpers ────────────────────────────────────────────────────────────────

const STATUS_CONFIG: Record<string, { label: string; cls: string }> = {
    pending: { label: 'Pending Approval', cls: 'bg-warning-subtle text-warning border border-warning-subtle' },
    approved: { label: 'Approved', cls: 'bg-success-subtle text-success border border-success-subtle' },
    auto_approved: { label: 'Auto-Approved', cls: 'bg-info-subtle text-info border border-info-subtle' },
    rejected: { label: 'Rejected', cls: 'bg-danger-subtle text-danger border border-danger-subtle' },
    expired: { label: 'Expired', cls: 'bg-secondary-subtle text-secondary border border-secondary-subtle' },
};

const ICON_MAP: Record<string, React.ReactNode> = {
    plan: <BiCalendar className="text-primary" />,
    booking: <BiBuilding className="text-info" />,
    payment: <BiMoney className="text-success" />,
    confirmed: <BiCheckCircle className="text-success" />,
    cancel_request: <MdOutlineCancel className="text-warning" />,
    approved: <BiCheckCircle className="text-success" />,
    auto_approved: <BiAlarm className="text-info" />,
    rejected: <BiXCircle className="text-danger" />,
    booking_cancelled: <MdOutlineCancel className="text-danger" />,
    ticket_cancelled: <BiReceipt className="text-danger" />,
    wallet_credit: <BiWallet className="text-success" />,
    chat_locked: <BiChat className="text-secondary" />,
};

const fmt = (d?: string) => d ? new Date(d).toLocaleString('en-IN', { day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' }) : '—';
const fmtDate = (d?: string) => d ? new Date(d).toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' }) : '—';
const fmtCur = (n?: number) => n !== undefined ? `₹${Number(n).toLocaleString('en-IN')}` : '—';

function StatusBadge({ status }: { status: string }) {
    const cfg = STATUS_CONFIG[status] || { label: status, cls: 'bg-light text-dark' };
    return <span className={`badge rounded-pill px-3 py-2 fw-semibold small ${cfg.cls}`}>{cfg.label}</span>;
}

function Avatar({ user, size = 38 }: { user?: any; size?: number }) {
    const name = `${user?.firstName || ''} ${user?.lastName || ''}`.trim() || '?';
    const initials = name.split(' ').map((w: string) => w[0]).join('').slice(0, 2).toUpperCase();
    const url = user?.photo ? getImageUrl(user.photo) : null;
    return url
        ? <img src={url} alt={name} className="rounded-circle object-fit-cover" style={{ width: size, height: size }} />
        : <div className="rounded-circle d-flex align-items-center justify-content-center fw-bold text-white small"
            style={{ width: size, height: size, background: 'linear-gradient(135deg,#e6533c,#c4422e)', fontSize: size * 0.38 }}>{initials}</div>;
}

// ── CSV Export helper ──────────────────────────────────────────────────────

function downloadCsv(data: any[], filename: string) {
    if (!data.length) { toast.error('No data to export'); return; }
    const headers = Object.keys(data[0]);
    const rows = data.map(r => headers.map(h => `"${String(r[h] ?? '').replace(/"/g, '""')}"`).join(','));
    const csv = [headers.join(','), ...rows].join('\n');
    const blob = new Blob([csv], { type: 'text/csv' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = filename;
    a.click();
}

// ── Main Component ─────────────────────────────────────────────────────────

export const CancelledPartyPlans: React.FC = () => {
    const qc = useQueryClient();
    const { user } = useAuthStore();

    // Filters
    const [search, setSearch] = useState('');
    const [status, setStatus] = useState('all');
    const [reason, setReason] = useState('all');
    const [requestedBy, setRequestedBy] = useState('all');
    const [startDate, setStartDate] = useState('');
    const [endDate, setEndDate] = useState('');
    const [page, setPage] = useState(1);
    const [showFilters, setShowFilters] = useState(false);

    // Detail panel
    const [selectedId, setSelectedId] = useState<string | null>(null);
    const [activeSection, setActiveSection] = useState('overview');

    // Investigation modal
    const [investigateId, setInvestigateId] = useState<string | null>(null);
    const [investigateNotes, setInvestigateNotes] = useState('');

    // Restore modal
    const [restoreId, setRestoreId] = useState<string | null>(null);
    const [restoreReason, setRestoreReason] = useState('');

    // Export
    const [exporting, setExporting] = useState(false);

    const filters = { search, status, reason, requestedBy, startDate, endDate, page, limit: 20 };

    const { data: listData, isLoading, isFetching, refetch } = useQuery({
        queryKey: ['cancelled-plans', filters],
        queryFn: () => cancellationsApi.getList(filters),
        keepPreviousData: true,
    } as any);

    const { data: detailData, isLoading: detailLoading } = useQuery({
        queryKey: ['cancelled-plans-detail', selectedId],
        queryFn: () => cancellationsApi.getDetail(selectedId!),
        enabled: !!selectedId,
    } as any);

    const investigateMut = useMutation({
        mutationFn: ({ id, notes }: { id: string; notes: string }) =>
            cancellationsApi.markForInvestigation(id, notes, user?.id || 'admin'),
        onSuccess: () => {
            toast.success('Flagged for investigation');
            setInvestigateId(null);
            setInvestigateNotes('');
            qc.invalidateQueries({ queryKey: ['cancelled-plans'] });
        },
        onError: () => toast.error('Failed to flag'),
    });

    const restoreMut = useMutation({
        mutationFn: ({ id, reason: r }: { id: string; reason: string }) =>
            cancellationsApi.restoreBooking(id, r, user?.id || 'admin'),
        onSuccess: () => {
            toast.success('Booking restored successfully');
            setRestoreId(null);
            setRestoreReason('');
            qc.invalidateQueries({ queryKey: ['cancelled-plans'] });
        },
        onError: () => toast.error('Failed to restore'),
    });

    const handleExport = useCallback(async () => {
        setExporting(true);
        try {
            const res = await cancellationsApi.exportData({ startDate: startDate || undefined, endDate: endDate || undefined, status: status !== 'all' ? status : undefined });
            if (res.success) downloadCsv(res.data, `cancellations_export_${new Date().toISOString().split('T')[0]}.csv`);
        } catch { toast.error('Export failed'); }
        finally { setExporting(false); }
    }, [startDate, endDate, status]);

    const records: CancellationRecord[] = (listData as any)?.data || [];
    const pagination = (listData as any)?.pagination;
    const detail: CancellationDetail | undefined = (detailData as any)?.data;

    const sections = ['overview', 'booking', 'timeline', 'payment', 'wallet', 'reliability', 'reason', 'chat', 'ticket', 'notifications', 'audit'];

    return (
        <div>
            {/* ─── Header ────────────────────────────────────────────────── */}
            <div className="d-flex align-items-center justify-content-between mb-4 flex-wrap gap-3">
                <div>
                    <h4 className="mb-1 fw-bold d-flex align-items-center gap-2">
                        <MdOutlineCancel className="text-danger" size={28} /> Cancelled Party Plans
                    </h4>
                    <p className="text-muted small mb-0">Complete history of all mutual cancellation requests. Nothing is deleted — full audit trail preserved.</p>
                </div>
                <div className="d-flex gap-2 flex-wrap">
                    <button className="btn btn-outline-secondary btn-sm d-flex align-items-center gap-1" onClick={() => setShowFilters(f => !f)}>
                        <BiFilterAlt /> Filters {showFilters ? <BiChevronUp /> : <BiChevronDown />}
                    </button>
                    <button className="btn btn-outline-secondary btn-sm d-flex align-items-center gap-1" onClick={() => refetch()} disabled={isFetching}>
                        <BiRefresh className={isFetching ? 'rotating' : ''} /> Refresh
                    </button>
                    <button className="btn btn-success btn-sm d-flex align-items-center gap-1" onClick={handleExport} disabled={exporting}>
                        <BiExport /> {exporting ? 'Exporting…' : 'Export CSV'}
                    </button>
                </div>
            </div>

            {/* ─── Filters ────────────────────────────────────────────────── */}
            {showFilters && (
                <div className="card border-0 shadow-sm mb-4">
                    <div className="card-body">
                        <div className="row g-3">
                            <div className="col-md-3">
                                <label className="form-label small fw-semibold">Search</label>
                                <div className="input-group input-group-sm">
                                    <span className="input-group-text"><BiSearch /></span>
                                    <input className="form-control" placeholder="Name, email, booking ID…" value={search} onChange={e => { setSearch(e.target.value); setPage(1); }} />
                                </div>
                            </div>
                            <div className="col-md-2">
                                <label className="form-label small fw-semibold">Status</label>
                                <select className="form-select form-select-sm" value={status} onChange={e => { setStatus(e.target.value); setPage(1); }}>
                                    <option value="all">All Statuses</option>
                                    <option value="pending">Pending</option>
                                    <option value="approved">Approved</option>
                                    <option value="auto_approved">Auto-Approved</option>
                                    <option value="rejected">Rejected</option>
                                    <option value="expired">Expired</option>
                                </select>
                            </div>
                            <div className="col-md-2">
                                <label className="form-label small fw-semibold">Reason</label>
                                <select className="form-select form-select-sm" value={reason} onChange={e => { setReason(e.target.value); setPage(1); }}>
                                    <option value="all">All Reasons</option>
                                    <option value="my_plans_changed">Plans Changed</option>
                                    <option value="not_available">Not Available</option>
                                    <option value="not_interested">Not Interested</option>
                                    <option value="found_another_plan">Found Another Plan</option>
                                    <option value="venue_changed">Venue Changed</option>
                                    <option value="personal_reasons">Personal Reasons</option>
                                    <option value="other">Other</option>
                                </select>
                            </div>
                            <div className="col-md-2">
                                <label className="form-label small fw-semibold">Requested By</label>
                                <select className="form-select form-select-sm" value={requestedBy} onChange={e => { setRequestedBy(e.target.value); setPage(1); }}>
                                    <option value="all">All</option>
                                    <option value="host">Host</option>
                                    <option value="participant">Participant</option>
                                </select>
                            </div>
                            <div className="col-md-2">
                                <label className="form-label small fw-semibold">Date Range</label>
                                <div className="d-flex gap-1">
                                    <input type="date" className="form-control form-control-sm" value={startDate} onChange={e => setStartDate(e.target.value)} />
                                    <input type="date" className="form-control form-control-sm" value={endDate} onChange={e => setEndDate(e.target.value)} />
                                </div>
                            </div>
                            <div className="col-md-1 d-flex align-items-end">
                                <button className="btn btn-outline-secondary btn-sm w-100" onClick={() => { setSearch(''); setStatus('all'); setReason('all'); setRequestedBy('all'); setStartDate(''); setEndDate(''); setPage(1); }}>
                                    Reset
                                </button>
                            </div>
                        </div>
                    </div>
                </div>
            )}

            {/* ─── Main layout ─────────────────────────────────────────────── */}
            <div className={`d-flex gap-3 ${selectedId ? 'align-items-start' : ''}`}>

                {/* ─── Table ─────────────────────────────────────────────── */}
                <div className="flex-grow-1" style={{ minWidth: 0 }}>
                    <div className="card border-0 shadow-sm">
                        <div className="card-body p-0">
                            {isLoading ? (
                                <div className="text-center py-5"><div className="spinner-border text-danger" /></div>
                            ) : records.length === 0 ? (
                                <div className="text-center py-5 text-muted">
                                    <MdOutlineCancel size={48} className="mb-3 opacity-25" />
                                    <p className="mb-0">No cancelled plans found matching your filters.</p>
                                </div>
                            ) : (
                                <div className="table-responsive">
                                    <table className="table table-hover align-middle mb-0 small">
                                        <thead className="table-light">
                                            <tr>
                                                <th className="px-3 py-3">Booking / Plan</th>
                                                <th>Host</th>
                                                <th>Participant</th>
                                                <th>Venue & Date</th>
                                                <th>Amount</th>
                                                <th>Wallet Credit</th>
                                                <th>Status</th>
                                                <th>Request Date</th>
                                                <th className="text-center">Actions</th>
                                            </tr>
                                        </thead>
                                        <tbody>
                                            {records.map(r => (
                                                <tr key={r.id} className={selectedId === r.id ? 'table-active' : ''}>
                                                    <td className="px-3">
                                                        <div className="fw-semibold text-primary" style={{ fontFamily: 'monospace', fontSize: '0.75rem' }}>
                                                            {r.bookingId ? r.bookingId.slice(0, 8) + '…' : '—'}
                                                        </div>
                                                        <div className="text-muted" style={{ fontFamily: 'monospace', fontSize: '0.72rem' }}>
                                                            Plan: {r.planId.slice(0, 8)}…
                                                        </div>
                                                        <div className="text-truncate fw-semibold" style={{ maxWidth: 130 }}>
                                                            {r.plan?.planTitle || '—'}
                                                        </div>
                                                    </td>
                                                    <td>
                                                        <div className="d-flex align-items-center gap-2">
                                                            <Avatar user={r.requester} size={32} />
                                                            <div>
                                                                <div className="fw-semibold">{r.requester?.firstName} {r.requester?.lastName}</div>
                                                                <div className="text-muted" style={{ fontSize: '0.72rem' }}>{r.requester?.email}</div>
                                                            </div>
                                                        </div>
                                                    </td>
                                                    <td>
                                                        <div className="d-flex align-items-center gap-2">
                                                            <Avatar user={r.recipient} size={32} />
                                                            <div>
                                                                <div className="fw-semibold">{r.recipient?.firstName} {r.recipient?.lastName}</div>
                                                                <div className="text-muted" style={{ fontSize: '0.72rem' }}>{r.recipient?.email}</div>
                                                            </div>
                                                        </div>
                                                    </td>
                                                    <td>
                                                        <div className="fw-semibold small">{r.plan?.venue?.name || '—'}</div>
                                                        <div className="text-muted" style={{ fontSize: '0.72rem' }}>{r.plan?.planDateTime ? fmtDate(r.plan.planDateTime) : '—'}</div>
                                                    </td>
                                                    <td>
                                                        <div className="fw-semibold">{fmtCur(r.booking?.totalAmount)}</div>
                                                        <div className="text-muted" style={{ fontSize: '0.72rem' }}>{r.booking?.paymentStatus || '—'}</div>
                                                    </td>
                                                    <td>
                                                        <div className="text-success fw-semibold">{fmtCur((r.hostDepositAmount || 0) + (r.joinerDepositAmount || 0))}</div>
                                                        <div className="text-muted" style={{ fontSize: '0.72rem' }}>Deposit refund</div>
                                                    </td>
                                                    <td><StatusBadge status={r.status} /></td>
                                                    <td>
                                                        <div style={{ fontSize: '0.78rem' }}>{fmtDate(r.requestedAt)}</div>
                                                    </td>
                                                    <td className="text-center">
                                                        <div className="d-flex gap-1 justify-content-center">
                                                            <button className="btn btn-sm btn-primary d-flex align-items-center gap-1" onClick={() => { setSelectedId(r.id); setActiveSection('overview'); }}
                                                                title="View Details"><BiDetail /></button>
                                                            <button className="btn btn-sm btn-outline-warning d-flex align-items-center gap-1" onClick={() => setInvestigateId(r.id)}
                                                                title="Flag for Investigation"><BiFlag /></button>
                                                        </div>
                                                    </td>
                                                </tr>
                                            ))}
                                        </tbody>
                                    </table>
                                </div>
                            )}
                        </div>
                    </div>

                    {/* Pagination */}
                    {pagination && pagination.totalPages > 1 && (
                        <div className="d-flex justify-content-between align-items-center mt-3 small text-muted">
                            <span>Showing {Math.min((page - 1) * 20 + 1, pagination.total)}–{Math.min(page * 20, pagination.total)} of {pagination.total} records</span>
                            <div className="d-flex gap-1">
                                <button className="btn btn-sm btn-outline-secondary" onClick={() => setPage(p => p - 1)} disabled={page <= 1}>‹ Prev</button>
                                {Array.from({ length: Math.min(5, pagination.totalPages) }, (_, i) => {
                                    const p = Math.max(1, Math.min(pagination.totalPages - 4, page - 2)) + i;
                                    return <button key={p} className={`btn btn-sm ${p === page ? 'btn-primary' : 'btn-outline-secondary'}`} onClick={() => setPage(p)}>{p}</button>;
                                })}
                                <button className="btn btn-sm btn-outline-secondary" onClick={() => setPage(p => p + 1)} disabled={page >= pagination.totalPages}>Next ›</button>
                            </div>
                        </div>
                    )}
                </div>

                {/* ─── Detail Panel ─────────────────────────────────────────── */}
                {selectedId && (
                    <div className="card border-0 shadow" style={{ width: 520, minWidth: 520, position: 'sticky', top: 80 }}>
                        <div className="card-header d-flex align-items-center justify-content-between bg-transparent border-bottom py-3 px-3">
                            <div className="d-flex align-items-center gap-2">
                                <MdOutlineHistory size={20} className="text-danger" />
                                <span className="fw-bold">Cancellation Detail</span>
                                {detail && <StatusBadge status={detail.cancellation.status} />}
                            </div>
                            <button className="btn btn-sm btn-outline-secondary d-flex align-items-center" onClick={() => setSelectedId(null)}><BiX /></button>
                        </div>

                        {/* Section Nav */}
                        <div className="border-bottom px-3 d-flex gap-0 overflow-auto" style={{ whiteSpace: 'nowrap' }}>
                            {sections.map(s => (
                                <button key={s} className={`btn btn-sm border-0 rounded-0 py-2 px-2 text-capitalize ${activeSection === s ? 'border-bottom border-2 border-primary text-primary fw-semibold' : 'text-muted'}`}
                                    onClick={() => setActiveSection(s)} style={{ fontSize: '0.72rem' }}>{s}</button>
                            ))}
                        </div>

                        <div className="card-body p-3" style={{ maxHeight: 'calc(100vh - 200px)', overflowY: 'auto' }}>
                            {detailLoading ? (
                                <div className="text-center py-5"><div className="spinner-border text-primary" /></div>
                            ) : detail ? (
                                <DetailContent detail={detail} section={activeSection} onInvestigate={setInvestigateId} onRestore={setRestoreId} />
                            ) : null}
                        </div>
                    </div>
                )}
            </div>

            {/* ─── Investigation Modal ─────────────────────────────────────── */}
            {investigateId && (
                <div className="modal fade show d-block" style={{ background: 'rgba(0,0,0,0.5)' }} onClick={e => e.target === e.currentTarget && setInvestigateId(null)}>
                    <div className="modal-dialog modal-dialog-centered">
                        <div className="modal-content border-0 shadow">
                            <div className="modal-header border-0">
                                <h5 className="modal-title d-flex align-items-center gap-2"><BiFlag className="text-warning" /> Flag for Investigation</h5>
                                <button className="btn-close" onClick={() => setInvestigateId(null)} />
                            </div>
                            <div className="modal-body">
                                <p className="text-muted small mb-3">This will permanently mark this cancellation for admin investigation. The reason will be logged in the audit trail.</p>
                                <label className="form-label fw-semibold small">Investigation Notes</label>
                                <textarea className="form-control" rows={4} placeholder="Describe why this cancellation is being flagged…" value={investigateNotes} onChange={e => setInvestigateNotes(e.target.value)} />
                            </div>
                            <div className="modal-footer border-0">
                                <button className="btn btn-outline-secondary btn-sm" onClick={() => setInvestigateId(null)}>Cancel</button>
                                <button className="btn btn-warning btn-sm d-flex align-items-center gap-1"
                                    disabled={(investigateMut as any).isPending || !investigateNotes.trim()}
                                    onClick={() => investigateMut.mutate({ id: investigateId, notes: investigateNotes })}>
                                    <BiFlag /> {(investigateMut as any).isPending ? 'Flagging…' : 'Flag for Investigation'}
                                </button>
                            </div>
                        </div>
                    </div>
                </div>
            )}

            {/* ─── Restore Modal ───────────────────────────────────────────── */}
            {restoreId && (
                <div className="modal fade show d-block" style={{ background: 'rgba(0,0,0,0.5)' }} onClick={e => e.target === e.currentTarget && setRestoreId(null)}>
                    <div className="modal-dialog modal-dialog-centered">
                        <div className="modal-content border-0 shadow">
                            <div className="modal-header border-0 border-bottom-0">
                                <h5 className="modal-title d-flex align-items-center gap-2"><BiRedo className="text-danger" /> Emergency Booking Restore</h5>
                                <button className="btn-close" onClick={() => setRestoreId(null)} />
                            </div>
                            <div className="modal-body">
                                <div className="alert alert-danger border-0 small">
                                    ⚠️ <strong>Super Admin Action.</strong> This will restore the booking, ticket, and party plan to CONFIRMED status. Wallet credits will NOT be automatically reversed. Notify both users manually after restore.
                                </div>
                                <label className="form-label fw-semibold small">Restore Reason (required)</label>
                                <textarea className="form-control" rows={3} placeholder="Explain why this booking is being emergency-restored…" value={restoreReason} onChange={e => setRestoreReason(e.target.value)} />
                            </div>
                            <div className="modal-footer border-0">
                                <button className="btn btn-outline-secondary btn-sm" onClick={() => setRestoreId(null)}>Cancel</button>
                                <button className="btn btn-danger btn-sm d-flex align-items-center gap-1"
                                    disabled={(restoreMut as any).isPending || !restoreReason.trim()}
                                    onClick={() => restoreMut.mutate({ id: restoreId, reason: restoreReason })}>
                                    <BiRedo /> {(restoreMut as any).isPending ? 'Restoring…' : 'Restore Booking'}
                                </button>
                            </div>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
};

// ── Detail Sections Component ────────────────────────────────────────────────

function DetailContent({ detail, section, onInvestigate, onRestore }: {
    detail: CancellationDetail;
    section: string;
    onInvestigate: (id: string) => void;
    onRestore: (id: string) => void;
}) {
    const { cancellation, ticket, chatSubscription, walletTransactions, timeline, reasonLabel, hoursBeforeEvent } = detail;
    const c = cancellation;

    const InfoRow = ({ label, value, mono = false }: { label: string; value: React.ReactNode; mono?: boolean }) => (
        <div className="d-flex justify-content-between py-2 border-bottom border-light" style={{ gap: 12 }}>
            <span className="text-muted small">{label}</span>
            <span className={`fw-semibold small text-end ${mono ? 'font-monospace' : ''}`} style={{ maxWidth: 270 }}>{value}</span>
        </div>
    );

    if (section === 'overview') return (
        <div>
            <div className="mb-3">
                <div className="fw-bold mb-2 d-flex align-items-center gap-2"><BiDetail className="text-primary" /> Booking Information</div>
                <InfoRow label="Cancellation ID" value={c.id} mono />
                <InfoRow label="Booking ID" value={c.bookingId || '—'} mono />
                <InfoRow label="Plan ID" value={c.planId} mono />
                <InfoRow label="Event" value={c.plan?.planTitle || '—'} />
                <InfoRow label="Venue" value={c.plan?.venue?.name || '—'} />
                <InfoRow label="Event Date" value={c.plan?.planDateTime ? fmt(c.plan.planDateTime) : '—'} />
                <InfoRow label="Hours Before Event" value={hoursBeforeEvent != null ? `${hoursBeforeEvent}h` : '—'} />
                <InfoRow label="Cancellation Status" value={<StatusBadge status={c.status} />} />
                <InfoRow label="Auto-Approval Eligible" value={c.autoApprovalEligible ? <span className="badge bg-success-subtle text-success">Yes</span> : <span className="badge bg-secondary-subtle text-secondary">No</span>} />
            </div>
            <div className="d-flex gap-2 pt-2 flex-wrap">
                <button className="btn btn-warning btn-sm d-flex align-items-center gap-1" onClick={() => onInvestigate(c.id)}><BiFlag /> Investigate</button>
                <button className="btn btn-outline-danger btn-sm d-flex align-items-center gap-1" onClick={() => onRestore(c.id)}><BiRedo /> Emergency Restore</button>
            </div>
        </div>
    );

    if (section === 'booking') return (
        <div>
            <div className="mb-3">
                <div className="fw-bold mb-2 d-flex align-items-center gap-2 text-primary"><BiUser /> Host</div>
                <div className="d-flex align-items-center gap-3 mb-3">
                    <Avatar user={c.requester} size={52} />
                    <div>
                        <div className="fw-bold">{c.requester?.firstName} {c.requester?.lastName}</div>
                        <div className="text-muted small">{c.requester?.email}</div>
                        <div className="text-muted small">{c.requester?.phone}</div>
                        {c.requester?.profile?.reliabilityScore !== undefined && (
                            <span className="badge bg-info-subtle text-info mt-1">⭐ Reliability: {c.requester.profile.reliabilityScore}</span>
                        )}
                    </div>
                </div>
                <div className="fw-bold mb-2 d-flex align-items-center gap-2 text-success mt-3"><BiUser /> Participant</div>
                <div className="d-flex align-items-center gap-3">
                    <Avatar user={c.recipient} size={52} />
                    <div>
                        <div className="fw-bold">{c.recipient?.firstName} {c.recipient?.lastName}</div>
                        <div className="text-muted small">{c.recipient?.email}</div>
                        <div className="text-muted small">{c.recipient?.phone}</div>
                        {c.recipient?.profile?.reliabilityScore !== undefined && (
                            <span className="badge bg-info-subtle text-info mt-1">⭐ Reliability: {c.recipient.profile.reliabilityScore}</span>
                        )}
                    </div>
                </div>
            </div>
        </div>
    );

    if (section === 'timeline') return (
        <div>
            <div className="fw-bold mb-3 d-flex align-items-center gap-2"><MdOutlineHistory className="text-primary" /> Event Timeline</div>
            <div className="position-relative" style={{ paddingLeft: 32 }}>
                <div className="position-absolute top-0 bottom-0" style={{ left: 11, width: 2, background: 'linear-gradient(to bottom, #e6533c, #26bf94)', opacity: 0.25, borderRadius: 4 }} />
                {timeline.map((t, i) => (
                    <div key={i} className="d-flex gap-3 mb-4 position-relative">
                        <div className="position-absolute d-flex align-items-center justify-content-center rounded-circle bg-white border border-2"
                            style={{ left: -32, width: 24, height: 24, top: 2, fontSize: 13 }}>
                            {ICON_MAP[t.icon] || <BiTime className="text-muted" />}
                        </div>
                        <div>
                            <div className="fw-semibold small">{t.event}</div>
                            {t.detail && <div className="text-muted" style={{ fontSize: '0.72rem' }}>{t.detail}</div>}
                            <div className="text-muted" style={{ fontSize: '0.7rem' }}>{fmt(t.time as any)}</div>
                        </div>
                    </div>
                ))}
            </div>
        </div>
    );

    if (section === 'payment') return (
        <div>
            <div className="fw-bold mb-2 d-flex align-items-center gap-2"><BiMoney className="text-success" /> Payment Information</div>
            <InfoRow label="Booking Amount" value={c.booking?.totalAmount ? `₹${c.booking.totalAmount.toLocaleString('en-IN')}` : '—'} />
            <InfoRow label="Payment Status" value={c.booking?.paymentStatus || '—'} />
            <InfoRow label="Booking Status" value={c.booking?.status || '—'} />
        </div>
    );

    if (section === 'wallet') return (
        <div>
            <div className="fw-bold mb-2 d-flex align-items-center gap-2"><BiWallet className="text-success" /> Wallet Transactions</div>
            <InfoRow label="Host Deposit (₹)" value={`₹${c.hostDepositAmount || 499}`} />
            <InfoRow label="Participant Deposit (₹)" value={`₹${c.joinerDepositAmount || 499}`} />
            <InfoRow label="Total Refunded" value={<span className="text-success fw-bold">₹{((c.hostDepositAmount || 0) + (c.joinerDepositAmount || 0)).toLocaleString('en-IN')}</span>} />
            <InfoRow label="Host Wallet Tx ID" value={c.hostWalletTransactionId || '—'} mono />
            <InfoRow label="Participant Wallet Tx ID" value={c.joinerWalletTransactionId || '—'} mono />
            {walletTransactions.length > 0 && (
                <div className="mt-3">
                    <div className="fw-semibold small mb-2">Wallet Credit Transactions</div>
                    {walletTransactions.map((wt, i) => (
                        <div key={i} className="small p-2 bg-success-subtle rounded mb-1 d-flex justify-content-between">
                            <span>₹{wt.refundAmount} credited</span>
                            <span className="text-muted">{fmtDate(wt.refundedAt)}</span>
                        </div>
                    ))}
                </div>
            )}
        </div>
    );

    if (section === 'reliability') return (
        <div>
            <div className="fw-bold mb-2 d-flex align-items-center gap-2"><BiShieldQuarter className="text-warning" /> Reliability Changes</div>
            <InfoRow label="Reliability Deduction" value={<span className="text-danger fw-bold">{c.reliabilityImpact || -5} pts per user</span>} />
            <InfoRow label="Host Score (current)" value={c.requester?.profile?.reliabilityScore ?? '—'} />
            <InfoRow label="Participant Score (current)" value={c.recipient?.profile?.reliabilityScore ?? '—'} />
            <div className="alert alert-warning border-0 small mt-3">
                <strong>Note:</strong> Reliability deductions were applied only after the cancellation was fully approved by both parties.
            </div>
        </div>
    );

    if (section === 'reason') return (
        <div>
            <div className="fw-bold mb-2 d-flex align-items-center gap-2"><BiFlag className="text-danger" /> Cancellation Reason</div>
            <div className="p-3 bg-danger-subtle rounded mb-3">
                <div className="fw-semibold text-danger">{reasonLabel}</div>
                {c.otherReasonText && !c.otherReasonText.startsWith('[ADMIN') && (
                    <div className="text-muted small mt-1">"{c.otherReasonText}"</div>
                )}
            </div>
            <InfoRow label="Requested By" value={`${c.requester?.firstName} ${c.requester?.lastName}`} />
            <InfoRow label="Request Date" value={fmt(c.requestedAt)} />
            <InfoRow label="Response Date" value={c.respondedAt ? fmt(c.respondedAt) : '—'} />
            <InfoRow label="Expires At" value={fmt(c.expiresAt)} />
            {c.otherReasonText?.startsWith('[ADMIN') && (
                <div className="mt-3">
                    <div className="fw-semibold small mb-1 text-warning">⚠️ Admin Note</div>
                    <div className="p-2 bg-warning-subtle rounded small font-monospace" style={{ fontSize: '0.72rem' }}>{c.otherReasonText}</div>
                </div>
            )}
        </div>
    );

    if (section === 'chat') return (
        <div>
            <div className="fw-bold mb-2 d-flex align-items-center gap-2"><BiChat className="text-primary" /> Chat Status</div>
            {chatSubscription ? (
                <>
                    <InfoRow label="Chat ID" value={chatSubscription.id} mono />
                    <InfoRow label="Chat Status" value={<span className={`badge ${chatSubscription.status === 'expired' ? 'bg-danger-subtle text-danger' : 'bg-success-subtle text-success'}`}>{chatSubscription.status}</span>} />
                    <InfoRow label="Status Updated" value={fmt(chatSubscription.updatedAt)} />
                    <div className="alert alert-info border-0 small mt-3">
                        After cancellation, the chat is locked to <strong>Read-Only</strong> mode. Neither user can send new messages.
                    </div>
                </>
            ) : <div className="text-muted small">No chat subscription found.</div>}
        </div>
    );

    if (section === 'ticket') return (
        <div>
            <div className="fw-bold mb-2 d-flex align-items-center gap-2"><BiReceipt className="text-primary" /> Ticket Information</div>
            {ticket ? (
                <>
                    <InfoRow label="Ticket ID" value={ticket.id} mono />
                    <InfoRow label="Ticket Status" value={<span className={`badge ${ticket.status === 'cancelled' ? 'bg-danger-subtle text-danger' : 'bg-success-subtle text-success'}`}>{ticket.status}</span>} />
                    {ticket.issuedAt && <InfoRow label="Issued At" value={fmt(ticket.issuedAt)} />}
                    {ticket.expiresAt && <InfoRow label="Expired At" value={fmt(ticket.expiresAt)} />}
                </>
            ) : <div className="text-muted small">No ticket found for this booking.</div>}
        </div>
    );

    if (section === 'notifications') return (
        <div>
            <div className="fw-bold mb-2 d-flex align-items-center gap-2"><BiAlarm className="text-primary" /> Notifications Sent</div>
            <div className="list-group list-group-flush small">
                {[
                    { event: 'Cancellation Requested', to: `${c.recipient?.firstName}`, at: c.requestedAt, icon: '📨' },
                    c.respondedAt && { event: c.status === 'approved' || c.status === 'auto_approved' ? 'Cancellation Approved' : 'Cancellation Rejected', to: `${c.requester?.firstName}`, at: c.respondedAt, icon: c.status === 'approved' || c.status === 'auto_approved' ? '✅' : '❌' },
                ].filter(Boolean).map((n: any, i) => (
                    <div key={i} className="list-group-item border-0 px-0 py-2">
                        <div className="d-flex justify-content-between">
                            <span>{n.icon} {n.event} → <strong>{n.to}</strong></span>
                            <span className="text-muted">{fmtDate(n.at)}</span>
                        </div>
                    </div>
                ))}
            </div>
        </div>
    );

    if (section === 'audit') return (
        <div>
            <div className="fw-bold mb-2 d-flex align-items-center gap-2"><MdOutlineHistory className="text-primary" /> Audit Logs</div>
            <InfoRow label="Cancellation Request ID" value={c.id} mono />
            <InfoRow label="Requested By (User ID)" value={c.requestedById} mono />
            <InfoRow label="Recipient (User ID)" value={c.recipientUserId} mono />
            <InfoRow label="Responded By (User ID)" value={c.respondedById || '—'} mono />
            <InfoRow label="Host Wallet Tx" value={c.hostWalletTransactionId || '—'} mono />
            <InfoRow label="Participant Wallet Tx" value={c.joinerWalletTransactionId || '—'} mono />
            <InfoRow label="Created At" value={fmt(c.requestedAt)} />
            <InfoRow label="Responded At" value={c.respondedAt ? fmt(c.respondedAt) : '—'} />
            <InfoRow label="Expires At" value={fmt(c.expiresAt)} />
            {c.otherReasonText?.startsWith('[ADMIN') && (
                <div className="mt-3">
                    <div className="fw-semibold small mb-1 text-warning">Admin Audit Entry</div>
                    <pre className="p-2 bg-light rounded small" style={{ fontSize: '0.68rem', whiteSpace: 'pre-wrap' }}>{c.otherReasonText}</pre>
                </div>
            )}
        </div>
    );

    return null;
}
