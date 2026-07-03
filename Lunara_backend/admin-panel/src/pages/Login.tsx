import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { BiShow, BiHide } from 'react-icons/bi';
import { useAuthStore } from '../store/authStore';
import { authApi } from '../api/auth';
import toast from 'react-hot-toast';

export const Login: React.FC = () => {
    const navigate = useNavigate();
    const { setAuth } = useAuthStore();
    const [email, setEmail] = useState('');
    const [password, setPassword] = useState('');
    const [showPassword, setShowPassword] = useState(false);
    const [loading, setLoading] = useState(false);
    const [rememberMe, setRememberMe] = useState(false);

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!email || !password) {
            toast.error('Please fill in all fields');
            return;
        }
        setLoading(true);
        try {
            const response = await authApi.login({ email, password });
            setAuth(response.data.user, response.data.accessToken, response.data.refreshToken);
            toast.success('Welcome back!');
            navigate('/');
        } catch (error: any) {
            toast.error(error.response?.data?.message || 'Login failed');
        } finally {
            setLoading(false);
        }
    };

    const handleDemoLogin = () => {
        const mockUser = {
            id: 'demo-admin-001',
            email: 'admin@lunara.com',
            firstName: 'Admin',
            lastName: 'User',
            role: 'admin',
        };
        setAuth(mockUser, 'demo-access-token', 'demo-refresh-token');
        toast.success('Welcome to Lunara Demo!');
        navigate('/');
    };

    return (
        <div className="login-cover">
            {/* Left Side - Cover */}
            <div className="login-cover-left">
                <div className="shape shape-1" />
                <div className="shape shape-2" />
                <div className="shape shape-3" />
                <div className="cover-content">
                    <div style={{
                        width: 64,
                        height: 64,
                        borderRadius: 16,
                        background: 'rgba(255,255,255,0.15)',
                        backdropFilter: 'blur(10px)',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        margin: '0 auto 1.5rem',
                        border: '1px solid rgba(255,255,255,0.2)',
                    }}>
                        <span style={{ fontSize: '1.75rem', fontWeight: 700, color: '#fff' }}>L</span>
                    </div>
                    <h1 className="cover-title">LUNARA</h1>
                    <p className="cover-subtitle">
                        Nightlife Discovery & Booking Platform.<br />
                        Manage venues, users, bookings and analytics from a single dashboard.
                    </p>
                    <div style={{
                        display: 'flex',
                        gap: '0.75rem',
                        justifyContent: 'center',
                        marginTop: '2rem',
                    }}>
                        {['2.5K+ Users', '150+ Venues', '99.9% Uptime'].map((stat) => (
                            <div key={stat} style={{
                                padding: '0.5rem 1rem',
                                background: 'rgba(255,255,255,0.1)',
                                borderRadius: 8,
                                border: '1px solid rgba(255,255,255,0.15)',
                                backdropFilter: 'blur(10px)',
                            }}>
                                <span style={{ fontSize: '0.75rem', fontWeight: 600, color: '#fff' }}>{stat}</span>
                            </div>
                        ))}
                    </div>
                </div>
            </div>

            {/* Right Side - Form */}
            <div className="login-cover-right">
                <div className="login-form-wrapper">
                    <div className="login-form-brand">
                        <div style={{
                            width: 38,
                            height: 38,
                            borderRadius: 10,
                            background: 'linear-gradient(135deg, #845adf, #6d28d9)',
                            display: 'flex',
                            alignItems: 'center',
                            justifyContent: 'center',
                            color: '#fff',
                            fontWeight: 700,
                            fontSize: '0.875rem',
                        }}>L</div>
                        <span style={{
                            fontSize: '1.125rem',
                            fontWeight: 700,
                            color: 'var(--vz-text-primary)',
                            letterSpacing: '-0.02em',
                        }}>LUNARA</span>
                    </div>

                    <h2 className="login-form-title">Sign In</h2>
                    <p className="login-form-subtitle">Welcome back! Please sign in to continue.</p>

                    <form onSubmit={handleSubmit}>
                        <div className="vz-form-group">
                            <label className="vz-form-label">Email Address</label>
                            <input
                                type="email"
                                className="vz-form-control"
                                placeholder="admin@lunara.com"
                                value={email}
                                onChange={(e) => setEmail(e.target.value)}
                                autoComplete="email"
                            />
                        </div>

                        <div className="vz-form-group">
                            <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '0.375rem' }}>
                                <label className="vz-form-label" style={{ marginBottom: 0 }}>Password</label>
                                <a href="#" style={{
                                    fontSize: '0.75rem',
                                    color: 'var(--vz-primary)',
                                    textDecoration: 'none',
                                }}>Forgot Password?</a>
                            </div>
                            <div style={{ position: 'relative' }}>
                                <input
                                    type={showPassword ? 'text' : 'password'}
                                    className="vz-form-control"
                                    placeholder="Enter your password"
                                    value={password}
                                    onChange={(e) => setPassword(e.target.value)}
                                    autoComplete="current-password"
                                    style={{ paddingRight: '2.5rem' }}
                                />
                                <button
                                    type="button"
                                    onClick={() => setShowPassword(!showPassword)}
                                    style={{
                                        position: 'absolute',
                                        right: '0.75rem',
                                        top: '50%',
                                        transform: 'translateY(-50%)',
                                        border: 'none',
                                        background: 'none',
                                        color: 'var(--vz-text-muted)',
                                        cursor: 'pointer',
                                        fontSize: '1.125rem',
                                        display: 'flex',
                                        padding: 0,
                                    }}
                                >
                                    {showPassword ? <BiHide /> : <BiShow />}
                                </button>
                            </div>
                        </div>

                        <div style={{
                            display: 'flex',
                            alignItems: 'center',
                            gap: '0.5rem',
                            marginBottom: '1.25rem',
                        }}>
                            <input
                                type="checkbox"
                                id="rememberMe"
                                checked={rememberMe}
                                onChange={(e) => setRememberMe(e.target.checked)}
                                style={{
                                    width: 16,
                                    height: 16,
                                    accentColor: 'var(--vz-primary)',
                                    cursor: 'pointer',
                                }}
                            />
                            <label
                                htmlFor="rememberMe"
                                style={{
                                    fontSize: '0.8125rem',
                                    color: 'var(--vz-text-secondary)',
                                    cursor: 'pointer',
                                }}
                            >
                                Remember me
                            </label>
                        </div>

                        <button
                            type="submit"
                            className="vz-btn vz-btn-primary"
                            disabled={loading}
                            style={{
                                width: '100%',
                                justifyContent: 'center',
                                padding: '0.625rem',
                                fontSize: '0.875rem',
                                fontWeight: 600,
                            }}
                        >
                            {loading ? 'Signing in...' : 'Sign In'}
                        </button>
                    </form>

                    <div style={{
                        display: 'flex',
                        alignItems: 'center',
                        gap: '0.75rem',
                        margin: '1.25rem 0',
                    }}>
                        <div style={{ flex: 1, height: 1, background: 'var(--vz-border-color, #e9edf4)' }} />
                        <span style={{ fontSize: '0.75rem', color: 'var(--vz-text-muted)', fontWeight: 500 }}>OR</span>
                        <div style={{ flex: 1, height: 1, background: 'var(--vz-border-color, #e9edf4)' }} />
                    </div>

                    <button
                        type="button"
                        onClick={handleDemoLogin}
                        style={{
                            width: '100%',
                            justifyContent: 'center',
                            padding: '0.625rem',
                            fontSize: '0.875rem',
                            fontWeight: 600,
                            border: '1.5px solid var(--vz-primary, #845adf)',
                            borderRadius: '0.375rem',
                            background: 'transparent',
                            color: 'var(--vz-primary, #845adf)',
                            cursor: 'pointer',
                            display: 'flex',
                            alignItems: 'center',
                            gap: '0.5rem',
                            transition: 'all 0.2s ease',
                        }}
                        onMouseEnter={(e) => {
                            e.currentTarget.style.background = 'var(--vz-primary, #845adf)';
                            e.currentTarget.style.color = '#fff';
                        }}
                        onMouseLeave={(e) => {
                            e.currentTarget.style.background = 'transparent';
                            e.currentTarget.style.color = 'var(--vz-primary, #845adf)';
                        }}
                    >
                        🚀 Demo Login (No Backend Required)
                    </button>

                    <p style={{
                        textAlign: 'center',
                        marginTop: '1.5rem',
                        fontSize: '0.8125rem',
                        color: 'var(--vz-text-muted)',
                    }}>
                        Don't have an account?{' '}
                        <a href="#" style={{ color: 'var(--vz-primary)', textDecoration: 'none', fontWeight: 600 }}>
                            Sign Up
                        </a>
                    </p>
                </div>
            </div>
        </div>
    );
};

export default Login;
