import React, { useState, useEffect, useCallback } from 'react';
import { useAuthStore } from '../store/authStore';

interface SMRequest {
  id: string;
  subject: string;
  tagline: string;
  eventDateTime: string;
  numberOfPersons: number;
  chargesPerHead: number;
  status:
    | 'pending'
    | 'approved'
    | 'rejected'
    | 'start_confirmation_pending'
    | 'in_progress'
    | 'end_confirmation_pending'
    | 'host_confirmed_ended'
    | 'admin_confirmed_ended'
    | 'settled'
    | 'completed'
    | 'not_started'
    | 'needs_host_contact'
    | 'cancelled';
  paymentAmount: number | null;
  paymentStatus: 'unpaid' | 'paid';
  mobileNumber: string;
  alternateMobileNumber: string | null;
  adminNotes: string | null;
  ticketId: string | null;
  settlementStatus: 'none' | 'requested' | 'approved' | 'settlement_pending' | 'paid' | 'settled';
  bankDetails: string | null;
  settlementTransactionId: string | null;
  settlementAmount: number | null;
  settlementDate: string | null;
  settlementMethod: string | null;
  createdAt: string;
  // Lifecycle attributes
  startedAt: string | null;
  startedBy: string | null;
  durationHours: number | null;
  expectedEndAt: string | null;
  endedAt: string | null;
  endedConfirmedBy: string | null;
  endedConfirmedAt: string | null;
  adminConfirmedEndedAt: string | null;
  adminConfirmedBy: string | null;
  settlementOverdue: boolean | null;
  escalatedAt?: string | null;
  escalationReason?: string | null;
  adminResolution?: string | null;
  adminResolutionNotes?: string | null;
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

export interface HostCancellationItem {
  id: string;
  meetId: string;
  hostUserId: string;
  reasonCategory: string;
  reasonText: string | null;
  status: 'PENDING_ADMIN_REVIEW' | 'APPROVED' | 'REFUND_PROCESSING' | 'COMPLETED' | 'REJECTED';
  totalMembersCount: number;
  totalCollectedAmount: number;
  refundPolicyPercentage: number | null;
  refundMethod: 'WALLET' | 'MANUAL_PAYOUT' | null;
  totalRefundAmount: number | null;
  adminReviewedBy: string | null;
  adminReviewedAt: string | null;
  adminNotes: string | null;
  hostDepositAmount: number | null;
  hostRefundType: 'FULL' | 'PARTIAL' | 'CUSTOM' | 'NO_REFUND' | null;
  hostRefundPercentage: number | null;
  hostRefundAmount: number | null;
  hostRefundDestination: 'WALLET' | 'UPI' | 'BANK' | 'NONE' | null;
  hostRefundStatus: 'NONE' | 'WALLET_CREDITED' | 'HOST_REFUND_PENDING_SETTLEMENT' | 'PAID' | null;
  hostPayoutDetails: any;
  hostSettlementTransactionId: string | null;
  hostSettledAt: string | null;
  hostSettledBy: string | null;
  hostSettlementNotes: string | null;
  createdAt: string;
  host?: {
    id: string;
    firstName: string;
    lastName: string;
    email: string;
    phone: string;
    profileImageUrl?: string;
    upiId?: string;
    accountNumber?: string;
    bankName?: string;
    ifscCode?: string;
  };
  meet?: {
    id: string;
    subject: string;
    eventDateTime: string;
    numberOfPersons: number;
    paymentAmount: number;
    chargesPerHead?: number;
    venue?: {
      name: string;
      area?: string;
      city?: string;
    };
  };
  memberRefunds?: any[];
}

interface Counts {
  pending: number;
  approved: number;
  rejected: number;
  payouts: number;
  inProgress?: number;
  completed?: number;
  needsContact?: number;
}

const BASE_URL =
  import.meta.env.VITE_API_URL ||
  (typeof window !== 'undefined' && window.location?.origin ? window.location.origin : 'http://localhost:9076');

const STATUS_COLORS: Record<string, { bg: string; text: string; border: string }> = {
  pending: { bg: 'rgba(245, 158, 11, 0.12)', text: '#d97706', border: 'rgba(245,158,11,0.3)' },
  approved: { bg: 'rgba(16, 185, 129, 0.12)', text: '#059669', border: 'rgba(16,185,129,0.3)' },
  start_confirmation_pending: { bg: 'rgba(139, 92, 246, 0.15)', text: '#7c3aed', border: 'rgba(139, 92, 246, 0.4)' },
  in_progress: { bg: 'rgba(59, 130, 246, 0.12)', text: '#2563eb', border: 'rgba(59,130,246,0.3)' },
  end_confirmation_pending: { bg: 'rgba(245, 158, 11, 0.15)', text: '#b45309', border: 'rgba(245,158,11,0.4)' },
  host_confirmed_ended: { bg: 'rgba(245, 158, 11, 0.15)', text: '#b45309', border: 'rgba(245,158,11,0.4)' },
  admin_confirmed_ended: { bg: 'rgba(124, 58, 237, 0.12)', text: '#7c3aed', border: 'rgba(124,58,237,0.3)' },
  completed: { bg: 'rgba(16, 185, 129, 0.15)', text: '#059669', border: 'rgba(16,185,129,0.4)' },
  settled: { bg: 'rgba(16, 185, 129, 0.2)', text: '#047857', border: 'rgba(16,185,129,0.5)' },
  needs_host_contact: { bg: 'rgba(239, 68, 68, 0.15)', text: '#dc2626', border: 'rgba(239, 68, 68, 0.4)' },
  not_started: { bg: 'rgba(107, 114, 128, 0.15)', text: '#4b5563', border: 'rgba(107, 114, 128, 0.3)' },
  rejected: { bg: 'rgba(239, 68, 68, 0.12)', text: '#dc2626', border: 'rgba(239,68,68,0.3)' },
  payouts: { bg: 'rgba(124, 58, 237, 0.12)', text: '#7c3aed', border: 'rgba(124,58,237,0.3)' },
};

export const StrangersMeet: React.FC = () => {
  const { accessToken } = useAuthStore();
  const [activeTab, setActiveTab] = useState<
    'pending' | 'approved' | 'in_progress' | 'needs_contact' | 'completed' | 'payouts' | 'rejected' | 'all' | 'cancellations'
  >('pending');
  const [requests, setRequests] = useState<SMRequest[]>([]);
  const [counts, setCounts] = useState<Counts>({ pending: 0, approved: 0, rejected: 0, payouts: 0 });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Cancellations state (Sections 15, 27, 28)
  const [cancellations, setCancellations] = useState<HostCancellationItem[]>([]);
  const [cancellationFilter, setCancellationFilter] = useState<'all' | 'pending' | 'settlement_pending' | 'completed' | 'rejected'>('all');
  const [cancellationCounts, setCancellationCounts] = useState({ all: 0, pending: 0, settlement_pending: 0, completed: 0, rejected: 0 });
  const [selectedCancellation, setSelectedCancellation] = useState<HostCancellationItem | null>(null);
  const [cancellationDetail, setCancellationDetail] = useState<any | null>(null);
  const [loadingDetail, setLoadingDetail] = useState(false);

  // Host approval decision state (Section 28)
  const [hostRefundDecision, setHostRefundDecision] = useState<'FULL' | 'PARTIAL' | 'CUSTOM' | 'NO_REFUND'>('FULL');
  const [hostRefundPercentage, setHostRefundPercentage] = useState<number>(100);
  const [hostRefundCustomAmount, setHostRefundCustomAmount] = useState<string>('0');
  const [hostRefundDestination, setHostRefundDestination] = useState<'WALLET' | 'UPI' | 'BANK'>('WALLET');
  const [cancellationRejectionReason, setCancellationRejectionReason] = useState<string>('');
  const [isRejectingCancellation, setIsRejectingCancellation] = useState(false);

  // Host manual settlement modal state (Section 15)
  const [settleCancellation, setSettleCancellation] = useState<HostCancellationItem | null>(null);
  const [hostSettleRef, setHostSettleRef] = useState('');
  const [hostSettleMethod, setHostSettleMethod] = useState('UPI');
  const [hostSettleNotes, setHostSettleNotes] = useState('');

  // Modal state
  const [selected, setSelected] = useState<SMRequest | null>(null);
  const [modalAction, setModalAction] = useState<
    'approve' | 'reject' | 'view' | 'settlement' | 'confirmEnded' | 'resolveEscalation' | null
  >(null);
  const [payAmount, setPayAmount] = useState('');
  const [chargesPerHead, setChargesPerHead] = useState('');
  const [adminNote, setAdminNote] = useState('');
  const [settlementTxnId, setSettlementTxnId] = useState('');
  const [settlementAmt, setSettlementAmt] = useState('');
  const [settlementMethod, setSettlementMethod] = useState('UPI');
  const [resolutionType, setResolutionType] = useState('MARK_COMPLETED');
  const [resolutionNotes, setResolutionNotes] = useState('');
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
    const platformChargePerSeat = req.platformChargePerSeat
      ? Number(req.platformChargePerSeat)
      : platformDepositTotal > 0 && totalSeats > 0
      ? platformDepositTotal / totalSeats
      : 0;
    const hostChargePerHead = Number(req.chargesPerHead || 0);
    const hostRevenueFromParticipants = paidSlots * hostChargePerHead;
    const platformSettlementToHost = unfilledSeats * platformChargePerSeat + hostRevenueFromParticipants;
    const netHostProfit = platformSettlementToHost - platformDepositTotal;

    return (
      <div style={{ marginTop: '1.25rem' }}>
        <h4
          style={{
            margin: '0 0 0.75rem',
            fontSize: '0.9rem',
            fontWeight: 700,
            borderBottom: '1px solid var(--vz-border-color)',
            paddingBottom: '0.4rem',
            color: '#7c3aed',
          }}
        >
          📊 Meetup Analytics & Financials (Automated Calculation)
        </h4>
        <div
          style={{
            display: 'flex',
            flexDirection: 'column',
            gap: '0.4rem',
            fontSize: '0.82rem',
            color: 'var(--vz-text-primary)',
          }}
        >
          <div
            style={{
              display: 'flex',
              justifyContent: 'space-between',
              borderBottom: '1px dashed var(--vz-border-color)',
              paddingBottom: '0.2rem',
            }}
          >
            <span>Total Seats:</span>
            <span style={{ fontWeight: 600 }}>{totalSeats} seats</span>
          </div>
          <div
            style={{
              display: 'flex',
              justifyContent: 'space-between',
              borderBottom: '1px dashed var(--vz-border-color)',
              paddingBottom: '0.2rem',
            }}
          >
            <span>Joined / Paid:</span>
            <span style={{ fontWeight: 600, color: '#7c3aed' }}>
              {joinedSlots} joined ({paidSlots} paid)
            </span>
          </div>
          <div
            style={{
              display: 'flex',
              justifyContent: 'space-between',
              borderBottom: '1px dashed var(--vz-border-color)',
              paddingBottom: '0.2rem',
            }}
          >
            <span>Unfilled Slots:</span>
            <span style={{ fontWeight: 600 }}>{unfilledSeats} unfilled</span>
          </div>
          <div
            style={{
              display: 'flex',
              justifyContent: 'space-between',
              borderBottom: '1px dashed var(--vz-border-color)',
              paddingBottom: '0.2rem',
            }}
          >
            <span>Host Pre-Paid Deposit:</span>
            <span style={{ fontWeight: 600 }}>₹{platformDepositTotal.toFixed(0)}</span>
          </div>
          <div
            style={{
              display: 'flex',
              justifyContent: 'space-between',
              borderBottom: '1px dashed var(--vz-border-color)',
              paddingBottom: '0.2rem',
            }}
          >
            <span>Platform Fee Per Seat:</span>
            <span style={{ fontWeight: 600 }}>₹{platformChargePerSeat.toFixed(2)}</span>
          </div>
          <div
            style={{
              display: 'flex',
              justifyContent: 'space-between',
              borderBottom: '1px dashed var(--vz-border-color)',
              paddingBottom: '0.2rem',
            }}
          >
            <span>Charges Per Head (Participants):</span>
            <span style={{ fontWeight: 600 }}>₹{hostChargePerHead.toFixed(0)}</span>
          </div>
          <div
            style={{
              display: 'flex',
              justifyContent: 'space-between',
              borderBottom: '1px dashed var(--vz-border-color)',
              paddingBottom: '0.2rem',
            }}
          >
            <span>Total Participant Revenue:</span>
            <span style={{ fontWeight: 600, color: '#059669' }}>₹{hostRevenueFromParticipants.toFixed(0)}</span>
          </div>
          <div
            style={{
              display: 'flex',
              justifyContent: 'space-between',
              background: 'rgba(5, 150, 105, 0.08)',
              padding: '0.5rem',
              borderRadius: 6,
              fontWeight: 700,
              marginTop: '0.25rem',
            }}
          >
            <span style={{ color: '#059669' }}>Host Payable Settlement:</span>
            <span style={{ color: '#059669' }}>₹{platformSettlementToHost.toFixed(0)}</span>
          </div>
          <div
            style={{
              display: 'flex',
              justifyContent: 'space-between',
              background: netHostProfit >= 0 ? 'rgba(16, 185, 129, 0.08)' : 'rgba(239, 68, 68, 0.08)',
              padding: '0.5rem',
              borderRadius: 6,
              fontWeight: 700,
            }}
          >
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
        <div
          style={{
            marginTop: '1rem',
            padding: '0.75rem',
            background: 'var(--vz-light)',
            borderRadius: 8,
            fontSize: '0.82rem',
            color: 'var(--vz-text-muted)',
            textAlign: 'center',
          }}
        >
          No settlement payout details provided yet by the host.
        </div>
      );
    }

    const maskAccount = (acc: string) => {
      if (acc.length <= 4) return acc;
      return '••••••••' + acc.slice(-4);
    };

    return (
      <div style={{ marginTop: '1.25rem' }}>
        <h4
          style={{
            margin: '0 0 0.75rem',
            fontSize: '0.9rem',
            fontWeight: 700,
            borderBottom: '1px solid var(--vz-border-color)',
            paddingBottom: '0.4rem',
            color: '#f59e0b',
          }}
        >
          🏦 Host Settlement Payout Details
        </h4>
        <div
          style={{
            display: 'flex',
            flexDirection: 'column',
            gap: '0.5rem',
            background: 'rgba(245, 158, 11, 0.05)',
            border: '1.5px dashed rgba(245, 158, 11, 0.25)',
            borderRadius: 10,
            padding: '1rem',
            fontSize: '0.85rem',
          }}
        >
          {req.upiId && (
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <span>
                <b>UPI ID:</b> {req.upiId}
              </span>
              <button
                onClick={() => handleCopy(req.upiId!, 'upi')}
                style={{
                  padding: '0.25rem 0.6rem',
                  fontSize: '0.75rem',
                  background: '#f59e0b',
                  color: '#fff',
                  border: 'none',
                  borderRadius: 4,
                  cursor: 'pointer',
                }}
              >
                {copiedField === 'upi' ? '✓ Copied' : '📋 Copy UPI'}
              </button>
            </div>
          )}
          {req.accountNumber && (
            <>
              <div
                style={{
                  display: 'flex',
                  justifyContent: 'space-between',
                  alignItems: 'center',
                  borderBottom: '1px solid rgba(245,158,11,0.1)',
                  paddingBottom: '0.25rem',
                }}
              >
                <span>
                  <b>Account Holder:</b> {req.accountHolderName || '—'}
                </span>
              </div>
              <div
                style={{
                  display: 'flex',
                  justifyContent: 'space-between',
                  alignItems: 'center',
                  borderBottom: '1px solid rgba(245,158,11,0.1)',
                  paddingBottom: '0.25rem',
                }}
              >
                <span>
                  <b>Bank Name:</b> {req.bankName || '—'}
                </span>
              </div>
              <div
                style={{
                  display: 'flex',
                  justifyContent: 'space-between',
                  alignItems: 'center',
                  borderBottom: '1px solid rgba(245,158,11,0.1)',
                  paddingBottom: '0.25rem',
                }}
              >
                <span>
                  <b>Account No:</b> {maskAccount(req.accountNumber)}
                </span>
                <button
                  onClick={() => handleCopy(req.accountNumber!, 'acct')}
                  style={{
                    padding: '0.25rem 0.6rem',
                    fontSize: '0.75rem',
                    background: '#f59e0b',
                    color: '#fff',
                    border: 'none',
                    borderRadius: 4,
                    cursor: 'pointer',
                  }}
                >
                  {copiedField === 'acct' ? '✓ Copied' : '📋 Copy Full'}
                </button>
              </div>
              <div
                style={{
                  display: 'flex',
                  justifyContent: 'space-between',
                  alignItems: 'center',
                  paddingBottom: '0.25rem',
                }}
              >
                <span>
                  <b>IFSC Code:</b> {req.ifscCode}
                </span>
                <button
                  onClick={() => handleCopy(req.ifscCode!, 'ifsc')}
                  style={{
                    padding: '0.2rem 0.6rem',
                    fontSize: '0.75rem',
                    background: '#f59e0b',
                    color: '#fff',
                    border: 'none',
                    borderRadius: 4,
                    cursor: 'pointer',
                  }}
                >
                  {copiedField === 'ifsc' ? '✓ Copied' : '📋 Copy'}
                </button>
              </div>
            </>
          )}
          {req.bankDetails && (
            <div
              style={{
                display: 'flex',
                justifyContent: 'space-between',
                alignItems: 'flex-start',
                marginTop: req.upiId || req.accountNumber ? '0.5rem' : '0',
              }}
            >
              <span style={{ whiteSpace: 'pre-wrap' }}>
                <b>Details:</b>
                <br />
                {req.bankDetails}
              </span>
              <button
                onClick={() => handleCopy(req.bankDetails!, 'legacy')}
                style={{
                  padding: '0.2rem 0.6rem',
                  fontSize: '0.75rem',
                  background: '#f59e0b',
                  color: '#fff',
                  border: 'none',
                  borderRadius: 4,
                  cursor: 'pointer',
                  flexShrink: 0,
                }}
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

  const fetchCancellations = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const statusParam = cancellationFilter === 'all' ? '' : `?status=${cancellationFilter}`;
      const res = await fetch(`${BASE_URL}/api/admin/strangers-meet/cancellations${statusParam}`, { headers });
      const data = await res.json();
      if (data.success) {
        setCancellations(data.data || []);
        if (data.counts) {
          setCancellationCounts(data.counts);
        }
      } else {
        setError(data.message || 'Failed to load cancellations');
      }
    } catch (e) {
      setError('Network error loading cancellations.');
    } finally {
      setLoading(false);
    }
  }, [cancellationFilter, accessToken]);

  const fetchRequests = useCallback(async () => {
    if (activeTab === 'cancellations') {
      fetchCancellations();
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const statusParam = activeTab === 'all' ? '' : `?status=${activeTab}`;
      const [reqRes, cancelRes] = await Promise.all([
        fetch(`${BASE_URL}/api/admin/strangers-meet${statusParam}`, { headers }),
        fetch(`${BASE_URL}/api/admin/strangers-meet/cancellations?limit=1`, { headers }).catch(() => null),
      ]);
      const data = await reqRes.json();
      if (data.success) {
        setRequests(data.data);
        setCounts(data.counts || {});
      } else {
        setError(data.message || 'Failed to load requests');
      }
      if (cancelRes) {
        const cancelData = await cancelRes.json();
        if (cancelData.success && cancelData.counts) {
          setCancellationCounts(cancelData.counts);
        }
      }
    } catch (e) {
      setError('Network error. Please try again.');
    } finally {
      setLoading(false);
    }
  }, [activeTab, accessToken, fetchCancellations]);

  useEffect(() => {
    if (activeTab === 'cancellations') {
      fetchCancellations();
    } else {
      fetchRequests();
    }
  }, [activeTab, fetchRequests, fetchCancellations]);

  // Auto-refresh every 20s
  useEffect(() => {
    const id = setInterval(() => {
      if (activeTab === 'cancellations') {
        fetchCancellations();
      } else {
        fetchRequests();
      }
    }, 20_000);
    return () => clearInterval(id);
  }, [activeTab, fetchRequests, fetchCancellations]);

  // Cancellation Modals & Actions (Sections 15, 27, 28)
  const openCancellationDetail = async (item: HostCancellationItem) => {
    setSelectedCancellation(item);
    setLoadingDetail(true);
    setIsRejectingCancellation(false);
    setCancellationRejectionReason('');
    setHostRefundDecision('FULL');
    setHostRefundPercentage(100);
    const depositAmt = Number(item.hostDepositAmount || (item.meet as any)?.paymentAmount || 0);
    setHostRefundCustomAmount(depositAmt.toString());
    setHostRefundDestination('WALLET');

    try {
      const res = await fetch(`${BASE_URL}/api/admin/strangers-meet/cancellations/${item.id}`, { headers });
      const data = await res.json();
      if (data.success) {
        setCancellationDetail(data.data);
      }
    } catch (e) {
      console.error('Failed to load detail', e);
    } finally {
      setLoadingDetail(false);
    }
  };

  const handleApproveCancellation = async () => {
    if (!selectedCancellation) return;
    setSubmitting(true);
    try {
      const depositAmt = Number(selectedCancellation.hostDepositAmount || (selectedCancellation.meet as any)?.paymentAmount || 0);
      let calculatedAmt = 0;
      if (hostRefundDecision === 'FULL') {
        calculatedAmt = depositAmt;
      } else if (hostRefundDecision === 'PARTIAL') {
        calculatedAmt = Math.round((depositAmt * (hostRefundPercentage / 100)) * 100) / 100;
      } else if (hostRefundDecision === 'CUSTOM') {
        calculatedAmt = Math.min(depositAmt, Math.max(0, parseFloat(hostRefundCustomAmount) || 0));
      } else {
        calculatedAmt = 0;
      }

      const res = await fetch(`${BASE_URL}/api/admin/strangers-meet/cancellations/${selectedCancellation.id}/approve`, {
        method: 'POST',
        headers,
        body: JSON.stringify({
          refundPercentage: 100, // 100% wallet refund to participants per Section 7-10
          refundMethod: 'WALLET',
          adminNotes: adminNote.trim() || undefined,
          hostRefundDecision,
          hostRefundPercentage: hostRefundDecision === 'PARTIAL' ? hostRefundPercentage : undefined,
          hostRefundCustomAmount: hostRefundDecision === 'CUSTOM' ? calculatedAmt : undefined,
          hostRefundDestination: calculatedAmt > 0 ? hostRefundDestination : 'NONE',
        }),
      });
      const data = await res.json();
      if (data.success) {
        setSuccessMsg('Host cancellation approved. Participant refunds issued and host refund processed.');
        setSelectedCancellation(null);
        setCancellationDetail(null);
        fetchCancellations();
        fetchRequests();
      } else {
        alert(data.message || 'Failed to approve cancellation');
      }
    } catch (e: any) {
      alert(e.message || 'Network error');
    } finally {
      setSubmitting(false);
    }
  };

  const handleRejectCancellation = async () => {
    if (!selectedCancellation) return;
    if (!cancellationRejectionReason.trim()) {
      alert('Please provide a reason for rejecting the cancellation.');
      return;
    }
    setSubmitting(true);
    try {
      const res = await fetch(`${BASE_URL}/api/admin/strangers-meet/cancellations/${selectedCancellation.id}/reject`, {
        method: 'POST',
        headers,
        body: JSON.stringify({
          reason: cancellationRejectionReason.trim(),
        }),
      });
      const data = await res.json();
      if (data.success) {
        setSuccessMsg('Host cancellation rejected. The meet remains active.');
        setSelectedCancellation(null);
        setCancellationDetail(null);
        fetchCancellations();
        fetchRequests();
      } else {
        alert(data.message || 'Failed to reject cancellation');
      }
    } catch (e: any) {
      alert(e.message || 'Network error');
    } finally {
      setSubmitting(false);
    }
  };

  const openHostSettlementModal = (item: HostCancellationItem) => {
    setSettleCancellation(item);
    setHostSettleRef('');
    setHostSettleMethod('UPI');
    setHostSettleNotes('');
  };

  const handleSettleHostRefund = async () => {
    if (!settleCancellation) return;
    if (!hostSettleRef.trim()) {
      alert('Payment Reference / Transaction ID is required');
      return;
    }
    setSubmitting(true);
    try {
      const res = await fetch(`${BASE_URL}/api/admin/strangers-meet/cancellations/${settleCancellation.id}/settle-host-refund`, {
        method: 'POST',
        headers,
        body: JSON.stringify({
          paymentReference: hostSettleRef.trim(),
          paymentMethod: hostSettleMethod,
          notes: hostSettleNotes.trim() || undefined,
        }),
      });
      const data = await res.json();
      if (data.success) {
        setSuccessMsg('Host refund marked as PAID successfully! Host notified.');
        setSettleCancellation(null);
        setHostSettleRef('');
        fetchCancellations();
      } else {
        alert(data.message || 'Failed to settle host refund');
      }
    } catch (e: any) {
      alert(e.message || 'Network error');
    } finally {
      setSubmitting(false);
    }
  };

  const openModal = (
    req: SMRequest,
    action: 'approve' | 'reject' | 'view' | 'settlement' | 'confirmEnded' | 'resolveEscalation'
  ) => {
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
    const platformChargePerSeat = req.platformChargePerSeat
      ? Number(req.platformChargePerSeat)
      : platformDepositTotal > 0 && totalSeats > 0
      ? platformDepositTotal / totalSeats
      : 0;
    const hostChargePerHead = Number(req.chargesPerHead || 0);
    const hostRevenueFromParticipants = paidSlots * hostChargePerHead;
    const platformSettlementToHost = unfilledSeats * platformChargePerSeat + hostRevenueFromParticipants;

    setSettlementAmt(
      req.settlementAmount
        ? req.settlementAmount.toString()
        : platformSettlementToHost > 0
        ? platformSettlementToHost.toFixed(0)
        : ''
    );
    setSettlementMethod(req.settlementMethod || 'UPI');
    setResolutionType('MARK_COMPLETED');
    setResolutionNotes('');
    setSuccessMsg(null);
  };

  const closeModal = () => {
    setSelected(null);
    setModalAction(null);
  };

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

  const handleAdminConfirmEnded = async (req: SMRequest) => {
    if (
      !window.confirm(
        `Confirm that Strangers Meet "${req.subject}" has ended? This will start the 24-hour host settlement window.`
      )
    ) {
      return;
    }
    setSubmitting(true);
    try {
      const res = await fetch(`${BASE_URL}/api/admin/strangers-meet/${req.id}/confirm-ended`, {
        method: 'PATCH',
        headers,
      });
      const data = await res.json();
      if (data.success) {
        alert('Strangers Meet verified as ended! Host notified that settlement will be processed within 24 hours.');
        fetchRequests();
      } else {
        alert(data.message || 'Failed to confirm meetup ended');
      }
    } catch (err: any) {
      alert(err.message || 'Network error');
    } finally {
      setSubmitting(false);
    }
  };

  const handleMarkSettled = async () => {
    if (!selected) return;
    if (!settlementTxnId.trim()) {
      alert('Payment Reference / Transaction ID is required');
      return;
    }
    const amt = parseFloat(settlementAmt);
    if (!settlementAmt || isNaN(amt) || amt <= 0) {
      alert('Enter a valid settlement amount');
      return;
    }
    setSubmitting(true);
    try {
      const res = await fetch(`${BASE_URL}/api/admin/strangers-meet/${selected.id}/mark-settled`, {
        method: 'POST',
        headers,
        body: JSON.stringify({
          paymentReference: settlementTxnId.trim(),
          amount: amt,
          settlementMethod: settlementMethod.trim(),
        }),
      });
      const data = await res.json();
      if (data.success) {
        setSuccessMsg(`Settlement of ₹${amt.toFixed(0)} marked as Settled! Host has received final breakdown notification.`);
        fetchRequests();
        setTimeout(closeModal, 2000);
      } else {
        alert(data.message || 'Failed to mark settlement');
      }
    } finally {
      setSubmitting(false);
    }
  };

  const handleResolveEscalation = async () => {
    if (!selected) return;
    setSubmitting(true);
    try {
      const res = await fetch(`${BASE_URL}/api/admin/strangers-meet/${selected.id}/resolve-escalation`, {
        method: 'POST',
        headers,
        body: JSON.stringify({
          resolution: resolutionType,
          resolutionNotes: resolutionNotes.trim() || undefined,
        }),
      });
      const data = await res.json();
      if (data.success) {
        setSuccessMsg(`Escalation resolved: ${resolutionType.replace(/_/g, ' ')}`);
        fetchRequests();
        setTimeout(closeModal, 1800);
      } else {
        alert(data.message || 'Failed to resolve escalation');
      }
    } catch (err: any) {
      alert(err.message || 'Network error');
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

  const fmt = (dt?: string | null) => {
    if (!dt) return '—';
    return new Date(dt).toLocaleString('en-IN', {
      day: '2-digit',
      month: 'short',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  };

  // ─────────────────────────────────────────────────────────────────────────────
  // RENDER: Cancellations & Refunds View (Sections 15, 27, 28)
  // ─────────────────────────────────────────────────────────────────────────────
  const renderCancellationsView = () => {
    const filterChips: { key: typeof cancellationFilter; label: string; count: number }[] = [
      { key: 'all', label: 'All', count: cancellationCounts.all },
      { key: 'pending', label: 'Pending Admin Review', count: cancellationCounts.pending },
      { key: 'settlement_pending', label: 'Settlement Pending', count: cancellationCounts.settlement_pending },
      { key: 'completed', label: 'Completed', count: cancellationCounts.completed },
      { key: 'rejected', label: 'Rejected', count: cancellationCounts.rejected },
    ];

    return (
      <div style={{ display: 'flex', flexDirection: 'column', gap: '1.25rem' }}>
        {/* Filter Chips Bar (Section 27) */}
        <div style={{ display: 'flex', gap: '0.6rem', flexWrap: 'wrap', alignItems: 'center' }}>
          {filterChips.map((chip) => {
            const isSelected = cancellationFilter === chip.key;
            return (
              <button
                key={chip.key}
                onClick={() => setCancellationFilter(chip.key)}
                style={{
                  padding: '0.4rem 0.85rem',
                  borderRadius: 20,
                  border: isSelected ? '1.5px solid #7c3aed' : '1px solid var(--vz-border-color)',
                  background: isSelected ? 'rgba(124, 58, 237, 0.12)' : 'var(--vz-card-bg)',
                  color: isSelected ? '#7c3aed' : 'var(--vz-text-primary)',
                  fontWeight: isSelected ? 700 : 500,
                  fontSize: '0.8rem',
                  cursor: 'pointer',
                  display: 'flex',
                  alignItems: 'center',
                  gap: '0.4rem',
                  transition: 'all 0.15s',
                }}
              >
                <span>{chip.label}</span>
                <span
                  style={{
                    background: isSelected ? '#7c3aed' : 'var(--vz-light)',
                    color: isSelected ? '#fff' : 'var(--vz-text-muted)',
                    borderRadius: 12,
                    padding: '0.05rem 0.45rem',
                    fontSize: '0.7rem',
                    fontWeight: 700,
                  }}
                >
                  {chip.count}
                </span>
              </button>
            );
          })}
        </div>

        {/* List of Cancellation Cards */}
        {cancellations.length === 0 ? (
          <div style={{ textAlign: 'center', padding: '4rem', color: 'var(--vz-text-muted)', background: 'var(--vz-card-bg)', borderRadius: 12, border: '1px solid var(--vz-border-color)' }}>
            <div style={{ fontSize: '2.5rem', marginBottom: '0.5rem' }}>📭</div>
            <div style={{ fontWeight: 600, fontSize: '0.95rem' }}>No cancellation requests in this filter</div>
          </div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
            {cancellations.map((item) => {
              const depositAmt = Number(item.hostDepositAmount || (item.meet as any)?.paymentAmount || 0);
              const isPending = item.status === 'PENDING_ADMIN_REVIEW';
              const isSettlementPending = item.hostRefundStatus === 'HOST_REFUND_PENDING_SETTLEMENT';
              const isPaid = item.hostRefundStatus === 'PAID';
              const isWalletCredited = item.hostRefundStatus === 'WALLET_CREDITED';

              return (
                <div
                  key={item.id}
                  style={{
                    background: 'var(--vz-card-bg)',
                    border: isPending
                      ? '1.5px solid #f59e0b'
                      : isSettlementPending
                      ? '1.5px solid #3b82f6'
                      : '1px solid var(--vz-border-color)',
                    borderRadius: 12,
                    padding: '1.25rem',
                    display: 'flex',
                    flexDirection: 'column',
                    gap: '1rem',
                  }}
                >
                  {/* Card Header */}
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', flexWrap: 'wrap', gap: '0.5rem' }}>
                    <div>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '0.6rem', marginBottom: '0.25rem' }}>
                        <h4 style={{ margin: 0, fontSize: '1.1rem', fontWeight: 700, color: 'var(--vz-text-primary)' }}>
                          {item.meet?.subject || 'Strangers Meet'}
                        </h4>
                        {/* Status badge */}
                        <span
                          style={{
                            padding: '0.2rem 0.6rem',
                            borderRadius: 6,
                            fontSize: '0.75rem',
                            fontWeight: 700,
                            background:
                              item.status === 'PENDING_ADMIN_REVIEW'
                                ? 'rgba(245, 158, 11, 0.15)'
                                : item.status === 'COMPLETED'
                                ? 'rgba(16, 185, 129, 0.15)'
                                : item.status === 'REJECTED'
                                ? 'rgba(239, 68, 68, 0.15)'
                                : 'rgba(59, 130, 246, 0.15)',
                            color:
                              item.status === 'PENDING_ADMIN_REVIEW'
                                ? '#d97706'
                                : item.status === 'COMPLETED'
                                ? '#059669'
                                : item.status === 'REJECTED'
                                ? '#dc2626'
                                : '#2563eb',
                            border: `1px solid ${
                              item.status === 'PENDING_ADMIN_REVIEW'
                                ? 'rgba(245, 158, 11, 0.3)'
                                : item.status === 'COMPLETED'
                                ? 'rgba(16, 185, 129, 0.3)'
                                : item.status === 'REJECTED'
                                ? 'rgba(239, 68, 68, 0.3)'
                                : 'rgba(59, 130, 246, 0.3)'
                            }`,
                          }}
                        >
                          {item.status.replace(/_/g, ' ')}
                        </span>

                        {/* Host refund status badge */}
                        {isSettlementPending && (
                          <span
                            style={{
                              padding: '0.2rem 0.6rem',
                              borderRadius: 6,
                              fontSize: '0.75rem',
                              fontWeight: 700,
                              background: 'rgba(245, 158, 11, 0.2)',
                              color: '#b45309',
                              border: '1px solid rgba(245, 158, 11, 0.4)',
                            }}
                          >
                            ⏳ Host Refund Pending Settlement (₹{Number(item.hostRefundAmount || 0).toFixed(0)})
                          </span>
                        )}
                        {isPaid && (
                          <span
                            style={{
                              padding: '0.2rem 0.6rem',
                              borderRadius: 6,
                              fontSize: '0.75rem',
                              fontWeight: 700,
                              background: 'rgba(16, 185, 129, 0.2)',
                              color: '#047857',
                              border: '1px solid rgba(16, 185, 129, 0.4)',
                            }}
                          >
                            ✓ Host Refund Settled (₹{Number(item.hostRefundAmount || 0).toFixed(0)}) • Ref: {item.hostSettlementTransactionId}
                          </span>
                        )}
                        {isWalletCredited && (
                          <span
                            style={{
                              padding: '0.2rem 0.6rem',
                              borderRadius: 6,
                              fontSize: '0.75rem',
                              fontWeight: 700,
                              background: 'rgba(16, 185, 129, 0.15)',
                              color: '#059669',
                              border: '1px solid rgba(16, 185, 129, 0.3)',
                            }}
                          >
                            ✓ Host Refund: Wallet Credited (₹{Number(item.hostRefundAmount || 0).toFixed(0)})
                          </span>
                        )}
                      </div>
                      <div style={{ color: 'var(--vz-text-muted)', fontSize: '0.825rem' }}>
                        📍 {item.meet?.venue?.name || 'Venue'} • 📅 {fmt(item.meet?.eventDateTime)} • Requested on: {fmt(item.createdAt)}
                      </div>
                    </div>

                    {/* Action buttons on card */}
                    <div style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap' }}>
                      {isPending && (
                        <button
                          onClick={() => openCancellationDetail(item)}
                          style={{
                            padding: '0.5rem 1rem',
                            borderRadius: 8,
                            border: 'none',
                            background: '#7c3aed',
                            color: '#fff',
                            fontSize: '0.8rem',
                            fontWeight: 700,
                            cursor: 'pointer',
                          }}
                        >
                          📋 Review & Decide Refunds
                        </button>
                      )}
                      {isSettlementPending && (
                        <button
                          onClick={() => openHostSettlementModal(item)}
                          style={{
                            padding: '0.5rem 1rem',
                            borderRadius: 8,
                            border: 'none',
                            background: '#059669',
                            color: '#fff',
                            fontSize: '0.8rem',
                            fontWeight: 700,
                            cursor: 'pointer',
                          }}
                        >
                          💸 Mark Host Refund as Paid
                        </button>
                      )}
                      <button
                        onClick={() => openCancellationDetail(item)}
                        style={{
                          padding: '0.5rem 0.85rem',
                          borderRadius: 8,
                          border: '1px solid var(--vz-border-color)',
                          background: 'transparent',
                          color: 'var(--vz-text-primary)',
                          fontSize: '0.8rem',
                          cursor: 'pointer',
                        }}
                      >
                        👁 View Details
                      </button>
                    </div>
                  </div>

                  {/* Host & Meet Metrics Grid */}
                  <div
                    style={{
                      display: 'grid',
                      gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))',
                      gap: '0.75rem',
                      background: 'rgba(0,0,0,0.03)',
                      borderRadius: 8,
                      padding: '0.85rem',
                    }}
                  >
                    <div>
                      <span style={{ fontSize: '0.75rem', color: 'var(--vz-text-muted)', display: 'block' }}>Host Details</span>
                      <strong style={{ fontSize: '0.875rem' }}>
                        {item.host?.firstName} {item.host?.lastName}
                      </strong>
                      <div style={{ fontSize: '0.75rem', color: 'var(--vz-text-muted)' }}>
                        📞 {item.host?.phone || '—'}
                      </div>
                    </div>
                    <div>
                      <span style={{ fontSize: '0.75rem', color: 'var(--vz-text-muted)', display: 'block' }}>Participants</span>
                      <strong style={{ fontSize: '0.875rem', color: '#7c3aed' }}>
                        {item.totalMembersCount} Paid / Confirmed
                      </strong>
                    </div>
                    <div>
                      <span style={{ fontSize: '0.75rem', color: 'var(--vz-text-muted)', display: 'block' }}>Total Participant Payments</span>
                      <strong style={{ fontSize: '0.875rem', color: '#059669' }}>
                        ₹{Number(item.totalCollectedAmount || 0).toFixed(0)}
                      </strong>
                    </div>
                    <div>
                      <span style={{ fontSize: '0.75rem', color: 'var(--vz-text-muted)', display: 'block' }}>Host Confirmation Deposit</span>
                      <strong style={{ fontSize: '0.875rem', color: '#d97706' }}>
                        ₹{depositAmt.toFixed(0)}
                      </strong>
                    </div>
                  </div>

                  {/* Reason section */}
                  <div
                    style={{
                      background: 'rgba(239, 68, 68, 0.05)',
                      borderLeft: '3px solid #ef4444',
                      padding: '0.6rem 0.85rem',
                      borderRadius: '0 6px 6px 0',
                    }}
                  >
                    <div style={{ fontSize: '0.8rem', fontWeight: 600, color: '#dc2626' }}>
                      Cancellation Reason: {item.reasonCategory}
                    </div>
                    {item.reasonText && (
                      <div style={{ fontSize: '0.775rem', color: 'var(--vz-text-primary)', marginTop: '0.2rem' }}>
                        "{item.reasonText}"
                      </div>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    );
  };

  // ─────────────────────────────────────────────────────────────────────────────
  // RENDER: Host Cancellation Review & Approval Modal (Section 28)
  // ─────────────────────────────────────────────────────────────────────────────
  const renderCancellationReviewModal = () => {
    if (!selectedCancellation) return null;
    const item = selectedCancellation;
    const depositAmt = Number(item.hostDepositAmount || (item.meet as any)?.paymentAmount || 0);

    let calculatedHostRefund = 0;
    if (hostRefundDecision === 'FULL') {
      calculatedHostRefund = depositAmt;
    } else if (hostRefundDecision === 'PARTIAL') {
      calculatedHostRefund = Math.round((depositAmt * (hostRefundPercentage / 100)) * 100) / 100;
    } else if (hostRefundDecision === 'CUSTOM') {
      calculatedHostRefund = Math.min(depositAmt, Math.max(0, parseFloat(hostRefundCustomAmount) || 0));
    } else {
      calculatedHostRefund = 0;
    }

    const hostPayout = cancellationDetail?.hostPayoutDetails || item.hostPayoutDetails || {};
    const paidJoiners = cancellationDetail?.paidJoiners || [];

    return (
      <div
        style={{
          position: 'fixed',
          inset: 0,
          background: 'rgba(0,0,0,0.6)',
          zIndex: 1060,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          padding: '1rem',
          overflowY: 'auto',
        }}
      >
        <div
          style={{
            background: 'var(--vz-card-bg)',
            border: '1px solid var(--vz-border-color)',
            borderRadius: 14,
            padding: '1.75rem',
            width: '100%',
            maxWidth: 720,
            maxHeight: '90vh',
            overflowY: 'auto',
            display: 'flex',
            flexDirection: 'column',
            gap: '1.25rem',
            boxShadow: '0 20px 25px -5px rgba(0, 0, 0, 0.3)',
          }}
        >
          {/* Header */}
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderBottom: '1px solid var(--vz-border-color)', paddingBottom: '0.75rem' }}>
            <div>
              <h3 style={{ margin: 0, fontSize: '1.25rem', fontWeight: 700 }}>
                Review Host Cancellation Request
              </h3>
              <p style={{ margin: '0.2rem 0 0', color: 'var(--vz-text-muted)', fontSize: '0.8rem' }}>
                Stranger Meet: {item.meet?.subject || 'Meet'} • Venue: {item.meet?.venue?.name || 'Venue'}
              </p>
            </div>
            <button
              onClick={() => {
                setSelectedCancellation(null);
                setCancellationDetail(null);
              }}
              style={{
                background: 'none',
                border: 'none',
                fontSize: '1.25rem',
                cursor: 'pointer',
                color: 'var(--vz-text-muted)',
              }}
            >
              ✕
            </button>
          </div>

          {/* Cancellation Info & Reason Box */}
          <div style={{ background: 'rgba(239, 68, 68, 0.06)', borderRadius: 10, padding: '1rem', border: '1px solid rgba(239, 68, 68, 0.2)' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '0.4rem' }}>
              <span style={{ fontWeight: 700, color: '#dc2626', fontSize: '0.875rem' }}>
                Reason: {item.reasonCategory}
              </span>
              <span style={{ fontSize: '0.75rem', color: 'var(--vz-text-muted)' }}>
                Requested {fmt(item.createdAt)}
              </span>
            </div>
            {item.reasonText && (
              <p style={{ margin: 0, fontSize: '0.85rem', color: 'var(--vz-text-primary)' }}>
                "{item.reasonText}"
              </p>
            )}
          </div>

          {/* Metrics summary */}
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))', gap: '0.75rem' }}>
            <div style={{ background: 'var(--vz-light)', padding: '0.75rem', borderRadius: 8 }}>
              <span style={{ fontSize: '0.72rem', color: 'var(--vz-text-muted)', display: 'block' }}>Paid Joiners</span>
              <strong style={{ fontSize: '1.1rem', color: '#7c3aed' }}>{item.totalMembersCount}</strong>
            </div>
            <div style={{ background: 'var(--vz-light)', padding: '0.75rem', borderRadius: 8 }}>
              <span style={{ fontSize: '0.72rem', color: 'var(--vz-text-muted)', display: 'block' }}>Total Collected</span>
              <strong style={{ fontSize: '1.1rem', color: '#059669' }}>₹{Number(item.totalCollectedAmount || 0).toFixed(0)}</strong>
            </div>
            <div style={{ background: 'var(--vz-light)', padding: '0.75rem', borderRadius: 8 }}>
              <span style={{ fontSize: '0.72rem', color: 'var(--vz-text-muted)', display: 'block' }}>Host Confirmation Deposit</span>
              <strong style={{ fontSize: '1.1rem', color: '#d97706' }}>₹{depositAmt.toFixed(0)}</strong>
            </div>
          </div>

          {/* Section 1: Participant Refund Policy (Sections 7-10, 28) */}
          <div style={{ border: '1px solid var(--vz-border-color)', borderRadius: 10, padding: '1rem' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '0.5rem' }}>
              <span style={{ fontSize: '1.1rem' }}>👥</span>
              <h4 style={{ margin: 0, fontSize: '0.95rem', fontWeight: 700 }}>
                Participant Refund Policy: 100% Lunara Wallet Refund
              </h4>
            </div>
            <p style={{ margin: '0 0 0.75rem', fontSize: '0.8rem', color: 'var(--vz-text-muted)' }}>
              Per platform rules, every confirmed participant automatically receives a 100% refund directly to their Lunara Wallet.
            </p>
            {loadingDetail ? (
              <div style={{ fontSize: '0.8rem', color: 'var(--vz-text-muted)' }}>Loading participant list…</div>
            ) : paidJoiners.length > 0 ? (
              <div style={{ maxHeight: 150, overflowY: 'auto', border: '1px solid var(--vz-border-color)', borderRadius: 6 }}>
                <table style={{ width: '100%', fontSize: '0.775rem', borderCollapse: 'collapse' }}>
                  <thead>
                    <tr style={{ background: 'var(--vz-light)', textAlign: 'left' }}>
                      <th style={{ padding: '0.4rem 0.6rem' }}>Participant</th>
                      <th style={{ padding: '0.4rem 0.6rem' }}>Paid Amount</th>
                      <th style={{ padding: '0.4rem 0.6rem' }}>Refund (100%)</th>
                      <th style={{ padding: '0.4rem 0.6rem' }}>Destination</th>
                    </tr>
                  </thead>
                  <tbody>
                    {paidJoiners.map((j: any) => (
                      <tr key={j.joinerId} style={{ borderTop: '1px solid var(--vz-border-color)' }}>
                        <td style={{ padding: '0.4rem 0.6rem' }}>{j.name}</td>
                        <td style={{ padding: '0.4rem 0.6rem' }}>₹{j.paidAmount}</td>
                        <td style={{ padding: '0.4rem 0.6rem', color: '#059669', fontWeight: 700 }}>₹{j.refundAmount}</td>
                        <td style={{ padding: '0.4rem 0.6rem', color: '#7c3aed' }}>Lunara Wallet</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            ) : (
              <div style={{ fontSize: '0.8rem', color: 'var(--vz-text-muted)' }}>
                {item.totalMembersCount} participants will receive wallet refunds.
              </div>
            )}
          </div>

          {/* Section 2: Host Confirmation Deposit Decision (Sections 13, 14, 28) */}
          <div style={{ border: '1.5px solid #f59e0b', borderRadius: 10, padding: '1rem', background: 'rgba(245, 158, 11, 0.03)' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '0.5rem' }}>
              <span style={{ fontSize: '1.1rem' }}>👑</span>
              <h4 style={{ margin: 0, fontSize: '0.95rem', fontWeight: 700, color: '#d97706' }}>
                Host Confirmation Deposit Decision (Deposit: ₹{depositAmt.toFixed(0)})
              </h4>
            </div>
            <p style={{ margin: '0 0 0.75rem', fontSize: '0.8rem', color: 'var(--vz-text-muted)' }}>
              The host paid a confirmation deposit of ₹{depositAmt.toFixed(0)}. Decide how much to refund:
            </p>

            {/* Radio Options */}
            <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem', marginBottom: '1rem' }}>
              <label style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', fontSize: '0.85rem', cursor: 'pointer' }}>
                <input
                  type="radio"
                  name="hostRefundDecision"
                  checked={hostRefundDecision === 'FULL'}
                  onChange={() => setHostRefundDecision('FULL')}
                />
                <span><strong>Full Refund (100%)</strong> — ₹{depositAmt.toFixed(0)}</span>
              </label>

              <label style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', fontSize: '0.85rem', cursor: 'pointer' }}>
                <input
                  type="radio"
                  name="hostRefundDecision"
                  checked={hostRefundDecision === 'PARTIAL'}
                  onChange={() => setHostRefundDecision('PARTIAL')}
                />
                <span><strong>Partial Refund (%)</strong></span>
                {hostRefundDecision === 'PARTIAL' && (
                  <div style={{ display: 'inline-flex', alignItems: 'center', gap: '0.3rem', marginLeft: '0.5rem' }}>
                    <input
                      type="number"
                      min="1"
                      max="99"
                      value={hostRefundPercentage}
                      onChange={(e) => setHostRefundPercentage(Math.max(1, Math.min(99, Number(e.target.value) || 0)))}
                      style={{ width: 60, padding: '0.2rem 0.4rem', borderRadius: 4, border: '1px solid var(--vz-border-color)', fontSize: '0.85rem' }}
                    />
                    <span>% = <strong>₹{calculatedHostRefund.toFixed(0)}</strong></span>
                  </div>
                )}
              </label>

              <label style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', fontSize: '0.85rem', cursor: 'pointer' }}>
                <input
                  type="radio"
                  name="hostRefundDecision"
                  checked={hostRefundDecision === 'CUSTOM'}
                  onChange={() => setHostRefundDecision('CUSTOM')}
                />
                <span><strong>Custom Amount</strong></span>
                {hostRefundDecision === 'CUSTOM' && (
                  <div style={{ display: 'inline-flex', alignItems: 'center', gap: '0.3rem', marginLeft: '0.5rem' }}>
                    <span>₹</span>
                    <input
                      type="number"
                      min="0"
                      max={depositAmt}
                      value={hostRefundCustomAmount}
                      onChange={(e) => setHostRefundCustomAmount(e.target.value)}
                      style={{ width: 90, padding: '0.2rem 0.4rem', borderRadius: 4, border: '1px solid var(--vz-border-color)', fontSize: '0.85rem' }}
                    />
                  </div>
                )}
              </label>

              <label style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', fontSize: '0.85rem', cursor: 'pointer' }}>
                <input
                  type="radio"
                  name="hostRefundDecision"
                  checked={hostRefundDecision === 'NO_REFUND'}
                  onChange={() => setHostRefundDecision('NO_REFUND')}
                />
                <span><strong>No Refund</strong> — ₹0 (Deposit forfeited)</span>
              </label>
            </div>

            {/* Destination Selection (if host refund > 0) */}
            {calculatedHostRefund > 0 && (
              <div style={{ borderTop: '1px dashed var(--vz-border-color)', paddingTop: '0.75rem', marginTop: '0.75rem' }}>
                <label style={{ display: 'block', marginBottom: '0.4rem', fontWeight: 600, fontSize: '0.825rem' }}>
                  Host Refund Destination:
                </label>
                <div style={{ display: 'flex', gap: '1rem', flexWrap: 'wrap' }}>
                  <label style={{ display: 'flex', alignItems: 'center', gap: '0.4rem', fontSize: '0.85rem', cursor: 'pointer' }}>
                    <input
                      type="radio"
                      name="hostRefundDest"
                      checked={hostRefundDestination === 'WALLET'}
                      onChange={() => setHostRefundDestination('WALLET')}
                    />
                    <span>💼 Lunara Wallet (Instant credit)</span>
                  </label>
                  <label style={{ display: 'flex', alignItems: 'center', gap: '0.4rem', fontSize: '0.85rem', cursor: 'pointer' }}>
                    <input
                      type="radio"
                      name="hostRefundDest"
                      checked={hostRefundDestination === 'UPI'}
                      onChange={() => setHostRefundDestination('UPI')}
                    />
                    <span>⚡ Host UPI {hostPayout.upiId ? `(${hostPayout.upiId})` : ''}</span>
                  </label>
                  <label style={{ display: 'flex', alignItems: 'center', gap: '0.4rem', fontSize: '0.85rem', cursor: 'pointer' }}>
                    <input
                      type="radio"
                      name="hostRefundDest"
                      checked={hostRefundDestination === 'BANK'}
                      onChange={() => setHostRefundDestination('BANK')}
                    />
                    <span>🏦 Bank Account {hostPayout.accountNumber ? `(•••${String(hostPayout.accountNumber).slice(-4)})` : ''}</span>
                  </label>
                </div>
                {hostRefundDestination !== 'WALLET' && (
                  <div style={{ marginTop: '0.5rem', fontSize: '0.75rem', color: '#b45309', background: 'rgba(245, 158, 11, 0.1)', padding: '0.4rem 0.6rem', borderRadius: 4 }}>
                    ⚠️ External settlement will be marked as "Pending Settlement". You will be able to mark it as PAID after initiating external transfer.
                  </div>
                )}
              </div>
            )}
          </div>

          {/* Admin Note Input */}
          <div>
            <label style={{ display: 'block', marginBottom: '0.3rem', fontSize: '0.825rem', fontWeight: 600 }}>
              Admin Note (Optional):
            </label>
            <input
              type="text"
              placeholder="e.g. Approved per medical certificate provided by host"
              value={adminNote}
              onChange={(e) => setAdminNote(e.target.value)}
              style={{ width: '100%', padding: '0.5rem 0.75rem', borderRadius: 6, border: '1px solid var(--vz-border-color)', fontSize: '0.85rem', boxSizing: 'border-box' }}
            />
          </div>

          {/* Rejection Section if toggled */}
          {isRejectingCancellation && (
            <div style={{ background: 'rgba(239, 68, 68, 0.08)', borderRadius: 8, padding: '0.85rem', border: '1px solid #ef4444' }}>
              <label style={{ display: 'block', marginBottom: '0.3rem', fontSize: '0.825rem', fontWeight: 700, color: '#dc2626' }}>
                Reason for Rejection *
              </label>
              <textarea
                placeholder="Explain to host why cancellation was rejected…"
                value={cancellationRejectionReason}
                onChange={(e) => setCancellationRejectionReason(e.target.value)}
                rows={2}
                style={{ width: '100%', padding: '0.5rem', borderRadius: 6, border: '1px solid #ef4444', fontSize: '0.85rem', boxSizing: 'border-box', marginBottom: '0.5rem' }}
              />
              <button
                onClick={handleRejectCancellation}
                disabled={submitting || !cancellationRejectionReason.trim()}
                style={{
                  padding: '0.45rem 1rem',
                  borderRadius: 6,
                  border: 'none',
                  background: '#dc2626',
                  color: '#fff',
                  fontWeight: 700,
                  fontSize: '0.8rem',
                  cursor: 'pointer',
                  opacity: submitting || !cancellationRejectionReason.trim() ? 0.6 : 1,
                }}
              >
                {submitting ? 'Rejecting…' : 'Confirm Rejection'}
              </button>
            </div>
          )}

          {/* Action Buttons */}
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderTop: '1px solid var(--vz-border-color)', paddingTop: '1rem' }}>
            <div>
              {!isRejectingCancellation ? (
                <button
                  onClick={() => setIsRejectingCancellation(true)}
                  disabled={submitting}
                  style={{
                    padding: '0.55rem 1rem',
                    borderRadius: 8,
                    border: '1px solid #dc2626',
                    background: 'transparent',
                    color: '#dc2626',
                    fontWeight: 600,
                    fontSize: '0.85rem',
                    cursor: 'pointer',
                  }}
                >
                  Reject Request
                </button>
              ) : (
                <button
                  onClick={() => setIsRejectingCancellation(false)}
                  style={{
                    padding: '0.55rem 1rem',
                    borderRadius: 8,
                    border: '1px solid var(--vz-border-color)',
                    background: 'transparent',
                    color: 'var(--vz-text-muted)',
                    fontSize: '0.85rem',
                    cursor: 'pointer',
                  }}
                >
                  Cancel Rejection
                </button>
              )}
            </div>

            <div style={{ display: 'flex', gap: '0.75rem' }}>
              <button
                onClick={() => {
                  setSelectedCancellation(null);
                  setCancellationDetail(null);
                }}
                disabled={submitting}
                style={{
                  padding: '0.55rem 1.25rem',
                  borderRadius: 8,
                  border: '1px solid var(--vz-border-color)',
                  background: 'transparent',
                  color: 'var(--vz-text-primary)',
                  fontSize: '0.85rem',
                  cursor: 'pointer',
                }}
              >
                Close
              </button>
              <button
                onClick={handleApproveCancellation}
                disabled={submitting}
                style={{
                  padding: '0.55rem 1.5rem',
                  borderRadius: 8,
                  border: 'none',
                  background: '#7c3aed',
                  color: '#fff',
                  fontWeight: 700,
                  fontSize: '0.85rem',
                  cursor: 'pointer',
                  opacity: submitting ? 0.7 : 1,
                }}
              >
                {submitting ? 'Processing…' : '✓ Approve & Process Refunds'}
              </button>
            </div>
          </div>
        </div>
      </div>
    );
  };

  // ─────────────────────────────────────────────────────────────────────────────
  // RENDER: Host Settlement Modal (Section 15)
  // ─────────────────────────────────────────────────────────────────────────────
  const renderHostSettlementModal = () => {
    if (!settleCancellation) return null;
    const item = settleCancellation;
    const hostPayout = item.hostPayoutDetails || item.host || {};

    return (
      <div
        style={{
          position: 'fixed',
          inset: 0,
          background: 'rgba(0,0,0,0.6)',
          zIndex: 1070,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          padding: '1rem',
        }}
      >
        <div
          style={{
            background: 'var(--vz-card-bg)',
            border: '1px solid var(--vz-border-color)',
            borderRadius: 14,
            padding: '1.75rem',
            width: '100%',
            maxWidth: 520,
            display: 'flex',
            flexDirection: 'column',
            gap: '1.25rem',
            boxShadow: '0 20px 25px -5px rgba(0, 0, 0, 0.3)',
          }}
        >
          {/* Header */}
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderBottom: '1px solid var(--vz-border-color)', paddingBottom: '0.75rem' }}>
            <div>
              <h3 style={{ margin: 0, fontSize: '1.2rem', fontWeight: 700 }}>
                Mark Host Refund as Settled
              </h3>
              <p style={{ margin: '0.2rem 0 0', color: 'var(--vz-text-muted)', fontSize: '0.8rem' }}>
                Stranger Meet: {item.meet?.subject}
              </p>
            </div>
            <button
              onClick={() => setSettleCancellation(null)}
              style={{ background: 'none', border: 'none', fontSize: '1.25rem', cursor: 'pointer', color: 'var(--vz-text-muted)' }}
            >
              ✕
            </button>
          </div>

          {/* Refund Amount & Host Payout Box */}
          <div style={{ background: 'rgba(16, 185, 129, 0.08)', borderRadius: 10, padding: '1rem', border: '1px solid rgba(16, 185, 129, 0.2)' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '0.5rem' }}>
              <span style={{ fontSize: '0.85rem', color: 'var(--vz-text-muted)' }}>Refund Amount to Pay:</span>
              <strong style={{ fontSize: '1.35rem', color: '#059669' }}>
                ₹{Number(item.hostRefundAmount || 0).toFixed(0)}
              </strong>
            </div>
            <div style={{ fontSize: '0.8rem', color: 'var(--vz-text-primary)' }}>
              <strong>Host:</strong> {item.host?.firstName} {item.host?.lastName} (📞 {item.host?.phone || '—'})
            </div>
            {hostPayout.upiId && (
              <div style={{ fontSize: '0.8rem', color: 'var(--vz-text-primary)', marginTop: '0.2rem' }}>
                <strong>UPI ID:</strong> {hostPayout.upiId}
              </div>
            )}
            {hostPayout.accountNumber && (
              <div style={{ fontSize: '0.8rem', color: 'var(--vz-text-primary)', marginTop: '0.2rem' }}>
                <strong>Bank Account:</strong> {hostPayout.accountNumber} ({hostPayout.bankName || 'Bank'}, IFSC: {hostPayout.ifscCode || '—'})
              </div>
            )}
          </div>

          {/* Inputs */}
          <div>
            <label style={{ display: 'block', marginBottom: '0.35rem', fontWeight: 600, fontSize: '0.85rem' }}>
              Payment Reference / Transaction ID *
            </label>
            <input
              type="text"
              placeholder="e.g. UPI-REF-99238491823 or IMPS-49382103"
              value={hostSettleRef}
              onChange={(e) => setHostSettleRef(e.target.value)}
              style={{ width: '100%', padding: '0.6rem 0.85rem', borderRadius: 8, border: '1.5px solid var(--vz-border-color)', fontSize: '0.9rem', boxSizing: 'border-box' }}
              autoFocus
            />
          </div>

          <div>
            <label style={{ display: 'block', marginBottom: '0.35rem', fontWeight: 600, fontSize: '0.85rem' }}>
              Payment Method
            </label>
            <select
              value={hostSettleMethod}
              onChange={(e) => setHostSettleMethod(e.target.value)}
              style={{ width: '100%', padding: '0.6rem 0.85rem', borderRadius: 8, border: '1.5px solid var(--vz-border-color)', fontSize: '0.9rem', boxSizing: 'border-box' }}
            >
              <option value="UPI">UPI</option>
              <option value="IMPS">IMPS (Immediate Payment)</option>
              <option value="NEFT">NEFT</option>
              <option value="RTGS">RTGS</option>
            </select>
          </div>

          <div>
            <label style={{ display: 'block', marginBottom: '0.35rem', fontWeight: 600, fontSize: '0.85rem' }}>
              Settlement Notes (Optional)
            </label>
            <input
              type="text"
              placeholder="e.g. Transferred via HDFC net banking"
              value={hostSettleNotes}
              onChange={(e) => setHostSettleNotes(e.target.value)}
              style={{ width: '100%', padding: '0.6rem 0.85rem', borderRadius: 8, border: '1.5px solid var(--vz-border-color)', fontSize: '0.85rem', boxSizing: 'border-box' }}
            />
          </div>

          {/* Action Buttons */}
          <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '0.75rem', borderTop: '1px solid var(--vz-border-color)', paddingTop: '1rem' }}>
            <button
              onClick={() => setSettleCancellation(null)}
              disabled={submitting}
              style={{ padding: '0.55rem 1.25rem', borderRadius: 8, border: '1px solid var(--vz-border-color)', background: 'transparent', cursor: 'pointer' }}
            >
              Cancel
            </button>
            <button
              onClick={handleSettleHostRefund}
              disabled={submitting || !hostSettleRef.trim()}
              style={{
                padding: '0.55rem 1.5rem',
                borderRadius: 8,
                border: 'none',
                background: '#059669',
                color: '#fff',
                fontWeight: 700,
                cursor: 'pointer',
                opacity: submitting || !hostSettleRef.trim() ? 0.6 : 1,
              }}
            >
              {submitting ? 'Confirming…' : 'Confirm Settlement'}
            </button>
          </div>
        </div>
      </div>
    );
  };

  const tabs = [
    { key: 'pending', label: 'Pending Approvals', count: counts.pending },
    { key: 'approved', label: 'Approved (Upcoming)', count: counts.approved },
    { key: 'in_progress', label: '🟢 In Progress / Live', count: counts.inProgress || 0 },
    { key: 'needs_contact', label: '⚠️ Needs Host Contact', count: counts.needsContact || 0 },
    { key: 'completed', label: '🏁 Completed Reviews', count: counts.completed || 0 },
    { key: 'payouts', label: '💳 Payouts & Settlements', count: counts.payouts || 0 },
    { key: 'cancellations', label: '❌ Cancellations & Refunds', count: cancellationCounts.pending || 0 },
    { key: 'rejected', label: 'Rejected', count: counts.rejected },
    {
      key: 'all',
      label: 'All',
      count:
        counts.pending +
        counts.approved +
        counts.rejected +
        (counts.inProgress || 0) +
        (counts.needsContact || 0) +
        (counts.completed || 0) +
        (counts.payouts || 0),
    },
  ] as const;

  return (
    <div style={{ padding: '1.5rem' }}>
      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '1.5rem' }}>
        <div>
          <h2 style={{ margin: 0, fontSize: '1.35rem', fontWeight: 700 }}>Strangers Meet Lifecycle & Settlements</h2>
          <p style={{ margin: '0.25rem 0 0', color: 'var(--vz-text-muted)', fontSize: '0.85rem' }}>
            Review requests, track live meetups, handle timeout escalations, and confirm host payouts
          </p>
        </div>
        <button
          onClick={activeTab === 'cancellations' ? fetchCancellations : fetchRequests}
          style={{
            padding: '0.5rem 1rem',
            borderRadius: 8,
            border: '1px solid var(--vz-border-color)',
            background: 'transparent',
            cursor: 'pointer',
            color: 'var(--vz-text-primary)',
            fontSize: '0.8rem',
          }}
        >
          ↻ Refresh
        </button>
      </div>

      {/* Tabs */}
      <div
        style={{
          display: 'flex',
          gap: '0.5rem',
          marginBottom: '1.25rem',
          borderBottom: '2px solid var(--vz-border-color)',
          paddingBottom: '0',
          overflowX: 'auto',
        }}
      >
        {tabs.map((t) => (
          <button
            key={t.key}
            onClick={() => setActiveTab(t.key as any)}
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
              whiteSpace: 'nowrap',
              transition: 'all 0.15s',
            }}
          >
            {t.label}
            {t.count > 0 && (
              <span
                style={{
                  background:
                    t.key === 'needs_contact'
                      ? '#ef4444'
                      : t.key === 'cancellations'
                      ? '#dc2626'
                      : activeTab === t.key
                      ? '#7c3aed'
                      : 'var(--vz-light)',
                  color: '#fff',
                  borderRadius: 20,
                  padding: '0.1rem 0.5rem',
                  fontSize: '0.72rem',
                  fontWeight: 700,
                }}
              >
                {t.count}
              </span>
            )}
          </button>
        ))}
      </div>

      {/* Content */}
      {loading ? (
        <div style={{ textAlign: 'center', padding: '3rem', color: 'var(--vz-text-muted)' }}>Loading…</div>
      ) : error ? (
        <div style={{ textAlign: 'center', padding: '3rem', color: '#dc2626' }}>{error}</div>
      ) : activeTab === 'cancellations' ? (
        renderCancellationsView()
      ) : requests.length === 0 ? (
        <div style={{ textAlign: 'center', padding: '4rem', color: 'var(--vz-text-muted)' }}>
          <div style={{ fontSize: '3rem', marginBottom: '1rem' }}>👥</div>
          <div style={{ fontWeight: 600 }}>No {activeTab.replace(/_/g, ' ')} requests</div>
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
          {requests.map((req) => {
            const sc = STATUS_COLORS[req.status] || STATUS_COLORS.pending;
            const isHostEnded = req.status === 'host_confirmed_ended';
            const isAdminVerified =
              req.status === 'admin_confirmed_ended' || req.settlementStatus === 'settlement_pending';
            const isSettled =
              req.status === 'completed' ||
              req.status === 'settled' ||
              req.settlementStatus === 'settled' ||
              req.settlementStatus === 'paid';
            const isEscalated = req.status === 'needs_host_contact';
            const isOverdue = req.settlementOverdue;

            return (
              <div
                key={req.id}
                style={{
                  background: 'var(--vz-card-bg)',
                  border: isEscalated
                    ? '2px solid #ef4444'
                    : isOverdue
                    ? '2px solid #f59e0b'
                    : '1px solid var(--vz-border-color)',
                  borderRadius: 14,
                  padding: '1.25rem',
                  display: 'flex',
                  gap: '1rem',
                  flexWrap: 'wrap',
                  alignItems: 'flex-start',
                }}
              >
                {/* Venue Image */}
                {req.venue?.imageUrl && (
                  <img
                    src={`${BASE_URL}${req.venue.imageUrl}`}
                    alt={req.venue.name}
                    style={{ width: 80, height: 70, borderRadius: 10, objectFit: 'cover', flexShrink: 0 }}
                    onError={(e) => {
                      (e.target as HTMLImageElement).style.display = 'none';
                    }}
                  />
                )}

                {/* Main Info */}
                <div style={{ flex: 1, minWidth: 200 }}>
                  <div
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      gap: '0.75rem',
                      flexWrap: 'wrap',
                      marginBottom: '0.4rem',
                    }}
                  >
                    <span style={{ fontWeight: 700, fontSize: '1rem' }}>{req.subject}</span>
                    <span
                      style={{
                        padding: '0.15rem 0.65rem',
                        borderRadius: 20,
                        fontSize: '0.72rem',
                        fontWeight: 700,
                        background: sc.bg,
                        color: sc.text,
                        border: `1px solid ${sc.border}`,
                      }}
                    >
                      {req.status.replace(/_/g, ' ').toUpperCase()}
                    </span>
                    {req.paymentStatus === 'paid' && (
                      <span
                        style={{
                          padding: '0.15rem 0.65rem',
                          borderRadius: 20,
                          fontSize: '0.72rem',
                          fontWeight: 700,
                          background: 'rgba(16,185,129,0.12)',
                          color: '#059669',
                          border: '1px solid rgba(16,185,129,0.3)',
                        }}
                      >
                        HOST DEPOSIT PAID ✓
                      </span>
                    )}
                    {isEscalated && (
                      <span
                        style={{
                          padding: '0.15rem 0.65rem',
                          borderRadius: 20,
                          fontSize: '0.72rem',
                          fontWeight: 800,
                          background: '#fee2e2',
                          color: '#dc2626',
                          border: '1px solid #f87171',
                        }}
                      >
                        ⚠️ ACTION REQUIRED: HOST TIMEOUT (24H)
                      </span>
                    )}
                    {isOverdue && !isSettled && (
                      <span
                        style={{
                          padding: '0.15rem 0.65rem',
                          borderRadius: 20,
                          fontSize: '0.72rem',
                          fontWeight: 800,
                          background: '#fef3c7',
                          color: '#b45309',
                          border: '1px solid #fcd34d',
                        }}
                      >
                        ⏱️ SETTLEMENT OVERDUE (&gt;24H)
                      </span>
                    )}
                  </div>
                  <p style={{ margin: '0 0 0.6rem', color: 'var(--vz-text-muted)', fontSize: '0.83rem' }}>
                    {req.tagline}
                  </p>

                  <div
                    style={{
                      display: 'flex',
                      gap: '1.2rem',
                      flexWrap: 'wrap',
                      fontSize: '0.8rem',
                      color: 'var(--vz-text-muted)',
                    }}
                  >
                    <span>
                      🏛️ <b>{req.venue?.name ?? '—'}</b>, {req.venue?.city}
                    </span>
                    <span>📅 Scheduled: {fmt(req.eventDateTime)}</span>
                    {req.startedAt && <span>🟢 Started: {fmt(req.startedAt)}</span>}
                    {req.durationHours && <span>⏱️ Duration: {req.durationHours}h</span>}
                    {req.expectedEndAt && <span>⏳ Expected End: {fmt(req.expectedEndAt)}</span>}
                    {req.endedAt && <span>🏁 Ended: {fmt(req.endedAt)}</span>}
                    <span>👥 {req.numberOfPersons} seats</span>
                    <span>📞 {req.mobileNumber}</span>
                    {req.user && (
                      <span>
                        👤 Host: {req.user.firstName} {req.user.lastName}
                      </span>
                    )}
                  </div>

                  <div
                    style={{
                      display: 'flex',
                      gap: '1.2rem',
                      flexWrap: 'wrap',
                      fontSize: '0.8rem',
                      color: 'var(--vz-text-muted)',
                      marginTop: '0.4rem',
                    }}
                  >
                    <span style={{ color: '#7c3aed', fontWeight: 600 }}>
                      👥 Joined: {req.joinedCount || 0} / {req.numberOfPersons} ({req.paymentCount || 0} Paid)
                    </span>
                    <span style={{ color: '#059669', fontWeight: 600 }}>
                      💰 Est. Settlement: ₹
                      {(
                        (req.numberOfPersons - (req.paymentCount || 0)) * (req.platformChargePerSeat || 0) +
                        (req.paymentCount || 0) * (req.chargesPerHead || 0)
                      ).toFixed(0)}
                    </span>
                    {req.settlementTransactionId && (
                      <span style={{ color: '#2563eb', fontWeight: 600 }}>
                        🧾 Txn ID: {req.settlementTransactionId} ({req.settlementMethod || 'UPI'})
                      </span>
                    )}
                  </div>

                  {isEscalated && req.escalationReason && (
                    <div
                      style={{
                        marginTop: '0.5rem',
                        padding: '0.5rem 0.75rem',
                        background: 'rgba(239, 68, 68, 0.08)',
                        border: '1px solid rgba(239, 68, 68, 0.2)',
                        borderRadius: 6,
                        fontSize: '0.8rem',
                        color: '#dc2626',
                      }}
                    >
                      ⚠️ <b>Escalation Reason:</b> {req.escalationReason} (Escalated: {fmt(req.escalatedAt)})
                    </div>
                  )}

                  {req.adminNotes && (
                    <div
                      style={{
                        marginTop: '0.5rem',
                        padding: '0.4rem 0.75rem',
                        background: 'var(--vz-light)',
                        borderRadius: 6,
                        fontSize: '0.78rem',
                        color: 'var(--vz-text-muted)',
                      }}
                    >
                      📝 {req.adminNotes}
                    </div>
                  )}
                  {req.ticketId && (
                    <div
                      style={{ marginTop: '0.4rem', fontSize: '0.75rem', color: '#7c3aed', fontFamily: 'monospace' }}
                    >
                      🎟️ Ticket: {req.ticketId}
                    </div>
                  )}
                </div>

                {/* Actions */}
                <div
                  style={{
                    display: 'flex',
                    flexDirection: 'column',
                    gap: '0.5rem',
                    flexShrink: 0,
                    minWidth: 170,
                  }}
                >
                  <button
                    onClick={() => openModal(req, 'view')}
                    style={{
                      padding: '0.45rem 1rem',
                      borderRadius: 8,
                      border: '1px solid var(--vz-border-color)',
                      background: 'transparent',
                      cursor: 'pointer',
                      fontSize: '0.8rem',
                      color: 'var(--vz-text-primary)',
                    }}
                  >
                    View Financials
                  </button>

                  {req.status === 'pending' && (
                    <>
                      <button
                        onClick={() => openModal(req, 'approve')}
                        style={{
                          padding: '0.45rem 1rem',
                          borderRadius: 8,
                          border: 'none',
                          background: '#7c3aed',
                          color: '#fff',
                          cursor: 'pointer',
                          fontSize: '0.8rem',
                          fontWeight: 600,
                        }}
                      >
                        ✓ Approve
                      </button>
                      <button
                        onClick={() => openModal(req, 'reject')}
                        style={{
                          padding: '0.45rem 1rem',
                          borderRadius: 8,
                          border: '1px solid #dc2626',
                          background: 'transparent',
                          color: '#dc2626',
                          cursor: 'pointer',
                          fontSize: '0.8rem',
                        }}
                      >
                        ✕ Reject
                      </button>
                    </>
                  )}

                  {isEscalated && (
                    <>
                      <a
                        href={`tel:${req.mobileNumber}`}
                        style={{
                          padding: '0.45rem 1rem',
                          borderRadius: 8,
                          border: '1px solid #ef4444',
                          background: 'rgba(239,68,68,0.1)',
                          color: '#dc2626',
                          textDecoration: 'none',
                          textAlign: 'center',
                          fontSize: '0.8rem',
                          fontWeight: 700,
                        }}
                      >
                        📞 Call Host ({req.mobileNumber})
                      </a>
                      <button
                        onClick={() => openModal(req, 'resolveEscalation')}
                        style={{
                          padding: '0.5rem 1rem',
                          borderRadius: 8,
                          border: 'none',
                          background: '#dc2626',
                          color: '#fff',
                          cursor: 'pointer',
                          fontSize: '0.8rem',
                          fontWeight: 700,
                        }}
                      >
                        ⚖️ Resolve Escalation
                      </button>
                    </>
                  )}

                  {isHostEnded && (
                    <button
                      onClick={() => handleAdminConfirmEnded(req)}
                      disabled={submitting}
                      style={{
                        padding: '0.55rem 1rem',
                        borderRadius: 8,
                        border: 'none',
                        background: '#b45309',
                        color: '#fff',
                        cursor: 'pointer',
                        fontSize: '0.8rem',
                        fontWeight: 700,
                      }}
                    >
                      ✓ Confirm Meet Ended
                    </button>
                  )}

                  {isAdminVerified && !isSettled && (
                    <button
                      onClick={() => openModal(req, 'settlement')}
                      style={{
                        padding: '0.55rem 1rem',
                        borderRadius: 8,
                        border: 'none',
                        background: '#059669',
                        color: '#fff',
                        cursor: 'pointer',
                        fontSize: '0.8rem',
                        fontWeight: 700,
                      }}
                    >
                      💸 Mark Amount as Settled
                    </button>
                  )}

                  {isSettled && (
                    <span
                      style={{
                        padding: '0.35rem 0.75rem',
                        borderRadius: 8,
                        background: 'rgba(16,185,129,0.12)',
                        color: '#059669',
                        fontSize: '0.75rem',
                        fontWeight: 700,
                        textAlign: 'center',
                        border: '1px solid rgba(16,185,129,0.3)',
                      }}
                    >
                      ✓ Settled (₹{Number(req.settlementAmount || 0).toFixed(0)})
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
        <div
          style={{
            position: 'fixed',
            inset: 0,
            background: 'rgba(0,0,0,0.5)',
            zIndex: 9999,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            padding: '1rem',
          }}
          onClick={closeModal}
        >
          <div
            style={{
              background: 'var(--vz-card-bg)',
              borderRadius: 16,
              padding: '2rem',
              width: '100%',
              maxWidth: 540,
              maxHeight: '90vh',
              overflowY: 'auto',
              boxShadow: '0 20px 60px rgba(0,0,0,0.3)',
            }}
            onClick={(e) => e.stopPropagation()}
          >
            {successMsg ? (
              <div style={{ textAlign: 'center', padding: '2rem 0' }}>
                <div style={{ fontSize: '2.5rem', marginBottom: '0.75rem' }}>
                  {modalAction === 'approve' ? '✅' : modalAction === 'settlement' ? '💸' : '⚖️'}
                </div>
                <div style={{ fontWeight: 700, fontSize: '1rem' }}>{successMsg}</div>
              </div>
            ) : (
              <>
                <h3 style={{ margin: '0 0 1.25rem', fontSize: '1.1rem' }}>
                  {modalAction === 'approve'
                    ? '✓ Approve Request'
                    : modalAction === 'reject'
                    ? '✕ Reject Request'
                    : modalAction === 'settlement'
                    ? '💸 Mark Amount as Settled'
                    : modalAction === 'resolveEscalation'
                    ? '⚖️ Resolve 24-Hour Timeout Escalation'
                    : '📋 Request & Settlement Details'}
                </h3>

                {/* Summary */}
                <div
                  style={{
                    background: 'var(--vz-light)',
                    borderRadius: 10,
                    padding: '1rem',
                    marginBottom: '1.25rem',
                    fontSize: '0.85rem',
                  }}
                >
                  <div style={{ fontWeight: 700, marginBottom: '0.5rem' }}>{selected.subject}</div>
                  <div style={{ color: 'var(--vz-text-muted)', marginBottom: '0.5rem' }}>{selected.tagline}</div>
                  <div
                    style={{
                      display: 'grid',
                      gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))',
                      gap: '0.4rem',
                      color: 'var(--vz-text-muted)',
                    }}
                  >
                    <span>🏛️ {selected.venue?.name}</span>
                    <span>🌆 {selected.venue?.city}</span>
                    <span>📅 Scheduled: {fmt(selected.eventDateTime)}</span>
                    {selected.startedAt && <span>🟢 Started: {fmt(selected.startedAt)}</span>}
                    {selected.expectedEndAt && <span>⏳ Expected End: {fmt(selected.expectedEndAt)}</span>}
                    {selected.endedAt && <span>🏁 Ended: {fmt(selected.endedAt)}</span>}
                    <span>👥 {selected.numberOfPersons} seats</span>
                    <span>📞 {selected.mobileNumber}</span>
                    <span>
                      👤 {selected.user?.firstName} {selected.user?.lastName}
                    </span>
                    <span>📧 {selected.user?.email}</span>
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
                      <label style={{ display: 'block', marginBottom: '0.4rem', fontWeight: 600, fontSize: '0.875rem' }}>
                        Deposit Amount (₹) *
                      </label>
                      <input
                        type="number"
                        min="1"
                        placeholder="e.g. 2500"
                        value={payAmount}
                        onChange={(e) => handlePayAmountChange(e.target.value)}
                        style={{
                          width: '100%',
                          padding: '0.6rem 0.85rem',
                          borderRadius: 8,
                          border: '1.5px solid var(--vz-border-color)',
                          background: 'var(--vz-card-bg)',
                          color: 'var(--vz-text-primary)',
                          fontSize: '1rem',
                          boxSizing: 'border-box',
                        }}
                        autoFocus
                      />
                    </div>
                    <div style={{ marginBottom: '1rem' }}>
                      <label style={{ display: 'block', marginBottom: '0.4rem', fontWeight: 600, fontSize: '0.875rem' }}>
                        Charges Per Head (₹) *
                      </label>
                      <input
                        type="number"
                        min="0"
                        placeholder="e.g. 350"
                        value={chargesPerHead}
                        onChange={(e) => handleChargesPerHeadChange(e.target.value)}
                        style={{
                          width: '100%',
                          padding: '0.6rem 0.85rem',
                          borderRadius: 8,
                          border: '1.5px solid var(--vz-border-color)',
                          background: 'var(--vz-card-bg)',
                          color: 'var(--vz-text-primary)',
                          fontSize: '1rem',
                          boxSizing: 'border-box',
                        }}
                      />
                    </div>
                  </>
                )}

                {modalAction === 'settlement' && selected && (
                  <>
                    {renderCalculations(selected)}
                    {renderBankDetails(selected)}
                    <div style={{ height: '1.25rem' }}></div>
                    <div style={{ marginBottom: '0.85rem' }}>
                      <label style={{ display: 'block', marginBottom: '0.4rem', fontWeight: 600, fontSize: '0.875rem' }}>
                        Payment Reference / Transaction ID *
                      </label>
                      <input
                        type="text"
                        placeholder="e.g. UPI-REF-99238491823 or BANK-TXN-1234"
                        value={settlementTxnId}
                        onChange={(e) => setSettlementTxnId(e.target.value)}
                        style={{
                          width: '100%',
                          padding: '0.6rem 0.85rem',
                          borderRadius: 8,
                          border: '1.5px solid var(--vz-border-color)',
                          background: 'var(--vz-card-bg)',
                          color: 'var(--vz-text-primary)',
                          fontSize: '0.9rem',
                          boxSizing: 'border-box',
                        }}
                        autoFocus
                      />
                    </div>
                    <div style={{ marginBottom: '0.85rem' }}>
                      <label style={{ display: 'block', marginBottom: '0.4rem', fontWeight: 600, fontSize: '0.875rem' }}>
                        Settlement Amount (₹) *
                      </label>
                      <input
                        type="number"
                        min="1"
                        placeholder="e.g. 5000"
                        value={settlementAmt}
                        onChange={(e) => setSettlementAmt(e.target.value)}
                        style={{
                          width: '100%',
                          padding: '0.6rem 0.85rem',
                          borderRadius: 8,
                          border: '1.5px solid var(--vz-border-color)',
                          background: 'var(--vz-card-bg)',
                          color: 'var(--vz-text-primary)',
                          fontSize: '0.9rem',
                          boxSizing: 'border-box',
                        }}
                      />
                    </div>
                    <div style={{ marginBottom: '1.25rem' }}>
                      <label style={{ display: 'block', marginBottom: '0.4rem', fontWeight: 600, fontSize: '0.875rem' }}>
                        Payment Method
                      </label>
                      <select
                        value={settlementMethod}
                        onChange={(e) => setSettlementMethod(e.target.value)}
                        style={{
                          width: '100%',
                          padding: '0.6rem 0.85rem',
                          borderRadius: 8,
                          border: '1.5px solid var(--vz-border-color)',
                          background: 'var(--vz-card-bg)',
                          color: 'var(--vz-text-primary)',
                          fontSize: '0.9rem',
                          boxSizing: 'border-box',
                        }}
                      >
                        <option value="UPI">UPI</option>
                        <option value="Bank Transfer">Bank Transfer</option>
                        <option value="IMPS">IMPS</option>
                        <option value="NEFT">NEFT</option>
                        <option value="RTGS">RTGS</option>
                      </select>
                    </div>
                  </>
                )}

                {modalAction === 'resolveEscalation' && selected && (
                  <>
                    <div style={{ marginBottom: '1rem' }}>
                      <label style={{ display: 'block', marginBottom: '0.4rem', fontWeight: 600, fontSize: '0.875rem' }}>
                        Resolution Decision *
                      </label>
                      <select
                        value={resolutionType}
                        onChange={(e) => setResolutionType(e.target.value)}
                        style={{
                          width: '100%',
                          padding: '0.6rem 0.85rem',
                          borderRadius: 8,
                          border: '1.5px solid var(--vz-border-color)',
                          background: 'var(--vz-card-bg)',
                          color: 'var(--vz-text-primary)',
                          fontSize: '0.9rem',
                          boxSizing: 'border-box',
                        }}
                      >
                        <option value="MARK_COMPLETED">Mark as Completed (Proceed to Settlement)</option>
                        <option value="MARK_NOT_STARTED">Mark as Not Started (Close Meetup)</option>
                        <option value="CANCELLED">Cancel Meetup</option>
                      </select>
                    </div>
                    <div style={{ marginBottom: '1.25rem' }}>
                      <label style={{ display: 'block', marginBottom: '0.4rem', fontWeight: 600, fontSize: '0.875rem' }}>
                        Investigation / Host Contact Notes
                      </label>
                      <textarea
                        placeholder="Details of conversation with host or investigation outcome…"
                        value={resolutionNotes}
                        onChange={(e) => setResolutionNotes(e.target.value)}
                        rows={3}
                        style={{
                          width: '100%',
                          padding: '0.6rem 0.85rem',
                          borderRadius: 8,
                          border: '1.5px solid var(--vz-border-color)',
                          background: 'var(--vz-card-bg)',
                          color: 'var(--vz-text-primary)',
                          fontSize: '0.875rem',
                          resize: 'vertical',
                          boxSizing: 'border-box',
                        }}
                      />
                    </div>
                  </>
                )}

                {(modalAction === 'approve' || modalAction === 'reject') && (
                  <div style={{ marginBottom: '1.25rem' }}>
                    <label style={{ display: 'block', marginBottom: '0.4rem', fontWeight: 600, fontSize: '0.875rem' }}>
                      Admin Note (optional)
                    </label>
                    <textarea
                      placeholder={modalAction === 'approve' ? 'Any instructions for the host…' : 'Reason for rejection…'}
                      value={adminNote}
                      onChange={(e) => setAdminNote(e.target.value)}
                      rows={3}
                      style={{
                        width: '100%',
                        padding: '0.6rem 0.85rem',
                        borderRadius: 8,
                        border: '1.5px solid var(--vz-border-color)',
                        background: 'var(--vz-card-bg)',
                        color: 'var(--vz-text-primary)',
                        fontSize: '0.875rem',
                        resize: 'vertical',
                        boxSizing: 'border-box',
                      }}
                    />
                  </div>
                )}

                <div style={{ display: 'flex', gap: '0.75rem', justifyContent: 'flex-end' }}>
                  <button
                    onClick={closeModal}
                    disabled={submitting}
                    style={{
                      padding: '0.6rem 1.25rem',
                      borderRadius: 8,
                      border: '1px solid var(--vz-border-color)',
                      background: 'transparent',
                      cursor: 'pointer',
                      color: 'var(--vz-text-primary)',
                    }}
                  >
                    Cancel
                  </button>
                  {modalAction === 'approve' && (
                    <button
                      onClick={handleApprove}
                      disabled={submitting || !payAmount || !chargesPerHead}
                      style={{
                        padding: '0.6rem 1.5rem',
                        borderRadius: 8,
                        border: 'none',
                        background: '#7c3aed',
                        color: '#fff',
                        cursor: 'pointer',
                        fontWeight: 600,
                        opacity: submitting ? 0.7 : 1,
                      }}
                    >
                      {submitting ? 'Approving…' : 'Approve & Set Payment'}
                    </button>
                  )}
                  {modalAction === 'reject' && (
                    <button
                      onClick={handleReject}
                      disabled={submitting}
                      style={{
                        padding: '0.6rem 1.5rem',
                        borderRadius: 8,
                        border: 'none',
                        background: '#dc2626',
                        color: '#fff',
                        cursor: 'pointer',
                        fontWeight: 600,
                        opacity: submitting ? 0.7 : 1,
                      }}
                    >
                      {submitting ? 'Rejecting…' : 'Confirm Reject'}
                    </button>
                  )}
                  {modalAction === 'resolveEscalation' && (
                    <button
                      onClick={handleResolveEscalation}
                      disabled={submitting}
                      style={{
                        padding: '0.6rem 1.5rem',
                        borderRadius: 8,
                        border: 'none',
                        background: '#dc2626',
                        color: '#fff',
                        cursor: 'pointer',
                        fontWeight: 700,
                        opacity: submitting ? 0.7 : 1,
                      }}
                    >
                      {submitting ? 'Saving…' : 'Confirm Resolution'}
                    </button>
                  )}
                  {modalAction === 'settlement' && (
                    <button
                      onClick={handleMarkSettled}
                      disabled={submitting || !settlementTxnId || !settlementAmt}
                      style={{
                        padding: '0.6rem 1.5rem',
                        borderRadius: 8,
                        border: 'none',
                        background: '#059669',
                        color: '#fff',
                        cursor: 'pointer',
                        fontWeight: 700,
                        opacity: submitting ? 0.7 : 1,
                      }}
                    >
                      {submitting ? 'Processing…' : '💸 Mark Amount as Settled'}
                    </button>
                  )}
                </div>
              </>
            )}
          </div>
        </div>
      )}

      {/* Host Cancellation Review & Approval Modal (Section 28) */}
      {selectedCancellation && renderCancellationReviewModal()}

      {/* Host Manual Settlement Modal (Section 15) */}
      {settleCancellation && renderHostSettlementModal()}
    </div>
  );
};

export default StrangersMeet;
