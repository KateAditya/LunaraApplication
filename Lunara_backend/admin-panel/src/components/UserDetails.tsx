import React, { useState } from 'react';
import {
    BiX, BiCalendar, BiPhone, BiEnvelope,
    BiShield, BiCheck, BiShieldQuarter, BiUser,
    BiIdCard, BiBlock
} from 'react-icons/bi';
import type { User } from '../types/user';

interface UserDetailsProps {
    user: User;
    onClose: () => void;
}

/* ═════════ Mini Components ═════════ */

const Badge: React.FC<{ label: string; color: string; bg: string }> = ({ label, color, bg }) => (
    <span style={{
        display: 'inline-block', padding: '0.1875rem 0.625rem', borderRadius: '999px',
        fontSize: '0.6875rem', fontWeight: 600, color, background: bg,
    }}>{label}</span>
);

const DetailRow: React.FC<{ icon: React.ReactNode; label: string; value?: string | number | null }> = ({ icon, label, value }) => {
    if (!value && value !== 0) return null;
    return (
        <div style={{ display: 'flex', alignItems: 'flex-start', gap: '0.625rem', marginBottom: '0.625rem' }}>
            <span style={{ fontSize: '0.875rem', color: 'var(--vz-text-muted)', marginTop: 1, flexShrink: 0, display: 'flex' }}>{icon}</span>
            <div>
                <div style={{ fontSize: '0.6875rem', color: 'var(--vz-text-muted)', textTransform: 'uppercase', letterSpacing: '0.03em' }}>{label}</div>
                <div style={{ fontSize: '0.8125rem', color: 'var(--vz-text-primary)', fontWeight: 500 }}>{value}</div>
            </div>
        </div>
    );
};

/* ═════════ STYLES ═════════ */
const overlay: React.CSSProperties = { position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.6)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 1080, backdropFilter: 'blur(4px)' };
const panel: React.CSSProperties = { width: '100%', maxWidth: 780, maxHeight: '92vh', display: 'flex', flexDirection: 'column', borderRadius: 'var(--vz-radius-lg)', overflow: 'hidden', boxShadow: '0 8px 40px rgba(0,0,0,0.25)' };
const sectionTitle: React.CSSProperties = { fontSize: '0.8125rem', fontWeight: 700, color: 'var(--vz-primary)', textTransform: 'uppercase', letterSpacing: '0.04em', marginBottom: '0.75rem', marginTop: '1rem' };
const thStyle: React.CSSProperties = { padding: '0.5rem 0.75rem', textAlign: 'left' as const, fontWeight: 600, color: 'var(--vz-text-muted)', textTransform: 'uppercase' as const, fontSize: '0.625rem' };
const tdStyle: React.CSSProperties = { padding: '0.5rem 0.75rem', color: 'var(--vz-text-primary)', fontSize: '0.75rem' };

const TABS = [
    { key: 'profile', label: 'Profile' },
    { key: 'identity', label: 'Identity & Social' },
    { key: 'history', label: 'History' },
    { key: 'security', label: 'Security' },
];

const roleColors: Record<string, { color: string; bg: string }> = {
    customer: { color: 'var(--vz-primary)', bg: 'rgba(var(--vz-primary-rgb), 0.1)' },
    venue_owner: { color: '#a855f7', bg: 'rgba(168,85,247,0.1)' },
    admin: { color: '#ef4444', bg: 'rgba(239,68,68,0.1)' },
    promoter: { color: '#f59e0b', bg: 'rgba(245,158,11,0.1)' },
};

export const UserDetails: React.FC<UserDetailsProps> = ({ user, onClose }) => {
    const [activeTab, setActiveTab] = useState(0);
    const rBadge = roleColors[user.role] || roleColors.customer;

    /* ─── Tab renderers ─── */

    const renderProfile = () => (
        <div>
            {/* Avatar + Name Header */}
            <div style={{ display: 'flex', alignItems: 'center', gap: '1rem', marginBottom: '1.25rem' }}>
                {user.avatarUrl ? (
                    <img src={user.avatarUrl} alt={`${user.firstName} ${user.lastName}`}
                        style={{ width: 64, height: 64, borderRadius: '50%', objectFit: 'cover', border: '3px solid var(--vz-primary)' }} />
                ) : (
                    <div style={{
                        width: 64, height: 64, borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center',
                        background: 'rgba(var(--vz-primary-rgb), 0.1)', color: 'var(--vz-primary)', fontSize: '1.5rem', fontWeight: 700,
                    }}>{user.firstName[0]}{user.lastName[0]}</div>
                )}
                <div>
                    <h5 style={{ margin: 0, fontSize: '1.25rem', fontWeight: 700, color: 'var(--vz-text-primary)' }}>
                        {user.firstName} {user.lastName}
                    </h5>
                    <div style={{ display: 'flex', gap: '0.375rem', marginTop: '0.25rem', flexWrap: 'wrap' }}>
                        <Badge label={user.role.replace('_', ' ').replace(/\b\w/g, l => l.toUpperCase())} color={rBadge.color} bg={rBadge.bg} />
                        {user.isActive ? <Badge label="● Active" color="var(--vz-success)" bg="rgba(var(--vz-success-rgb), 0.08)" /> : <Badge label="○ Inactive" color="var(--vz-danger)" bg="rgba(var(--vz-danger-rgb), 0.08)" />}
                        {user.isAutoblocked && <Badge label="⚠ Autoblocked" color="#ffffff" bg="#e6533c" />}
                    </div>
                </div>
            </div>

            {/* Contact Info */}
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.5rem' }}>
                <DetailRow icon={<BiEnvelope />} label="Email" value={user.email} />
                <DetailRow icon={<BiPhone />} label="Phone" value={user.phone} />
                <DetailRow icon={<BiBlock />} label="Block Count" value={user.blockCount ?? 0} />
                {user.isAutoblocked && <DetailRow icon={<BiShield />} label="Autoblock Reason" value={user.autoblockedReason || 'safety reports/guidelines violation'} />}
            </div>

            {/* Verification Flags */}
            <div style={sectionTitle}>Verification Status</div>
            <div style={{ display: 'flex', gap: '0.625rem', flexWrap: 'wrap' }}>
                {[
                    { key: user.isVerified, label: 'Account Verified' },
                    { key: user.isPhoneVerified, label: 'Phone Verified' },
                    { key: user.isEmailVerified, label: 'Email Verified' },
                ].map((item, i) => (
                    <div key={i} style={{
                        display: 'flex', alignItems: 'center', gap: '0.375rem',
                        padding: '0.375rem 0.75rem', borderRadius: '999px',
                        border: `1.5px solid ${item.key ? 'var(--vz-success)' : 'var(--vz-border-color)'}`,
                        background: item.key ? 'rgba(var(--vz-success-rgb), 0.06)' : 'transparent',
                        fontSize: '0.75rem', fontWeight: 500,
                        color: item.key ? 'var(--vz-success)' : 'var(--vz-text-muted)',
                    }}>
                        {item.key ? <BiCheck /> : '○'} {item.label}
                    </div>
                ))}
            </div>

            {/* Dates */}
            <div style={sectionTitle}>Account Dates</div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: '0.5rem' }}>
                <DetailRow icon={<BiCalendar />} label="Created" value={new Date(user.createdAt).toLocaleDateString('en-IN', { dateStyle: 'medium' })} />
                <DetailRow icon={<BiCalendar />} label="Updated" value={new Date(user.updatedAt).toLocaleDateString('en-IN', { dateStyle: 'medium' })} />
                <DetailRow icon={<BiCalendar />} label="Last Login" value={user.lastLoginAt ? new Date(user.lastLoginAt).toLocaleDateString('en-IN', { dateStyle: 'medium' }) : 'Never'} />
            </div>
        </div>
    );

    const renderIdentitySocial = () => (
        <div>
            <div style={sectionTitle}>Identity</div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: '0.5rem' }}>
                <DetailRow icon={<BiCalendar />} label="Date of Birth" value={user.identity.dob ? new Date(user.identity.dob).toLocaleDateString('en-IN', { dateStyle: 'long' }) : undefined} />
                <DetailRow icon={<BiUser />} label="Gender" value={user.identity.gender.charAt(0).toUpperCase() + user.identity.gender.slice(1)} />
                <DetailRow icon={<BiIdCard />} label="Nationality" value={user.identity.nationality} />
            </div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.5rem' }}>
                <DetailRow icon={<BiShield />} label="PAN Number" value={user.identity.panNumber} />
                <DetailRow icon={<BiShield />} label="Aadhaar" value={user.identity.aadhaarNumber} />
            </div>

            <div style={sectionTitle}>Bio</div>
            {user.social.bio && <p style={{ fontSize: '0.8125rem', color: 'var(--vz-text-secondary)', lineHeight: 1.6, marginBottom: '0.75rem' }}>{user.social.bio}</p>}

            {/* Profile Photos */}
            {user.social.profilePhotos && user.social.profilePhotos.length > 0 && (
                <div style={{ marginBottom: '0.75rem' }}>
                    <div style={{ fontSize: '0.6875rem', color: 'var(--vz-text-muted)', textTransform: 'uppercase', letterSpacing: '0.03em', marginBottom: '0.375rem' }}>Profile Photos</div>
                    <div style={{ display: 'flex', gap: '0.5rem', overflowX: 'auto' }}>
                        {user.social.profilePhotos.map((p: string, i: number) => (
                            <img key={i} src={p} alt={`Photo ${i + 1}`}
                                style={{ width: 80, height: 100, objectFit: 'cover', borderRadius: 'var(--vz-radius)', flexShrink: 0 }} />
                        ))}
                    </div>
                </div>
            )}

            {/* Interests */}
            {user.social.interests && user.social.interests.length > 0 && (
                <div style={{ marginBottom: '0.75rem' }}>
                    <div style={{ fontSize: '0.6875rem', color: 'var(--vz-text-muted)', textTransform: 'uppercase', letterSpacing: '0.03em', marginBottom: '0.375rem' }}>Interests</div>
                    <div style={{ display: 'flex', gap: '0.25rem', flexWrap: 'wrap' }}>
                        {user.social.interests.map((i: string) => (
                            <span key={i} style={{ padding: '0.125rem 0.5rem', borderRadius: '999px', fontSize: '0.625rem', background: 'rgba(var(--vz-primary-rgb), 0.08)', color: 'var(--vz-primary)', fontWeight: 500 }}>{i}</span>
                        ))}
                    </div>
                </div>
            )}

            {/* Vibes */}
            {user.social.vibes && user.social.vibes.length > 0 && (
                <div style={{ marginBottom: '0.75rem' }}>
                    <div style={{ fontSize: '0.6875rem', color: 'var(--vz-text-muted)', textTransform: 'uppercase', letterSpacing: '0.03em', marginBottom: '0.375rem' }}>Vibes</div>
                    <div style={{ display: 'flex', gap: '0.25rem', flexWrap: 'wrap' }}>
                        {user.social.vibes.map((v: string) => (
                            <span key={v} style={{ padding: '0.125rem 0.5rem', borderRadius: '999px', fontSize: '0.625rem', background: 'rgba(var(--vz-success-rgb), 0.08)', color: 'var(--vz-success)', fontWeight: 500 }}>{v}</span>
                        ))}
                    </div>
                </div>
            )}

            {/* Languages */}
            {user.social.languages && user.social.languages.length > 0 && (
                <div>
                    <div style={{ fontSize: '0.6875rem', color: 'var(--vz-text-muted)', textTransform: 'uppercase', letterSpacing: '0.03em', marginBottom: '0.375rem' }}>Languages</div>
                    <div style={{ display: 'flex', gap: '0.25rem', flexWrap: 'wrap' }}>
                        {user.social.languages.map((l: string) => (
                            <span key={l} style={{ padding: '0.125rem 0.5rem', borderRadius: '999px', fontSize: '0.625rem', background: 'rgba(168,85,247,0.08)', color: '#a855f7', fontWeight: 500 }}>{l}</span>
                        ))}
                    </div>
                </div>
            )}
        </div>
    );

    const renderHistory = () => (
        <div>
            {/* Bookings */}
            <div style={sectionTitle}>Booking History</div>
            {user.history.bookings.length === 0 ? (
                <p style={{ fontSize: '0.8125rem', color: 'var(--vz-text-muted)' }}>No bookings yet.</p>
            ) : (
                <div style={{ borderRadius: 'var(--vz-radius)', border: '1px solid var(--vz-border-color)', overflow: 'hidden', marginBottom: '1rem' }}>
                    <table style={{ width: '100%', borderCollapse: 'collapse' }}>
                        <thead>
                            <tr style={{ background: 'var(--vz-border-color)' }}>
                                <th style={thStyle}>Venue</th>
                                <th style={thStyle}>Date</th>
                                <th style={thStyle}>Status</th>
                                <th style={thStyle}>Amount</th>
                            </tr>
                        </thead>
                        <tbody>
                            {user.history.bookings.map(b => (
                                <tr key={b.id} style={{ borderTop: '1px solid var(--vz-border-color)' }}>
                                    <td style={tdStyle}>{b.venueName}</td>
                                    <td style={tdStyle}>{new Date(b.date).toLocaleDateString('en-IN', { dateStyle: 'medium' })}</td>
                                    <td style={tdStyle}>
                                        <Badge
                                            label={b.status}
                                            color={b.status === 'completed' ? 'var(--vz-success)' : b.status === 'cancelled' ? 'var(--vz-danger)' : '#f59e0b'}
                                            bg={b.status === 'completed' ? 'rgba(var(--vz-success-rgb), 0.1)' : b.status === 'cancelled' ? 'rgba(var(--vz-danger-rgb), 0.1)' : 'rgba(245,158,11,0.1)'}
                                        />
                                    </td>
                                    <td style={tdStyle}>₹{b.amount.toLocaleString()}</td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>
            )}

            {/* Payments */}
            <div style={sectionTitle}>Payment History</div>
            {user.history.payments.length === 0 ? (
                <p style={{ fontSize: '0.8125rem', color: 'var(--vz-text-muted)' }}>No payments yet.</p>
            ) : (
                <div style={{ borderRadius: 'var(--vz-radius)', border: '1px solid var(--vz-border-color)', overflow: 'hidden', marginBottom: '1rem' }}>
                    <table style={{ width: '100%', borderCollapse: 'collapse' }}>
                        <thead>
                            <tr style={{ background: 'var(--vz-border-color)' }}>
                                <th style={thStyle}>Amount</th>
                                <th style={thStyle}>Status</th>
                                <th style={thStyle}>Date</th>
                                <th style={thStyle}>Method</th>
                            </tr>
                        </thead>
                        <tbody>
                            {user.history.payments.map(p => (
                                <tr key={p.id} style={{ borderTop: '1px solid var(--vz-border-color)' }}>
                                    <td style={tdStyle}>₹{p.amount.toLocaleString()}</td>
                                    <td style={tdStyle}>
                                        <Badge label={p.status} color={p.status === 'success' ? 'var(--vz-success)' : 'var(--vz-danger)'} bg={p.status === 'success' ? 'rgba(var(--vz-success-rgb), 0.1)' : 'rgba(var(--vz-danger-rgb), 0.1)'} />
                                    </td>
                                    <td style={tdStyle}>{new Date(p.date).toLocaleDateString('en-IN', { dateStyle: 'medium' })}</td>
                                    <td style={tdStyle}>{p.method}</td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>
            )}

            {/* Reviews */}
            <div style={sectionTitle}>Reviews Written</div>
            {user.history.reviews.length === 0 ? (
                <p style={{ fontSize: '0.8125rem', color: 'var(--vz-text-muted)' }}>No reviews yet.</p>
            ) : (
                <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem' }}>
                    {user.history.reviews.map(r => (
                        <div key={r.id} style={{ padding: '0.75rem', borderRadius: 'var(--vz-radius)', border: '1px solid var(--vz-border-color)' }}>
                            <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '0.25rem' }}>
                                <span style={{ fontSize: '0.8125rem', fontWeight: 600, color: 'var(--vz-text-primary)' }}>{r.venueName}</span>
                                <span style={{ fontSize: '0.75rem', color: '#f59e0b', fontWeight: 600 }}>
                                    {'★'.repeat(r.rating)}{'☆'.repeat(5 - r.rating)}
                                </span>
                            </div>
                            <p style={{ fontSize: '0.75rem', color: 'var(--vz-text-secondary)', margin: 0 }}>{r.comment}</p>
                            <div style={{ fontSize: '0.625rem', color: 'var(--vz-text-muted)', marginTop: '0.25rem' }}>
                                {new Date(r.date).toLocaleDateString('en-IN', { dateStyle: 'medium' })}
                            </div>
                        </div>
                    ))}
                </div>
            )}
        </div>
    );

    const renderSecurity = () => (
        <div>
            <div style={sectionTitle}>Authentication</div>
            <div style={{ display: 'flex', gap: '0.625rem', marginBottom: '1rem', flexWrap: 'wrap' }}>
                <div style={{
                    display: 'flex', alignItems: 'center', gap: '0.375rem',
                    padding: '0.375rem 0.75rem', borderRadius: '999px',
                    border: `1.5px solid ${user.security.mfaEnabled ? 'var(--vz-success)' : 'var(--vz-border-color)'}`,
                    background: user.security.mfaEnabled ? 'rgba(var(--vz-success-rgb), 0.06)' : 'transparent',
                    fontSize: '0.75rem', fontWeight: 500,
                    color: user.security.mfaEnabled ? 'var(--vz-success)' : 'var(--vz-text-muted)',
                }}>
                    <BiShieldQuarter /> MFA: {user.security.mfaEnabled ? 'Enabled' : 'Disabled'}
                </div>
                <div style={{
                    display: 'flex', alignItems: 'center', gap: '0.375rem',
                    padding: '0.375rem 0.75rem', borderRadius: '999px',
                    border: `1.5px solid ${user.security.forcePasswordChange ? '#f59e0b' : 'var(--vz-border-color)'}`,
                    background: user.security.forcePasswordChange ? 'rgba(245,158,11,0.06)' : 'transparent',
                    fontSize: '0.75rem', fontWeight: 500,
                    color: user.security.forcePasswordChange ? '#f59e0b' : 'var(--vz-text-muted)',
                }}>
                    Force Password Change: {user.security.forcePasswordChange ? 'Yes' : 'No'}
                </div>
            </div>
            <DetailRow icon={<BiCalendar />} label="Last Password Change" value={user.security.lastPasswordChange ? new Date(user.security.lastPasswordChange).toLocaleDateString('en-IN', { dateStyle: 'long' }) : 'Unknown'} />

            <div style={sectionTitle}>Login History</div>
            {user.security.loginHistory.length === 0 ? (
                <p style={{ fontSize: '0.8125rem', color: 'var(--vz-text-muted)' }}>No login records.</p>
            ) : (
                <div style={{ borderRadius: 'var(--vz-radius)', border: '1px solid var(--vz-border-color)', overflow: 'hidden' }}>
                    <table style={{ width: '100%', borderCollapse: 'collapse' }}>
                        <thead>
                            <tr style={{ background: 'var(--vz-border-color)' }}>
                                <th style={thStyle}>Timestamp</th>
                                <th style={thStyle}>IP Address</th>
                                <th style={thStyle}>Device</th>
                                <th style={thStyle}>Location</th>
                            </tr>
                        </thead>
                        <tbody>
                            {user.security.loginHistory.map((entry, idx) => (
                                <tr key={idx} style={{ borderTop: '1px solid var(--vz-border-color)' }}>
                                    <td style={tdStyle}>{new Date(entry.timestamp).toLocaleString('en-IN', { dateStyle: 'medium', timeStyle: 'short' })}</td>
                                    <td style={{ ...tdStyle, fontFamily: 'monospace', fontSize: '0.6875rem' }}>{entry.ip}</td>
                                    <td style={tdStyle}>{entry.device}</td>
                                    <td style={tdStyle}>{entry.location}</td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>
            )}
        </div>
    );

    const tabRenderers = [renderProfile, renderIdentitySocial, renderHistory, renderSecurity];

    return (
        <div style={overlay} onClick={onClose}>
            <div className="vz-card" style={panel} onClick={e => e.stopPropagation()}>
                {/* Header */}
                <div className="vz-card-header" style={{ padding: '0.875rem 1.25rem' }}>
                    <h6 className="vz-card-title" style={{ margin: 0, fontSize: '1rem' }}>User Details</h6>
                    <button className="vz-btn-icon" onClick={onClose}><BiX /></button>
                </div>

                {/* Tab Bar */}
                <div style={{
                    display: 'flex', gap: 0, borderBottom: '1px solid var(--vz-border-color)',
                    overflowX: 'auto', flexShrink: 0, background: 'var(--vz-card-bg)',
                }}>
                    {TABS.map((tab, idx) => (
                        <button
                            key={tab.key}
                            onClick={() => setActiveTab(idx)}
                            style={{
                                padding: '0.625rem 1rem',
                                fontSize: '0.75rem', fontWeight: activeTab === idx ? 700 : 500,
                                color: activeTab === idx ? 'var(--vz-primary)' : 'var(--vz-text-muted)',
                                background: 'none', border: 'none',
                                borderBottom: activeTab === idx ? '2px solid var(--vz-primary)' : '2px solid transparent',
                                cursor: 'pointer', fontFamily: 'var(--vz-font)',
                                whiteSpace: 'nowrap', transition: 'all 0.2s ease',
                            }}
                        >{tab.label}</button>
                    ))}
                </div>

                {/* Body */}
                <div style={{ flex: 1, overflowY: 'auto', padding: '1.25rem', overflowX: 'hidden' }}>
                    {tabRenderers[activeTab]()}
                </div>

                {/* Footer */}
                <div style={{
                    display: 'flex', justifyContent: 'flex-end',
                    padding: '0.75rem 1.25rem', borderTop: '1px solid var(--vz-border-color)',
                    background: 'var(--vz-card-bg)', flexShrink: 0,
                }}>
                    <button className="vz-btn vz-btn-outline vz-btn-sm" onClick={onClose}>Close</button>
                </div>
            </div>
        </div>
    );
};

export default UserDetails;
