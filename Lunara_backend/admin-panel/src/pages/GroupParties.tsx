import React, { useState, useEffect, useCallback } from 'react';
import apiClient from '../api/client';

interface GroupParty {
  id: string;
  userId: string;
  venueId: string;
  numberOfFriends: number;
  tableBookingCharge: number;
  discountAmount: number;
  totalAmount: number;
  status: 'pending' | 'confirmed' | 'cancelled';
  paymentStatus: 'pending' | 'paid' | 'failed';
  paymentId?: string;
  partyDate: string;
  mobileNumber: string;
  optionalMobileNumber?: string;
  createdAt: string;
  creator: {
    id: string;
    firstName: string;
    lastName: string;
    email: string;
    phone: string;
  } | null;
  venue: {
    id: string;
    name: string;
    city: string;
  } | null;
  foodPreference?: string;
  drinkPreference?: string;
}

const STATUS_COLORS: Record<string, { bg: string; text: string; border: string }> = {
  pending: { bg: 'rgba(245, 158, 11, 0.12)', text: '#d97706', border: 'rgba(245,158,11,0.3)' },
  confirmed: { bg: 'rgba(16, 185, 129, 0.12)', text: '#059669', border: 'rgba(16,185,129,0.3)' },
  cancelled: { bg: 'rgba(239, 68, 68, 0.12)', text: '#dc2626', border: 'rgba(239,68,68,0.3)' },
};

export const GroupParties: React.FC = () => {
  const [activeTab, setActiveTab] = useState<'pending' | 'confirmed' | 'cancelled' | 'all'>('all');
  const [parties, setParties] = useState<GroupParty[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  
  const [selected, setSelected] = useState<GroupParty | null>(null);

  const fetchParties = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const statusParam = activeTab === 'all' ? '' : `?status=${activeTab}`;
      const res: any = await apiClient.get(`/api/admin/group-parties${statusParam}`);
      
      // Axios interceptor unwrap gives us the direct response data
      if (res.success) {
        setParties(res.data);
      } else {
        setError(res.error || 'Failed to load group parties');
      }
    } catch (e: any) {
      setError(e.response?.data?.message || 'Network error. Please try again.');
    } finally {
      setLoading(false);
    }
  }, [activeTab]);

  useEffect(() => { fetchParties(); }, [fetchParties]);

  useEffect(() => {
    const id = setInterval(fetchParties, 30_000);
    return () => clearInterval(id);
  }, [fetchParties]);

  const openModal = (party: GroupParty) => {
    setSelected(party);
  };

  const closeModal = () => { setSelected(null); };

  const fmt = (dt: string) =>
    new Date(dt).toLocaleString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });

  const tabs = [
    { key: 'all', label: 'All' },
    { key: 'pending', label: 'Pending' },
    { key: 'confirmed', label: 'Confirmed' },
    { key: 'cancelled', label: 'Cancelled' },
  ] as const;

  return (
    <div style={{ padding: '1.5rem' }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '1.5rem' }}>
        <div>
          <h2 style={{ margin: 0, fontSize: '1.35rem', fontWeight: 700 }}>Group Parties</h2>
          <p style={{ margin: '0.25rem 0 0', color: 'var(--vz-text-muted)', fontSize: '0.85rem' }}>
            Review and manage group party bookings
          </p>
        </div>
        <button
          onClick={fetchParties}
          style={{ padding: '0.5rem 1rem', borderRadius: 8, border: '1px solid var(--vz-border-color)', background: 'transparent', cursor: 'pointer', color: 'var(--vz-text-primary)', fontSize: '0.8rem' }}
        >
          ↻ Refresh
        </button>
      </div>

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
              transition: 'all 0.15s',
            }}
          >
            {t.label}
          </button>
        ))}
      </div>

      {loading ? (
        <div style={{ textAlign: 'center', padding: '3rem', color: 'var(--vz-text-muted)' }}>Loading group parties…</div>
      ) : error ? (
        <div style={{ textAlign: 'center', padding: '3rem', color: '#dc2626' }}>{error}</div>
      ) : parties.length === 0 ? (
        <div style={{ textAlign: 'center', padding: '4rem', color: 'var(--vz-text-muted)' }}>
          <div style={{ fontSize: '3rem', marginBottom: '1rem' }}>🎉</div>
          <div style={{ fontWeight: 600 }}>No {activeTab} group parties</div>
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
          {parties.map(party => {
            const sc = STATUS_COLORS[party.status] || STATUS_COLORS['pending'];
            return (
              <div key={party.id} style={{ background: 'var(--vz-card-bg)', border: '1px solid var(--vz-border-color)', borderRadius: 14, padding: '1.25rem', display: 'flex', gap: '1rem', flexWrap: 'wrap', alignItems: 'flex-start' }}>
                <div style={{ flex: 1, minWidth: 200 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem', flexWrap: 'wrap', marginBottom: '0.4rem' }}>
                    <span style={{ fontWeight: 700, fontSize: '1rem' }}>Group Party at {party.venue?.name || 'Unknown'}</span>
                    <span style={{ padding: '0.15rem 0.65rem', borderRadius: 20, fontSize: '0.72rem', fontWeight: 700, background: sc.bg, color: sc.text, border: `1px solid ${sc.border}` }}>
                      {party.status.toUpperCase()}
                    </span>
                    {party.paymentStatus === 'paid' && (
                      <span style={{ padding: '0.15rem 0.65rem', borderRadius: 20, fontSize: '0.72rem', fontWeight: 700, background: 'rgba(16,185,129,0.12)', color: '#059669', border: '1px solid rgba(16,185,129,0.3)' }}>
                        PAID ✓
                      </span>
                    )}
                  </div>
                  <div style={{ display: 'flex', gap: '1.2rem', flexWrap: 'wrap', fontSize: '0.8rem', color: 'var(--vz-text-muted)' }}>
                    <span>🏛️ <b>{party.venue?.name ?? '—'}</b>, {party.venue?.city}</span>
                    <span>📅 {fmt(party.partyDate)}</span>
                    <span>👥 {party.numberOfFriends} friends</span>
                    <span>📞 {party.mobileNumber}</span>
                    {party.optionalMobileNumber && <span>📞 {party.optionalMobileNumber} (Alt)</span>}
                    {party.creator && <span>👤 {party.creator.firstName} {party.creator.lastName}</span>}
                    <span>💰 ₹{Number(party.totalAmount).toFixed(0)}</span>
                    {party.foodPreference && <span>🥗 {party.foodPreference}</span>}
                    {party.drinkPreference && <span>🍹 {party.drinkPreference}</span>}
                  </div>
                </div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem', flexShrink: 0 }}>
                  <button onClick={() => openModal(party)} style={{ padding: '0.45rem 1rem', borderRadius: 8, border: '1px solid var(--vz-border-color)', background: 'transparent', cursor: 'pointer', fontSize: '0.8rem', color: 'var(--vz-text-primary)' }}>
                    View Details
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {selected && (
        <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.5)', zIndex: 9999, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '1rem' }} onClick={closeModal}>
          <div style={{ background: 'var(--vz-card-bg)', borderRadius: 16, padding: '2rem', width: '100%', maxWidth: 520, boxShadow: '0 20px 60px rgba(0,0,0,0.3)' }} onClick={e => e.stopPropagation()}>
            <h3 style={{ margin: '0 0 1.25rem', fontSize: '1.1rem' }}>📋 Group Party Details</h3>
            <div style={{ background: 'var(--vz-light)', borderRadius: 10, padding: '1rem', marginBottom: '1.25rem', fontSize: '0.85rem' }}>
              <div style={{ fontWeight: 700, marginBottom: '0.5rem' }}>Group Party at {selected.venue?.name}</div>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.4rem', color: 'var(--vz-text-muted)' }}>
                <span>🏛️ {selected.venue?.name}</span>
                <span>🌆 {selected.venue?.city}</span>
                <span>📅 {fmt(selected.partyDate)}</span>
                <span>👥 {selected.numberOfFriends} friends</span>
                <span>💰 Total: ₹{selected.totalAmount}</span>
                <span>💸 Discount: ₹{selected.discountAmount}</span>
                <span>📞 {selected.mobileNumber}</span>
                {selected.optionalMobileNumber && <span>📞 {selected.optionalMobileNumber} (Alt)</span>}
                <span>👤 {selected.creator?.firstName} {selected.creator?.lastName}</span>
                <span>📧 {selected.creator?.email}</span>
                <span>💳 Payment: {selected.paymentStatus.toUpperCase()}</span>
                {selected.paymentId && <span>🧾 ID: {selected.paymentId}</span>}
                {selected.foodPreference && <span>🥗 Food Pref: {selected.foodPreference}</span>}
                {selected.drinkPreference && <span>🍹 Drink Pref: {selected.drinkPreference}</span>}
              </div>
            </div>
            <div style={{ display: 'flex', justifyContent: 'flex-end' }}>
              <button onClick={closeModal} style={{ padding: '0.6rem 1.25rem', borderRadius: 8, border: '1px solid var(--vz-border-color)', background: 'transparent', cursor: 'pointer', color: 'var(--vz-text-primary)' }}>
                Close
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default GroupParties;
