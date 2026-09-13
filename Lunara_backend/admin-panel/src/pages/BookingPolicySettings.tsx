import React, { useState, useEffect } from 'react';
import toast from 'react-hot-toast';
import {
  BiSave,
  BiReset,
  BiUndo,
  BiTimeFive,
  BiShieldQuarter,
  BiInfoCircle,
  BiCheckCircle,
  BiCalculator,
  BiTrendingUp,
} from 'react-icons/bi';
import {
  bookingPolicyApi,
  type BookingPolicyType,
} from '../api/bookingPolicy';

interface PolicyFormState {
  minBookingLeadTimeHours: number;
  cancellationCutoffHours: number;
  refundEnabled: boolean;
  refundPercentage: number;
  isActive: boolean;
}

const defaultSoloPolicy: PolicyFormState = {
  minBookingLeadTimeHours: 2.0,
  cancellationCutoffHours: 2.0,
  refundEnabled: true,
  refundPercentage: 80.0,
  isActive: true,
};

const defaultGroupPolicy: PolicyFormState = {
  minBookingLeadTimeHours: 2.0,
  cancellationCutoffHours: 2.0,
  refundEnabled: true,
  refundPercentage: 80.0,
  isActive: true,
};

const defaultStrangerPolicy: PolicyFormState = {
  minBookingLeadTimeHours: 2.0,
  cancellationCutoffHours: 2.0,
  refundEnabled: true,
  refundPercentage: 100.0,
  isActive: true,
};

export const BookingPolicySettings: React.FC = () => {
  const [soloForm, setSoloForm] = useState<PolicyFormState>(defaultSoloPolicy);
  const [soloOriginal, setSoloOriginal] = useState<PolicyFormState>(defaultSoloPolicy);

  const [groupForm, setGroupForm] = useState<PolicyFormState>(defaultGroupPolicy);
  const [groupOriginal, setGroupOriginal] = useState<PolicyFormState>(defaultGroupPolicy);

  const [strangerForm, setStrangerForm] = useState<PolicyFormState>(defaultStrangerPolicy);
  const [strangerOriginal, setStrangerOriginal] = useState<PolicyFormState>(defaultStrangerPolicy);

  const [activeTab, setActiveTab] = useState<'SOLO_BOOKING' | 'GROUP_PARTY' | 'STRANGERS_MEET'>('SOLO_BOOKING');
  const [loading, setLoading] = useState(true);
  const [savingType, setSavingType] = useState<BookingPolicyType | 'ALL' | null>(null);

  // Simulation calculator states
  const [simPriceSolo, setSimPriceSolo] = useState<number>(1000);
  const [simPriceGroup, setSimPriceGroup] = useState<number>(2500);
  const [simPriceStranger, setSimPriceStranger] = useState<number>(1500);

  useEffect(() => {
    fetchPolicies();
  }, []);

  const fetchPolicies = async () => {
    setLoading(true);
    try {
      const res = await bookingPolicyApi.getPolicies();
      if (res.success && res.data) {
        if (res.data.SOLO_BOOKING) {
          const s = res.data.SOLO_BOOKING;
          const sState: PolicyFormState = {
            minBookingLeadTimeHours: Number(s.minBookingLeadTimeHours) || 2.0,
            cancellationCutoffHours: Number(s.cancellationCutoffHours) || 2.0,
            refundEnabled: s.refundEnabled !== false,
            refundPercentage: Number(s.refundPercentage) || 80.0,
            isActive: s.isActive !== false,
          };
          setSoloForm(sState);
          setSoloOriginal(sState);
        }
        if (res.data.GROUP_PARTY) {
          const g = res.data.GROUP_PARTY;
          const gState: PolicyFormState = {
            minBookingLeadTimeHours: Number(g.minBookingLeadTimeHours) || 2.0,
            cancellationCutoffHours: Number(g.cancellationCutoffHours) || 2.0,
            refundEnabled: g.refundEnabled !== false,
            refundPercentage: Number(g.refundPercentage) || 80.0,
            isActive: g.isActive !== false,
          };
          setGroupForm(gState);
          setGroupOriginal(gState);
        }
        if (res.data.STRANGERS_MEET) {
          const sm = res.data.STRANGERS_MEET;
          const smState: PolicyFormState = {
            minBookingLeadTimeHours: Number(sm.minBookingLeadTimeHours) || 2.0,
            cancellationCutoffHours: Number(sm.cancellationCutoffHours) || 2.0,
            refundEnabled: sm.refundEnabled !== false,
            refundPercentage: Number(sm.refundPercentage) || 100.0,
            isActive: sm.isActive !== false,
          };
          setStrangerForm(smState);
          setStrangerOriginal(smState);
        }
      }
    } catch (err: any) {
      toast.error(err.response?.data?.message || 'Failed to load booking & refund policies');
    } finally {
      setLoading(false);
    }
  };

  const handleSavePolicy = async (type: BookingPolicyType) => {
    setSavingType(type);
    let form = soloForm;
    if (type === 'GROUP_PARTY') form = groupForm;
    if (type === 'STRANGERS_MEET') form = strangerForm;

    try {
      const res = await bookingPolicyApi.updatePolicy({
        bookingType: type,
        minBookingLeadTimeHours: form.minBookingLeadTimeHours,
        cancellationCutoffHours: form.cancellationCutoffHours,
        refundEnabled: form.refundEnabled,
        refundPercentage: form.refundPercentage,
        isActive: form.isActive,
      });

      if (res.success) {
        if (type === 'SOLO_BOOKING') {
          setSoloOriginal(form);
        } else if (type === 'GROUP_PARTY') {
          setGroupOriginal(form);
        } else if (type === 'STRANGERS_MEET') {
          setStrangerOriginal(form);
        }
        const label = type === 'SOLO_BOOKING' ? 'Solo Booking' : type === 'GROUP_PARTY' ? 'Group Party' : 'Strangers Meet';
        toast.success(
          `✅ ${label} Refund & Cancellation Policy Settings updated successfully!`
        );
      }
    } catch (err: any) {
      toast.error(err.response?.data?.message || 'Failed to save policy settings');
    } finally {
      setSavingType(null);
    }
  };

  const handleSaveAll = async () => {
    setSavingType('ALL');
    try {
      await Promise.all([
        bookingPolicyApi.updatePolicy({
          bookingType: 'SOLO_BOOKING',
          ...soloForm,
        }),
        bookingPolicyApi.updatePolicy({
          bookingType: 'GROUP_PARTY',
          ...groupForm,
        }),
        bookingPolicyApi.updatePolicy({
          bookingType: 'STRANGERS_MEET',
          ...strangerForm,
        }),
      ]);
      setSoloOriginal(soloForm);
      setGroupOriginal(groupForm);
      setStrangerOriginal(strangerForm);
      toast.success('🎉 All Refund & Booking Policy Settings updated successfully!');
    } catch (err: any) {
      toast.error(err.response?.data?.message || 'Failed to save all settings');
    } finally {
      setSavingType(null);
    }
  };

  const handleReset = (type: BookingPolicyType) => {
    if (type === 'SOLO_BOOKING') {
      setSoloForm(soloOriginal);
    } else if (type === 'GROUP_PARTY') {
      setGroupForm(groupOriginal);
    } else if (type === 'STRANGERS_MEET') {
      setStrangerForm(strangerOriginal);
    }
    toast('Settings reset to saved values', { icon: '↩️' });
  };

  const isSoloDirty =
    soloForm.minBookingLeadTimeHours !== soloOriginal.minBookingLeadTimeHours ||
    soloForm.cancellationCutoffHours !== soloOriginal.cancellationCutoffHours ||
    soloForm.refundEnabled !== soloOriginal.refundEnabled ||
    soloForm.refundPercentage !== soloOriginal.refundPercentage ||
    soloForm.isActive !== soloOriginal.isActive;

  const isGroupDirty =
    groupForm.minBookingLeadTimeHours !== groupOriginal.minBookingLeadTimeHours ||
    groupForm.cancellationCutoffHours !== groupOriginal.cancellationCutoffHours ||
    groupForm.refundEnabled !== groupOriginal.refundEnabled ||
    groupForm.refundPercentage !== groupOriginal.refundPercentage ||
    groupForm.isActive !== groupOriginal.isActive;

  const isStrangerDirty =
    strangerForm.minBookingLeadTimeHours !== strangerOriginal.minBookingLeadTimeHours ||
    strangerForm.cancellationCutoffHours !== strangerOriginal.cancellationCutoffHours ||
    strangerForm.refundEnabled !== strangerOriginal.refundEnabled ||
    strangerForm.refundPercentage !== strangerOriginal.refundPercentage ||
    strangerForm.isActive !== strangerOriginal.isActive;

  const isAnyDirty = isSoloDirty || isGroupDirty || isStrangerDirty;

  if (loading) {
    return (
      <div className="d-flex justify-content-center align-items-center" style={{ height: 400 }}>
        <div className="spinner-border text-primary" role="status">
          <span className="visually-hidden">Loading policy settings...</span>
        </div>
      </div>
    );
  }

  return (
    <div className="container-fluid p-0">
      {/* Page Header */}
      <div className="d-flex flex-wrap justify-content-between align-items-center gap-3 mb-4">
        <div className="d-flex align-items-center gap-3">
          <div
            style={{
              background: 'linear-gradient(135deg, #7F00FF, #A855F7)',
              borderRadius: 14,
              padding: '14px',
              color: 'white',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              boxShadow: '0 8px 20px rgba(127, 0, 255, 0.25)',
            }}
          >
            <BiUndo size={30} />
          </div>
          <div>
            <h4 style={{ margin: 0, fontWeight: 800, letterSpacing: '-0.02em' }}>
              Refund & Cancellation Policy Settings
            </h4>
            <p style={{ margin: 0, color: 'var(--vz-text-muted)', fontSize: '0.875rem' }}>
              Configure cancellation cutoff windows, lead times, and automatic Smart Wallet refund percentages for Solo Bookings and Group Parties.
            </p>
          </div>
        </div>

        {/* Global Save Controls */}
        <div className="d-flex align-items-center gap-2">
          <button
            type="button"
            className="btn btn-light"
            onClick={fetchPolicies}
            disabled={savingType !== null}
            style={{ fontWeight: 600 }}
          >
            Refresh
          </button>
          <button
            type="button"
            className="btn btn-primary d-flex align-items-center gap-2"
            onClick={handleSaveAll}
            disabled={!isAnyDirty || savingType !== null}
            style={{
              fontWeight: 700,
              background: 'linear-gradient(135deg, #7F00FF, #6B21A8)',
              borderColor: '#7F00FF',
            }}
          >
            {savingType === 'ALL' ? (
              <>
                <span className="spinner-border spinner-border-sm" /> Saving All...
              </>
            ) : (
              <>
                <BiSave size={18} /> Save All Changes
              </>
            )}
          </button>
        </div>
      </div>

      {/* Summary Stat Cards */}
      <div className="row g-3 mb-4">
        <div className="col-12 col-sm-6 col-xl-3">
          <div
            className="card h-100 shadow-sm border-0"
            style={{ background: 'var(--vz-card-bg)', borderRadius: 14 }}
          >
            <div className="card-body p-3 d-flex align-items-center justify-content-between">
              <div>
                <div className="text-muted small fw-semibold">Solo Booking Refund</div>
                <div className="fs-4 fw-bold mt-1 text-primary">
                  {soloForm.refundEnabled ? `${soloForm.refundPercentage}%` : 'Disabled'}
                </div>
                <div className="small text-muted mt-1">
                  Cutoff: <strong>{soloForm.cancellationCutoffHours}h</strong> before event
                </div>
              </div>
              <div
                style={{
                  background: 'rgba(127, 0, 255, 0.1)',
                  color: '#7F00FF',
                  padding: 12,
                  borderRadius: 12,
                }}
              >
                <BiUndo size={24} />
              </div>
            </div>
          </div>
        </div>

        <div className="col-12 col-sm-6 col-xl-3">
          <div
            className="card h-100 shadow-sm border-0"
            style={{ background: 'var(--vz-card-bg)', borderRadius: 14 }}
          >
            <div className="card-body p-3 d-flex align-items-center justify-content-between">
              <div>
                <div className="text-muted small fw-semibold">Group Party Refund</div>
                <div className="fs-4 fw-bold mt-1 text-info">
                  {groupForm.refundEnabled ? `${groupForm.refundPercentage}%` : 'Disabled'}
                </div>
                <div className="small text-muted mt-1">
                  Cutoff: <strong>{groupForm.cancellationCutoffHours}h</strong> before event
                </div>
              </div>
              <div
                style={{
                  background: 'rgba(14, 165, 233, 0.1)',
                  color: '#0ea5e9',
                  padding: 12,
                  borderRadius: 12,
                }}
              >
                <BiTrendingUp size={24} />
              </div>
            </div>
          </div>
        </div>

        <div className="col-12 col-sm-6 col-xl-3">
          <div
            className="card h-100 shadow-sm border-0"
            style={{ background: 'var(--vz-card-bg)', borderRadius: 14 }}
          >
            <div className="card-body p-3 d-flex align-items-center justify-content-between">
              <div>
                <div className="text-muted small fw-semibold">Solo Lead Time</div>
                <div className="fs-4 fw-bold mt-1 text-success">
                  {soloForm.minBookingLeadTimeHours} Hours
                </div>
                <div className="small text-muted mt-1">
                  Status: <strong>{soloForm.isActive ? 'Enforced' : 'Inactive'}</strong>
                </div>
              </div>
              <div
                style={{
                  background: 'rgba(34, 197, 94, 0.1)',
                  color: '#22c55e',
                  padding: 12,
                  borderRadius: 12,
                }}
              >
                <BiTimeFive size={24} />
              </div>
            </div>
          </div>
        </div>

        <div className="col-12 col-sm-6 col-xl-3">
          <div
            className="card h-100 shadow-sm border-0"
            style={{ background: 'var(--vz-card-bg)', borderRadius: 14 }}
          >
            <div className="card-body p-3 d-flex align-items-center justify-content-between">
              <div>
                <div className="text-muted small fw-semibold">Group Lead Time</div>
                <div className="fs-4 fw-bold mt-1 text-warning">
                  {groupForm.minBookingLeadTimeHours} Hours
                </div>
                <div className="small text-muted mt-1">
                  Status: <strong>{groupForm.isActive ? 'Enforced' : 'Inactive'}</strong>
                </div>
              </div>
              <div
                style={{
                  background: 'rgba(234, 179, 8, 0.1)',
                  color: '#eab308',
                  padding: 12,
                  borderRadius: 12,
                }}
              >
                <BiShieldQuarter size={24} />
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Tabs Navigation */}
      <div className="card border-0 shadow-sm mb-4" style={{ background: 'var(--vz-card-bg)', borderRadius: 16 }}>
        <div className="card-header border-0 bg-transparent p-3 pb-0">
          <ul className="nav nav-tabs card-header-tabs gap-2" role="tablist">
            <li className="nav-item">
              <button
                className={`nav-link px-4 py-3 fw-bold d-flex align-items-center gap-2 ${
                  activeTab === 'SOLO_BOOKING' ? 'active' : ''
                }`}
                onClick={() => setActiveTab('SOLO_BOOKING')}
                style={{
                  borderRadius: '10px 10px 0 0',
                  color: activeTab === 'SOLO_BOOKING' ? '#7F00FF' : 'var(--vz-text-muted)',
                  borderBottom: activeTab === 'SOLO_BOOKING' ? '3px solid #7F00FF' : 'none',
                }}
              >
                <span>Solo Bookings Policy</span>
                {isSoloDirty && (
                  <span className="badge bg-warning text-dark" style={{ fontSize: '0.65rem' }}>
                    Unsaved
                  </span>
                )}
              </button>
            </li>
            <li className="nav-item">
              <button
                className={`nav-link px-4 py-3 fw-bold d-flex align-items-center gap-2 ${
                  activeTab === 'GROUP_PARTY' ? 'active' : ''
                }`}
                onClick={() => setActiveTab('GROUP_PARTY')}
                style={{
                  borderRadius: '10px 10px 0 0',
                  color: activeTab === 'GROUP_PARTY' ? '#7F00FF' : 'var(--vz-text-muted)',
                  borderBottom: activeTab === 'GROUP_PARTY' ? '3px solid #7F00FF' : 'none',
                }}
              >
                <span>Group Parties Policy (≤ 20 Guests)</span>
                {isGroupDirty && (
                  <span className="badge bg-warning text-dark" style={{ fontSize: '0.65rem' }}>
                    Unsaved
                  </span>
                )}
              </button>
            </li>
            <li className="nav-item">
              <button
                className={`nav-link px-4 py-3 fw-bold d-flex align-items-center gap-2 ${
                  activeTab === 'STRANGERS_MEET' ? 'active' : ''
                }`}
                onClick={() => setActiveTab('STRANGERS_MEET')}
                style={{
                  borderRadius: '10px 10px 0 0',
                  color: activeTab === 'STRANGERS_MEET' ? '#7F00FF' : 'var(--vz-text-muted)',
                  borderBottom: activeTab === 'STRANGERS_MEET' ? '3px solid #7F00FF' : 'none',
                }}
              >
                <span>Strangers Meet Policy</span>
                {isStrangerDirty && (
                  <span className="badge bg-warning text-dark" style={{ fontSize: '0.65rem' }}>
                    Unsaved
                  </span>
                )}
              </button>
            </li>
          </ul>
        </div>

        <div className="card-body p-4">
          {/* TAB 1: SOLO BOOKING POLICY */}
          {activeTab === 'SOLO_BOOKING' && (
            <div className="row g-4">
              <div className="col-12 col-lg-7">
                <div className="d-flex justify-content-between align-items-center mb-3">
                  <h5 className="fw-bold m-0 text-primary">Solo Table Booking Policy</h5>
                  <div className="form-check form-switch d-flex align-items-center gap-2">
                    <input
                      className="form-check-input"
                      type="checkbox"
                      id="soloIsActive"
                      checked={soloForm.isActive}
                      onChange={(e) => setSoloForm({ ...soloForm, isActive: e.target.checked })}
                      style={{ cursor: 'pointer', width: 40, height: 20 }}
                    />
                    <label className="form-check-label fw-semibold" htmlFor="soloIsActive" style={{ cursor: 'pointer' }}>
                      {soloForm.isActive ? (
                        <span className="badge bg-success-subtle text-success">Policy Active</span>
                      ) : (
                        <span className="badge bg-danger-subtle text-danger">Policy Inactive</span>
                      )}
                    </label>
                  </div>
                </div>

                <p className="text-muted small mb-4">
                  These settings govern solo entries, individual table bookings, cancellation validity windows, and the percentage refunded to the user's Smart Wallet.
                </p>

                {/* Refund Enabled Toggle */}
                <div className="p-3 mb-4 rounded-3 border" style={{ background: 'var(--vz-card-bg)' }}>
                  <div className="d-flex justify-content-between align-items-center">
                    <div>
                      <h6 className="fw-bold mb-1">Allow Cancellation Refunds</h6>
                      <div className="text-muted small">
                        If disabled, solo bookings cannot be cancelled for a monetary refund.
                      </div>
                    </div>
                    <div className="form-check form-switch">
                      <input
                        className="form-check-input"
                        type="checkbox"
                        id="soloRefundEnabled"
                        checked={soloForm.refundEnabled}
                        onChange={(e) => setSoloForm({ ...soloForm, refundEnabled: e.target.checked })}
                        style={{ cursor: 'pointer', width: 44, height: 22 }}
                      />
                    </div>
                  </div>
                </div>

                {/* Refund Percentage Slider */}
                <div className="mb-4">
                  <div className="d-flex justify-content-between align-items-center mb-2">
                    <label className="form-label fw-bold mb-0">Refund Percentage (%)</label>
                    <span className="badge fs-6" style={{ background: '#7F00FF', color: '#fff' }}>
                      {soloForm.refundPercentage}% Refund
                    </span>
                  </div>
                  <input
                    type="range"
                    className="form-range"
                    min="0"
                    max="100"
                    step="1"
                    value={soloForm.refundPercentage}
                    disabled={!soloForm.refundEnabled}
                    onChange={(e) => setSoloForm({ ...soloForm, refundPercentage: Number(e.target.value) })}
                    style={{ cursor: soloForm.refundEnabled ? 'pointer' : 'not-allowed' }}
                  />
                  <div className="d-flex justify-content-between align-items-center gap-1 mt-2">
                    {[0, 25, 50, 75, 80, 90, 100].map((preset) => (
                      <button
                        key={preset}
                        type="button"
                        className={`btn btn-sm ${
                          soloForm.refundPercentage === preset ? 'btn-primary' : 'btn-outline-secondary'
                        }`}
                        disabled={!soloForm.refundEnabled}
                        onClick={() => setSoloForm({ ...soloForm, refundPercentage: preset })}
                        style={{ fontSize: '0.75rem', padding: '2px 8px' }}
                      >
                        {preset}%
                      </button>
                    ))}
                  </div>
                  <small className="text-muted d-block mt-2">
                    Remaining {100 - soloForm.refundPercentage}% is retained as the platform cancellation charge.
                  </small>
                </div>

                <hr className="my-4" />

                {/* Cancellation Cutoff Hours */}
                <div className="mb-4">
                  <label className="form-label fw-bold mb-1">
                    Cancellation Cutoff Window (Hours Before Event)
                  </label>
                  <p className="text-muted small mb-2">
                    Users must cancel at least this many hours prior to their booking start time to receive a refund.
                  </p>
                  <div className="input-group">
                    <input
                      type="number"
                      step="0.5"
                      min="0"
                      max="168"
                      className="form-control form-control-lg"
                      value={soloForm.cancellationCutoffHours}
                      onChange={(e) =>
                        setSoloForm({ ...soloForm, cancellationCutoffHours: parseFloat(e.target.value) || 0 })
                      }
                    />
                    <span className="input-group-text fw-semibold">Hours Before Event</span>
                  </div>
                  <div className="d-flex gap-2 mt-2">
                    {[1, 2, 4, 6, 12, 24, 48].map((hrs) => (
                      <button
                        key={hrs}
                        type="button"
                        className={`btn btn-sm ${
                          soloForm.cancellationCutoffHours === hrs ? 'btn-primary' : 'btn-outline-secondary'
                        }`}
                        onClick={() => setSoloForm({ ...soloForm, cancellationCutoffHours: hrs })}
                        style={{ fontSize: '0.75rem', padding: '2px 8px' }}
                      >
                        {hrs}h
                      </button>
                    ))}
                  </div>
                </div>

                {/* Minimum Booking Lead Time Hours */}
                <div className="mb-4">
                  <label className="form-label fw-bold mb-1">
                    Minimum Booking Lead Time (Hours)
                  </label>
                  <p className="text-muted small mb-2">
                    Bookings must be placed at least this many hours before the venue start time.
                  </p>
                  <div className="input-group">
                    <input
                      type="number"
                      step="0.5"
                      min="0"
                      max="168"
                      className="form-control form-control-lg"
                      value={soloForm.minBookingLeadTimeHours}
                      onChange={(e) =>
                        setSoloForm({ ...soloForm, minBookingLeadTimeHours: parseFloat(e.target.value) || 0 })
                      }
                    />
                    <span className="input-group-text fw-semibold">Hours Prior</span>
                  </div>
                  <div className="d-flex gap-2 mt-2">
                    {[0.5, 1, 2, 3, 4, 6, 12].map((hrs) => (
                      <button
                        key={hrs}
                        type="button"
                        className={`btn btn-sm ${
                          soloForm.minBookingLeadTimeHours === hrs ? 'btn-primary' : 'btn-outline-secondary'
                        }`}
                        onClick={() => setSoloForm({ ...soloForm, minBookingLeadTimeHours: hrs })}
                        style={{ fontSize: '0.75rem', padding: '2px 8px' }}
                      >
                        {hrs}h
                      </button>
                    ))}
                  </div>
                </div>

                {/* Form Buttons */}
                <div className="d-flex align-items-center gap-2 mt-4 pt-2">
                  <button
                    type="button"
                    className="btn btn-primary px-4 py-2 fw-bold d-flex align-items-center gap-2"
                    onClick={() => handleSavePolicy('SOLO_BOOKING')}
                    disabled={!isSoloDirty || savingType !== null}
                    style={{ background: 'linear-gradient(135deg, #7F00FF, #6B21A8)', borderColor: '#7F00FF' }}
                  >
                    {savingType === 'SOLO_BOOKING' ? (
                      <>
                        <span className="spinner-border spinner-border-sm" /> Saving Solo Policy...
                      </>
                    ) : (
                      <>
                        <BiSave size={18} /> Save Solo Booking Policy
                      </>
                    )}
                  </button>
                  <button
                    type="button"
                    className="btn btn-light px-3 py-2 fw-semibold d-flex align-items-center gap-1"
                    onClick={() => handleReset('SOLO_BOOKING')}
                    disabled={!isSoloDirty || savingType !== null}
                  >
                    <BiReset size={18} /> Reset
                  </button>
                </div>
              </div>

              {/* SIMULATOR & POLICY EXPLANATION */}
              <div className="col-12 col-lg-5">
                <div className="card border-0 shadow-sm p-4 mb-4" style={{ background: 'rgba(127, 0, 255, 0.03)', border: '1px solid rgba(127, 0, 255, 0.15)', borderRadius: 16 }}>
                  <div className="d-flex align-items-center gap-2 mb-3">
                    <BiCalculator size={22} className="text-primary" />
                    <h6 className="fw-bold m-0">Live Solo Refund Simulation</h6>
                  </div>

                  <label className="form-label small fw-semibold text-muted mb-1">Simulate Ticket Price (₹)</label>
                  <input
                    type="number"
                    min="0"
                    step="50"
                    className="form-control mb-3"
                    value={simPriceSolo}
                    onChange={(e) => setSimPriceSolo(Number(e.target.value) || 0)}
                  />

                  <div className="p-3 bg-white rounded-3 border mb-3 shadow-sm">
                    <div className="d-flex justify-content-between align-items-center mb-2">
                      <span className="text-muted small">Total Paid:</span>
                      <span className="fw-bold">₹{simPriceSolo.toLocaleString('en-IN')}</span>
                    </div>
                    <div className="d-flex justify-content-between align-items-center mb-2">
                      <span className="text-success small fw-semibold">
                        Refund to Wallet ({soloForm.refundPercentage}%):
                      </span>
                      <span className="fw-bold text-success fs-5">
                        {soloForm.refundEnabled
                          ? `₹${((simPriceSolo * soloForm.refundPercentage) / 100).toFixed(0)}`
                          : '₹0 (Refunds Disabled)'}
                      </span>
                    </div>
                    <div className="d-flex justify-content-between align-items-center pt-2 border-top">
                      <span className="text-danger small">Cancellation Charge:</span>
                      <span className="fw-semibold text-danger">
                        {soloForm.refundEnabled
                          ? `₹${(simPriceSolo - (simPriceSolo * soloForm.refundPercentage) / 100).toFixed(0)}`
                          : `₹${simPriceSolo.toFixed(0)} (100% Fee)`}
                      </span>
                    </div>
                  </div>

                  <div className="small text-muted">
                    <div className="d-flex align-items-start gap-2 mb-2">
                      <BiCheckCircle className="text-success mt-1 flex-shrink-0" />
                      <span>
                        Refunds are credited immediately to the user's <strong>Lunara Smart Wallet</strong> as non-expiring credit.
                      </span>
                    </div>
                    <div className="d-flex align-items-start gap-2">
                      <BiInfoCircle className="text-primary mt-1 flex-shrink-0" />
                      <span>
                        If cancelled within <strong>{soloForm.cancellationCutoffHours}h</strong> of booking time, the app alerts the user that cutoff has passed and refund is locked.
                      </span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          )}

          {/* TAB 2: GROUP PARTY POLICY */}
          {activeTab === 'GROUP_PARTY' && (
            <div className="row g-4">
              <div className="col-12 col-lg-7">
                <div className="d-flex justify-content-between align-items-center mb-3">
                  <h5 className="fw-bold m-0 text-info">Group Party Booking Policy (≤ 20 Guests)</h5>
                  <div className="form-check form-switch d-flex align-items-center gap-2">
                    <input
                      className="form-check-input"
                      type="checkbox"
                      id="groupIsActive"
                      checked={groupForm.isActive}
                      onChange={(e) => setGroupForm({ ...groupForm, isActive: e.target.checked })}
                      style={{ cursor: 'pointer', width: 40, height: 20 }}
                    />
                    <label className="form-check-label fw-semibold" htmlFor="groupIsActive" style={{ cursor: 'pointer' }}>
                      {groupForm.isActive ? (
                        <span className="badge bg-success-subtle text-success">Policy Active</span>
                      ) : (
                        <span className="badge bg-danger-subtle text-danger">Policy Inactive</span>
                      )}
                    </label>
                  </div>
                </div>

                <p className="text-muted small mb-4">
                  Controls table bookings with friends, small group parties (≤ 20 friends), cancellation lead-time rules, and automated wallet refund processing.
                </p>

                {/* Refund Enabled Toggle */}
                <div className="p-3 mb-4 rounded-3 border" style={{ background: 'var(--vz-card-bg)' }}>
                  <div className="d-flex justify-content-between align-items-center">
                    <div>
                      <h6 className="fw-bold mb-1">Allow Group Party Cancellation Refunds</h6>
                      <div className="text-muted small">
                        If disabled, group party host cancellations will not issue wallet refunds.
                      </div>
                    </div>
                    <div className="form-check form-switch">
                      <input
                        className="form-check-input"
                        type="checkbox"
                        id="groupRefundEnabled"
                        checked={groupForm.refundEnabled}
                        onChange={(e) => setGroupForm({ ...groupForm, refundEnabled: e.target.checked })}
                        style={{ cursor: 'pointer', width: 44, height: 22 }}
                      />
                    </div>
                  </div>
                </div>

                {/* Refund Percentage Slider */}
                <div className="mb-4">
                  <div className="d-flex justify-content-between align-items-center mb-2">
                    <label className="form-label fw-bold mb-0">Refund Percentage (%)</label>
                    <span className="badge fs-6 bg-info text-white">
                      {groupForm.refundPercentage}% Refund
                    </span>
                  </div>
                  <input
                    type="range"
                    className="form-range"
                    min="0"
                    max="100"
                    step="1"
                    value={groupForm.refundPercentage}
                    disabled={!groupForm.refundEnabled}
                    onChange={(e) => setGroupForm({ ...groupForm, refundPercentage: Number(e.target.value) })}
                    style={{ cursor: groupForm.refundEnabled ? 'pointer' : 'not-allowed' }}
                  />
                  <div className="d-flex justify-content-between align-items-center gap-1 mt-2">
                    {[0, 25, 50, 75, 80, 90, 100].map((preset) => (
                      <button
                        key={preset}
                        type="button"
                        className={`btn btn-sm ${
                          groupForm.refundPercentage === preset ? 'btn-info text-white' : 'btn-outline-secondary'
                        }`}
                        disabled={!groupForm.refundEnabled}
                        onClick={() => setGroupForm({ ...groupForm, refundPercentage: preset })}
                        style={{ fontSize: '0.75rem', padding: '2px 8px' }}
                      >
                        {preset}%
                      </button>
                    ))}
                  </div>
                  <small className="text-muted d-block mt-2">
                    Remaining {100 - groupForm.refundPercentage}% is retained as venue reservation cancellation fee.
                  </small>
                </div>

                <hr className="my-4" />

                {/* Cancellation Cutoff Hours */}
                <div className="mb-4">
                  <label className="form-label fw-bold mb-1">
                    Group Cancellation Cutoff Window (Hours Before Event)
                  </label>
                  <p className="text-muted small mb-2">
                    Host must cancel at least this many hours prior to party start time to trigger automated refund.
                  </p>
                  <div className="input-group">
                    <input
                      type="number"
                      step="0.5"
                      min="0"
                      max="168"
                      className="form-control form-control-lg"
                      value={groupForm.cancellationCutoffHours}
                      onChange={(e) =>
                        setGroupForm({ ...groupForm, cancellationCutoffHours: parseFloat(e.target.value) || 0 })
                      }
                    />
                    <span className="input-group-text fw-semibold">Hours Before Event</span>
                  </div>
                  <div className="d-flex gap-2 mt-2">
                    {[1, 2, 4, 6, 12, 24, 48].map((hrs) => (
                      <button
                        key={hrs}
                        type="button"
                        className={`btn btn-sm ${
                          groupForm.cancellationCutoffHours === hrs ? 'btn-info text-white' : 'btn-outline-secondary'
                        }`}
                        onClick={() => setGroupForm({ ...groupForm, cancellationCutoffHours: hrs })}
                        style={{ fontSize: '0.75rem', padding: '2px 8px' }}
                      >
                        {hrs}h
                      </button>
                    ))}
                  </div>
                </div>

                {/* Minimum Booking Lead Time Hours */}
                <div className="mb-4">
                  <label className="form-label fw-bold mb-1">
                    Minimum Group Booking Lead Time (Hours)
                  </label>
                  <p className="text-muted small mb-2">
                    Group parties must be created at least this many hours prior to event start.
                  </p>
                  <div className="input-group">
                    <input
                      type="number"
                      step="0.5"
                      min="0"
                      max="168"
                      className="form-control form-control-lg"
                      value={groupForm.minBookingLeadTimeHours}
                      onChange={(e) =>
                        setGroupForm({ ...groupForm, minBookingLeadTimeHours: parseFloat(e.target.value) || 0 })
                      }
                    />
                    <span className="input-group-text fw-semibold">Hours Prior</span>
                  </div>
                  <div className="d-flex gap-2 mt-2">
                    {[0.5, 1, 2, 3, 4, 6, 12].map((hrs) => (
                      <button
                        key={hrs}
                        type="button"
                        className={`btn btn-sm ${
                          groupForm.minBookingLeadTimeHours === hrs ? 'btn-info text-white' : 'btn-outline-secondary'
                        }`}
                        onClick={() => setGroupForm({ ...groupForm, minBookingLeadTimeHours: hrs })}
                        style={{ fontSize: '0.75rem', padding: '2px 8px' }}
                      >
                        {hrs}h
                      </button>
                    ))}
                  </div>
                </div>

                {/* Form Buttons */}
                <div className="d-flex align-items-center gap-2 mt-4 pt-2">
                  <button
                    type="button"
                    className="btn btn-info text-white px-4 py-2 fw-bold d-flex align-items-center gap-2"
                    onClick={() => handleSavePolicy('GROUP_PARTY')}
                    disabled={!isGroupDirty || savingType !== null}
                  >
                    {savingType === 'GROUP_PARTY' ? (
                      <>
                        <span className="spinner-border spinner-border-sm" /> Saving Group Policy...
                      </>
                    ) : (
                      <>
                        <BiSave size={18} /> Save Group Party Policy
                      </>
                    )}
                  </button>
                  <button
                    type="button"
                    className="btn btn-light px-3 py-2 fw-semibold d-flex align-items-center gap-1"
                    onClick={() => handleReset('GROUP_PARTY')}
                    disabled={!isGroupDirty || savingType !== null}
                  >
                    <BiReset size={18} /> Reset
                  </button>
                </div>
              </div>

              {/* SIMULATOR & POLICY EXPLANATION */}
              <div className="col-12 col-lg-5">
                <div className="card border-0 shadow-sm p-4 mb-4" style={{ background: 'rgba(14, 165, 233, 0.03)', border: '1px solid rgba(14, 165, 233, 0.2)', borderRadius: 16 }}>
                  <div className="d-flex align-items-center gap-2 mb-3">
                    <BiCalculator size={22} className="text-info" />
                    <h6 className="fw-bold m-0">Live Group Party Refund Simulation</h6>
                  </div>

                  <label className="form-label small fw-semibold text-muted mb-1">Simulate Party Booking Total (₹)</label>
                  <input
                    type="number"
                    min="0"
                    step="100"
                    className="form-control mb-3"
                    value={simPriceGroup}
                    onChange={(e) => setSimPriceGroup(Number(e.target.value) || 0)}
                  />

                  <div className="p-3 bg-white rounded-3 border mb-3 shadow-sm">
                    <div className="d-flex justify-content-between align-items-center mb-2">
                      <span className="text-muted small">Total Party Charge:</span>
                      <span className="fw-bold">₹{simPriceGroup.toLocaleString('en-IN')}</span>
                    </div>
                    <div className="d-flex justify-content-between align-items-center mb-2">
                      <span className="text-info small fw-semibold">
                        Refund to Host Wallet ({groupForm.refundPercentage}%):
                      </span>
                      <span className="fw-bold text-info fs-5">
                        {groupForm.refundEnabled
                          ? `₹${((simPriceGroup * groupForm.refundPercentage) / 100).toFixed(0)}`
                          : '₹0 (Refunds Disabled)'}
                      </span>
                    </div>
                    <div className="d-flex justify-content-between align-items-center pt-2 border-top">
                      <span className="text-danger small">Cancellation Charge:</span>
                      <span className="fw-semibold text-danger">
                        {groupForm.refundEnabled
                          ? `₹${(simPriceGroup - (simPriceGroup * groupForm.refundPercentage) / 100).toFixed(0)}`
                          : `₹${simPriceGroup.toFixed(0)} (100% Fee)`}
                      </span>
                    </div>
                  </div>

                  <div className="small text-muted">
                    <div className="d-flex align-items-start gap-2 mb-2">
                      <BiCheckCircle className="text-success mt-1 flex-shrink-0" />
                      <span>
                        Applies to small group parties (≤ 20 friends). Large party requests (&gt; 20 friends) undergo custom admin review and approval.
                      </span>
                    </div>
                    <div className="d-flex align-items-start gap-2">
                      <BiInfoCircle className="text-info mt-1 flex-shrink-0" />
                      <span>
                        Upon cancellation, venue capacity is released and mutual invites are cancelled automatically.
                      </span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          )}

          {/* TAB 3: STRANGERS MEET POLICY */}
          {activeTab === 'STRANGERS_MEET' && (
            <div className="row g-4">
              <div className="col-12 col-lg-7">
                <div className="d-flex justify-content-between align-items-center mb-3">
                  <h5 className="fw-bold m-0" style={{ color: '#7F00FF' }}>Strangers Meet Cancellation & Refund Policy</h5>
                  <div className="form-check form-switch d-flex align-items-center gap-2">
                    <input
                      className="form-check-input"
                      type="checkbox"
                      id="strangerIsActive"
                      checked={strangerForm.isActive}
                      onChange={(e) => setStrangerForm({ ...strangerForm, isActive: e.target.checked })}
                      style={{ cursor: 'pointer', width: 40, height: 20 }}
                    />
                    <label className="form-check-label fw-semibold" htmlFor="strangerIsActive" style={{ cursor: 'pointer' }}>
                      {strangerForm.isActive ? (
                        <span className="badge bg-success-subtle text-success">Policy Active</span>
                      ) : (
                        <span className="badge bg-danger-subtle text-danger">Policy Inactive</span>
                      )}
                    </label>
                  </div>
                </div>

                <p className="text-muted small mb-4">
                  Governs participant cancellation requests to the host, cutoff lead-time windows (1h, 2h, 5h, 10h, 1 day, 2 days, or custom), automated wallet refunds (&lt; ₹1500), and payout thresholds.
                </p>

                {/* Refund Enabled Toggle */}
                <div className="p-3 mb-4 rounded-3 border" style={{ background: 'var(--vz-card-bg)' }}>
                  <div className="d-flex justify-content-between align-items-center">
                    <div>
                      <h6 className="fw-bold mb-1">Allow Participant Cancellation Refunds</h6>
                      <div className="text-muted small">
                        If enabled, accepted participant cancellations will issue refunds to user wallets (&lt; ₹1500) or external payout (≥ ₹1500).
                      </div>
                    </div>
                    <div className="form-check form-switch">
                      <input
                        className="form-check-input"
                        type="checkbox"
                        id="strangerRefundEnabled"
                        checked={strangerForm.refundEnabled}
                        onChange={(e) => setStrangerForm({ ...strangerForm, refundEnabled: e.target.checked })}
                        style={{ cursor: 'pointer', width: 44, height: 22 }}
                      />
                    </div>
                  </div>
                </div>

                {/* Refund Percentage Slider */}
                <div className="mb-4">
                  <div className="d-flex justify-content-between align-items-center mb-2">
                    <label className="form-label fw-bold mb-0">Default Refund Percentage (%)</label>
                    <span className="badge fs-6" style={{ background: '#7F00FF', color: '#fff' }}>
                      {strangerForm.refundPercentage}% Refund
                    </span>
                  </div>
                  <input
                    type="range"
                    className="form-range"
                    min="0"
                    max="100"
                    step="1"
                    value={strangerForm.refundPercentage}
                    disabled={!strangerForm.refundEnabled}
                    onChange={(e) => setStrangerForm({ ...strangerForm, refundPercentage: Number(e.target.value) })}
                    style={{ cursor: strangerForm.refundEnabled ? 'pointer' : 'not-allowed' }}
                  />
                  <div className="d-flex justify-content-between align-items-center gap-1 mt-2">
                    {[0, 25, 50, 75, 80, 90, 100].map((preset) => (
                      <button
                        key={preset}
                        type="button"
                        className={`btn btn-sm ${
                          strangerForm.refundPercentage === preset ? 'btn-primary' : 'btn-outline-secondary'
                        }`}
                        disabled={!strangerForm.refundEnabled}
                        onClick={() => setStrangerForm({ ...strangerForm, refundPercentage: preset })}
                        style={{ fontSize: '0.75rem', padding: '2px 8px' }}
                      >
                        {preset}%
                      </button>
                    ))}
                  </div>
                  <small className="text-muted d-block mt-2">
                    Standard policy is 100% refund upon host acceptance before event cutoff.
                  </small>
                </div>

                <hr className="my-4" />

                {/* Cancellation Cutoff Hours Selection (1, 2, 5, 10, 1 day, 2 days, custom) */}
                <div className="mb-4">
                  <label className="form-label fw-bold mb-1">
                    Cancellation Cutoff Window (Before Meetup Time)
                  </label>
                  <p className="text-muted small mb-2">
                    How much time before the Stranger Meet can participants or the host request cancellation. Select a quick preset or enter custom hours/days.
                  </p>
                  
                  {/* Preset Cutoff Chips */}
                  <div className="d-flex flex-wrap gap-2 mb-3">
                    {[
                      { label: '1 Hour', hours: 1 },
                      { label: '2 Hours', hours: 2 },
                      { label: '5 Hours', hours: 5 },
                      { label: '10 Hours', hours: 10 },
                      { label: '1 Day (24h)', hours: 24 },
                      { label: '2 Days (48h)', hours: 48 },
                    ].map((preset) => (
                      <button
                        key={preset.hours}
                        type="button"
                        className={`btn btn-sm px-3 py-2 fw-semibold ${
                          strangerForm.cancellationCutoffHours === preset.hours
                            ? 'btn-primary shadow-sm'
                            : 'btn-outline-secondary'
                        }`}
                        onClick={() => setStrangerForm({ ...strangerForm, cancellationCutoffHours: preset.hours })}
                        style={{
                          borderRadius: 10,
                          fontSize: '0.85rem',
                          background: strangerForm.cancellationCutoffHours === preset.hours ? 'linear-gradient(135deg, #7F00FF, #6B21A8)' : undefined,
                          borderColor: strangerForm.cancellationCutoffHours === preset.hours ? '#7F00FF' : undefined,
                        }}
                      >
                        ⏱️ {preset.label}
                      </button>
                    ))}
                  </div>

                  {/* Custom Cutoff Input */}
                  <div className="input-group">
                    <input
                      type="number"
                      step="0.5"
                      min="0"
                      max="720"
                      className="form-control form-control-lg"
                      value={strangerForm.cancellationCutoffHours}
                      onChange={(e) =>
                        setStrangerForm({ ...strangerForm, cancellationCutoffHours: parseFloat(e.target.value) || 0 })
                      }
                    />
                    <span className="input-group-text fw-semibold">
                      Hours Before Event ({strangerForm.cancellationCutoffHours >= 24 ? `${(strangerForm.cancellationCutoffHours / 24).toFixed(1)} Days` : `${strangerForm.cancellationCutoffHours} Hours`})
                    </span>
                  </div>
                  <small className="text-muted d-block mt-2">
                    Current Cutoff: <strong>{strangerForm.cancellationCutoffHours >= 24 ? `${(strangerForm.cancellationCutoffHours / 24).toFixed(1)} Day(s) (${strangerForm.cancellationCutoffHours} Hours)` : `${strangerForm.cancellationCutoffHours} Hour(s)`}</strong> prior to meetup time.
                  </small>
                </div>

                {/* Minimum Booking Lead Time Hours */}
                <div className="mb-4">
                  <label className="form-label fw-bold mb-1">
                    Minimum Meetup Creation Lead Time (Hours)
                  </label>
                  <p className="text-muted small mb-2">
                    Stranger Meets must be scheduled at least this many hours in advance of the event start date.
                  </p>
                  <div className="input-group">
                    <input
                      type="number"
                      step="0.5"
                      min="0"
                      max="168"
                      className="form-control form-control-lg"
                      value={strangerForm.minBookingLeadTimeHours}
                      onChange={(e) =>
                        setStrangerForm({ ...strangerForm, minBookingLeadTimeHours: parseFloat(e.target.value) || 0 })
                      }
                    />
                    <span className="input-group-text fw-semibold">Hours Lead Time</span>
                  </div>
                  <div className="d-flex gap-2 mt-2">
                    {[1, 2, 4, 6, 12, 24, 48].map((hrs) => (
                      <button
                        key={hrs}
                        type="button"
                        className={`btn btn-sm ${
                          strangerForm.minBookingLeadTimeHours === hrs ? 'btn-primary' : 'btn-outline-secondary'
                        }`}
                        onClick={() => setStrangerForm({ ...strangerForm, minBookingLeadTimeHours: hrs })}
                        style={{ fontSize: '0.75rem', padding: '2px 8px' }}
                      >
                        {hrs}h
                      </button>
                    ))}
                  </div>
                </div>

                {/* Form Buttons */}
                <div className="d-flex align-items-center gap-2 mt-4 pt-2">
                  <button
                    type="button"
                    className="btn btn-primary px-4 py-2 fw-bold d-flex align-items-center gap-2"
                    onClick={() => handleSavePolicy('STRANGERS_MEET')}
                    disabled={!isStrangerDirty || savingType !== null}
                    style={{ background: 'linear-gradient(135deg, #7F00FF, #6B21A8)', borderColor: '#7F00FF' }}
                  >
                    {savingType === 'STRANGERS_MEET' ? (
                      <>
                        <span className="spinner-border spinner-border-sm" /> Saving Strangers Meet Policy...
                      </>
                    ) : (
                      <>
                        <BiSave size={18} /> Save Strangers Meet Policy
                      </>
                    )}
                  </button>
                  <button
                    type="button"
                    className="btn btn-light px-3 py-2 fw-semibold d-flex align-items-center gap-1"
                    onClick={() => handleReset('STRANGERS_MEET')}
                    disabled={!isStrangerDirty || savingType !== null}
                  >
                    <BiReset size={18} /> Reset
                  </button>
                </div>
              </div>

              {/* SIMULATOR & POLICY EXPLANATION */}
              <div className="col-12 col-lg-5">
                <div className="card border-0 shadow-sm p-4 mb-4" style={{ background: 'rgba(127, 0, 255, 0.03)', border: '1px solid rgba(127, 0, 255, 0.2)', borderRadius: 16 }}>
                  <div className="d-flex align-items-center gap-2 mb-3">
                    <BiCalculator size={22} style={{ color: '#7F00FF' }} />
                    <h6 className="fw-bold m-0">Live Stranger Meet Refund Simulation</h6>
                  </div>

                  <label className="form-label small fw-semibold text-muted mb-1">Simulate Per-Head Member Payment (₹)</label>
                  <input
                    type="number"
                    min="0"
                    step="100"
                    className="form-control mb-3"
                    value={simPriceStranger}
                    onChange={(e) => setSimPriceStranger(Number(e.target.value) || 0)}
                  />

                  <div className="p-3 bg-white rounded-3 border mb-3 shadow-sm">
                    <div className="d-flex justify-content-between align-items-center mb-2">
                      <span className="text-muted small">Participant Paid Amount:</span>
                      <span className="fw-bold">₹{simPriceStranger.toLocaleString('en-IN')}</span>
                    </div>
                    <div className="d-flex justify-content-between align-items-center mb-2">
                      <span className="text-success small fw-semibold">
                        Refund Amount ({strangerForm.refundPercentage}%):
                      </span>
                      <span className="fw-bold text-success fs-5">
                        {strangerForm.refundEnabled
                          ? `₹${((simPriceStranger * strangerForm.refundPercentage) / 100).toFixed(0)}`
                          : '₹0 (Refunds Disabled)'}
                      </span>
                    </div>
                    <div className="d-flex justify-content-between align-items-center mb-2">
                      <span className="text-muted small">Refund Routing:</span>
                      <span className="badge bg-primary-subtle text-primary fw-bold">
                        {simPriceStranger < 1500 ? 'Direct to Lunara Wallet (< ₹1500)' : 'Choice of Wallet / UPI / Bank (≥ ₹1500)'}
                      </span>
                    </div>
                    <div className="d-flex justify-content-between align-items-center pt-2 border-top">
                      <span className="text-danger small">Cancellation Fee:</span>
                      <span className="fw-semibold text-danger">
                        {strangerForm.refundEnabled
                          ? `₹${(simPriceStranger - (simPriceStranger * strangerForm.refundPercentage) / 100).toFixed(0)}`
                          : `₹${simPriceStranger.toFixed(0)} (100% Fee)`}
                      </span>
                    </div>
                  </div>

                  <div className="small text-muted">
                    <div className="d-flex align-items-start gap-2 mb-2">
                      <BiCheckCircle className="text-success mt-1 flex-shrink-0" />
                      <span>
                        Cancellations submitted at least <strong>{strangerForm.cancellationCutoffHours >= 24 ? `${(strangerForm.cancellationCutoffHours / 24).toFixed(0)} day(s)` : `${strangerForm.cancellationCutoffHours} hour(s)`}</strong> before start time are eligible for host review.
                      </span>
                    </div>
                    <div className="d-flex align-items-start gap-2 mb-2">
                      <BiInfoCircle className="text-primary mt-1 flex-shrink-0" />
                      <span>
                        Under ₹1500 refunds are automatically credited to the participant's Lunara Wallet without manual payout steps.
                      </span>
                    </div>
                    <div className="d-flex align-items-start gap-2">
                      <BiShieldQuarter className="text-warning mt-1 flex-shrink-0" />
                      <span>
                        Tickets for cancelled participants are immediately revoked and marked invalid in Ticket Pocket.
                      </span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

export default BookingPolicySettings;
