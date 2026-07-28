import React, { useState, useCallback } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import toast from 'react-hot-toast';
import {
    BiTrash, BiRefresh, BiSearch, BiUser, BiPhone, BiEnvelope,
    BiCalendar, BiShield, BiNote, BiX, BiCheckCircle, BiError,
    BiInfoCircle, BiFilter, BiTimeFive,
} from 'react-icons/bi';
import { usersApi } from '../api/users';

interface DeletedAccount {
    id: string;
    originalUserId: string;
    email: string;
    phone: string;
    firstName: string;
    lastName: string;
    dateOfBirth: string;
    role: string;
    gender?: string;
    city?: string;
    bio?: string;
    profileImageUrl?: string;
    occupation?: string;
    education?: string;
    isVerified: boolean;
    blockCount: number;
    isAutoblocked: boolean;
    autoblockedReason?: string;
    noShowCount: number;
    lastLoginAt?: string;
    registeredAt?: string;
    deletionReason?: string;
    deletedByUser: boolean;
    adminNotes?: string;
    ipAddress?: string;
    bookingsCount: number;
    subscriptionsCount: number;
    photosCount: number;
    createdAt: string;
}

const formatDate = (d?: string | null) => {
    if (!d) return '—';
    return new Date(d).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' });
};

const formatDateOnly = (d?: string | null) => {
    if (!d) return '—';
    return new Date(d).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });
};

// ── Detail Modal ──────────────────────────────────────────────────────────────
const DetailModal: React.FC<{
    record: DeletedAccount;
    onClose: () => void;
    onRestore: (id: string, notes: string) => void;
    onSaveNotes: (id: string, notes: string) => void;
    restoring: boolean;
    savingNotes: boolean;
}> = ({ record, onClose, onRestore, onSaveNotes, restoring, savingNotes }) => {
    const [notes, setNotes] = useState(record.adminNotes || '');
    const [restoreNotes, setRestoreNotes] = useState('');
    const [showRestoreConfirm, setShowRestoreConfirm] = useState(false);
    const [activeTab, setActiveTab] = useState<'profile' | 'plans' | 'meets' | 'requests'>('profile');

    const { data: detailData, isLoading } = useQuery({
        queryKey: ['deletedAccountDetail', record.id],
        queryFn: () => usersApi.getDeletedAccountById(record.id)
    });

    const activity = (detailData as any)?.activity || (detailData as any)?.data?.activity;

    return (
        <div className="modal-overlay" onClick={onClose} style={{ zIndex: 9999 }}>
            <div className="modal-container" onClick={e => e.stopPropagation()} style={{ maxWidth: 780, maxHeight: '90vh', overflow: 'auto' }}>
                {/* Header */}
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 20 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                        <div style={{ width: 48, height: 48, borderRadius: '50%', background: 'linear-gradient(135deg, #e6533c, #c0392b)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff', fontSize: 20, fontWeight: 700 }}>
                            {record.firstName?.charAt(0) || '?'}
                        </div>
                        <div>
                            <div style={{ fontWeight: 700, fontSize: '1.05rem' }}>{record.firstName} {record.lastName}</div>
                            <div style={{ fontSize: '0.78rem', color: 'var(--vz-text-muted)' }}>Deleted {formatDate(record.createdAt)}</div>
                        </div>
                    </div>
                    <button className="btn-icon" onClick={onClose}><BiX size={20} /></button>
                </div>

                {/* Status Banner */}
                <div style={{ background: 'rgba(230,83,60,0.1)', border: '1px solid rgba(230,83,60,0.3)', borderRadius: 10, padding: '12px 16px', marginBottom: 20, display: 'flex', gap: 10, alignItems: 'center' }}>
                    <BiTrash style={{ color: '#e6533c', flexShrink: 0 }} size={18} />
                    <div style={{ fontSize: '0.82rem', color: 'var(--vz-text-primary)' }}>
                        <b>Account permanently deleted</b> — {record.deletedByUser ? 'Self-deleted by user' : 'Deleted by admin'}
                        {record.deletionReason && <span style={{ color: 'var(--vz-text-muted)' }}> · Reason: "{record.deletionReason}"</span>}
                    </div>
                </div>

                {/* Tabs */}
                <div style={{ display: 'flex', gap: 20, borderBottom: '1px solid var(--vz-border)', marginBottom: 20 }}>
                    <div onClick={() => setActiveTab('profile')} style={{ paddingBottom: 8, cursor: 'pointer', fontWeight: 600, fontSize: '0.85rem', color: activeTab === 'profile' ? 'var(--vz-primary)' : 'var(--vz-text-muted)', borderBottom: activeTab === 'profile' ? '2px solid var(--vz-primary)' : '2px solid transparent' }}>Profile Overview</div>
                    <div onClick={() => setActiveTab('plans')} style={{ paddingBottom: 8, cursor: 'pointer', fontWeight: 600, fontSize: '0.85rem', color: activeTab === 'plans' ? 'var(--vz-primary)' : 'var(--vz-text-muted)', borderBottom: activeTab === 'plans' ? '2px solid var(--vz-primary)' : '2px solid transparent' }}>Hosted Plans</div>
                    <div onClick={() => setActiveTab('meets')} style={{ paddingBottom: 8, cursor: 'pointer', fontWeight: 600, fontSize: '0.85rem', color: activeTab === 'meets' ? 'var(--vz-primary)' : 'var(--vz-text-muted)', borderBottom: activeTab === 'meets' ? '2px solid var(--vz-primary)' : '2px solid transparent' }}>Strangers Meets</div>
                    <div onClick={() => setActiveTab('requests')} style={{ paddingBottom: 8, cursor: 'pointer', fontWeight: 600, fontSize: '0.85rem', color: activeTab === 'requests' ? 'var(--vz-primary)' : 'var(--vz-text-muted)', borderBottom: activeTab === 'requests' ? '2px solid var(--vz-primary)' : '2px solid transparent' }}>Sent Requests</div>
                </div>

                {/* Tab Content */}
                {activeTab === 'profile' && (
                    <>
                        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16, marginBottom: 20 }}>
                            <div className="card" style={{ padding: 16 }}>
                                <div style={{ fontWeight: 600, fontSize: '0.8rem', marginBottom: 12, color: 'var(--vz-text-muted)', textTransform: 'uppercase', letterSpacing: '0.05em' }}>Identity</div>
                                <InfoRow icon={<BiEnvelope />} label="Email" value={record.email} />
                                <InfoRow icon={<BiPhone />} label="Phone" value={record.phone} />
                                <InfoRow icon={<BiUser />} label="Gender" value={record.gender} />
                                <InfoRow icon={<BiCalendar />} label="Date of Birth" value={formatDateOnly(record.dateOfBirth)} />
                                <InfoRow icon={<BiShield />} label="Role" value={record.role} />
                                <InfoRow icon={<BiInfoCircle />} label="City" value={record.city} />
                                <InfoRow icon={<BiInfoCircle />} label="Occupation" value={record.occupation} />
                            </div>
                            <div className="card" style={{ padding: 16 }}>
                                <div style={{ fontWeight: 600, fontSize: '0.8rem', marginBottom: 12, color: 'var(--vz-text-muted)', textTransform: 'uppercase', letterSpacing: '0.05em' }}>Account Stats</div>
                                <InfoRow icon={<BiCheckCircle />} label="Verified" value={record.isVerified ? 'Yes' : 'No'} valueColor={record.isVerified ? '#26bf94' : '#e6533c'} />
                                <InfoRow icon={<BiCalendar />} label="Registered" value={formatDate(record.registeredAt)} />
                                <InfoRow icon={<BiTimeFive />} label="Last Login" value={formatDate(record.lastLoginAt)} />
                                <InfoRow icon={<BiError />} label="Block Count" value={String(record.blockCount)} valueColor={record.blockCount > 0 ? '#e6533c' : undefined} />
                                <InfoRow icon={<BiError />} label="No-Shows" value={String(record.noShowCount)} valueColor={record.noShowCount > 0 ? '#e6533c' : undefined} />
                                <InfoRow icon={<BiCalendar />} label="Bookings" value={String(record.bookingsCount)} />
                                <InfoRow icon={<BiShield />} label="Subscriptions" value={String(record.subscriptionsCount)} />
                            </div>
                        </div>

                        <div className="card" style={{ padding: 16, marginBottom: 16 }}>
                            <div style={{ fontWeight: 600, fontSize: '0.8rem', marginBottom: 12, color: 'var(--vz-text-muted)', textTransform: 'uppercase', letterSpacing: '0.05em' }}>Deletion Metadata</div>
                            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
                                <InfoRow icon={<BiInfoCircle />} label="Original User ID" value={record.originalUserId} mono />
                                <InfoRow icon={<BiInfoCircle />} label="Archive Record ID" value={record.id} mono />
                                <InfoRow icon={<BiInfoCircle />} label="IP Address" value={record.ipAddress} />
                                <InfoRow icon={<BiInfoCircle />} label="Deleted At" value={formatDate(record.createdAt)} />
                                {record.autoblockedReason && <InfoRow icon={<BiError />} label="Autoblock Reason" value={record.autoblockedReason} />}
                            </div>
                            {record.bio && (
                                <div style={{ marginTop: 12, padding: '10px 12px', background: 'var(--vz-bg-secondary)', borderRadius: 8, fontSize: '0.82rem', color: 'var(--vz-text-muted)' }}>
                                    <b>Bio:</b> {record.bio}
                                </div>
                            )}
                        </div>

                        <div className="card" style={{ padding: 16, marginBottom: 16 }}>
                            <div style={{ fontWeight: 600, fontSize: '0.8rem', marginBottom: 10, color: 'var(--vz-text-muted)', textTransform: 'uppercase', letterSpacing: '0.05em' }}>
                                <BiNote style={{ marginRight: 6, verticalAlign: 'middle' }} />Admin Notes
                            </div>
                            <textarea
                                value={notes}
                                onChange={e => setNotes(e.target.value)}
                                placeholder="Add investigation notes, contact attempts, audit remarks..."
                                style={{ width: '100%', minHeight: 80, padding: '10px 12px', borderRadius: 8, border: '1px solid var(--vz-border)', background: 'var(--vz-bg-secondary)', color: 'var(--vz-text-primary)', fontSize: '0.82rem', resize: 'vertical', outline: 'none', fontFamily: 'inherit' }}
                            />
                            <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: 8 }}>
                                <button className="btn btn-outline-primary btn-sm" onClick={() => onSaveNotes(record.id, notes)} disabled={savingNotes}>
                                    {savingNotes ? 'Saving...' : 'Save Notes'}
                                </button>
                            </div>
                        </div>

                        <div className="card" style={{ padding: 16, border: '1px solid rgba(38,191,148,0.3)', background: 'rgba(38,191,148,0.04)' }}>
                            <div style={{ fontWeight: 600, fontSize: '0.8rem', marginBottom: 8, color: '#26bf94', textTransform: 'uppercase', letterSpacing: '0.05em' }}>
                                <BiRefresh style={{ marginRight: 6, verticalAlign: 'middle' }} />Restore Account
                            </div>
                            <p style={{ fontSize: '0.82rem', color: 'var(--vz-text-muted)', marginBottom: 10 }}>
                                Restoring the account will re-activate the user and allow them to log in again. The archive record will remain for audit purposes.
                            </p>
                            {showRestoreConfirm ? (
                                <>
                                    <textarea
                                        value={restoreNotes}
                                        onChange={e => setRestoreNotes(e.target.value)}
                                        placeholder="Reason for restoring (optional)..."
                                        style={{ width: '100%', minHeight: 60, padding: '10px 12px', borderRadius: 8, border: '1px solid rgba(38,191,148,0.4)', background: 'var(--vz-bg-secondary)', color: 'var(--vz-text-primary)', fontSize: '0.82rem', marginBottom: 10, outline: 'none', fontFamily: 'inherit' }}
                                    />
                                    <div style={{ display: 'flex', gap: 8 }}>
                                        <button className="btn btn-success btn-sm" onClick={() => onRestore(record.id, restoreNotes)} disabled={restoring}>
                                            {restoring ? 'Restoring...' : '✓ Confirm Restore'}
                                        </button>
                                        <button className="btn btn-outline-secondary btn-sm" onClick={() => setShowRestoreConfirm(false)}>Cancel</button>
                                    </div>
                                </>
                            ) : (
                                <button className="btn btn-success btn-sm" onClick={() => setShowRestoreConfirm(true)}>
                                    <BiRefresh style={{ marginRight: 4 }} />Restore This Account
                                </button>
                            )}
                        </div>
                    </>
                )}

                {/* Additional Dynamic Tabs */}
                {activeTab !== 'profile' && isLoading && <div style={{ padding: 20, textAlign: 'center', fontSize: '0.85rem' }}>Loading data...</div>}
                {activeTab !== 'profile' && !isLoading && activity && (
                    <div style={{ minHeight: 200 }}>
                        {activeTab === 'plans' && (
                            <div>
                                <h6 style={{ fontSize: '0.85rem', marginBottom: 10, color: 'var(--vz-text-muted)' }}>Table Plans ({activity.plans?.length || 0})</h6>
                                {activity.plans?.length > 0 ? (
                                    <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginBottom: 20 }}>
                                        {activity.plans.map((p: any) => (
                                            <div key={p.id} style={{ padding: 12, background: 'var(--vz-bg-secondary)', borderRadius: 8, fontSize: '0.8rem' }}>
                                                <strong>{p.status}</strong> — {p.tablePackage} package on {formatDateOnly(p.planDate)} at {p.startTime} <br />
                                                <span style={{ color: 'var(--vz-text-muted)' }}>Joiners: {p.currentJoiners}/{p.maxJoiners}</span>
                                            </div>
                                        ))}
                                    </div>
                                ) : <div style={{ fontSize: '0.8rem', color: 'var(--vz-text-muted)' }}>No table plans hosted.</div>}
                                
                                <h6 style={{ fontSize: '0.85rem', marginBottom: 10, marginTop: 20, color: 'var(--vz-text-muted)' }}>Party Plans ({activity.partyPlans?.length || 0})</h6>
                                {activity.partyPlans?.length > 0 ? (
                                    <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                                        {activity.partyPlans.map((p: any) => (
                                            <div key={p.id} style={{ padding: 12, background: 'var(--vz-bg-secondary)', borderRadius: 8, fontSize: '0.8rem' }}>
                                                <strong>{p.status}</strong> — {formatDate(p.planDateTime)} <br />
                                                <span style={{ color: 'var(--vz-text-muted)' }}>{p.message}</span>
                                            </div>
                                        ))}
                                    </div>
                                ) : <div style={{ fontSize: '0.8rem', color: 'var(--vz-text-muted)' }}>No party plans hosted.</div>}
                            </div>
                        )}

                        {activeTab === 'meets' && (
                            <div>
                                <h6 style={{ fontSize: '0.85rem', marginBottom: 10, color: 'var(--vz-text-muted)' }}>Strangers Meet Requests ({activity.strangersMeets?.length || 0})</h6>
                                {activity.strangersMeets?.length > 0 ? (
                                    <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                                        {activity.strangersMeets.map((m: any) => (
                                            <div key={m.id} style={{ padding: 12, background: 'var(--vz-bg-secondary)', borderRadius: 8, fontSize: '0.8rem' }}>
                                                <strong>{m.status}</strong> — Need {m.requiredPersons} person(s) on {formatDateOnly(m.date)} at {m.time} <br />
                                                <span style={{ color: 'var(--vz-text-muted)' }}>{m.description}</span>
                                            </div>
                                        ))}
                                    </div>
                                ) : <div style={{ fontSize: '0.8rem', color: 'var(--vz-text-muted)' }}>No stranger meets requested.</div>}
                            </div>
                        )}

                        {activeTab === 'requests' && (
                            <div>
                                <h6 style={{ fontSize: '0.85rem', marginBottom: 10, color: 'var(--vz-text-muted)' }}>Sent Table Plan Requests ({activity.sentPlanRequests?.length || 0})</h6>
                                {activity.sentPlanRequests?.length > 0 ? (
                                    <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginBottom: 20 }}>
                                        {activity.sentPlanRequests.map((r: any) => (
                                            <div key={r.id} style={{ padding: 12, background: 'var(--vz-bg-secondary)', borderRadius: 8, fontSize: '0.8rem' }}>
                                                <strong>{r.status}</strong> — Request to join Plan ID: {r.planId} <br />
                                                {r.message && <span style={{ color: 'var(--vz-text-muted)' }}>"{r.message}"</span>}
                                            </div>
                                        ))}
                                    </div>
                                ) : <div style={{ fontSize: '0.8rem', color: 'var(--vz-text-muted)' }}>No table plan requests sent.</div>}
                                
                                <h6 style={{ fontSize: '0.85rem', marginBottom: 10, marginTop: 20, color: 'var(--vz-text-muted)' }}>Sent Party Plan Requests ({activity.sentPartyRequests?.length || 0})</h6>
                                {activity.sentPartyRequests?.length > 0 ? (
                                    <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                                        {activity.sentPartyRequests.map((r: any) => (
                                            <div key={r.id} style={{ padding: 12, background: 'var(--vz-bg-secondary)', borderRadius: 8, fontSize: '0.8rem' }}>
                                                <strong>{r.status}</strong> — Request to join Party Plan ID: {r.planId}
                                            </div>
                                        ))}
                                    </div>
                                ) : <div style={{ fontSize: '0.8rem', color: 'var(--vz-text-muted)' }}>No party plan requests sent.</div>}
                            </div>
                        )}
                    </div>
                )}
            </div>
        </div>
    );
};

const InfoRow: React.FC<{ icon: React.ReactNode; label: string; value?: string | null; valueColor?: string; mono?: boolean }> = ({ icon, label, value, valueColor, mono }) => (
    <div style={{ display: 'flex', alignItems: 'flex-start', gap: 8, marginBottom: 8 }}>
        <span style={{ color: 'var(--vz-text-muted)', marginTop: 2, flexShrink: 0 }}>{icon}</span>
        <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: '0.72rem', color: 'var(--vz-text-muted)', marginBottom: 1 }}>{label}</div>
            <div style={{ fontSize: '0.82rem', color: valueColor || 'var(--vz-text-primary)', fontFamily: mono ? 'monospace' : undefined, wordBreak: 'break-all', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                {value || '—'}
            </div>
        </div>
    </div>
);

// ── Main Page ─────────────────────────────────────────────────────────────────
export const DeletedAccounts: React.FC = () => {
    const qc = useQueryClient();
    const [page, setPage] = useState(1);
    const [search, setSearch] = useState('');
    const [searchInput, setSearchInput] = useState('');
    const [from, setFrom] = useState('');
    const [to, setTo] = useState('');
    const [selected, setSelected] = useState<DeletedAccount | null>(null);

    const { data, isLoading, isError } = useQuery({
        queryKey: ['deleted-accounts', page, search, from, to],
        queryFn: () => usersApi.getDeletedAccounts({ page, limit: 15, search: search || undefined, from: from || undefined, to: to || undefined }),
        placeholderData: (prev) => prev,
    });

    const notesMutation = useMutation({
        mutationFn: ({ id, notes }: { id: string; notes: string }) => usersApi.updateDeletedAccountNotes(id, notes),
        onSuccess: () => { toast.success('Notes saved'); qc.invalidateQueries({ queryKey: ['deleted-accounts'] }); },
        onError: () => toast.error('Failed to save notes'),
    });

    const restoreMutation = useMutation({
        mutationFn: ({ id, notes }: { id: string; notes: string }) => usersApi.restoreDeletedAccount(id, notes),
        onSuccess: () => {
            toast.success('Account restored successfully');
            qc.invalidateQueries({ queryKey: ['deleted-accounts'] });
            setSelected(null);
        },
        onError: () => toast.error('Failed to restore account'),
    });

    const handleSearch = useCallback(() => { setSearch(searchInput); setPage(1); }, [searchInput]);

    const records: DeletedAccount[] = (data as any)?.deletedAccounts || [];
    const totalPages: number = (data as any)?.totalPages || 1;
    const totalCount: number = (data as any)?.count || 0;

    return (
        <div>
            {/* Page Intro */}
            <div className="card" style={{ marginBottom: 20, padding: '20px 24px', background: 'linear-gradient(135deg, rgba(230,83,60,0.08) 0%, rgba(192,57,43,0.04) 100%)', border: '1px solid rgba(230,83,60,0.2)' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
                    <div style={{ width: 44, height: 44, borderRadius: 12, background: 'linear-gradient(135deg, #e6533c, #c0392b)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff', flexShrink: 0 }}>
                        <BiTrash size={22} />
                    </div>
                    <div>
                        <h4 style={{ margin: 0, fontWeight: 700 }}>Deleted Accounts Archive</h4>
                        <p style={{ margin: 0, fontSize: '0.83rem', color: 'var(--vz-text-muted)', marginTop: 2 }}>
                            Audit log of permanently deleted accounts. Data is retained for compliance & investigation. Admins can restore accounts or add investigation notes.
                        </p>
                    </div>
                    <div style={{ marginLeft: 'auto', textAlign: 'right', flexShrink: 0 }}>
                        <div style={{ fontSize: '1.6rem', fontWeight: 800, color: '#e6533c' }}>{totalCount}</div>
                        <div style={{ fontSize: '0.72rem', color: 'var(--vz-text-muted)' }}>Total Records</div>
                    </div>
                </div>
            </div>

            {/* Filters */}
            <div className="card" style={{ padding: '16px 20px', marginBottom: 16 }}>
                <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap', alignItems: 'flex-end' }}>
                    <div style={{ flex: '1 1 220px' }}>
                        <label style={{ fontSize: '0.75rem', color: 'var(--vz-text-muted)', marginBottom: 4, display: 'block' }}>Search</label>
                        <div style={{ position: 'relative' }}>
                            <BiSearch style={{ position: 'absolute', left: 10, top: '50%', transform: 'translateY(-50%)', color: 'var(--vz-text-muted)' }} />
                            <input
                                value={searchInput}
                                onChange={e => setSearchInput(e.target.value)}
                                onKeyDown={e => e.key === 'Enter' && handleSearch()}
                                placeholder="Name, email, phone..."
                                style={{ paddingLeft: 32, width: '100%' }}
                                className="form-control form-control-sm"
                            />
                        </div>
                    </div>
                    <div style={{ flex: '0 1 160px' }}>
                        <label style={{ fontSize: '0.75rem', color: 'var(--vz-text-muted)', marginBottom: 4, display: 'block' }}>From Date</label>
                        <input type="date" value={from} onChange={e => { setFrom(e.target.value); setPage(1); }} className="form-control form-control-sm" />
                    </div>
                    <div style={{ flex: '0 1 160px' }}>
                        <label style={{ fontSize: '0.75rem', color: 'var(--vz-text-muted)', marginBottom: 4, display: 'block' }}>To Date</label>
                        <input type="date" value={to} onChange={e => { setTo(e.target.value); setPage(1); }} className="form-control form-control-sm" />
                    </div>
                    <button className="btn btn-primary btn-sm" onClick={handleSearch} style={{ flexShrink: 0 }}>
                        <BiFilter style={{ marginRight: 4 }} />Apply
                    </button>
                    {(search || from || to) && (
                        <button className="btn btn-outline-secondary btn-sm" onClick={() => { setSearch(''); setSearchInput(''); setFrom(''); setTo(''); setPage(1); }} style={{ flexShrink: 0 }}>
                            <BiX style={{ marginRight: 4 }} />Clear
                        </button>
                    )}
                </div>
            </div>

            {/* Table */}
            <div className="card" style={{ overflow: 'hidden' }}>
                {isLoading ? (
                    <div style={{ padding: 60, textAlign: 'center', color: 'var(--vz-text-muted)' }}>
                        <div className="spinner-border spinner-border-sm" style={{ marginRight: 8 }} />Loading deleted accounts...
                    </div>
                ) : isError ? (
                    <div style={{ padding: 60, textAlign: 'center', color: '#e6533c' }}>
                        <BiError size={32} style={{ marginBottom: 8, display: 'block', margin: '0 auto 8px' }} />
                        Failed to load deleted accounts
                    </div>
                ) : records.length === 0 ? (
                    <div style={{ padding: 60, textAlign: 'center', color: 'var(--vz-text-muted)' }}>
                        <BiCheckCircle size={36} style={{ display: 'block', margin: '0 auto 12px', color: '#26bf94' }} />
                        <div style={{ fontWeight: 600, marginBottom: 4 }}>No deleted accounts found</div>
                        <div style={{ fontSize: '0.83rem' }}>No accounts match your current filters</div>
                    </div>
                ) : (
                    <div style={{ overflowX: 'auto' }}>
                        <table className="table table-hover" style={{ margin: 0 }}>
                            <thead>
                                <tr>
                                    <th style={{ width: 40 }}>#</th>
                                    <th>User</th>
                                    <th>Contact</th>
                                    <th>Deletion Reason</th>
                                    <th>Deleted By</th>
                                    <th>Bookings</th>
                                    <th>Deleted At</th>
                                    <th>Actions</th>
                                </tr>
                            </thead>
                            <tbody>
                                {records.map((r, i) => (
                                    <tr key={r.id}>
                                        <td style={{ color: 'var(--vz-text-muted)', fontSize: '0.78rem' }}>{(page - 1) * 15 + i + 1}</td>
                                        <td>
                                            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                                                <div style={{ width: 36, height: 36, borderRadius: '50%', background: 'linear-gradient(135deg, #e6533c55, #c0392b33)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#e6533c', fontWeight: 700, fontSize: '0.9rem', flexShrink: 0 }}>
                                                    {r.firstName?.charAt(0)}
                                                </div>
                                                <div>
                                                    <div style={{ fontWeight: 600, fontSize: '0.85rem' }}>{r.firstName} {r.lastName}</div>
                                                    <div style={{ fontSize: '0.74rem', color: 'var(--vz-text-muted)' }}>{r.role} · {r.city || 'No city'}</div>
                                                </div>
                                            </div>
                                        </td>
                                        <td>
                                            <div style={{ fontSize: '0.82rem' }}>{r.email}</div>
                                            <div style={{ fontSize: '0.74rem', color: 'var(--vz-text-muted)' }}>{r.phone}</div>
                                        </td>
                                        <td>
                                            <div style={{ maxWidth: 160, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', fontSize: '0.82rem', color: r.deletionReason ? 'var(--vz-text-primary)' : 'var(--vz-text-muted)' }}>
                                                {r.deletionReason || 'No reason provided'}
                                            </div>
                                        </td>
                                        <td>
                                            <span className={`badge ${r.deletedByUser ? 'bg-warning-subtle text-warning' : 'bg-danger-subtle text-danger'}`} style={{ fontSize: '0.72rem' }}>
                                                {r.deletedByUser ? 'User' : 'Admin'}
                                            </span>
                                        </td>
                                        <td style={{ fontSize: '0.82rem' }}>{r.bookingsCount}</td>
                                        <td style={{ fontSize: '0.8rem', color: 'var(--vz-text-muted)', whiteSpace: 'nowrap' }}>{formatDate(r.createdAt)}</td>
                                        <td>
                                            <button className="btn btn-sm btn-outline-primary" onClick={() => setSelected(r)} title="View Details">
                                                <BiInfoCircle />
                                            </button>
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                )}

                {/* Pagination */}
                {totalPages > 1 && (
                    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '12px 20px', borderTop: '1px solid var(--vz-border)' }}>
                        <span style={{ fontSize: '0.8rem', color: 'var(--vz-text-muted)' }}>Page {page} of {totalPages} · {totalCount} records</span>
                        <div style={{ display: 'flex', gap: 6 }}>
                            <button className="btn btn-sm btn-outline-secondary" disabled={page <= 1} onClick={() => setPage(p => p - 1)}>← Prev</button>
                            <button className="btn btn-sm btn-outline-secondary" disabled={page >= totalPages} onClick={() => setPage(p => p + 1)}>Next →</button>
                        </div>
                    </div>
                )}
            </div>

            {/* Detail Modal */}
            {selected && (
                <DetailModal
                    record={selected}
                    onClose={() => setSelected(null)}
                    onRestore={(id, notes) => restoreMutation.mutate({ id, notes })}
                    onSaveNotes={(id, notes) => notesMutation.mutate({ id, notes })}
                    restoring={restoreMutation.isPending}
                    savingNotes={notesMutation.isPending}
                />
            )}
        </div>
    );
};

export default DeletedAccounts;
