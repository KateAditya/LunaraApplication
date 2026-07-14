import React, { useState, useEffect, useCallback } from 'react';
import { useAuthStore } from '../store/authStore';

interface SMRequest {
  id: string;
  subject: string;
  tagline: string;
  eventDateTime: string;
  numberOfPersons: number;
  chargesPerHead: number;
  status: 'pending' | 'approved' | 'rejected';
  paymentAmount: number | null;
  paymentStatus: 'unpaid' | 'paid';
  mobileNumber: string;
  alternateMobileNumber: string | null;
  adminNotes: string | null;
  ticketId: string | null;
  settlementStatus: 'none' | 'requested' | 'paid';
  bankDetails: string | null;
  settlementTransactionId: string | null;
  settlementAmount: number | null;
  settlementDate: string | null;
  settlementMethod: string | null;
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
  bankName: string | null;
  accountNumber: string | null;
  accountHolderName: string | null;
  ifscCode: string | null;
  upiId: string | null;
  platformChargePerSeat: number | null;
  joinedCount: number;
  paymentCount: number;
  remainingCount: number;
  foodPreference?: string;
  drinkPreference?: string;
}

interface Counts { pending: number; approved: number; rejected: number; }

const BASE_URL = import.meta.env.VITE_API_URL || 
  (window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1'
    ? 'http://localhost:9076'
    : `${window.location.protocol}//${window.location.hostname}:9076`);

const STATUS_COLORS: Record<string, { bg: string; text: string; border: string }> = {
  pending: { bg: 'rgba(245, 158, 11, 0.12)', text: '#d97706', border: 'rgba(245,158,11,0.3)' },
  approved: { bg: 'rgba(16, 185, 129, 0.12)', text: '#059669', border: 'rgba(16,185,129,0.3)' },
  rejected: { bg: 'rgba(239, 68, 68, 0.12)', text: '#dc2626', border: 'rgba(239,68,68,0.3)' },
};

export const StrangersMeet: React.FC = () => {
  const { accessToken } = useAuthStore();
  const [activeTab, setActiveTab] = useState<'pending' | 'approved' | 'rejected' | 'all'>('pending');
  const [requests, setRequests] = useState<SMRequest[]>([]);
  const [counts, setCounts] = useState<Counts>({ pending: 0, approved: 0, rejected: 0 });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Modal state
  const [selected, setSelected] = useState<SMRequest | null>(null);
  const [modalAction, setModalAction] = useState<'approve' | 'reject' | 'view' | 'settlement' | null>(null);
  const [payAmount, setPayAmount] = useState('');
  const [chargesPerHead, setChargesPerHead] = useState('');
  const [adminNote, setAdminNote] = useState('');
  const [settlementTxnId, setSettlementTxnId] = useState('');
  const [settlementAmt, setSettlementAmt] = useState('');
  const [settlementMethod, setSettlementMethod] = useState('Bank Transfer');
  const [submitting, setSubmitting] = useState(false);
  const [successMsg, setSuccessMsg] = useState<string | null>(null);

  const [copiedField, setCopiedField] = useState<string | null>(null);
  const handleCopy = (text: string, fieldName: string) => {
    navigator.clipboard.writeText(text);
    setCopiedField(fieldName);
    setTimeout(() => setCopiedField(null), 2000);
  };

  const renderCalculations = (req: SMRequest) => {
    const totalSeats = req.numberOfPersons;
    const paidSlots = req.paymentCount || 0;
    const joinedSlots = req.joinedCount || 0;
    const unfilledSeats = Math.max(0, totalSeats - paidSlots);
    const platformDepositTotal = Number(req.paymentAmount || 0);
    const platformChargePerSeat = req.platformChargePerSeat ? Number(req.platformChargePerSeat) : 
      (platformDepositTotal > 0 && totalSeats > 0 ? platformDepositTotal / totalSeats : 0);
    const hostChargePerHead = Number(req.chargesPerHead || 0);
    const hostRevenueFromParticipants = paidSlots * hostChargePerHead;
    const platformSettlementToHost = (unfilledSeats * platformChargePerSeat) + hostRevenueFromParticipants;
    const netHostProfit = platformSettlementToHost - platformDepositTotal;

    return (
      <div style={{ marginTop: '1.25rem' }}>
        <h4 style={{ margin: '0 0 0.75rem', fontSize: '0.9rem', fontWeight: 700, borderBottom: '1px solid var(--vz-border-color)', paddingBottom: '0.4rem', color: '#7c3aed' }}>
          📊 Meetup Analytics & Financials
        </h4>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '0.4rem', fontSize: '0.82rem', color: 'var(--vz-text-primary)' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', borderBottom: '1px dashed var(--vz-border-color)', paddingBottom: '0.2rem' }}>
            <span>Total Seats:</span>
            <span style={{ fontWeight: 600 }}>{totalSeats} seats</span>
          </div>
          <div style={{ display: 'flex', justifyContent: 'space-between', borderBottom: '1px dashed var(--vz-border-color)', paddingBottom: '0.2rem' }}>
            <span>Joined / Paid:</span>
            <span style={{ fontWeight: 600, color: '#7c3aed' }}>{joinedSlots} joined ({paidSlots} paid)</span>
          </div>
          <div style={{ display: 'flex', justifyContent: 'space-between', borderBottom: '1px dashed var(--vz-border-color)', paddingBottom: '0.2rem' }}>
            <span>Unfilled Slots:</span>
            <span style={{ fontWeight: 600 }}>{unfilledSeats} unfilled</span>
          </div>
          <div style={{ display: 'flex', justifyContent: 'space-between', borderBottom: '1px dashed var(--vz-border-color)', paddingBottom: '0.2rem' }}>
            <span>Host Pre-Paid Deposit:</span>
            <span style={{ fontWeight: 600 }}>₹{platformDepositTotal.toFixed(0)}</span>
          </div>
          <div style={{ display: 'flex', justifyContent: 'space-between', borderBottom: '1px dashed var(--vz-border-color)', paddingBottom: '0.2rem' }}>
            <span>Platform Fee Per Seat:</span>
            <span style={{ fontWeight: 600 }}>₹{platformChargePerSeat.toFixed(2)}</span>
          </div>
          <div style={{ display: 'flex', justifyContent: 'space-between', borderBottom: '1px dashed var(--vz-border-color)', paddingBottom: '0.2rem' }}>
            <span>Charges Per Head (for participants):</span>
            <span style={{ fontWeight: 600 }}>₹{hostChargePerHead.toFixed(0)}</span>
          </div>
          <div style={{ display: 'flex', justifyContent: 'space-between', borderBottom: '1px dashed var(--vz-border-color)', paddingBottom: '0.2rem' }}>
            <span>Total Participant Revenue:</span>
            <span style={{ fontWeight: 600, color: '#059669' }}>₹{hostRevenueFromParticipants.toFixed(0)}</span>
          </div>
          <div style={{ display: 'flex', justifyContent: 'space-between', background: 'rgba(5, 150, 105, 0.08)', padding: '0.5rem', borderRadius: 6, fontWeight: 700, marginTop: '0.25rem' }}>
            <span style={{ color: '#059669' }}>Host Settlement Amount:</span>
            <span style={{ color: '#059669' }}>₹{platformSettlementToHost.toFixed(0)}</span>
          </div>
          <div style={{ display: 'flex', justifyContent: 'space-between', background: netHostProfit >= 0 ? 'rgba(16, 185, 129, 0.08)' : 'rgba(239, 68, 68, 0.08)', padding: '0.5rem', borderRadius: 6, fontWeight: 700 }}>
            <span>Host Net Profit:</span>
            <span style={{ color: netHostProfit >= 0 ? '#059669' : '#dc2626' }}>
              {netHostProfit >= 0 ? '+' : ''}₹{netHostProfit.toFixed(0)}
            </span>
          </div>
        </div>
      </div>
    );
  };

  const renderBankDetails = (req: SMRequest) => {
    const hasStructured = req.upiId || req.accountNumber;
    if (!hasStructured && !req.bankDetails) {
      return (
        <div style={{ marginTop: '1rem', padding: '0.75rem', background: 'var(--vz-light)', borderRadius: 8, fontSize: '0.82rem', color: 'var(--vz-text-muted)', textAlign: 'center' }}>
          No settlement payment details provided yet by the host.
        </div>
      );
    }

    return (
      <div style={{ marginTop: '1.25rem' }}>
        <h4 style={{ margin: '0 0 0.75rem', fontSize: '0.9rem', fontWeight: 700, borderBottom: '1px solid var(--vz-border-color)', paddingBottom: '0.4rem', color: '#f59e0b' }}>
          🏦 Host Settlement Payment Details
        </h4>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem', background: 'rgba(245, 158, 11, 0.05)', border: '1.5px dashed rgba(245, 158, 11, 0.25)', borderRadius: 10, padding: '1rem', fontSize: '0.85rem' }}>
          {req.upiId && (
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <span><b>UPI ID:</b> {req.upiId}</span>
              <button 
                onClick={() => handleCopy(req.upiId!, 'upi')}
                style={{ padding: '0.25rem 0.6rem', fontSize: '0.75rem', background: '#f59e0b', color: '#fff', border: 'none', borderRadius: 4, cursor: 'pointer', display: 'flex', gap: '0.25rem', alignItems: 'center' }}
              >
                {copiedField === 'upi' ? '✓ Copied' : '📋 Copy'}
              </button>
            </div>
          )}
          {req.accountNumber && (
            <>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderBottom: '1px solid rgba(245,158,11,0.1)', paddingBottom: '0.25rem' }}>
                <span><b>Account Holder:</b> {req.accountHolderName || '—'}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderBottom: '1px solid rgba(245,158,11,0.1)', paddingBottom: '0.25rem' }}>
                <span><b>Bank Name:</b> {req.bankName || '—'}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderBottom: '1px solid rgba(245,158,11,0.1)', paddingBottom: '0.25rem' }}>
                <span><b>Account No:</b> {req.accountNumber}</span>
                <button 
                  onClick={() => handleCopy(req.accountNumber!, 'acct')}
                  style={{ padding: '0.25rem 0.6rem', fontSize: '0.75rem', background: '#f59e0b', color: '#fff', border: 'none', borderRadius: 4, cursor: 'pointer' }}
                >
                  {copiedField === 'acct' ? '✓ Copied' : '📋 Copy'}
                </button>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', paddingBottom: '0.25rem' }}>
                <span><b>IFSC Code:</b> {req.ifscCode}</span>
                <button 
                  onClick={() => handleCopy(req.ifscCode!, 'ifsc')}
                  style={{ padding: '0.2rem 0.6rem', fontSize: '0.75rem', background: '#f59e0b', color: '#fff', border: 'none', borderRadius: 4, cursor: 'pointer' }}
                >
                  {copiedField === 'ifsc' ? '✓ Copied' : '📋 Copy'}
                </button>
              </div>
            </>
          )}
          {req.bankDetails && (
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginTop: req.upiId || req.accountNumber ? '0.5rem' : '0' }}>
              <span style={{ whiteSpace: 'pre-wrap' }}><b>Details summary:</b><br/>{req.bankDetails}</span>
              <button 
                onClick={() => handleCopy(req.bankDetails!, 'legacy')}
                style={{ padding: '0.2rem 0.6rem', fontSize: '0.75rem', background: '#f59e0b', color: '#fff', border: 'none', borderRadius: 4, cursor: 'pointer', flexShrink: 0 }}
              >
                {copiedField === 'legacy' ? '✓ Copied' : '📋 Copy'}
              </button>
            </div>
          )}
        </div>
      </div>
    );
  };

  const headers = { 'Content-Type': 'application/json', Authorization: `Bearer ${accessToken}` };

  const fetchRequests = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const statusParam = activeTab === 'all' ? '' : `?status=${activeTab}`;
      const res = await fetch(`${BASE_URL}/api/admin/strangers-meet${statusParam}`, { headers });
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

  const openModal = (req: SMRequest, action: 'approve' | 'reject' | 'view' | 'settlement') => {
    setSelected(req);
    setModalAction(action);
    setPayAmount(req.paymentAmount ? req.paymentAmount.toString() : '');
    setChargesPerHead(req.chargesPerHead ? req.chargesPerHead.toString() : '');
    setAdminNote(req.adminNotes || '');
    setSettlementTxnId(req.settlementTransactionId || '');
    
    // Auto-calculate suggested settlement amount to pre-fill
    const totalSeats = req.numberOfPersons;
    const paidSlots = req.paymentCount || 0;
    const unfilledSeats = Math.max(0, totalSeats - paidSlots);
    const platformDepositTotal = Number(req.paymentAmount || 0);
    const platformChargePerSeat = req.platformChargePerSeat ? Number(req.platformChargePerSeat) : 
      (platformDepositTotal > 0 && totalSeats > 0 ? platformDepositTotal / totalSeats : 0);
    const hostChargePerHead = Number(req.chargesPerHead || 0);
    const hostRevenueFromParticipants = paidSlots * hostChargePerHead;
    const platformSettlementToHost = (unfilledSeats * platformChargePerSeat) + hostRevenueFromParticipants;

    setSettlementAmt(req.settlementAmount ? req.settlementAmount.toString() : (platformSettlementToHost > 0 ? platformSettlementToHost.toFixed(0) : ''));
    setSettlementMethod(req.settlementMethod || 'Bank Transfer');
    setSuccessMsg(null);
  };

  const closeModal = () => { setSelected(null); setModalAction(null); };

  const handlePayAmountChange = (value: string) => {
    setPayAmount(value);
    if (selected && selected.numberOfPersons > 0) {
      const amt = parseFloat(value);
      if (!isNaN(amt)) {
        setChargesPerHead(Math.round(amt / selected.numberOfPersons).toString());
      } else {
        setChargesPerHead('');
      }
    }
  };

  const handleChargesPerHeadChange = (value: string) => {
    setChargesPerHead(value);
    if (selected && selected.numberOfPersons > 0) {
      const cpHead = parseFloat(value);
      if (!isNaN(cpHead)) {
        setPayAmount(Math.round(cpHead * selected.numberOfPersons).toString());
      } else {
        setPayAmount('');
      }
    }
  };

  const handleApprove = async () => {
    if (!selected) return;
    const amount = parseFloat(payAmount);
    if (!payAmount || isNaN(amount) || amount <= 0) {
      alert('Please enter a valid deposit payment amount');
      return;
    }
    const cpHead = parseFloat(chargesPerHead);
    if (!chargesPerHead || isNaN(cpHead) || cpHead < 0) {
      alert('Please enter a valid charges per head (0 or more)');
      return;
    }
    setSubmitting(true);
    try {
      const res = await fetch(`${BASE_URL}/api/admin/strangers-meet/${selected.id}/approve`, {
        method: 'PATCH',
        headers,
        body: JSON.stringify({ paymentAmount: amount, chargesPerHead: cpHead, adminNotes: adminNote || undefined }),
      });
      const data = await res.json();
      if (data.success) {
        setSuccessMsg(`Approved! Deposit ₹${amount.toFixed(0)}, Charges/head ₹${cpHead.toFixed(0)}`);
        fetchRequests();
        setTimeout(closeModal, 1800);
      } else {
        alert(data.message || 'Failed to approve');
      }
    } finally {
      setSubmitting(false);
    }
  };

  const handlePaySettlement = async () => {
    if (!selected) return;
    if (!settlementTxnId.trim()) { alert('Transaction ID is required'); return; }
    const amt = parseFloat(settlementAmt);
    if (!settlementAmt || isNaN(amt) || amt <= 0) { alert('Enter a valid settlement amount'); return; }
    setSubmitting(true);
    try {
      const res = await fetch(`${BASE_URL}/api/admin/strangers-meet/${selected.id}/pay-settlement`, {
        method: 'POST',
        headers,
        body: JSON.stringify({ transactionId: settlementTxnId.trim(), amount: amt, paymentMethod: settlementMethod }),
      });
      const data = await res.json();
      if (data.success) {
        setSuccessMsg(`Settlement of ₹${amt.toFixed(0)} marked as paid!`);
        fetchRequests();
        setTimeout(closeModal, 1800);
      } else {
        alert(data.message || 'Failed to pay settlement');
      }
    } finally {
      setSubmitting(false);
    }
  };

  const handleReject = async () => {
    if (!selected) return;
    setSubmitting(true);
    try {
      const res = await fetch(`${BASE_URL}/api/admin/strangers-meet/${selected.id}/reject`, {
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
    { key: 'pending', label: 'Pending', count: counts.pending },
    { key: 'approved', label: 'Approved', count: counts.approved },
    { key: 'rejected', label: 'Rejected', count: counts.rejected },
    { key: 'all', label: 'All', count: counts.pending + counts.approved + counts.rejected },
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
                    <span>📞 {req.mobileNumber}</span>
                    {req.alternateMobileNumber && <span>📞 {req.alternateMobileNumber} (Alt)</span>}
                    {req.user && <span>👤 {req.user.firstName} {req.user.lastName}</span>}
                    {req.paymentAmount && <span>💰 ₹{Number(req.paymentAmount).toFixed(0)}</span>}
                    {req.foodPreference && <span>🥗 Food Pref: {req.foodPreference}</span>}
                    {req.drinkPreference && <span>🍹 Drink Pref: {req.drinkPreference}</span>}
                  </div>
                  <div style={{ display: 'flex', gap: '1.2rem', flexWrap: 'wrap', fontSize: '0.8rem', color: 'var(--vz-text-muted)', marginTop: '0.4rem' }}>
                    <span style={{ color: '#7c3aed', fontWeight: 600 }}>👥 Joined: {req.joinedCount || 0} / {req.numberOfPersons} ({req.paymentCount || 0} Paid)</span>
                    {req.status === 'approved' && (
                      <span style={{ color: '#059669', fontWeight: 600 }}>
                        💰 Est. Settlement: ₹{(((req.numberOfPersons - (req.paymentCount || 0)) * (req.platformChargePerSeat || 0)) + ((req.paymentCount || 0) * (req.chargesPerHead || 0))).toFixed(0)}
                      </span>
                    )}
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
                  {req.settlementStatus === 'requested' && (
                    <button onClick={() => openModal(req, 'settlement')} style={{ padding: '0.45rem 1rem', borderRadius: 8, border: 'none', background: '#f59e0b', color: '#fff', cursor: 'pointer', fontSize: '0.8rem', fontWeight: 600 }}>
                      💰 Pay Settlement
                    </button>
                  )}
                  {req.settlementStatus === 'paid' && (
                    <span style={{ padding: '0.3rem 0.75rem', borderRadius: 8, background: 'rgba(16,185,129,0.12)', color: '#059669', fontSize: '0.75rem', fontWeight: 700, textAlign: 'center' }}>
                      ✓ Settled
                    </span>
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
          <div style={{ background: 'var(--vz-card-bg)', borderRadius: 16, padding: '2rem', width: '100%', maxWidth: 520, maxHeight: '90vh', overflowY: 'auto', boxShadow: '0 20px 60px rgba(0,0,0,0.3)' }} onClick={e => e.stopPropagation()}>
            {successMsg ? (
              <div style={{ textAlign: 'center', padding: '2rem 0' }}>
                <div style={{ fontSize: '2.5rem', marginBottom: '0.75rem' }}>{modalAction === 'approve' ? '✅' : modalAction === 'settlement' ? '💸' : '❌'}</div>
                <div style={{ fontWeight: 700, fontSize: '1rem' }}>{successMsg}</div>
              </div>
            ) : (
              <>
                <h3 style={{ margin: '0 0 1.25rem', fontSize: '1.1rem' }}>
                  {modalAction === 'approve' ? '✓ Approve Request' : modalAction === 'reject' ? '✕ Reject Request' : modalAction === 'settlement' ? '💰 Pay Settlement' : '📋 Request Details'}
                </h3>

                {/* Summary */}
                <div style={{ background: 'var(--vz-light)', borderRadius: 10, padding: '1rem', marginBottom: '1.25rem', fontSize: '0.85rem' }}>
                  <div style={{ fontWeight: 700, marginBottom: '0.5rem' }}>{selected.subject}</div>
                  <div style={{ color: 'var(--vz-text-muted)', marginBottom: '0.5rem' }}>{selected.tagline}</div>
                  <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: '0.4rem', color: 'var(--vz-text-muted)' }}>
                    <span>🏛️ {selected.venue?.name}</span>
                    <span>🌆 {selected.venue?.city}</span>
                    <span>📅 {fmt(selected.eventDateTime)}</span>
                    <span>👥 {selected.numberOfPersons} persons</span>
                    <span>📞 {selected.mobileNumber}</span>
                    {selected.alternateMobileNumber && <span>📞 {selected.alternateMobileNumber} (Alt)</span>}
                    <span>👤 {selected.user?.firstName} {selected.user?.lastName}</span>
                    <span>📧 {selected.user?.email}</span>
                    {selected.foodPreference && <span>🥗 Food Pref: {selected.foodPreference}</span>}
                    {selected.drinkPreference && <span>🍹 Drink Pref: {selected.drinkPreference}</span>}
                  </div>
                </div>

                {modalAction === 'view' && selected && (
                  <>
                    {renderCalculations(selected)}
                    {renderBankDetails(selected)}
                  </>
                )}
                {modalAction === 'approve' && (
                  <>
                    <div style={{ marginBottom: '0.85rem' }}>
                      <label style={{ display: 'block', marginBottom: '0.4rem', fontWeight: 600, fontSize: '0.875rem' }}>Deposit Amount (₹) *</label>
                      <input type="number" min="1" placeholder="e.g. 2500" value={payAmount} onChange={e => handlePayAmountChange(e.target.value)}
                        style={{ width: '100%', padding: '0.6rem 0.85rem', borderRadius: 8, border: '1.5px solid var(--vz-border-color)', background: 'var(--vz-card-bg)', color: 'var(--vz-text-primary)', fontSize: '1rem', boxSizing: 'border-box' }} autoFocus />
                    </div>
                    <div style={{ marginBottom: '1rem' }}>
                      <label style={{ display: 'block', marginBottom: '0.4rem', fontWeight: 600, fontSize: '0.875rem' }}>Charges Per Head (₹) *</label>
                      <input type="number" min="0" placeholder="e.g. 350" value={chargesPerHead} onChange={e => handleChargesPerHeadChange(e.target.value)}
                        style={{ width: '100%', padding: '0.6rem 0.85rem', borderRadius: 8, border: '1.5px solid var(--vz-border-color)', background: 'var(--vz-card-bg)', color: 'var(--vz-text-primary)', fontSize: '1rem', boxSizing: 'border-box' }} />
                    </div>
                  </>
                )}
                {modalAction === 'settlement' && selected && (
                  <>
                    {renderBankDetails(selected)}
                    <div style={{ height: '1.25rem' }}></div>
                    <div style={{ marginBottom: '0.85rem', background: 'rgba(124,58,237,0.05)', borderRadius: 8, padding: '0.75rem', fontSize: '0.8rem' }}>
                      <b>Suggested Settlement:</b> ₹{settlementAmt} <br/>
                      <span style={{ color: 'var(--vz-text-muted)' }}>
                        Calculated as: ({selected.numberOfPersons - (selected.paymentCount || 0)} unfilled seats × platform fee per seat) + ({(selected.paymentCount || 0)} paid seats × host head charges)
                      </span>
                    </div>
                    <div style={{ marginBottom: '0.85rem' }}>
                      <label style={{ display: 'block', marginBottom: '0.4rem', fontWeight: 600, fontSize: '0.875rem' }}>Transaction ID *</label>
                      <input type="text" placeholder="e.g. TXN1234567890" value={settlementTxnId} onChange={e => setSettlementTxnId(e.target.value)}
                        style={{ width: '100%', padding: '0.6rem 0.85rem', borderRadius: 8, border: '1.5px solid var(--vz-border-color)', background: 'var(--vz-card-bg)', color: 'var(--vz-text-primary)', fontSize: '0.9rem', boxSizing: 'border-box' }} autoFocus />
                    </div>
                    <div style={{ marginBottom: '0.85rem' }}>
                      <label style={{ display: 'block', marginBottom: '0.4rem', fontWeight: 600, fontSize: '0.875rem' }}>Settlement Amount (₹) *</label>
                      <input type="number" min="1" placeholder="e.g. 5000" value={settlementAmt} onChange={e => setSettlementAmt(e.target.value)}
                        style={{ width: '100%', padding: '0.6rem 0.85rem', borderRadius: 8, border: '1.5px solid var(--vz-border-color)', background: 'var(--vz-card-bg)', color: 'var(--vz-text-primary)', fontSize: '0.9rem', boxSizing: 'border-box' }} />
                    </div>
                    <div style={{ marginBottom: '1.25rem' }}>
                      <label style={{ display: 'block', marginBottom: '0.4rem', fontWeight: 600, fontSize: '0.875rem' }}>Payment Method</label>
                      <select value={settlementMethod} onChange={e => setSettlementMethod(e.target.value)}
                        style={{ width: '100%', padding: '0.6rem 0.85rem', borderRadius: 8, border: '1.5px solid var(--vz-border-color)', background: 'var(--vz-card-bg)', color: 'var(--vz-text-primary)', fontSize: '0.9rem', boxSizing: 'border-box' }}>
                        <option>Bank Transfer</option>
                        <option>UPI Payout</option>
                        <option>NEFT</option>
                        <option>IMPS</option>
                        <option>RTGS</option>
                      </select>
                    </div>
                  </>
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
                    <button onClick={handleApprove} disabled={submitting || !payAmount || !chargesPerHead} style={{ padding: '0.6rem 1.5rem', borderRadius: 8, border: 'none', background: '#7c3aed', color: '#fff', cursor: 'pointer', fontWeight: 600, opacity: submitting ? 0.7 : 1 }}>
                      {submitting ? 'Approving…' : 'Approve & Set Payment'}
                    </button>
                  )}
                  {modalAction === 'reject' && (
                    <button onClick={handleReject} disabled={submitting} style={{ padding: '0.6rem 1.5rem', borderRadius: 8, border: 'none', background: '#dc2626', color: '#fff', cursor: 'pointer', fontWeight: 600, opacity: submitting ? 0.7 : 1 }}>
                      {submitting ? 'Rejecting…' : 'Confirm Reject'}
                    </button>
                  )}
                  {modalAction === 'settlement' && (
                    <button onClick={handlePaySettlement} disabled={submitting || !settlementTxnId || !settlementAmt} style={{ padding: '0.6rem 1.5rem', borderRadius: 8, border: 'none', background: '#f59e0b', color: '#fff', cursor: 'pointer', fontWeight: 600, opacity: submitting ? 0.7 : 1 }}>
                      {submitting ? 'Processing…' : '💰 Mark as Paid'}
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
