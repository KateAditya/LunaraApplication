import React, { useState } from 'react';
import {
    BiX, BiSave, BiChevronLeft, BiChevronRight,
    BiUser, BiIdCard, BiHeart, BiShieldQuarter, BiCheckCircle
} from 'react-icons/bi';
import type { User } from '../types/user';
import { INTERESTS_OPTIONS } from '../types/user';

interface UserFormProps {
    user?: User | null;
    onClose: () => void;
    onSave: (data: any) => void;
}

const ROLE_OPTIONS = ['customer', 'venue_owner', 'admin', 'promoter'] as const;

const TAB_CONFIG = [
    { key: 'basic', label: 'Basic Info', icon: <BiUser /> },
    { key: 'profile', label: 'Profile', icon: <BiIdCard /> },
    { key: 'preferences', label: 'Preferences', icon: <BiHeart /> },
    { key: 'security', label: 'Security', icon: <BiShieldQuarter /> },
];

const getDefaultForm = (user?: User | null) => ({
    // Basic
    firstName: user?.firstName || '',
    lastName: user?.lastName || '',
    email: user?.email || '',
    phone: user?.phone || '+91 ',
    role: user?.role || 'customer',
    avatarUrl: user?.avatarUrl || '',
    isActive: user?.isActive ?? true,
    isVerified: user?.isVerified ?? false,
    isPhoneVerified: user?.isPhoneVerified ?? false,
    isEmailVerified: user?.isEmailVerified ?? false,
    password: '',

    // Profile (Demographics & Vibe)
    displayName: user?.profile?.displayName || '',
    bio: user?.profile?.bio || '',
    gender: user?.profile?.gender || 'MALE',
    city: user?.profile?.city || '',
    occupation: user?.profile?.occupation || '',
    education: user?.profile?.education || '',

    // Preferences (Matching & Lifestyle)
    smokingPreference: user?.preferences?.smokingPreference || '',
    minAgePreference: user?.preferences?.minAgePreference || 18,
    maxAgePreference: user?.preferences?.maxAgePreference || 60,
    budgetRange: user?.preferences?.budgetRange || '',
    musicPreference: user?.preferences?.musicPreference || [],
    drinkPreference: user?.preferences?.drinkPreference || [],
    preferredGenders: user?.preferences?.preferredGenders || [],
    showMeInMatching: user?.preferences?.showMeInMatching ?? true,

    // Security
    mfaEnabled: user?.security?.mfaEnabled ?? false,
    forcePasswordChange: user?.security?.forcePasswordChange ?? false,
});

/* ═════════ STYLES ═════════ */
const overlay: React.CSSProperties = { position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.6)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 1080, backdropFilter: 'blur(4px)' };
const panel: React.CSSProperties = { width: '100%', maxWidth: 700, maxHeight: '92vh', display: 'flex', flexDirection: 'column', borderRadius: 'var(--vz-radius-lg)', overflow: 'hidden', boxShadow: '0 8px 40px rgba(0,0,0,0.25)' };
const field: React.CSSProperties = { marginBottom: '0.875rem' };
const labelStyle: React.CSSProperties = { display: 'block', fontSize: '0.75rem', fontWeight: 600, color: 'var(--vz-text-secondary)', marginBottom: '0.25rem', textTransform: 'uppercase', letterSpacing: '0.03em' };
const gridTwo: React.CSSProperties = { display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.75rem' };
const gridThree: React.CSSProperties = { display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: '0.75rem' };

export const UserForm: React.FC<UserFormProps> = ({ user, onClose, onSave }) => {
    const [activeTab, setActiveTab] = useState(0);
    const [form, setForm] = useState(getDefaultForm(user));

    const set = (key: string, val: any) => setForm(prev => ({ ...prev, [key]: val }));

    const toggleMulti = (key: 'musicPreference' | 'drinkPreference' | 'preferredGenders', val: string) => {
        setForm(prev => ({
            ...prev,
            [key]: (prev[key] as string[]).includes(val) ? (prev[key] as string[]).filter(v => v !== val) : [...(prev[key] as string[]), val],
        }));
    };

    const handleSubmit = () => {
        const payload = {
            firstName: form.firstName,
            lastName: form.lastName,
            email: form.email,
            phone: form.phone,
            role: form.role,
            isActive: form.isActive,
            isVerified: form.isVerified,
            profile: {
                displayName: form.displayName,
                bio: form.bio,
                gender: form.gender,
                city: form.city,
                occupation: form.occupation,
                education: form.education,
            },
            preferences: {
                smokingPreference: form.smokingPreference,
                minAgePreference: form.minAgePreference,
                maxAgePreference: form.maxAgePreference,
                budgetRange: form.budgetRange,
                musicPreference: form.musicPreference,
                drinkPreference: form.drinkPreference,
                preferredGenders: form.preferredGenders,
                showMeInMatching: form.showMeInMatching,
            }
        };

        if (!user) {
            (payload as any).password = form.password;
        }

        onSave(payload);
    };

    /* ─── Tab renderers ─── */

    const renderBasicInfo = () => (
        <div>
            <div style={gridTwo}>
                <div style={field}>
                    <label style={labelStyle}>First Name *</label>
                    <input className="vz-form-control" placeholder="e.g. Priya" value={form.firstName} onChange={e => set('firstName', e.target.value)} />
                </div>
                <div style={field}>
                    <label style={labelStyle}>Last Name *</label>
                    <input className="vz-form-control" placeholder="e.g. Sharma" value={form.lastName} onChange={e => set('lastName', e.target.value)} />
                </div>
            </div>
            <div style={gridTwo}>
                <div style={field}>
                    <label style={labelStyle}>Email *</label>
                    <input className="vz-form-control" type="email" placeholder="user@email.com" value={form.email} onChange={e => set('email', e.target.value)} />
                </div>
                <div style={field}>
                    <label style={labelStyle}>Phone *</label>
                    <input className="vz-form-control" placeholder="e.g. 9876543210" value={form.phone} onChange={e => set('phone', e.target.value)} />
                </div>
            </div>
            {!user && (
                <div style={gridTwo}>
                    <div style={field}>
                        <label style={labelStyle}>Temporary Password *</label>
                        <input className="vz-form-control" type="password" placeholder="Min 6 characters" value={form.password} onChange={e => set('password', e.target.value)} />
                    </div>
                </div>
            )}
            <div style={gridTwo}>
                <div style={field}>
                    <label style={labelStyle}>Role *</label>
                    <select className="vz-form-control" value={form.role} onChange={e => set('role', e.target.value)}>
                        {ROLE_OPTIONS.map(r => (
                            <option key={r} value={r}>{r.replace('_', ' ').replace(/\b\w/g, l => l.toUpperCase())}</option>
                        ))}
                    </select>
                </div>
                <div style={field}>
                    <label style={labelStyle}>Avatar URL</label>
                    <input className="vz-form-control" placeholder="https://..." value={form.avatarUrl} onChange={e => set('avatarUrl', e.target.value)} />
                </div>
            </div>
            <div style={{ display: 'flex', gap: '1.5rem', marginTop: '0.75rem', flexWrap: 'wrap' }}>
                {([
                    { key: 'isActive', label: 'Active' },
                    { key: 'isVerified', label: 'Verified' },
                    { key: 'isPhoneVerified', label: 'Phone Verified' },
                    { key: 'isEmailVerified', label: 'Email Verified' },
                ] as const).map(flag => (
                    <label key={flag.key} style={{ display: 'flex', alignItems: 'center', gap: '0.375rem', cursor: 'pointer', fontSize: '0.8125rem', fontWeight: 500, color: 'var(--vz-text-primary)' }}>
                        <input
                            type="checkbox"
                            checked={form[flag.key] as boolean}
                            onChange={e => set(flag.key, e.target.checked)}
                            style={{ width: 16, height: 16, accentColor: 'var(--vz-primary)' }}
                        />
                        {flag.label}
                    </label>
                ))}
            </div>
        </div>
    );

    const renderProfile = () => (
        <div>
            <div style={gridTwo}>
                <div style={field}>
                    <label style={labelStyle}>Display Name</label>
                    <input className="vz-form-control" placeholder="Public facing name" value={form.displayName} onChange={e => set('displayName', e.target.value)} />
                </div>
                <div style={field}>
                    <label style={labelStyle}>Gender</label>
                    <select className="vz-form-control" value={form.gender} onChange={e => set('gender', e.target.value)}>
                        <option value="MALE">Male</option>
                        <option value="FEMALE">Female</option>
                        <option value="OTHER">Other</option>
                    </select>
                </div>
            </div>

            <div style={field}>
                <label style={labelStyle}>Bio</label>
                <textarea className="vz-form-control" rows={3} placeholder="Tell us about this user..." value={form.bio} onChange={e => set('bio', e.target.value)} style={{ resize: 'vertical', minHeight: 64 }} />
            </div>

            <div style={gridThree}>
                <div style={field}>
                    <label style={labelStyle}>City</label>
                    <input className="vz-form-control" placeholder="e.g. Mumbai" value={form.city} onChange={e => set('city', e.target.value)} />
                </div>
                <div style={field}>
                    <label style={labelStyle}>Occupation</label>
                    <input className="vz-form-control" placeholder="e.g. UI Designer" value={form.occupation} onChange={e => set('occupation', e.target.value)} />
                </div>
                <div style={field}>
                    <label style={labelStyle}>Education</label>
                    <input className="vz-form-control" placeholder="e.g. Bachelor's Degree" value={form.education} onChange={e => set('education', e.target.value)} />
                </div>
            </div>
        </div>
    );

    const renderPreferences = () => (
        <div>
            <div style={gridThree}>
                <div style={field}>
                    <label style={labelStyle}>Smoking Habit</label>
                    <select className="vz-form-control" value={form.smokingPreference} onChange={e => set('smokingPreference', e.target.value)}>
                        <option value="">Select...</option>
                        <option value="NON-SMOKER">Non-Smoker</option>
                        <option value="SOCIALLY">Socially</option>
                        <option value="REGULARLY">Regularly</option>
                    </select>
                </div>
                <div style={field}>
                    <label style={labelStyle}>Target Gender</label>
                    <div style={{ display: 'flex', gap: '0.375rem', flexWrap: 'wrap', marginTop: 8 }}>
                        {['MEN', 'WOMEN', 'ALL'].map(g => (
                            <button
                                type="button" key={g}
                                onClick={() => toggleMulti('preferredGenders', g)}
                                style={{
                                    padding: '0.25rem 0.625rem', borderRadius: '999px',
                                    border: `1.5px solid ${form.preferredGenders.includes(g) ? 'var(--vz-primary)' : 'var(--vz-border-color)'}`,
                                    background: form.preferredGenders.includes(g) ? 'rgba(var(--vz-primary-rgb), 0.1)' : 'transparent',
                                    color: form.preferredGenders.includes(g) ? 'var(--vz-primary)' : 'var(--vz-text-muted)',
                                    fontSize: '0.6875rem', fontWeight: 500, cursor: 'pointer', fontFamily: 'var(--vz-font)', transition: 'all 0.2s ease',
                                }}
                            >{g}</button>
                        ))}
                    </div>
                </div>
                <div style={field}>
                    <label style={labelStyle}>Show Me In Matching</label>
                    <label style={{ display: 'flex', alignItems: 'center', gap: '0.375rem', cursor: 'pointer', fontSize: '0.8125rem', fontWeight: 500, color: 'var(--vz-text-primary)', marginTop: 8 }}>
                        <input
                            type="checkbox"
                            checked={form.showMeInMatching}
                            onChange={e => set('showMeInMatching', e.target.checked)}
                            style={{ width: 16, height: 16, accentColor: 'var(--vz-primary)' }}
                        />
                        Enabled
                    </label>
                </div>
            </div>

            <div style={gridTwo}>
                <div style={field}>
                    <label style={labelStyle}>Min Age Target</label>
                    <input className="vz-form-control" type="number" value={form.minAgePreference} onChange={e => set('minAgePreference', parseInt(e.target.value))} />
                </div>
                <div style={field}>
                    <label style={labelStyle}>Max Age Target</label>
                    <input className="vz-form-control" type="number" value={form.maxAgePreference} onChange={e => set('maxAgePreference', parseInt(e.target.value))} />
                </div>
            </div>

            <div style={field}>
                <label style={labelStyle}>Music Genres</label>
                <div style={{ display: 'flex', gap: '0.375rem', flexWrap: 'wrap' }}>
                    {INTERESTS_OPTIONS.map(i => (
                        <button
                            type="button" key={i}
                            onClick={() => toggleMulti('musicPreference', i)}
                            style={{
                                padding: '0.25rem 0.625rem', borderRadius: '999px',
                                border: `1.5px solid ${form.musicPreference.includes(i) ? 'var(--vz-success)' : 'var(--vz-border-color)'}`,
                                background: form.musicPreference.includes(i) ? 'rgba(var(--vz-success-rgb), 0.1)' : 'transparent',
                                color: form.musicPreference.includes(i) ? 'var(--vz-success)' : 'var(--vz-text-muted)',
                                fontSize: '0.6875rem', fontWeight: 500, cursor: 'pointer', fontFamily: 'var(--vz-font)', transition: 'all 0.2s ease',
                            }}
                        >{i}</button>
                    ))}
                </div>
            </div>
        </div>
    );

    const renderSecurity = () => (
        <div>
            <div style={{ display: 'flex', gap: '1.5rem', marginBottom: '1rem' }}>
                <label style={{ display: 'flex', alignItems: 'center', gap: '0.375rem', cursor: 'pointer', fontSize: '0.8125rem', fontWeight: 500, color: 'var(--vz-text-primary)' }}>
                    <input type="checkbox" checked={form.mfaEnabled} onChange={e => set('mfaEnabled', e.target.checked)} style={{ width: 16, height: 16, accentColor: 'var(--vz-primary)' }} />
                    Enable Multi-Factor Authentication (MFA)
                </label>
            </div>
            <div style={{ display: 'flex', gap: '1.5rem', marginBottom: '1rem' }}>
                <label style={{ display: 'flex', alignItems: 'center', gap: '0.375rem', cursor: 'pointer', fontSize: '0.8125rem', fontWeight: 500, color: 'var(--vz-text-primary)' }}>
                    <input type="checkbox" checked={form.forcePasswordChange} onChange={e => set('forcePasswordChange', e.target.checked)} style={{ width: 16, height: 16, accentColor: 'var(--vz-warning, #f59e0b)' }} />
                    Force Password Change on Next Login
                </label>
            </div>

            {/* Login History (read-only if editing) */}
            {user?.security?.loginHistory && user.security.loginHistory.length > 0 && (
                <div style={{ marginTop: '1rem' }}>
                    <div style={{ fontSize: '0.8125rem', fontWeight: 700, color: 'var(--vz-primary)', marginBottom: '0.75rem', textTransform: 'uppercase', letterSpacing: '0.04em' }}>Recent Login History</div>
                    <div style={{ borderRadius: 'var(--vz-radius)', border: '1px solid var(--vz-border-color)', overflow: 'hidden' }}>
                        <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '0.75rem' }}>
                            <thead>
                                <tr style={{ background: 'var(--vz-border-color)' }}>
                                    <th style={{ padding: '0.5rem 0.75rem', textAlign: 'left', fontWeight: 600, color: 'var(--vz-text-muted)', textTransform: 'uppercase', fontSize: '0.625rem' }}>Timestamp</th>
                                    <th style={{ padding: '0.5rem 0.75rem', textAlign: 'left', fontWeight: 600, color: 'var(--vz-text-muted)', textTransform: 'uppercase', fontSize: '0.625rem' }}>IP</th>
                                    <th style={{ padding: '0.5rem 0.75rem', textAlign: 'left', fontWeight: 600, color: 'var(--vz-text-muted)', textTransform: 'uppercase', fontSize: '0.625rem' }}>Device</th>
                                    <th style={{ padding: '0.5rem 0.75rem', textAlign: 'left', fontWeight: 600, color: 'var(--vz-text-muted)', textTransform: 'uppercase', fontSize: '0.625rem' }}>Location</th>
                                </tr>
                            </thead>
                            <tbody>
                                {user.security.loginHistory.map((entry, idx) => (
                                    <tr key={idx} style={{ borderTop: '1px solid var(--vz-border-color)' }}>
                                        <td style={{ padding: '0.5rem 0.75rem', color: 'var(--vz-text-primary)' }}>{new Date(entry.timestamp).toLocaleString('en-IN', { dateStyle: 'medium', timeStyle: 'short' })}</td>
                                        <td style={{ padding: '0.5rem 0.75rem', color: 'var(--vz-text-secondary)', fontFamily: 'monospace' }}>{entry.ip}</td>
                                        <td style={{ padding: '0.5rem 0.75rem', color: 'var(--vz-text-secondary)' }}>{entry.device}</td>
                                        <td style={{ padding: '0.5rem 0.75rem', color: 'var(--vz-text-secondary)' }}>{entry.location}</td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                </div>
            )}

            {user?.security?.lastPasswordChange && (
                <div style={{ marginTop: '1rem', fontSize: '0.75rem', color: 'var(--vz-text-muted)' }}>
                    Last password change: <strong style={{ color: 'var(--vz-text-primary)' }}>{new Date(user.security.lastPasswordChange).toLocaleDateString('en-IN', { dateStyle: 'long' })}</strong>
                </div>
            )}
        </div>
    );

    const tabRenderers = [renderBasicInfo, renderProfile, renderPreferences, renderSecurity];

    return (
        <div style={overlay} onClick={onClose}>
            <div className="vz-card" style={panel} onClick={e => e.stopPropagation()}>
                {/* Header */}
                <div className="vz-card-header" style={{ padding: '0.875rem 1.25rem' }}>
                    <h6 className="vz-card-title" style={{ margin: 0, fontSize: '1rem' }}>
                        {user ? 'Edit User' : 'Add New User'}
                    </h6>
                    <button className="vz-btn-icon" onClick={onClose}><BiX /></button>
                </div>

                {/* Tab Bar */}
                <div style={{
                    display: 'flex', gap: 0, borderBottom: '1px solid var(--vz-border-color)',
                    overflowX: 'auto', flexShrink: 0, background: 'var(--vz-card-bg)',
                }}>
                    {TAB_CONFIG.map((tab, idx) => (
                        <button
                            key={tab.key}
                            onClick={() => setActiveTab(idx)}
                            style={{
                                display: 'flex', alignItems: 'center', gap: '0.375rem',
                                padding: '0.625rem 0.875rem',
                                fontSize: '0.75rem', fontWeight: activeTab === idx ? 700 : 500,
                                color: activeTab === idx ? 'var(--vz-primary)' : 'var(--vz-text-muted)',
                                background: 'none', border: 'none',
                                borderBottom: activeTab === idx ? '2px solid var(--vz-primary)' : '2px solid transparent',
                                cursor: 'pointer', fontFamily: 'var(--vz-font)',
                                whiteSpace: 'nowrap', transition: 'all 0.2s ease',
                            }}
                        >
                            <span style={{ fontSize: '0.875rem', display: 'flex' }}>{tab.icon}</span>
                            {tab.label}
                            {idx < activeTab && <BiCheckCircle style={{ fontSize: '0.75rem', color: 'var(--vz-success)' }} />}
                        </button>
                    ))}
                </div>

                {/* Body */}
                <div style={{ flex: 1, overflowY: 'auto', padding: '1.25rem', overflowX: 'hidden' }}>
                    {tabRenderers[activeTab]()}
                </div>

                {/* Footer */}
                <div style={{
                    display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                    padding: '0.75rem 1.25rem', borderTop: '1px solid var(--vz-border-color)',
                    background: 'var(--vz-card-bg)', flexShrink: 0,
                }}>
                    <div style={{ display: 'flex', gap: '0.5rem' }}>
                        {activeTab > 0 && (
                            <button className="vz-btn vz-btn-outline vz-btn-sm" onClick={() => setActiveTab(prev => prev - 1)}>
                                <BiChevronLeft /> Prev
                            </button>
                        )}
                    </div>
                    <div style={{ fontSize: '0.6875rem', color: 'var(--vz-text-muted)' }}>
                        Step {activeTab + 1} of {TAB_CONFIG.length}
                    </div>
                    <div style={{ display: 'flex', gap: '0.5rem' }}>
                        <button type="button" className="vz-btn vz-btn-outline vz-btn-sm" onClick={onClose}>Cancel</button>
                        {activeTab < TAB_CONFIG.length - 1 ? (
                            <button className="vz-btn vz-btn-primary vz-btn-sm" onClick={() => setActiveTab(prev => prev + 1)}>
                                Next <BiChevronRight />
                            </button>
                        ) : (
                            <button className="vz-btn vz-btn-primary vz-btn-sm" onClick={handleSubmit}>
                                <BiSave /> {user ? 'Update' : 'Save'} User
                            </button>
                        )}
                    </div>
                </div>
            </div>
        </div>
    );
};

export default UserForm;
