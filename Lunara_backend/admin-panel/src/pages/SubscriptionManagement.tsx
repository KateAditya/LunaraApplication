import React, { useEffect, useState } from 'react';
import { 
    BiPlus, BiPencil, BiTrash, BiCopy, BiArchive, 
    BiCheckCircle, BiRefresh, BiDollar, BiUserCheck, 
    BiTrendingUp, BiCrown, 
    BiSlider, BiTrendingDown, BiCalendar
} from 'react-icons/bi';
import { 
    subscriptionsApi, 
    type SubscriptionPlan, 
    type SubscriptionFeature, 
    type PlanFeature, 
    type SubscriptionTransaction, 
    type AnalyticsOverview 
} from '../api/subscriptions';
import { useThemeMode } from '../context/ThemeContext';

export const SubscriptionManagement: React.FC = () => {
    const { mode } = useThemeMode();
    const isDark = mode === 'dark';

    // State
    const [activeTab, setActiveTab] = useState<'analytics' | 'plans' | 'features' | 'transactions' | 'users'>('analytics');
    const [plans, setPlans] = useState<SubscriptionPlan[]>([]);
    const [features, setFeatures] = useState<SubscriptionFeature[]>([]);
    const [transactions, setTransactions] = useState<SubscriptionTransaction[]>([]);
    const [analytics, setAnalytics] = useState<AnalyticsOverview | null>(null);
    const [loading, setLoading] = useState(true);

    // Subscribed Users State
    const [subscribedUsers, setSubscribedUsers] = useState<any[]>([]);
    const [usersPage, setUsersPage] = useState(1);
    const [usersTotalPages, setUsersTotalPages] = useState(1);
    const [usersLoading, setUsersLoading] = useState(false);

    // Extend / Expire Modals State
    const [showExtendModal, setShowExtendModal] = useState(false);
    const [showExpireModal, setShowExpireModal] = useState(false);
    const [selectedUser, setSelectedUser] = useState<any | null>(null);
    const [actionDays, setActionDays] = useState<number>(30);
    const [actionReason, setActionReason] = useState<string>('');

    // Pagination/Filters for Transactions
    const [txPage, setTxPage] = useState(1);
    const [txTotalPages, setTxTotalPages] = useState(1);
    const [txStatus, setTxStatus] = useState('');
    const [txType, setTxType] = useState('');

    // Modal state
    const [showPlanModal, setShowPlanModal] = useState(false);
    const [editingPlan, setEditingPlan] = useState<Partial<SubscriptionPlan> | null>(null);
    const [showFeatureMatrixPlan, setShowFeatureMatrixPlan] = useState<SubscriptionPlan | null>(null);
    const [matrixFeatures, setMatrixFeatures] = useState<PlanFeature[]>([]);

    useEffect(() => {
        fetchInitialData();
    }, []);

    useEffect(() => {
        if (activeTab === 'transactions') {
            fetchTransactions();
        }
    }, [activeTab, txPage, txStatus, txType]);

    useEffect(() => {
        if (activeTab === 'users') {
            fetchSubscribedUsers();
        }
    }, [activeTab, usersPage]);

    const fetchInitialData = async () => {
        setLoading(true);
        try {
            const [plansRes, featuresRes, analyticsRes] = await Promise.all([
                subscriptionsApi.getPlans(),
                subscriptionsApi.getFeatures(),
                subscriptionsApi.getAnalytics()
            ]);

            if (plansRes.success) setPlans(plansRes.data);
            if (featuresRes.success) setFeatures(featuresRes.data);
            if (analyticsRes.success) setAnalytics(analyticsRes.data);
        } catch (error) {
            console.error('Error fetching subscription data:', error);
        } finally {
            setLoading(false);
        }
    };

    const fetchTransactions = async () => {
        try {
            const res = await subscriptionsApi.getTransactions({
                page: txPage,
                limit: 10,
                status: txStatus,
                type: txType
            });
            if (res.success) {
                setTransactions(res.data.transactions);
                setTxTotalPages(res.data.pagination.totalPages);
            }
        } catch (error) {
            console.error('Error fetching transactions:', error);
        }
    };

    const fetchSubscribedUsers = async () => {
        setUsersLoading(true);
        try {
            const res = await subscriptionsApi.getSubscribedUsers({
                page: usersPage,
                limit: 10
            });
            if (res.success) {
                setSubscribedUsers(res.data.subscriptions);
                setUsersTotalPages(res.data.pagination.totalPages);
            }
        } catch (error) {
            console.error('Error fetching subscribed users:', error);
        } finally {
            setUsersLoading(false);
        }
    };

    const handleForceExpire = async (userId: string, reason: string) => {
        try {
            const res = await subscriptionsApi.forceExpireUserSubscription(userId, reason);
            if (res.success) {
                alert('Subscription force-expired successfully.');
                setShowExpireModal(false);
                setActionReason('');
                fetchSubscribedUsers();
            }
        } catch (error: any) {
            alert(error.response?.data?.message || 'Failed to force-expire subscription.');
        }
    };

    const handleExtend = async (userId: string, days: number, reason: string) => {
        try {
            const res = await subscriptionsApi.extendUserSubscription(userId, days, reason);
            if (res.success) {
                alert(`Subscription extended successfully by ${days} days.`);
                setShowExtendModal(false);
                setActionReason('');
                fetchSubscribedUsers();
            }
        } catch (error: any) {
            alert(error.response?.data?.message || 'Failed to extend subscription.');
        }
    };

    // Styling
    const colors = {
        bg: isDark ? '#000000' : '#f8f9fa',
        cardBg: isDark ? 'rgba(255, 255, 255, 0.05)' : '#ffffff',
        border: isDark ? 'rgba(255, 255, 255, 0.1)' : '#e9edf4',
        text: isDark ? '#ffffff' : '#212529',
        textMuted: isDark ? 'rgba(255, 255, 255, 0.7)' : '#6c757d',
        electricViolet: '#7F00FF',
        cyberCyan: '#00E5FF',
        hotPink: '#E100FF',
        deepBlue: '#00A9FF',
        success: '#10b981',
        warning: '#f59e0b',
        danger: '#ef4444'
    };

    // CRUD Handlers
    const handleTogglePlan = async (id: string) => {
        try {
            const res = await subscriptionsApi.togglePlanStatus(id);
            if (res.success) {
                setPlans(plans.map(p => p.id === id ? { ...p, isActive: res.data.isActive } : p));
            }
        } catch (error) {
            console.error('Error toggling status:', error);
        }
    };

    const handleDuplicatePlan = async (id: string) => {
        if (!window.confirm('Duplicate this plan?')) return;
        try {
            const res = await subscriptionsApi.duplicatePlan(id);
            if (res.success) {
                alert('Plan duplicated successfully');
                fetchInitialData();
            }
        } catch (error) {
            console.error('Error duplicating plan:', error);
        }
    };

    const handleArchivePlan = async (id: string) => {
        if (!window.confirm('Archive this plan? It will be hidden from users.')) return;
        try {
            const res = await subscriptionsApi.archivePlan(id);
            if (res.success) {
                alert('Plan archived successfully');
                fetchInitialData();
            }
        } catch (error) {
            console.error('Error archiving plan:', error);
        }
    };

    const handleDeletePlan = async (id: string) => {
        if (!window.confirm('Are you absolutely sure you want to delete this plan? This cannot be undone.')) return;
        try {
            const res = await subscriptionsApi.deletePlan(id);
            if (res.success) {
                alert('Plan deleted successfully');
                setPlans(plans.filter(p => p.id !== id));
            }
        } catch (error: any) {
            alert(error.response?.data?.message || 'Failed to delete plan.');
        }
    };

    const handleOpenEditPlan = (plan: SubscriptionPlan) => {
        setEditingPlan(plan);
        setShowPlanModal(true);
    };

    const handleOpenCreatePlan = () => {
        setEditingPlan({
            name: '',
            displayName: '',
            description: '',
            tier: 'CORE',
            price: 0,
            durationDays: 30,
            currency: 'INR',
            themeColor: '#7F00FF',
            badge: '',
            isActive: true,
            isPopular: false,
            isRecommended: false,
            superlikesPerCycle: 0,
            boostsPerCycle: 0,
            backtrackLimit: 3,
            hasHideProfile: false,
            hasPriorityVisibility: false,
            hasTrustBadge: false,
            hasEliteBadge: false,
            canSeeWhoLiked: false,
            displayOrder: plans.length + 1,
            dailyMatchRequests: -1,
            dailyLikes: -1,
            dailyPosts: -1,
        });
        setShowPlanModal(true);
    };

    const handleSavePlan = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!editingPlan) return;

        try {
            if (editingPlan.id) {
                const res = await subscriptionsApi.updatePlan(editingPlan.id, editingPlan);
                if (res.success) {
                    alert('Plan updated successfully');
                    setShowPlanModal(false);
                    fetchInitialData();
                }
            } else {
                const res = await subscriptionsApi.createPlan(editingPlan);
                if (res.success) {
                    alert('Plan created successfully');
                    setShowPlanModal(false);
                    fetchInitialData();
                }
            }
        } catch (error) {
            console.error('Error saving plan:', error);
        }
    };

    const handleOpenFeatureMatrix = async (plan: SubscriptionPlan) => {
        setShowFeatureMatrixPlan(plan);
        try {
            const res = await subscriptionsApi.getPlanFeatures(plan.id);
            if (res.success) {
                // Pre-populate missing features from the global catalog
                const mapped = features.map(f => {
                    const existing = res.data.find(pf => pf.featureId === f.id);
                    return existing || {
                        id: '',
                        packageId: plan.id,
                        featureId: f.id,
                        isEnabled: false,
                        value: { enabled: false },
                        feature: f
                    };
                });
                setMatrixFeatures(mapped);
            }
        } catch (error) {
            console.error('Error loading plan features:', error);
        }
    };

    const handleSaveMatrix = async () => {
        if (!showFeatureMatrixPlan) return;
        try {
            const updates = matrixFeatures.map(f => ({
                featureId: f.featureId,
                isEnabled: f.isEnabled,
                value: f.value
            }));
            const res = await subscriptionsApi.updatePlanFeatures(showFeatureMatrixPlan.id, updates);
            if (res.success) {
                alert('Plan features updated successfully');
                setShowFeatureMatrixPlan(null);
            }
        } catch (error) {
            console.error('Error saving matrix:', error);
        }
    };

    const handleMatrixToggle = (idx: number) => {
        const next = [...matrixFeatures];
        next[idx].isEnabled = !next[idx].isEnabled;
        if (!next[idx].value) next[idx].value = {};
        next[idx].value.enabled = next[idx].isEnabled;
        setMatrixFeatures(next);
    };

    const handleMatrixValueChange = (idx: number, val: any) => {
        const next = [...matrixFeatures];
        if (!next[idx].value) next[idx].value = {};
        const valueType = next[idx].feature?.valueType;
        
        if (valueType === 'integer' || valueType === 'decimal') {
            next[idx].value.value = val === 'unlimited' ? 'unlimited' : Number(val);
        } else {
            next[idx].value.value = val;
        }
        setMatrixFeatures(next);
    };

    if (loading) {
        return (
            <div className="d-flex justify-content-center align-items-center" style={{ minHeight: '60vh' }}>
                <div className="spinner-border text-primary" role="status">
                    <span className="visually-hidden">Loading Subscription Engine...</span>
                </div>
            </div>
        );
    }

    return (
        <div style={{ color: colors.text }}>
            {/* Header greeting */}
            <div className="mb-4 d-flex justify-content-between align-items-center animate-in animate-in-1">
                <div>
                    <p className="mb-0 text-uppercase" style={{ fontSize: '0.75rem', letterSpacing: '2px', color: colors.textMuted, fontWeight: 600 }}>
                        Engine Administration
                    </p>
                    <h2 className="mb-0" style={{ fontWeight: 800, fontFamily: "'Outfit', sans-serif" }}>
                        SUBSCRIPTION MANAGE
                    </h2>
                </div>
                <div>
                    <button onClick={fetchInitialData} className="btn btn-outline-secondary d-flex align-items-center gap-2">
                        <BiRefresh size={18} /> Sync Data
                    </button>
                </div>
            </div>

            {/* Navigation Tabs */}
            <div className="d-flex gap-2 mb-4 p-1 border-bottom" style={{ borderColor: colors.border }}>
                {[
                    { id: 'analytics', label: 'Overview & Stats', icon: <BiTrendingUp /> },
                    { id: 'plans', label: 'Subscription Tiers', icon: <BiCrown /> },
                    { id: 'features', label: 'Feature Catalog & Matrix', icon: <BiSlider /> },
                    { id: 'transactions', label: 'Transactions & Invoices', icon: <BiCalendar /> },
                    { id: 'users', label: 'Subscribed Users', icon: <BiUserCheck /> }
                ].map(t => (
                    <button
                        key={t.id}
                        onClick={() => setActiveTab(t.id as any)}
                        className={`btn d-flex align-items-center gap-2 px-4 py-2 border-0 rounded-3`}
                        style={{
                            background: activeTab === t.id ? `${colors.electricViolet}15` : 'transparent',
                            color: activeTab === t.id ? colors.electricViolet : colors.textMuted,
                            fontWeight: 700,
                            fontSize: '0.85rem',
                            transition: 'all 0.2s ease'
                        }}
                    >
                        {t.icon}
                        {t.label}
                    </button>
                ))}
            </div>

            {/* TAB 1: ANALYTICS & OVERVIEW */}
            {activeTab === 'analytics' && analytics && (
                <div className="animate-in animate-in-2">
                    {/* Metrics row */}
                    <div className="row g-3 mb-4">
                        {[
                            { label: 'Active Subscribers', value: analytics.stats.activeSubscribers, icon: <BiUserCheck />, cls: 'success' },
                            { label: 'Monthly Revenue', value: `₹${(analytics.stats.monthlyRevenue || 0).toLocaleString()}`, icon: <BiDollar />, cls: 'primary' },
                            { label: 'Total Revenue (All Time)', value: `₹${(analytics.stats.totalRevenue || 0).toLocaleString()}`, icon: <BiTrendingUp />, cls: 'warning' },
                            { label: 'Growth rate (MoM)', value: `${analytics.stats.revenueGrowth}%`, icon: Number(analytics.stats.revenueGrowth) >= 0 ? <BiTrendingUp /> : <BiTrendingDown />, cls: Number(analytics.stats.revenueGrowth) >= 0 ? 'success' : 'danger' }
                        ].map((m, idx) => (
                            <div className="col-md-3" key={idx}>
                                <div className="vz-card">
                                    <div className="vz-card-body d-flex justify-content-between align-items-center" style={{ background: colors.cardBg, borderColor: colors.border }}>
                                        <div>
                                            <span style={{ fontSize: '0.75rem', fontWeight: 600, color: colors.textMuted }}>{m.label}</span>
                                            <h3 className="mt-1 mb-0" style={{ fontWeight: 800 }}>{m.value}</h3>
                                        </div>
                                        <div className={`rounded-circle p-3 d-flex align-items-center justify-content-center text-${m.cls}`} style={{ background: `var(--vz-${m.cls}-subtle)` }}>
                                            {m.icon}
                                        </div>
                                    </div>
                                </div>
                            </div>
                        ))}
                    </div>

                    <div className="row g-3">
                        {/* Revenue & growth chart card */}
                        <div className="col-md-8">
                            <div className="vz-card">
                                <div className="vz-card-body" style={{ background: colors.cardBg }}>
                                    <h6 className="mb-4 text-uppercase" style={{ letterSpacing: '1px', fontWeight: 700 }}>6-Month Revenue & Subscriber Growth</h6>
                                    <div style={{ height: '300px', display: 'flex', flexDirection: 'column', justifyContent: 'space-between' }}>
                                        <div className="d-flex align-items-end justify-content-between h-75 px-4">
                                            {analytics.growthData.map((g, idx) => (
                                                <div key={idx} className="d-flex flex-column align-items-center gap-2" style={{ flex: 1 }}>
                                                    <div style={{
                                                        height: `${Math.min(100, Math.max(10, (g.revenue / (analytics.stats.totalRevenue || 1)) * 300))}px`,
                                                        width: '24px',
                                                        background: `linear-gradient(to top, ${colors.electricViolet}, ${colors.hotPink})`,
                                                        borderRadius: '6px 6px 0 0',
                                                        transition: 'height 0.3s ease'
                                                    }} />
                                                    <span style={{ fontSize: '0.75rem', fontWeight: 600 }}>{g.month}</span>
                                                </div>
                                            ))}
                                        </div>
                                        <div className="d-flex justify-content-around border-top pt-3" style={{ borderColor: colors.border }}>
                                            {analytics.growthData.map((g, idx) => (
                                                <div key={idx} className="text-center">
                                                    <div style={{ fontSize: '0.8rem', fontWeight: 700 }}>₹{g.revenue.toLocaleString()}</div>
                                                    <div style={{ fontSize: '0.7rem', color: colors.textMuted }}>{g.subscribers} Subscribers</div>
                                                </div>
                                            ))}
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>

                        {/* Plan distribution donut representation */}
                        <div className="col-md-4">
                            <div className="vz-card">
                                <div className="vz-card-body" style={{ background: colors.cardBg }}>
                                    <h6 className="mb-4 text-uppercase" style={{ letterSpacing: '1px', fontWeight: 700 }}>Plan Distribution</h6>
                                    <div className="d-flex flex-column gap-3">
                                        {analytics.planDistribution.map((p, idx) => (
                                            <div key={idx}>
                                                <div className="d-flex justify-content-between align-items-center mb-1">
                                                    <span style={{ fontSize: '0.8rem', fontWeight: 700 }}>{p.planName}</span>
                                                    <span style={{ fontSize: '0.8rem', fontWeight: 600 }}>{p.count} Active</span>
                                                </div>
                                                <div className="progress" style={{ height: '8px', background: isDark ? 'rgba(255,255,255,0.1)' : '#eee' }}>
                                                    <div className="progress-bar" style={{
                                                        width: `${analytics.stats.activeSubscribers ? (p.count / analytics.stats.activeSubscribers) * 100 : 0}%`,
                                                        background: colors.electricViolet
                                                    }} />
                                                </div>
                                            </div>
                                        ))}
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            )}

            {/* TAB 2: SUBSCRIPTION PLANS */}
            {activeTab === 'plans' && (
                <div className="animate-in animate-in-2">
                    <div className="d-flex justify-content-between align-items-center mb-4">
                        <h5 className="mb-0" style={{ fontWeight: 700 }}>Manage Plans</h5>
                        <button onClick={handleOpenCreatePlan} className="btn btn-primary d-flex align-items-center gap-2">
                            <BiPlus size={18} /> Create New Plan
                        </button>
                    </div>

                    <div className="row g-3 mb-5">
                        {plans.map(p => (
                            <div className="col-md-4" key={p.id}>
                                <div className="card h-100" style={{
                                    background: colors.cardBg,
                                    borderColor: p.isPopular ? colors.hotPink : colors.border,
                                    borderRadius: '16px',
                                    borderWidth: p.isPopular ? '2px' : '1px',
                                    overflow: 'hidden',
                                    position: 'relative'
                                }}>
                                    {p.isPopular && (
                                        <div style={{
                                            position: 'absolute',
                                            top: '12px',
                                            right: '-30px',
                                            background: colors.hotPink,
                                            color: '#fff',
                                            fontSize: '0.65rem',
                                            fontWeight: 800,
                                            padding: '4px 30px',
                                            transform: 'rotate(45deg)'
                                        }}>
                                            POPULAR
                                        </div>
                                    )}
                                    <div className="card-body p-4 d-flex flex-column">
                                        <span className="text-uppercase" style={{ fontSize: '0.7rem', fontWeight: 800, color: p.themeColor || colors.electricViolet }}>
                                            {p.tier}
                                        </span>
                                        <h4 className="card-title my-2" style={{ fontWeight: 800 }}>{p.name}</h4>
                                        <div className="d-flex align-items-baseline gap-1 my-3">
                                            <span style={{ fontSize: '2rem', fontWeight: 900 }}>₹{p.price}</span>
                                            <span style={{ fontSize: '0.8rem', color: colors.textMuted }}>/ {p.durationDays} days</span>
                                        </div>
                                        <p style={{ fontSize: '0.8rem', color: colors.textMuted, minHeight: '40px' }}>{p.description || 'No description provided.'}</p>
                                        
                                        {/* Action buttons */}
                                        <div className="mt-auto d-flex gap-2 pt-3 border-top" style={{ borderColor: colors.border }}>
                                            <button onClick={() => handleOpenEditPlan(p)} className="btn btn-sm btn-outline-secondary" title="Edit Properties">
                                                <BiPencil /> Edit
                                            </button>
                                            <button onClick={() => handleOpenFeatureMatrix(p)} className="btn btn-sm btn-outline-primary" title="Edit Feature Matrix">
                                                <BiSlider /> Features
                                            </button>
                                            <button onClick={() => handleDuplicatePlan(p.id)} className="btn btn-sm btn-outline-info" title="Duplicate Plan">
                                                <BiCopy />
                                            </button>
                                            <button onClick={() => handleArchivePlan(p.id)} className="btn btn-sm btn-outline-warning" title="Archive Plan">
                                                <BiArchive />
                                            </button>
                                            <button onClick={() => handleDeletePlan(p.id)} className="btn btn-sm btn-outline-danger" title="Delete Plan">
                                                <BiTrash />
                                            </button>
                                        </div>
                                        <div className="mt-3 d-flex justify-content-between align-items-center">
                                            <div className="form-check form-switch">
                                                <input
                                                    className="form-check-input"
                                                    type="checkbox"
                                                    checked={p.isActive}
                                                    onChange={() => handleTogglePlan(p.id)}
                                                />
                                                <span style={{ fontSize: '0.75rem', fontWeight: 600 }}>{p.isActive ? 'Active' : 'Disabled'}</span>
                                            </div>
                                            <span style={{ fontSize: '0.75rem', color: colors.textMuted }}>
                                                {p.activeSubscribers || 0} active subscribers
                                            </span>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        ))}
                    </div>
                </div>
            )}

            {/* TAB 3: FEATURES & MATRIX */}
            {activeTab === 'features' && (
                <div className="animate-in animate-in-2">
                    <div className="vz-card mb-4">
                        <div className="vz-card-body" style={{ background: colors.cardBg }}>
                            <h5 className="mb-3" style={{ fontWeight: 700 }}>Feature Matrix Management</h5>
                            <p style={{ fontSize: '0.8rem', color: colors.textMuted }}>
                                Select a plan below to edit its dynamic permissions, daily usage caps, and custom feature key values directly.
                            </p>
                            <div className="d-flex flex-wrap gap-2">
                                {plans.map(p => (
                                    <button
                                        key={p.id}
                                        onClick={() => handleOpenFeatureMatrix(p)}
                                        className="btn btn-outline-primary px-3 py-2 d-flex align-items-center gap-2"
                                        style={{ fontWeight: 700, fontSize: '0.8rem' }}
                                    >
                                        <BiCrown /> Configure: {p.name}
                                    </button>
                                ))}
                            </div>
                        </div>
                    </div>

                    <div className="vz-card">
                        <div className="vz-card-body" style={{ background: colors.cardBg, padding: 0 }}>
                            <div className="table-responsive">
                                <table className="table mb-0 align-middle">
                                    <thead style={{ background: isDark ? 'rgba(255,255,255,0.02)' : '#f8f9fa' }}>
                                        <tr>
                                            <th style={{ width: '25%' }}>Feature Key / Name</th>
                                            <th>Type</th>
                                            <th>Category</th>
                                            <th style={{ width: '40%' }}>Global Description</th>
                                            <th>Status</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        {features.map(f => (
                                            <tr key={f.id}>
                                                <td>
                                                    <div style={{ fontWeight: 700 }}>{f.name}</div>
                                                    <code style={{ fontSize: '0.7rem', color: colors.electricViolet }}>{f.key}</code>
                                                </td>
                                                <td><span className="badge bg-secondary">{f.valueType}</span></td>
                                                <td><span className="badge bg-info">{f.category}</span></td>
                                                <td style={{ fontSize: '0.8rem', color: colors.textMuted }}>{f.description}</td>
                                                <td>
                                                    <span className={`badge bg-${f.isActive ? 'success' : 'danger'}-subtle text-${f.isActive ? 'success' : 'danger'}`}>
                                                        {f.isActive ? 'Active' : 'Inactive'}
                                                    </span>
                                                </td>
                                            </tr>
                                        ))}
                                    </tbody>
                                </table>
                            </div>
                        </div>
                    </div>
                </div>
            )}

            {/* TAB 4: TRANSACTIONS */}
            {activeTab === 'transactions' && (
                <div className="animate-in animate-in-2">
                    <div className="vz-card mb-3">
                        <div className="vz-card-body d-flex justify-content-between align-items-center" style={{ background: colors.cardBg }}>
                            <div className="d-flex gap-2">
                                <select className="form-select form-select-sm" value={txStatus} onChange={e => setTxStatus(e.target.value)} style={{ width: '130px' }}>
                                    <option value="">All Statuses</option>
                                    <option value="success">Success</option>
                                    <option value="pending">Pending</option>
                                    <option value="failed">Failed</option>
                                </select>
                                <select className="form-select form-select-sm" value={txType} onChange={e => setTxType(e.target.value)} style={{ width: '130px' }}>
                                    <option value="">All Types</option>
                                    <option value="purchase">Purchase</option>
                                    <option value="renew">Renew</option>
                                    <option value="upgrade">Upgrade</option>
                                    <option value="boost">Boost</option>
                                </select>
                            </div>
                        </div>
                    </div>

                    <div className="vz-card">
                        <div className="vz-card-body" style={{ background: colors.cardBg, padding: 0 }}>
                            <div className="table-responsive">
                                <table className="table mb-0 align-middle">
                                    <thead>
                                        <tr>
                                            <th>Invoice / Date</th>
                                            <th>User</th>
                                            <th>Package</th>
                                            <th>Type</th>
                                            <th>Amount</th>
                                            <th>Gateway Info</th>
                                            <th>Status</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        {transactions.map(tx => (
                                            <tr key={tx.id}>
                                                <td>
                                                    <div style={{ fontWeight: 700 }}>{tx.invoiceNumber || 'N/A'}</div>
                                                    <div style={{ fontSize: '0.75rem', color: colors.textMuted }}>
                                                        {new Date(tx.createdAt).toLocaleString()}
                                                    </div>
                                                </td>
                                                <td>
                                                    <div style={{ fontWeight: 600 }}>
                                                        {tx.user ? `${tx.user.firstName} ${tx.user.lastName}` : 'System User'}
                                                    </div>
                                                    <div style={{ fontSize: '0.75rem', color: colors.textMuted }}>{tx.user?.email}</div>
                                                </td>
                                                <td><span className="badge bg-primary-subtle text-primary">{tx.package?.name || 'In-App Boost'}</span></td>
                                                <td><span className="badge bg-secondary">{tx.type}</span></td>
                                                <td style={{ fontWeight: 700 }}>₹{tx.amount}</td>
                                                <td>
                                                    <div style={{ fontSize: '0.75rem' }}>{tx.paymentGateway}</div>
                                                    <code style={{ fontSize: '0.65rem' }}>{tx.gatewayPaymentId || 'N/A'}</code>
                                                </td>
                                                <td>
                                                    <span className={`badge bg-${tx.status === 'success' ? 'success' : 'warning'}-subtle text-${tx.status === 'success' ? 'success' : 'warning'}`}>
                                                        {tx.status}
                                                    </span>
                                                </td>
                                            </tr>
                                        ))}
                                    </tbody>
                                </table>
                            </div>
                            
                            {/* Pagination Controls */}
                            <div className="d-flex justify-content-between align-items-center p-3 border-top" style={{ borderColor: colors.border }}>
                                <div style={{ fontSize: '0.8rem', color: colors.textMuted }}>
                                    Page {txPage} of {txTotalPages}
                                </div>
                                <div className="d-flex gap-2">
                                    <button 
                                        className="btn btn-sm btn-outline-secondary" 
                                        disabled={txPage <= 1} 
                                        onClick={() => setTxPage(prev => Math.max(1, prev - 1))}
                                    >
                                        Previous
                                    </button>
                                    <button 
                                        className="btn btn-sm btn-outline-secondary" 
                                        disabled={txPage >= txTotalPages} 
                                        onClick={() => setTxPage(prev => Math.min(txTotalPages, prev + 1))}
                                    >
                                        Next
                                    </button>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            )}

            {/* TAB 5: SUBSCRIBED USERS */}
            {activeTab === 'users' && (
                <div className="animate-in animate-in-2">
                    <div className="vz-card mb-3">
                        <div className="vz-card-body d-flex justify-content-between align-items-center" style={{ background: colors.cardBg }}>
                            <h5 className="mb-0" style={{ fontWeight: 700 }}>Active Subscribed Users</h5>
                            <button onClick={fetchSubscribedUsers} className="btn btn-sm btn-outline-secondary d-flex align-items-center gap-2">
                                <BiRefresh size={16} /> Reload Users
                            </button>
                        </div>
                    </div>

                    <div className="vz-card">
                        <div className="vz-card-body" style={{ background: colors.cardBg, padding: 0 }}>
                            {usersLoading ? (
                                <div className="d-flex justify-content-center align-items-center py-5">
                                    <div className="spinner-border text-primary" role="status">
                                        <span className="visually-hidden">Loading users...</span>
                                    </div>
                                </div>
                            ) : subscribedUsers.length === 0 ? (
                                <div className="text-center py-5">
                                    <BiUserCheck size={48} className="text-muted mb-3" />
                                    <h6>No Active Subscriptions Found</h6>
                                    <p className="text-muted small">No users are currently subscribed to a VIP package.</p>
                                </div>
                            ) : (
                                <>
                                    <div className="table-responsive">
                                        <table className="table mb-0 align-middle">
                                            <thead>
                                                <tr>
                                                    <th>User Details</th>
                                                    <th>Package Tier</th>
                                                    <th>Billing Cycle</th>
                                                    <th>Status</th>
                                                    <th className="text-end px-4">Actions</th>
                                                </tr>
                                            </thead>
                                            <tbody>
                                                {subscribedUsers.map((sub: any) => {
                                                    const name = sub.user ? `${sub.user.firstName} ${sub.user.lastName}` : 'N/A';
                                                    const email = sub.user?.email || 'N/A';
                                                    const planName = sub.package?.name || 'Unknown Plan';
                                                    const planTier = (sub.package?.tier || 'free').toUpperCase();
                                                    const isActive = sub.status === 'active';

                                                    return (
                                                        <tr key={sub.id}>
                                                            <td>
                                                                <div style={{ fontWeight: 700 }}>{name}</div>
                                                                <div style={{ fontSize: '0.75rem', color: colors.textMuted }}>{email}</div>
                                                            </td>
                                                            <td>
                                                                <span className="badge bg-primary-subtle text-primary">{planName}</span>
                                                                <span className="badge bg-secondary ms-2">{planTier}</span>
                                                            </td>
                                                            <td>
                                                                <div style={{ fontSize: '0.85rem' }}>
                                                                    <strong>Start:</strong> {new Date(sub.startDate).toLocaleDateString()}
                                                                </div>
                                                                <div style={{ fontSize: '0.85rem' }}>
                                                                    <strong>Expires:</strong> {new Date(sub.endDate).toLocaleDateString()}
                                                                </div>
                                                            </td>
                                                            <td>
                                                                <span className={`badge bg-${isActive ? 'success' : 'danger'}-subtle text-${isActive ? 'success' : 'danger'}`}>
                                                                    {sub.status.toUpperCase()}
                                                                </span>
                                                            </td>
                                                            <td className="text-end px-4">
                                                                <div className="d-flex justify-content-end gap-2">
                                                                    <button
                                                                        className="btn btn-sm btn-outline-primary d-flex align-items-center gap-1"
                                                                        disabled={!isActive}
                                                                        onClick={() => {
                                                                            setSelectedUser(sub);
                                                                            setActionDays(30);
                                                                            setActionReason('');
                                                                            setShowExtendModal(true);
                                                                        }}
                                                                    >
                                                                        <BiPlus /> Extend
                                                                    </button>
                                                                    <button
                                                                        className="btn btn-sm btn-outline-danger d-flex align-items-center gap-1"
                                                                        disabled={!isActive}
                                                                        onClick={() => {
                                                                            setSelectedUser(sub);
                                                                            setActionReason('');
                                                                            setShowExpireModal(true);
                                                                        }}
                                                                    >
                                                                        <BiTrash /> Revoke
                                                                    </button>
                                                                </div>
                                                            </td>
                                                        </tr>
                                                    );
                                                })}
                                            </tbody>
                                        </table>
                                    </div>

                                    {/* Pagination Controls */}
                                    <div className="d-flex justify-content-between align-items-center p-3 border-top" style={{ borderColor: colors.border }}>
                                        <div style={{ fontSize: '0.8rem', color: colors.textMuted }}>
                                            Page {usersPage} of {usersTotalPages}
                                        </div>
                                        <div className="d-flex gap-2">
                                            <button
                                                className="btn btn-sm btn-outline-secondary"
                                                disabled={usersPage <= 1}
                                                onClick={() => setUsersPage(prev => Math.max(1, prev - 1))}
                                            >
                                                Previous
                                            </button>
                                            <button
                                                className="btn btn-sm btn-outline-secondary"
                                                disabled={usersPage >= usersTotalPages}
                                                onClick={() => setUsersPage(prev => Math.min(usersTotalPages, prev + 1))}
                                            >
                                                Next
                                            </button>
                                        </div>
                                    </div>
                                </>
                            )}
                        </div>
                    </div>
                </div>
            )}

            {/* MODAL 1: PLAN PROPERTIES CREATION / EDITOR */}
            {showPlanModal && editingPlan && (
                <div className="modal fade show d-block" style={{ background: 'rgba(0,0,0,0.6)', backdropFilter: 'blur(4px)' }}>
                    <div className="modal-dialog modal-lg modal-dialog-centered">
                        <div className="modal-content" style={{ background: isDark ? '#151515' : '#fff', borderColor: colors.border }}>
                            <div className="modal-header">
                                <h5 className="modal-title" style={{ fontWeight: 800 }}>
                                    {editingPlan.id ? 'Edit Plan Settings' : 'Create New Subscription Package'}
                                </h5>
                                <button onClick={() => setShowPlanModal(false)} className="btn-close btn-close-white" />
                            </div>
                            <form onSubmit={handleSavePlan}>
                                <div className="modal-body" style={{ maxHeight: '70vh', overflowY: 'auto' }}>
                                    <div className="row g-3">
                                        <div className="col-md-6">
                                            <label className="form-label" style={{ fontWeight: 700, fontSize: '0.8rem' }}>Plan Code Name</label>
                                            <input
                                                type="text"
                                                className="form-control"
                                                required
                                                value={editingPlan.name || ''}
                                                onChange={e => setEditingPlan({ ...editingPlan, name: e.target.value })}
                                            />
                                        </div>
                                        <div className="col-md-6">
                                            <label className="form-label" style={{ fontWeight: 700, fontSize: '0.8rem' }}>Pricing Tier (Unique Tag)</label>
                                            <select
                                                className="form-select"
                                                value={editingPlan.tier || 'CORE'}
                                                onChange={e => setEditingPlan({ ...editingPlan, tier: e.target.value as any })}
                                            >
                                                <option value="FREE">Free</option>
                                                <option value="CORE">Core</option>
                                                <option value="PLUS">Plus</option>
                                                <option value="PRO">Pro</option>
                                                <option value="ELITE">Elite</option>
                                            </select>
                                        </div>
                                        <div className="col-md-6">
                                            <label className="form-label" style={{ fontWeight: 700, fontSize: '0.8rem' }}>Price (INR)</label>
                                            <input
                                                type="number"
                                                className="form-control"
                                                required
                                                value={editingPlan.price ?? 0}
                                                onChange={e => setEditingPlan({ ...editingPlan, price: Number(e.target.value) })}
                                            />
                                        </div>
                                        <div className="col-md-6">
                                            <label className="form-label" style={{ fontWeight: 700, fontSize: '0.8rem' }}>Duration (Days)</label>
                                            <input
                                                type="number"
                                                className="form-control"
                                                required
                                                value={editingPlan.durationDays ?? 30}
                                                onChange={e => setEditingPlan({ ...editingPlan, durationDays: Number(e.target.value) })}
                                            />
                                        </div>
                                        <div className="col-12">
                                            <label className="form-label" style={{ fontWeight: 700, fontSize: '0.8rem' }}>Plan Description</label>
                                            <textarea
                                                className="form-control"
                                                rows={2}
                                                value={editingPlan.description || ''}
                                                onChange={e => setEditingPlan({ ...editingPlan, description: e.target.value })}
                                            />
                                        </div>
                                        <div className="col-md-4">
                                            <label className="form-label" style={{ fontWeight: 700, fontSize: '0.8rem' }}>Daily Likes (-1 for Unlimited)</label>
                                            <input
                                                type="number"
                                                className="form-control"
                                                value={editingPlan.dailyLikes ?? -1}
                                                onChange={e => setEditingPlan({ ...editingPlan, dailyLikes: Number(e.target.value) })}
                                            />
                                        </div>
                                        <div className="col-md-4">
                                            <label className="form-label" style={{ fontWeight: 700, fontSize: '0.8rem' }}>Daily Matches (-1 for Unlimited)</label>
                                            <input
                                                type="number"
                                                className="form-control"
                                                value={editingPlan.dailyMatchRequests ?? -1}
                                                onChange={e => setEditingPlan({ ...editingPlan, dailyMatchRequests: Number(e.target.value) })}
                                            />
                                        </div>
                                        <div className="col-md-4">
                                            <label className="form-label" style={{ fontWeight: 700, fontSize: '0.8rem' }}>Daily Feed Posts (-1 for Unlimited)</label>
                                            <input
                                                type="number"
                                                className="form-control"
                                                value={editingPlan.dailyPosts ?? -1}
                                                onChange={e => setEditingPlan({ ...editingPlan, dailyPosts: Number(e.target.value) })}
                                            />
                                        </div>
                                        <div className="col-md-4">
                                            <label className="form-label" style={{ fontWeight: 700, fontSize: '0.8rem' }}>Superlikes per Cycle</label>
                                            <input
                                                type="number"
                                                className="form-control"
                                                value={editingPlan.superlikesPerCycle ?? 0}
                                                onChange={e => setEditingPlan({ ...editingPlan, superlikesPerCycle: Number(e.target.value) })}
                                            />
                                        </div>
                                        <div className="col-md-4">
                                            <label className="form-label" style={{ fontWeight: 700, fontSize: '0.8rem' }}>Boosts per Cycle</label>
                                            <input
                                                type="number"
                                                className="form-control"
                                                value={editingPlan.boostsPerCycle ?? 0}
                                                onChange={e => setEditingPlan({ ...editingPlan, boostsPerCycle: Number(e.target.value) })}
                                            />
                                        </div>
                                        <div className="col-md-4">
                                            <label className="form-label" style={{ fontWeight: 700, fontSize: '0.8rem' }}>Backtrack Limit</label>
                                            <input
                                                type="number"
                                                className="form-control"
                                                value={editingPlan.backtrackLimit ?? 3}
                                                onChange={e => setEditingPlan({ ...editingPlan, backtrackLimit: Number(e.target.value) })}
                                            />
                                        </div>
                                        <div className="col-md-6">
                                            <label className="form-label" style={{ fontWeight: 700, fontSize: '0.8rem' }}>Theme Color Hex</label>
                                            <input
                                                type="color"
                                                className="form-control form-control-color w-100"
                                                value={editingPlan.themeColor || '#7F00FF'}
                                                onChange={e => setEditingPlan({ ...editingPlan, themeColor: e.target.value })}
                                            />
                                        </div>
                                        <div className="col-md-6 d-flex align-items-center gap-4">
                                            <div className="form-check">
                                                <input
                                                    type="checkbox"
                                                    className="form-check-input"
                                                    id="isPopular"
                                                    checked={!!editingPlan.isPopular}
                                                    onChange={e => setEditingPlan({ ...editingPlan, isPopular: e.target.checked })}
                                                />
                                                <label className="form-check-label" htmlFor="isPopular">Mark as Popular</label>
                                            </div>
                                        </div>
                                        <div className="col-12">
                                            <label className="form-label" style={{ fontWeight: 700, fontSize: '0.8rem' }}>Feature Flags</label>
                                            <div className="d-flex flex-wrap gap-4">
                                                <div className="form-check">
                                                    <input
                                                        type="checkbox"
                                                        className="form-check-input"
                                                        id="hasHideProfile"
                                                        checked={!!editingPlan.hasHideProfile}
                                                        onChange={e => setEditingPlan({ ...editingPlan, hasHideProfile: e.target.checked })}
                                                    />
                                                    <label className="form-check-label" htmlFor="hasHideProfile">Hide Profile Access</label>
                                                </div>
                                                <div className="form-check">
                                                    <input
                                                        type="checkbox"
                                                        className="form-check-input"
                                                        id="hasPriorityVisibility"
                                                        checked={!!editingPlan.hasPriorityVisibility}
                                                        onChange={e => setEditingPlan({ ...editingPlan, hasPriorityVisibility: e.target.checked })}
                                                    />
                                                    <label className="form-check-label" htmlFor="hasPriorityVisibility">Priority Visibility</label>
                                                </div>
                                                <div className="form-check">
                                                    <input
                                                        type="checkbox"
                                                        className="form-check-input"
                                                        id="hasTrustBadge"
                                                        checked={!!editingPlan.hasTrustBadge}
                                                        onChange={e => setEditingPlan({ ...editingPlan, hasTrustBadge: e.target.checked })}
                                                    />
                                                    <label className="form-check-label" htmlFor="hasTrustBadge">Trust Badge</label>
                                                </div>
                                                <div className="form-check">
                                                    <input
                                                        type="checkbox"
                                                        className="form-check-input"
                                                        id="hasEliteBadge"
                                                        checked={!!editingPlan.hasEliteBadge}
                                                        onChange={e => setEditingPlan({ ...editingPlan, hasEliteBadge: e.target.checked })}
                                                    />
                                                    <label className="form-check-label" htmlFor="hasEliteBadge">Elite Badge</label>
                                                </div>
                                                <div className="form-check">
                                                    <input
                                                        type="checkbox"
                                                        className="form-check-input"
                                                        id="canSeeWhoLiked"
                                                        checked={!!editingPlan.canSeeWhoLiked}
                                                        onChange={e => setEditingPlan({ ...editingPlan, canSeeWhoLiked: e.target.checked })}
                                                    />
                                                    <label className="form-check-label" htmlFor="canSeeWhoLiked">See Who Liked Me</label>
                                                </div>
                                                <div className="form-check">
                                                    <input
                                                        type="checkbox"
                                                        className="form-check-input"
                                                        id="isRecommended"
                                                        checked={!!editingPlan.isRecommended}
                                                        onChange={e => setEditingPlan({ ...editingPlan, isRecommended: e.target.checked })}
                                                    />
                                                    <label className="form-check-label" htmlFor="isRecommended">Mark as Recommended</label>
                                                </div>
                                            </div>
                                        </div>
                                    </div>
                                </div>
                                <div className="modal-footer">
                                    <button type="button" onClick={() => setShowPlanModal(false)} className="btn btn-outline-secondary">Cancel</button>
                                    <button type="submit" className="btn btn-primary px-4">Save Plan Changes</button>
                                </div>
                            </form>
                        </div>
                    </div>
                </div>
            )}

            {/* MODAL 2: PLAN MATRIX EDITOR */}
            {showFeatureMatrixPlan && (
                <div className="modal fade show d-block" style={{ background: 'rgba(0,0,0,0.6)', backdropFilter: 'blur(4px)' }}>
                    <div className="modal-dialog modal-lg modal-dialog-centered">
                        <div className="modal-content" style={{ background: isDark ? '#151515' : '#fff', borderColor: colors.border }}>
                            <div className="modal-header">
                                <h5 className="modal-title" style={{ fontWeight: 800 }}>
                                    Feature Matrix Editor — {showFeatureMatrixPlan.name}
                                </h5>
                                <button onClick={() => setShowFeatureMatrixPlan(null)} className="btn-close btn-close-white" />
                            </div>
                            <div className="modal-body" style={{ maxHeight: '60vh', overflowY: 'auto' }}>
                                <div className="d-flex flex-column gap-3">
                                    {matrixFeatures.map((mf, idx) => {
                                        const f = mf.feature;
                                        if (!f) return null;
                                        const valObj = mf.value || { enabled: false };

                                        return (
                                            <div key={f.id} className="p-3 border rounded-3" style={{ borderColor: colors.border, background: isDark ? 'rgba(255,255,255,0.02)' : '#fafafa' }}>
                                                <div className="d-flex justify-content-between align-items-center mb-2">
                                                    <div>
                                                        <span style={{ fontWeight: 700 }}>{f.name}</span>
                                                        <div style={{ fontSize: '0.75rem', color: colors.textMuted }}>{f.description}</div>
                                                    </div>
                                                    <div className="form-check form-switch">
                                                        <input
                                                            className="form-check-input"
                                                            type="checkbox"
                                                            checked={mf.isEnabled}
                                                            onChange={() => handleMatrixToggle(idx)}
                                                        />
                                                        <span style={{ fontSize: '0.8rem', fontWeight: 600 }}>
                                                            {mf.isEnabled ? 'Enabled' : 'Disabled'}
                                                        </span>
                                                    </div>
                                                </div>

                                                {mf.isEnabled && (
                                                    <div className="mt-2 pt-2 border-top" style={{ borderColor: colors.border }}>
                                                        {f.valueType === 'boolean' && (
                                                            <div className="form-text text-success d-flex align-items-center gap-1">
                                                                <BiCheckCircle /> Boolean Access Allowed
                                                            </div>
                                                        )}
                                                        {(f.valueType === 'integer' || f.valueType === 'decimal') && (
                                                            <div className="d-flex align-items-center gap-3">
                                                                <label style={{ fontSize: '0.75rem', fontWeight: 700 }}>Limit Value:</label>
                                                                <input
                                                                    type="text"
                                                                    className="form-control form-control-sm"
                                                                    placeholder="e.g. 10 or 'unlimited'"
                                                                    value={valObj.value !== undefined ? valObj.value : ''}
                                                                    onChange={e => handleMatrixValueChange(idx, e.target.value)}
                                                                    style={{ width: '150px' }}
                                                                />
                                                                <button
                                                                    type="button"
                                                                    onClick={() => handleMatrixValueChange(idx, 'unlimited')}
                                                                    className="btn btn-sm btn-outline-info"
                                                                >
                                                                    Set Unlimited
                                                                </button>
                                                            </div>
                                                        )}
                                                        {f.valueType === 'text' && (
                                                            <div className="d-flex align-items-center gap-3">
                                                                <label style={{ fontSize: '0.75rem', fontWeight: 700 }}>Config Text:</label>
                                                                <input
                                                                    type="text"
                                                                    className="form-control form-control-sm"
                                                                    value={valObj.value !== undefined ? valObj.value : ''}
                                                                    onChange={e => handleMatrixValueChange(idx, e.target.value)}
                                                                />
                                                            </div>
                                                        )}
                                                    </div>
                                                )}
                                            </div>
                                        );
                                    })}
                                </div>
                            </div>
                            <div className="modal-footer">
                                <button type="button" onClick={() => setShowFeatureMatrixPlan(null)} className="btn btn-outline-secondary">Cancel</button>
                                <button type="button" onClick={handleSaveMatrix} className="btn btn-primary px-4">Save Matrix Updates</button>
                            </div>
                        </div>
                    </div>
                </div>
            )}

            {/* MODAL 3: EXTEND USER SUBSCRIPTION */}
            {showExtendModal && selectedUser && (
                <div className="modal fade show d-block" style={{ background: 'rgba(0,0,0,0.6)', backdropFilter: 'blur(4px)' }}>
                    <div className="modal-dialog modal-dialog-centered">
                        <div className="modal-content" style={{ background: isDark ? '#151515' : '#fff', borderColor: colors.border }}>
                            <div className="modal-header">
                                <h5 className="modal-title" style={{ fontWeight: 800 }}>
                                    Extend VIP Subscription
                                </h5>
                                <button onClick={() => setShowExtendModal(false)} className="btn-close btn-close-white" />
                            </div>
                            <div className="modal-body">
                                <div className="mb-3 animate-in animate-in-1">
                                    <p className="small text-muted mb-1" style={{ fontSize: '0.65rem', letterSpacing: '1px', fontWeight: 700 }}>USER</p>
                                    <h6 className="mb-1" style={{ fontWeight: 700 }}>
                                        {selectedUser.user ? `${selectedUser.user.firstName} ${selectedUser.user.lastName}` : 'N/A'}
                                    </h6>
                                    <span style={{ fontSize: '0.75rem', color: colors.textMuted }}>{selectedUser.user?.email}</span>
                                </div>
                                <div className="mb-4 animate-in animate-in-2">
                                    <p className="small text-muted mb-1" style={{ fontSize: '0.65rem', letterSpacing: '1px', fontWeight: 700 }}>CURRENT PLAN</p>
                                    <h6 className="mb-1">{selectedUser.package?.name} ({selectedUser.package?.tier?.toUpperCase()})</h6>
                                    <span style={{ fontSize: '0.75rem', color: colors.textMuted }}>
                                        Expires: {new Date(selectedUser.endDate).toLocaleDateString()}
                                    </span>
                                </div>
                                <div className="row g-3">
                                    <div className="col-12">
                                        <label className="form-label" style={{ fontWeight: 700, fontSize: '0.8rem' }}>Days to Add</label>
                                        <input
                                            type="number"
                                            className="form-control"
                                            value={actionDays}
                                            onChange={e => setActionDays(Math.max(1, Number(e.target.value)))}
                                            min={1}
                                            required
                                        />
                                    </div>
                                    <div className="col-12">
                                        <label className="form-label" style={{ fontWeight: 700, fontSize: '0.8rem' }}>Reason for Extension</label>
                                        <textarea
                                            className="form-control"
                                            rows={2}
                                            placeholder="e.g. Compensating for platform outage"
                                            value={actionReason}
                                            onChange={e => setActionReason(e.target.value)}
                                        />
                                    </div>
                                </div>
                            </div>
                            <div className="modal-footer">
                                <button type="button" onClick={() => setShowExtendModal(false)} className="btn btn-outline-secondary">Cancel</button>
                                <button
                                    type="button"
                                    onClick={() => handleExtend(selectedUser.userId, actionDays, actionReason)}
                                    className="btn btn-primary px-4"
                                >
                                    Confirm Extension
                                </button>
                            </div>
                        </div>
                    </div>
                </div>
            )}

            {/* MODAL 4: FORCE EXPIRE USER SUBSCRIPTION */}
            {showExpireModal && selectedUser && (
                <div className="modal fade show d-block" style={{ background: 'rgba(0,0,0,0.6)', backdropFilter: 'blur(4px)' }}>
                    <div className="modal-dialog modal-dialog-centered">
                        <div className="modal-content" style={{ background: isDark ? '#151515' : '#fff', borderColor: colors.border }}>
                            <div className="modal-header">
                                <h5 className="modal-title text-danger" style={{ fontWeight: 800 }}>
                                    Revoke VIP Subscription
                                </h5>
                                <button onClick={() => setShowExpireModal(false)} className="btn-close btn-close-white" />
                            </div>
                            <div className="modal-body">
                                <div className="alert alert-danger mb-3" style={{ fontSize: '0.8rem', background: 'rgba(220,53,69,0.1)', color: '#dc3545', borderColor: 'transparent' }}>
                                    Warning: This will immediately set the user's subscription to Expired and revoke VIP feature access.
                                </div>
                                <div className="mb-3 animate-in animate-in-1">
                                    <p className="small text-muted mb-1" style={{ fontSize: '0.65rem', letterSpacing: '1px', fontWeight: 700 }}>USER</p>
                                    <h6 className="mb-1" style={{ fontWeight: 700 }}>
                                        {selectedUser.user ? `${selectedUser.user.firstName} ${selectedUser.user.lastName}` : 'N/A'}
                                    </h6>
                                    <span style={{ fontSize: '0.75rem', color: colors.textMuted }}>{selectedUser.user?.email}</span>
                                </div>
                                <div className="mb-4 animate-in animate-in-2">
                                    <p className="small text-muted mb-1" style={{ fontSize: '0.65rem', letterSpacing: '1px', fontWeight: 700 }}>PLAN TO EXPIRE</p>
                                    <h6>{selectedUser.package?.name} ({selectedUser.package?.tier?.toUpperCase()})</h6>
                                </div>
                                <div className="col-12">
                                    <label className="form-label" style={{ fontWeight: 700, fontSize: '0.8rem' }}>Reason for Revocation</label>
                                    <textarea
                                        className="form-control"
                                        rows={2}
                                        placeholder="e.g. Terms of Service violation / Chargeback"
                                        value={actionReason}
                                        onChange={e => setActionReason(e.target.value)}
                                        required
                                    />
                                </div>
                            </div>
                            <div className="modal-footer">
                                <button type="button" onClick={() => setShowExpireModal(false)} className="btn btn-outline-secondary">Cancel</button>
                                <button
                                    type="button"
                                    onClick={() => handleForceExpire(selectedUser.userId, actionReason)}
                                    className="btn btn-danger px-4"
                                >
                                    Force Expire
                                </button>
                            </div>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
};

export default SubscriptionManagement;
