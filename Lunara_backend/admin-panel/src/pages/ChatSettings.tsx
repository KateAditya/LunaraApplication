import React, { useState, useEffect } from 'react';
import axios from 'axios';
import toast from 'react-hot-toast';
import { BiSave, BiReset, BiChat } from 'react-icons/bi';
import { useAuthStore } from '../store/authStore';

const API_BASE = import.meta.env.VITE_API_URL || 'http://192.168.0.155:9076';

interface ChatSettingsData {
  freeDays: number;
  extensionDays: number;
  extensionPrice: number;
}

const defaultSettings: ChatSettingsData = {
  freeDays: 7,
  extensionDays: 7,
  extensionPrice: 100,
};

export const ChatSettings: React.FC = () => {
  const { accessToken } = useAuthStore();
  const [settings, setSettings] = useState<ChatSettingsData>(defaultSettings);
  const [original, setOriginal] = useState<ChatSettingsData>(defaultSettings);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  const headers = { Authorization: `Bearer ${accessToken}` };

  useEffect(() => {
    const load = async () => {
      try {
        const res = await axios.get(`${API_BASE}/api/admin/settings/chat`, { headers });
        if (res.data?.success) {
          setSettings(res.data.data);
          setOriginal(res.data.data);
        }
      } catch {
        toast.error('Failed to load chat settings');
      } finally {
        setLoading(false);
      }
    };
    load();
  }, []);

  const handleSave = async () => {
    setSaving(true);
    try {
      const res = await axios.put(`${API_BASE}/api/admin/settings/chat`, settings, { headers });
      if (res.data?.success) {
        setOriginal(settings);
        toast.success('✅ Chat settings updated successfully!');
      }
    } catch {
      toast.error('Failed to save settings');
    } finally {
      setSaving(false);
    }
  };

  const handleReset = () => {
    setSettings(original);
    toast('Settings reset to last saved values.', { icon: '↩️' });
  };

  const isDirty =
    settings.freeDays !== original.freeDays ||
    settings.extensionDays !== original.extensionDays ||
    settings.extensionPrice !== original.extensionPrice;

  if (loading) {
    return (
      <div className="d-flex justify-content-center align-items-center" style={{ height: 300 }}>
        <div className="spinner-border text-primary" />
      </div>
    );
  }

  return (
    <div>
      {/* Header */}
      <div className="d-flex align-items-center gap-3 mb-4">
        <div style={{
          background: 'linear-gradient(135deg, #7F00FF, #A855F7)',
          borderRadius: 12,
          padding: '12px',
          color: 'white',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
        }}>
          <BiChat size={28} />
        </div>
        <div>
          <h4 style={{ margin: 0, fontWeight: 800 }}>Chat Payment Settings</h4>
          <p style={{ margin: 0, color: 'var(--vz-text-muted)', fontSize: '0.875rem' }}>
            Control how long users can chat for free and paid extension pricing.
          </p>
        </div>
      </div>

      <div className="row g-4">
        {/* Free Days Card */}
        <div className="col-md-4">
          <div className="card" style={{ borderRadius: 16, border: '2px solid var(--vz-border-color)' }}>
            <div className="card-body p-4">
              <div className="d-flex align-items-center gap-2 mb-3">
                <span style={{ fontSize: 24 }}>🎁</span>
                <h6 style={{ margin: 0, fontWeight: 700 }}>Free Chat Days</h6>
              </div>
              <p className="text-muted small mb-3">
                Number of days users can chat for free after a mutual match.
              </p>
              <div className="input-group">
                <input
                  type="number"
                  className="form-control form-control-lg"
                  style={{ borderRadius: '10px 0 0 10px', fontWeight: 700, fontSize: '1.5rem', textAlign: 'center' }}
                  min={1}
                  max={30}
                  value={settings.freeDays}
                  onChange={(e) => setSettings({ ...settings, freeDays: parseInt(e.target.value) || 1 })}
                />
                <span className="input-group-text" style={{ borderRadius: '0 10px 10px 0', fontWeight: 600 }}>days</span>
              </div>
              <div className="mt-2 d-flex gap-2">
                {[3, 5, 7, 10].map(d => (
                  <button
                    key={d}
                    className={`btn btn-sm ${settings.freeDays === d ? 'btn-primary' : 'btn-outline-secondary'}`}
                    style={{ borderRadius: 8 }}
                    onClick={() => setSettings({ ...settings, freeDays: d })}
                  >
                    {d}d
                  </button>
                ))}
              </div>
            </div>
          </div>
        </div>

        {/* Extension Days Card */}
        <div className="col-md-4">
          <div className="card" style={{ borderRadius: 16, border: '2px solid var(--vz-border-color)' }}>
            <div className="card-body p-4">
              <div className="d-flex align-items-center gap-2 mb-3">
                <span style={{ fontSize: 24 }}>⚡</span>
                <h6 style={{ margin: 0, fontWeight: 700 }}>Extension Days</h6>
              </div>
              <p className="text-muted small mb-3">
                Number of additional days granted when a user pays to extend chat.
              </p>
              <div className="input-group">
                <input
                  type="number"
                  className="form-control form-control-lg"
                  style={{ borderRadius: '10px 0 0 10px', fontWeight: 700, fontSize: '1.5rem', textAlign: 'center' }}
                  min={1}
                  max={90}
                  value={settings.extensionDays}
                  onChange={(e) => setSettings({ ...settings, extensionDays: parseInt(e.target.value) || 1 })}
                />
                <span className="input-group-text" style={{ borderRadius: '0 10px 10px 0', fontWeight: 600 }}>days</span>
              </div>
              <div className="mt-2 d-flex gap-2">
                {[7, 14, 30].map(d => (
                  <button
                    key={d}
                    className={`btn btn-sm ${settings.extensionDays === d ? 'btn-primary' : 'btn-outline-secondary'}`}
                    style={{ borderRadius: 8 }}
                    onClick={() => setSettings({ ...settings, extensionDays: d })}
                  >
                    {d}d
                  </button>
                ))}
              </div>
            </div>
          </div>
        </div>

        {/* Extension Price Card */}
        <div className="col-md-4">
          <div className="card" style={{ borderRadius: 16, border: '2px solid var(--vz-border-color)' }}>
            <div className="card-body p-4">
              <div className="d-flex align-items-center gap-2 mb-3">
                <span style={{ fontSize: 24 }}>💰</span>
                <h6 style={{ margin: 0, fontWeight: 700 }}>Extension Price</h6>
              </div>
              <p className="text-muted small mb-3">
                The amount (₹) a user pays to extend the chat by the number of extension days.
              </p>
              <div className="input-group">
                <span className="input-group-text" style={{ borderRadius: '10px 0 0 10px', fontWeight: 700, fontSize: '1.2rem' }}>₹</span>
                <input
                  type="number"
                  className="form-control form-control-lg"
                  style={{ borderRadius: '0 10px 10px 0', fontWeight: 700, fontSize: '1.5rem', textAlign: 'center' }}
                  min={1}
                  value={settings.extensionPrice}
                  onChange={(e) => setSettings({ ...settings, extensionPrice: parseFloat(e.target.value) || 1 })}
                />
              </div>
              <div className="mt-2 d-flex gap-2">
                {[49, 99, 149, 199].map(p => (
                  <button
                    key={p}
                    className={`btn btn-sm ${settings.extensionPrice === p ? 'btn-success' : 'btn-outline-secondary'}`}
                    style={{ borderRadius: 8 }}
                    onClick={() => setSettings({ ...settings, extensionPrice: p })}
                  >
                    ₹{p}
                  </button>
                ))}
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Preview Summary */}
      <div className="card mt-4" style={{ borderRadius: 16, background: 'linear-gradient(135deg, #7F00FF15, #A855F715)', border: '2px solid #7F00FF30' }}>
        <div className="card-body p-4">
          <h6 style={{ fontWeight: 800, color: '#7F00FF' }}>📋 Summary Preview</h6>
          <p className="mb-0" style={{ fontSize: '0.9375rem', lineHeight: 1.8 }}>
            After a mutual match, users get <strong>{settings.freeDays} free days</strong> to chat.
            Once the free period expires, either user can pay <strong>₹{settings.extensionPrice}</strong> to
            extend chatting for <strong>{settings.extensionDays} more days</strong>.
            Alternatively, one user can request the other to pay for the extension.
          </p>
        </div>
      </div>

      {/* Action Buttons */}
      <div className="d-flex gap-3 mt-4">
        <button
          className="btn btn-primary d-flex align-items-center gap-2"
          style={{ borderRadius: 12, padding: '10px 28px', fontWeight: 700, background: 'linear-gradient(135deg, #7F00FF, #A855F7)', border: 'none' }}
          onClick={handleSave}
          disabled={saving || !isDirty}
        >
          {saving ? <span className="spinner-border spinner-border-sm" /> : <BiSave size={18} />}
          {saving ? 'Saving...' : 'Save Settings'}
        </button>
        <button
          className="btn btn-outline-secondary d-flex align-items-center gap-2"
          style={{ borderRadius: 12, padding: '10px 20px', fontWeight: 600 }}
          onClick={handleReset}
          disabled={!isDirty}
        >
          <BiReset size={18} />
          Reset
        </button>
      </div>
    </div>
  );
};

export default ChatSettings;
