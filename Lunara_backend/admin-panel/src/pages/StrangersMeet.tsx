import React, { useState, useEffect, useCallback } from 'react';
import { useAuthStore } from '../store/authStore';

interface SMRequest {
  id: string;
  subject: string;
  tagline: string;
  eventDateTime: string;
  numberOfPersons: number;
  status: 'pending' | 'approved' | 'rejected';
  paymentAmount: number | null;
  paymentStatus: 'unpaid' | 'paid';
  adminNotes: string | null;
  ticketId: string | null;
  createdAt: string;
  user: {
    id: string;
    firstName: string;
    lastName: string;
    email: string;
    phone: string;
    photoUrl: string | null;
    city: string | null;
  } | null;
  venue: {
    id: string;
    name: string;
    addressLine1: string;
    area: string;
    city: string;
    category: string;
    imageUrl: string | null;
  } | null;
}

interface Counts { pending: number; approved: number; rejected: number; }

const BASE_URL = import.meta.env.VITE_API_URL || 'http://103.224.247.35:9076';

const STATUS_COLORS: Record<string, { bg: string; text: string; border: string }> = {
  pending:  { bg: 'rgba(245, 158, 11, 0.12)', text: '#d97706',  border: 'rgba(245,158,11,0.3)' },
  approved: { bg: 'rgba(16, 185, 129, 0.12)', text: '#059669',  border: 'rgba(16,185,129,0.3)' },
  rejected: { bg: 'rgba(239, 68, 68, 0.12)',  text: '#dc2626',  border: 'rgba(239,68,68,0.3)'  },
};

export const StrangersMeet: React.FC = () => {
  const { accessToken } = useAuthStore();
  const [activeTab, setActiveTab] = useState<'pending' | 'approved' | 'rejected' | 'all'>('pending');
  const [requests, setRequests]   = useState<SMRequest[]>([]);
  const [counts, setCounts]       = useState<Counts>({ pending: 0, approved: 0, rejected: 0 });
  const [loading, setLoading]     = useState(false);
  const [error, setError]         = useState<string | null>(null);

  // Modal state
  const [selected, setSelected]       = useState<SMRequest | null>(null);
  const [modalAction, setModalAction] = useState<'approve' | 'reject' | 'view' | null>(null);
  const [payAmount, setPayAmount]     = useState('');
  const [adminNote, setAdminNote]     = useState('');
  const [submitting, setSubmitting]   = useState(false);
  const [successMsg, setSuccessMsg]   = useState<string | null>(null);

  const headers = { 'Content-Type': 'application/json', Authorization: `Bearer ${accessToken}` };

  const fetchRequests = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const statusParam = activeTab === 'all' ? '' : `?status=${activeTab}`;
      const res  = await fetch(`${BASE_URL}/api/admin/strangers-meet${statusParam}`, { headers });
      const data = await res.json();
      if (data.success) {
        setRequests(data.data);
        setCounts(data.counts);
      } else {
        setError(data.message || 'Failed to load requests');
      }
    } catch (e) {
      setError('Network error. Please try again.');
    } finally {
      setLoading(false);
    }
  }, [activeTab, accessToken]);

  useEffect(() => { fetchRequests(); }, [fetchRequests]);

  // Auto-refresh every 30s
  useEffect(() => {
    const id = setInterval(fetchRequests, 30_000);
    return () => clearInterval(id);
  }, [fetchRequests]);

  const openModal = (req: SMRequest, action: 'approve' | 'reject' | 'view') => {
    setSelected(req);
    setModalAction(action);
    setPayAmount('');
    setAdminNote('');
    setSuccessMsg(null);
  };

  const closeModal = () => { setSelected(null); setModalAction(null); };

  const handleApprove = async () => {
    if (!selected) return;
    const amount = parseFloat(payAmount);
    if (!payAmount || isNaN(amount) || amount <= 0) {
      alert('Please enter a valid payment amount');
      return;
    }
    setSubmitting(true);
    try {
      const res  = await fetch(`${BASE_URL}/api/admin/strangers-meet/${selected.id}/approve`, {
        method: 'PATCH',
        headers,
        body: JSON.stringify({ paymentAmount: amount, adminNotes: adminNote || undefined }),
      });
      const data = await res.json();
      if (data.success) {
        setSuccessMsg(`Request approved with payment of ₹${amount.toFixed(0)}`);
        fetchRequests();
        setTimeout(closeModal, 1500);
      } else {
        alert(data.message || 'Failed to approve');
      }
    } finally {
      setSubmitting(false);
    }
  };

  const handleReject = async () => {
    if (!selected) return;
    setSubmitting(true);
    try {
      const res  = await fetch(`${BASE_URL}/api/admin/strangers-meet/${selected.id}/reject`, {
        method: 'PATCH',
        headers,
        body: JSON.stringify({ adminNotes: adminNote || undefined }),
      });
      const data = await res.json();
      if (data.success) {
        setSuccessMsg('Request rejected');
        fetchRequests();
        setTimeout(closeModal, 1500);
      } else {
        alert(data.message || 'Failed to reject');
      }
    } finally {
      setSubmitting(false);
    }
  };

  const fmt = (dt: string) =>
    new Date(dt).toLocaleString('en-IN', { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' });

  const tabs = [
    { key: 'pending',  label: 'Pending',  count: counts.pending },
    { key: 'approved', label: 'Approved', count: counts.approved },
    { key: 'rejected', label: 'Rejected', count: counts.rejected },
    { key: 'all',      label: 'All',      count: counts.pending + counts.approved + counts.rejected },
  ] as const;

  return (
    <div style={{ padding: '1.5rem' }}>
      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '1.5rem' }}>
        <div>
          <h2 style={{ margin: 0, fontSize: '1.35rem', fontWeight: 700 }}>Strangers Meet Requests</h2>
          <p style={{ margin: '0.25rem 0 0', color: 'var(--vz-text-muted)', fontSize: '0.85rem' }}>
            Review and manage event arrangement requests from users
          </p>
        </div>
        <button
          onClick={fetchRequests}
          style={{ padding: '0.5rem 1rem', borderRadius: 8, border: '1px solid var(--vz-border-color)', background: 'transparent', cursor: 'pointer', color: 'var(--vz-text-primary)', fontSize: '0.8rem' }}
        >
          ↻ Refresh
        </button>
      </div>

      {/* Tabs */}
      <div style={{ display: 'flex', gap: '0.5rem', marginBottom: '1.25rem', borderBottom: '2px solid var(--vz-border-color)', paddingBottom: '0' }}>
        {tabs.map(t => (
          <button
            key={t.key}
            onClick={() => setActiveTab(t.key)}
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
              display: 'flex',
              alignItems: 'center',
              gap: '0.4rem',
              transition: 'all 0.15s',
            }}
          >
            {t.label}
            {t.count > 0 && (
              <span style={{
                background: activeTab === t.key ? '#7c3aed' : 'var(--vz-light)',
                color: activeTab === t.key ? '#fff' : 'var(--vz-text-muted)',
                borderRadius: 20,
                padding: '0.1rem 0.5rem',
                fontSize: '0.72rem',
                fontWeight: 700,
              }}>
                {t.count}
              </span>
            )}
          </button>
        ))}
      </div>

      {/* Content */}
      {loading ? (
        <div style={{ textAlign: 'center', padding: '3rem', color: 'var(--vz-text-muted)' }}>Loading requests…</div>
      ) : error ? (
        <div style={{ textAlign: 'center', padding: '3rem', color: '#dc2626' }}>{error}</div>
      ) : requests.length === 0 ? (
        <div style={{ textAlign: 'center', padding: '4rem', color: 'var(--vz-text-muted)' }}>
          <div style={{ fontSize: '3rem', marginBottom: '1rem' }}>👥</div>
          <div style={{ fontWeight: 600 }}>No {activeTab} requests</div>
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
          {requests.map(req => {
            const sc = STATUS_COLORS[req.status];
            return (
              <div key={req.id} style={{ background: 'var(--vz-card-bg)', border: '1px solid var(--vz-border-color)', borderRadius: 14, padding: '1.25rem', display: 'flex', gap: '1rem', flexWrap: 'wrap', alignItems: 'flex-start' }}>
                {/* Venue Image */}
                {req.venue?.imageUrl && (
                  <img
                    src={`${BASE_URL}${req.venue.imageUrl}`}
                    alt={req.venue.name}
                    style={{ width: 80, height: 70, borderRadius: 10, objectFit: 'cover', flexShrink: 0 }}
                    onError={e => { (e.target as HTMLImageElement).style.display = 'none'; }}
                  />
                )}

                {/* Main Info */}
                <div style={{ flex: 1, minWidth: 200 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem', flexWrap: 'wrap', marginBottom: '0.4rem' }}>
                    <span style={{ fontWeight: 700, fontSize: '1rem' }}>{req.subject}</span>
                    <span style={{ padding: '0.15rem 0.65rem', borderRadius: 20, fontSize: '0.72rem', fontWeight: 700, background: sc.bg, color: sc.text, border: `1px solid ${sc.border}` }}>
                      {req.status.toUpperCase()}
                    </span>
                    {req.paymentStatus === 'paid' && (
                      <span style={{ padding: '0.15rem 0.65rem', borderRadius: 20, fontSize: '0.72rem', fontWeight: 700, background: 'rgba(16,185,129,0.12)', color: '#059669', border: '1px solid rgba(16,185,129,0.3)' }}>
                        PAID ✓
                      </span>
                    )}
                  </div>
                  <p style={{ margin: '0 0 0.6rem', color: 'var(--vz-text-muted)', fontSize: '0.83rem' }}>{req.tagline}</p>
                  <div style={{ display: 'flex', gap: '1.2rem', flexWrap: 'wrap', fontSize: '0.8rem', color: 'var(--vz-text-muted)' }}>
                    <span>🏛️ <b>{req.venue?.name ?? '—'}</b>, {req.venue?.city}</span>
                    <span>📅 {fmt(req.eventDateTime)}</span>
                    <span>👥 {req.numberOfPersons} persons</span>
                    {req.user && <span>👤 {req.user.firstName} {req.user.lastName}</span>}
                    {req.paymentAmount && <span>💰 ₹{Number(req.paymentAmount).toFixed(0)}</span>}
                  </div>
                  {req.adminNotes && (
                    <div style={{ marginTop: '0.5rem', padding: '0.4rem 0.75rem', background: 'var(--vz-light)', borderRadius: 6, fontSize: '0.78rem', color: 'var(--vz-text-muted)' }}>
                      📝 {req.adminNotes}
                    </div>
                  )}
                  {req.ticketId && (
                    <div style={{ marginTop: '0.4rem', fontSize: '0.75rem', color: '#7c3aed', fontFamily: 'monospace' }}>
                      🎟️ Ticket: {req.ticketId}
                    </div>
                  )}
                </div>

                {/* Actions */}
                <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem', flexShrink: 0 }}>
                  <button onClick={() => openModal(req, 'view')} style={{ padding: '0.45rem 1rem', borderRadius: 8, border: '1px solid var(--vz-border-color)', background: 'transparent', cursor: 'pointer', fontSize: '0.8rem', color: 'var(--vz-text-primary)' }}>
                    View Details
                  </button>
                  {req.status === 'pending' && (
                    <>
                      <button onClick={() => openModal(req, 'approve')} style={{ padding: '0.45rem 1rem', borderRadius: 8, border: 'none', background: '#7c3aed', color: '#fff', cursor: 'pointer', fontSize: '0.8rem', fontWeight: 600 }}>
                        ✓ Approve
                      </button>
                      <button onClick={() => openModal(req, 'reject')} style={{ padding: '0.45rem 1rem', borderRadius: 8, border: '1px solid #dc2626', background: 'transparent', color: '#dc2626', cursor: 'pointer', fontSize: '0.8rem' }}>
                        ✕ Reject
                      </button>
                    </>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* Modal */}
      {selected && modalAction && (
        <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.5)', zIndex: 9999, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '1rem' }} onClick={closeModal}>
          <div style={{ background: 'var(--vz-card-bg)', borderRadius: 16, padding: '2rem', width: '100%', maxWidth: 520, boxShadow: '0 20px 60px rgba(0,0,0,0.3)' }} onClick={e => e.stopPropagation()}>
            {successMsg ? (
              <div style={{ textAlign: 'center', padding: '2rem 0' }}>
                <div style={{ fontSize: '2.5rem', marginBottom: '0.75rem' }}>{modalAction === 'approve' ? '✅' : '❌'}</div>
                <div style={{ fontWeight: 700, fontSize: '1rem' }}>{successMsg}</div>
              </div>
            ) : (
              <>
                <h3 style={{ margin: '0 0 1.25rem', fontSize: '1.1rem' }}>
                  {modalAction === 'approve' ? '✓ Approve Request' : modalAction === 'reject' ? '✕ Reject Request' : '📋 Request Details'}
                </h3>

                {/* Summary */}
                <div style={{ background: 'var(--vz-light)', borderRadius: 10, padding: '1rem', marginBottom: '1.25rem', fontSize: '0.85rem' }}>
                  <div style={{ fontWeight: 700, marginBottom: '0.5rem' }}>{selected.subject}</div>
                  <div style={{ color: 'var(--vz-text-muted)', marginBottom: '0.5rem' }}>{selected.tagline}</div>
                  <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.4rem', color: 'var(--vz-text-muted)' }}>
                    <span>🏛️ {selected.venue?.name}</span>
                    <span>🌆 {selected.venue?.city}</span>
                    <span>📅 {fmt(selected.eventDateTime)}</span>
                    <span>👥 {selected.numberOfPersons} persons</span>
                    <span>👤 {selected.user?.firstName} {selected.user?.lastName}</span>
                    <span>📧 {selected.user?.email}</span>
                  </div>
                </div>

                {modalAction === 'approve' && (
                  <div style={{ marginBottom: '1rem' }}>
                    <label style={{ display: 'block', marginBottom: '0.4rem', fontWeight: 600, fontSize: '0.875rem' }}>
                      Payment Amount (₹) *
                    </label>
                    <input
                      type="number"
                      min="1"
                      placeholder="Enter amount e.g. 2500"
                      value={payAmount}
                      onChange={e => setPayAmount(e.target.value)}
                      style={{ width: '100%', padding: '0.6rem 0.85rem', borderRadius: 8, border: '1.5px solid var(--vz-border-color)', background: 'var(--vz-card-bg)', color: 'var(--vz-text-primary)', fontSize: '1rem', boxSizing: 'border-box' }}
                      autoFocus
                    />
                  </div>
                )}

                {(modalAction === 'approve' || modalAction === 'reject') && (
                  <div style={{ marginBottom: '1.25rem' }}>
                    <label style={{ display: 'block', marginBottom: '0.4rem', fontWeight: 600, fontSize: '0.875rem' }}>
                      Admin Note (optional)
                    </label>
                    <textarea
                      placeholder={modalAction === 'approve' ? 'Any instructions for the user…' : 'Reason for rejection…'}
                      value={adminNote}
                      onChange={e => setAdminNote(e.target.value)}
                      rows={3}
                      style={{ width: '100%', padding: '0.6rem 0.85rem', borderRadius: 8, border: '1.5px solid var(--vz-border-color)', background: 'var(--vz-card-bg)', color: 'var(--vz-text-primary)', fontSize: '0.875rem', resize: 'vertical', boxSizing: 'border-box' }}
                    />
                  </div>
                )}

                <div style={{ display: 'flex', gap: '0.75rem', justifyContent: 'flex-end' }}>
                  <button onClick={closeModal} disabled={submitting} style={{ padding: '0.6rem 1.25rem', borderRadius: 8, border: '1px solid var(--vz-border-color)', background: 'transparent', cursor: 'pointer', color: 'var(--vz-text-primary)' }}>
                    Cancel
                  </button>
                  {modalAction === 'approve' && (
                    <button onClick={handleApprove} disabled={submitting || !payAmount} style={{ padding: '0.6rem 1.5rem', borderRadius: 8, border: 'none', background: '#7c3aed', color: '#fff', cursor: 'pointer', fontWeight: 600, opacity: submitting ? 0.7 : 1 }}>
                      {submitting ? 'Approving…' : 'Approve & Set Payment'}
                    </button>
                  )}
                  {modalAction === 'reject' && (
                    <button onClick={handleReject} disabled={submitting} style={{ padding: '0.6rem 1.5rem', borderRadius: 8, border: 'none', background: '#dc2626', color: '#fff', cursor: 'pointer', fontWeight: 600, opacity: submitting ? 0.7 : 1 }}>
                      {submitting ? 'Rejecting…' : 'Confirm Reject'}
                    </button>
                  )}
                </div>
              </>
            )}
          </div>
        </div>
      )}
    </div>
  );
};

export default StrangersMeet;
