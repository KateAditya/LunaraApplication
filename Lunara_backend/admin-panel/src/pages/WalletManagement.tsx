import React, { useState, useEffect } from 'react';
import {
    BiWallet,
    BiRefresh,
    BiSearch,
    BiPlusCircle,
    BiLock,
    BiDownload,
    BiCheckCircle,
    BiXCircle,
    BiSolidZap,
    BiGift,
    BiDetail,
    BiLockAlt,
    BiUndo,
    BiCoinStack,
    BiSliderAlt,
    BiListUl,
} from 'react-icons/bi';
import walletApi, { type WalletConfig, type WalletTransactionItem, type WalletLedgerMetrics } from '../api/wallet';

export const WalletManagement: React.FC = () => {
    const [config, setConfig] = useState<WalletConfig>({
        scope: 'global',
        minRechargeAmount: 100,
        maxRechargeAmount: 50000,
        suggestedAmounts: [100, 250, 500, 1000, 2000],
        dailyRechargeLimit: 100000,
        monthlyRechargeLimit: 500000,
        isWalletActive: true,
    });

    const [transactions, setTransactions] = useState<WalletTransactionItem[]>([]);
    const [metrics, setMetrics] = useState<WalletLedgerMetrics>({
        totalRecharge: 0,
        totalSpent: 0,
        totalPromotional: 0,
        totalCashback: 0,
        totalRewards: 0,
        totalRefunds: 0,
        totalLockedDeposits: 0,
        totalAvailablePool: 0,
        activeWalletsCount: 0,
        frozenWalletsCount: 0,
    });

    const [loading, setLoading] = useState(false);
    const [savingConfig, setSavingConfig] = useState(false);

    // Filters
    const [search, setSearch] = useState('');
    const [typeFilter, setTypeFilter] = useState('ALL');
    const [statusFilter, setStatusFilter] = useState('ALL');
    const [page, setPage] = useState(1);
    const [totalPages, setTotalPages] = useState(1);

    // Modals
    const [showAdjustModal, setShowAdjustModal] = useState(false);
    const [adjustUserId, setAdjustUserId] = useState('');
    const [adjustType, setAdjustType] = useState<'credit' | 'debit'>('credit');
    const [adjustAmount, setAdjustAmount] = useState<number | ''>('');
    const [adjustCategory, setAdjustCategory] = useState<'regular' | 'promotional' | 'reward'>('regular');
    const [adjustReason, setAdjustReason] = useState('');

    const [showFreezeModal, setShowFreezeModal] = useState(false);
    const [freezeUserId, setFreezeUserId] = useState('');
    const [freezeReason, setFreezeReason] = useState('');
    const [freezeAction, setFreezeAction] = useState<'freeze' | 'unfreeze'>('freeze');

    const [notification, setNotification] = useState<{ type: 'success' | 'error'; message: string } | null>(null);

    useEffect(() => {
        fetchConfig();
        fetchLedger();
    }, [page, typeFilter, statusFilter]);

    const showMsg = (message: string, type: 'success' | 'error' = 'success') => {
        setNotification({ type, message });
        setTimeout(() => setNotification(null), 4000);
    };

    const fetchConfig = async () => {
        try {
            const res = await walletApi.getConfig();
            if (res.success && res.data) {
                setConfig(res.data);
            }
        } catch (err: any) {
            console.error('Failed to fetch wallet config:', err);
        }
    };

    const fetchLedger = async () => {
        setLoading(true);
        try {
            const res = await walletApi.getLedger({
                page,
                limit: 25,
                search: search.trim() || undefined,
                transactionType: typeFilter !== 'ALL' ? typeFilter : undefined,
                status: statusFilter !== 'ALL' ? statusFilter : undefined,
            });

            if (res.success && res.data) {
                setTransactions(res.data.transactions || []);
                setMetrics(res.data.metrics || {
                    totalRecharge: 0,
                    totalSpent: 0,
                    totalPromotional: 0,
                    totalCashback: 0,
                    totalRewards: 0,
                    totalRefunds: 0,
                    totalLockedDeposits: 0,
                    totalAvailablePool: 0,
                    activeWalletsCount: 0,
                    frozenWalletsCount: 0,
                });
                setTotalPages(res.data.pagination?.totalPages || 1);
            }
        } catch (err: any) {
            showMsg(err.message || 'Failed to fetch ledger', 'error');
        } finally {
            setLoading(false);
        }
    };

    const handleSaveConfig = async (e: React.FormEvent) => {
        e.preventDefault();
        setSavingConfig(true);
        try {
            const res = await walletApi.updateConfig(config);
            if (res.success) {
                showMsg('Smart Credit Wallet settings updated successfully!');
            }
        } catch (err: any) {
            showMsg(err.message || 'Failed to update settings', 'error');
        } finally {
            setSavingConfig(false);
        }
    };

    const handleExecuteAdjustment = async () => {
        if (!adjustUserId || !adjustAmount || adjustAmount <= 0 || !adjustReason) {
            showMsg('Please fill all adjustment fields', 'error');
            return;
        }

        try {
            if (adjustType === 'credit') {
                await walletApi.manualCredit(adjustUserId, Number(adjustAmount), adjustReason, adjustCategory);
                showMsg(`Credited ₹${adjustAmount} to user wallet!`);
            } else {
                await walletApi.manualDebit(adjustUserId, Number(adjustAmount), adjustReason);
                showMsg(`Debited ₹${adjustAmount} from user wallet!`);
            }
            setShowAdjustModal(false);
            setAdjustUserId('');
            setAdjustAmount('');
            setAdjustReason('');
            fetchLedger();
        } catch (err: any) {
            showMsg(err.response?.data?.message || err.message || 'Adjustment failed', 'error');
        }
    };

    const handleToggleFreeze = async () => {
        if (!freezeUserId) return;
        try {
            if (freezeAction === 'freeze') {
                if (!freezeReason) {
                    showMsg('Freeze reason is required', 'error');
                    return;
                }
                await walletApi.freezeWallet(freezeUserId, freezeReason);
                showMsg('User wallet frozen.');
            } else {
                await walletApi.unfreezeWallet(freezeUserId);
                showMsg('User wallet unfrozen.');
            }
            setShowFreezeModal(false);
            setFreezeUserId('');
            setFreezeReason('');
            fetchLedger();
        } catch (err: any) {
            showMsg(err.message || 'Action failed', 'error');
        }
    };

    const handleExportCSV = () => {
        window.open(`/api/admin/wallet/transactions?format=csv`, '_blank');
    };

    return (
        <div className="container-fluid py-4">
            {/* Header Hero Banner */}
            <div className="card border-0 shadow-sm mb-4" style={{ background: 'linear-gradient(135deg, #4338ca 0%, #312e81 60%, #1e1b4b 100%)', borderRadius: '16px' }}>
                <div className="card-body p-4 text-white">
                    <div className="d-flex flex-column flex-md-row justify-content-between align-items-md-center gap-3">
                        <div>
                            <div className="d-flex align-items-center gap-2 mb-1">
                                <span className="p-2 rounded-3 bg-white bg-opacity-10 text-white">
                                    <BiWallet size={26} />
                                </span>
                                <h4 className="fw-bold mb-0 text-white">Smart Credit Wallet & Financial Engine</h4>
                            </div>
                            <p className="mb-0 text-white-50 small">
                                Central financial ledger for Lunara. Track recharges, locked commitment deposits, wallet refunds, and rewards.
                            </p>
                        </div>
                        <div className="d-flex flex-wrap align-items-center gap-2">
                            <button
                                onClick={() => { setShowAdjustModal(true); setAdjustUserId(''); }}
                                className="btn btn-light btn-sm fw-semibold d-flex align-items-center gap-2 shadow-sm"
                            >
                                <BiPlusCircle className="text-primary" size={16} /> Adjust Balance
                            </button>
                            <button
                                onClick={() => { setShowFreezeModal(true); setFreezeUserId(''); }}
                                className="btn btn-warning btn-sm fw-semibold d-flex align-items-center gap-2 shadow-sm text-dark"
                            >
                                <BiLock size={16} /> Freeze / Unfreeze
                            </button>
                            <button
                                onClick={fetchLedger}
                                className="btn btn-outline-light btn-sm d-flex align-items-center gap-1"
                                title="Refresh data"
                            >
                                <BiRefresh size={16} className={loading ? 'fa-spin' : ''} /> Refresh
                            </button>
                        </div>
                    </div>
                </div>
            </div>

            {/* Notification alert */}
            {notification && (
                <div className={`alert ${notification.type === 'success' ? 'alert-success' : 'alert-danger'} d-flex align-items-center gap-2 mb-4 shadow-sm`} role="alert">
                    {notification.type === 'success' ? <BiCheckCircle size={20} /> : <BiXCircle size={20} />}
                    <div>{notification.message}</div>
                </div>
            )}

            {/* Metrics Cards */}
            <div className="row g-3 mb-4">
                <div className="col-xl-3 col-md-6">
                    <div className="card border-0 shadow-sm h-100">
                        <div className="card-body p-3">
                            <div className="d-flex align-items-center justify-content-between mb-2">
                                <span className="text-muted small fw-semibold text-uppercase">Total Recharged</span>
                                <span className="p-2 rounded bg-success-subtle text-success">
                                    <BiWallet size={18} />
                                </span>
                            </div>
                            <h3 className="fw-bold mb-1 text-success">₹{(metrics.totalRecharge || 0).toLocaleString('en-IN')}</h3>
                            <span className="text-muted small">Lifetime User Deposits</span>
                        </div>
                    </div>
                </div>

                <div className="col-xl-3 col-md-6">
                    <div className="card border-0 shadow-sm h-100">
                        <div className="card-body p-3">
                            <div className="d-flex align-items-center justify-content-between mb-2">
                                <span className="text-muted small fw-semibold text-uppercase">Platform Spend</span>
                                <span className="p-2 rounded bg-primary-subtle text-primary">
                                    <BiSolidZap size={18} />
                                </span>
                            </div>
                            <h3 className="fw-bold mb-1 text-primary">₹{(metrics.totalSpent || 0).toLocaleString('en-IN')}</h3>
                            <span className="text-muted small">Bookings, VIP & Boosts</span>
                        </div>
                    </div>
                </div>

                <div className="col-xl-3 col-md-6">
                    <div className="card border-0 shadow-sm h-100">
                        <div className="card-body p-3">
                            <div className="d-flex align-items-center justify-content-between mb-2">
                                <span className="text-muted small fw-semibold text-uppercase">Locked Deposits</span>
                                <span className="p-2 rounded bg-warning-subtle text-warning">
                                    <BiLockAlt size={18} />
                                </span>
                            </div>
                            <h3 className="fw-bold mb-1 text-warning">₹{(metrics.totalLockedDeposits || 0).toLocaleString('en-IN')}</h3>
                            <span className="text-muted small">Active Party Deposits</span>
                        </div>
                    </div>
                </div>

                <div className="col-xl-3 col-md-6">
                    <div className="card border-0 shadow-sm h-100">
                        <div className="card-body p-3">
                            <div className="d-flex align-items-center justify-content-between mb-2">
                                <span className="text-muted small fw-semibold text-uppercase">Processed Refunds</span>
                                <span className="p-2 rounded bg-info-subtle text-info">
                                    <BiUndo size={18} />
                                </span>
                            </div>
                            <h3 className="fw-bold mb-1 text-info">₹{(metrics.totalRefunds || 0).toLocaleString('en-IN')}</h3>
                            <span className="text-muted small">Wallet Refunds Credited</span>
                        </div>
                    </div>
                </div>

                <div className="col-xl-3 col-md-6">
                    <div className="card border-0 shadow-sm h-100">
                        <div className="card-body p-3">
                            <div className="d-flex align-items-center justify-content-between mb-2">
                                <span className="text-muted small fw-semibold text-uppercase">Promotional Grants</span>
                                <span className="p-2 rounded bg-danger-subtle text-danger">
                                    <BiGift size={18} />
                                </span>
                            </div>
                            <h3 className="fw-bold mb-1 text-danger">₹{(metrics.totalPromotional || 0).toLocaleString('en-IN')}</h3>
                            <span className="text-muted small">Admin & Campaign Credits</span>
                        </div>
                    </div>
                </div>

                <div className="col-xl-3 col-md-6">
                    <div className="card border-0 shadow-sm h-100">
                        <div className="card-body p-3">
                            <div className="d-flex align-items-center justify-content-between mb-2">
                                <span className="text-muted small fw-semibold text-uppercase">Cashback & Rewards</span>
                                <span className="p-2 rounded bg-secondary-subtle text-secondary">
                                    <BiCoinStack size={18} />
                                </span>
                            </div>
                            <h3 className="fw-bold mb-1 text-secondary">₹{((metrics.totalCashback || 0) + (metrics.totalRewards || 0)).toLocaleString('en-IN')}</h3>
                            <span className="text-muted small">Earned Rewards & Cashback</span>
                        </div>
                    </div>
                </div>

                <div className="col-xl-3 col-md-6">
                    <div className="card border-0 shadow-sm h-100">
                        <div className="card-body p-3">
                            <div className="d-flex align-items-center justify-content-between mb-2">
                                <span className="text-muted small fw-semibold text-uppercase">Available Pool</span>
                                <span className="p-2 rounded bg-purple-subtle text-purple" style={{ backgroundColor: 'rgba(132, 90, 223, 0.1)', color: '#845adf' }}>
                                    <BiWallet size={18} />
                                </span>
                            </div>
                            <h3 className="fw-bold mb-1" style={{ color: '#845adf' }}>₹{(metrics.totalAvailablePool || 0).toLocaleString('en-IN')}</h3>
                            <span className="text-muted small">System Unspent Balance</span>
                        </div>
                    </div>
                </div>

                <div className="col-xl-3 col-md-6">
                    <div className="card border-0 shadow-sm h-100">
                        <div className="card-body p-3">
                            <div className="d-flex align-items-center justify-content-between mb-2">
                                <span className="text-muted small fw-semibold text-uppercase">Active / Frozen</span>
                                <span className="p-2 rounded bg-dark-subtle text-dark">
                                    <BiDetail size={18} />
                                </span>
                            </div>
                            <h3 className="fw-bold mb-1">
                                {metrics.activeWalletsCount || 0}
                                {metrics.frozenWalletsCount ? (
                                    <span className="text-danger small fs-6 ms-2">({metrics.frozenWalletsCount} frozen)</span>
                                ) : null}
                            </h3>
                            <span className="text-muted small">Total User Wallets</span>
                        </div>
                    </div>
                </div>
            </div>

            {/* Wallet Settings Section */}
            <div className="card border-0 shadow-sm mb-4">
                <div className="card-header bg-transparent border-0 pt-3 pb-2 d-flex align-items-center gap-2">
                    <BiSliderAlt size={18} className="text-primary" />
                    <h5 className="fw-bold mb-0">Recharge & Wallet Controls</h5>
                </div>
                <div className="card-body">
                    <form onSubmit={handleSaveConfig} className="row g-3">
                        <div className="col-md-4">
                            <label className="form-label small fw-semibold text-muted">Minimum Recharge (₹)</label>
                            <input
                                type="number"
                                value={config.minRechargeAmount}
                                onChange={(e) => setConfig({ ...config, minRechargeAmount: Number(e.target.value) })}
                                className="form-control"
                            />
                        </div>

                        <div className="col-md-4">
                            <label className="form-label small fw-semibold text-muted">Maximum Recharge (₹)</label>
                            <input
                                type="number"
                                value={config.maxRechargeAmount}
                                onChange={(e) => setConfig({ ...config, maxRechargeAmount: Number(e.target.value) })}
                                className="form-control"
                            />
                        </div>

                        <div className="col-md-4">
                            <label className="form-label small fw-semibold text-muted">Suggested Chips (comma separated)</label>
                            <input
                                type="text"
                                value={config.suggestedAmounts ? config.suggestedAmounts.join(', ') : ''}
                                onChange={(e) => setConfig({
                                    ...config,
                                    suggestedAmounts: e.target.value.split(',').map((s) => Number(s.trim())).filter((n) => !isNaN(n) && n > 0),
                                })}
                                className="form-control"
                            />
                        </div>

                        <div className="col-md-4">
                            <label className="form-label small fw-semibold text-muted">Daily Limit per User (₹)</label>
                            <input
                                type="number"
                                value={config.dailyRechargeLimit}
                                onChange={(e) => setConfig({ ...config, dailyRechargeLimit: Number(e.target.value) })}
                                className="form-control"
                            />
                        </div>

                        <div className="col-md-4">
                            <label className="form-label small fw-semibold text-muted">Monthly Limit per User (₹)</label>
                            <input
                                type="number"
                                value={config.monthlyRechargeLimit}
                                onChange={(e) => setConfig({ ...config, monthlyRechargeLimit: Number(e.target.value) })}
                                className="form-control"
                            />
                        </div>

                        <div className="col-md-4 d-flex align-items-center pt-md-4">
                            <div className="form-check form-switch">
                                <input
                                    type="checkbox"
                                    role="switch"
                                    id="walletActiveSwitch"
                                    checked={config.isWalletActive}
                                    onChange={(e) => setConfig({ ...config, isWalletActive: e.target.checked })}
                                    className="form-check-input"
                                    style={{ cursor: 'pointer' }}
                                />
                                <label className="form-check-label fw-semibold ms-2" htmlFor="walletActiveSwitch">
                                    Smart Wallet Feature Enabled
                                </label>
                            </div>
                        </div>

                        <div className="col-12 text-end">
                            <button
                                type="submit"
                                disabled={savingConfig}
                                className="btn btn-primary px-4 fw-semibold"
                            >
                                {savingConfig ? 'Saving Settings...' : 'Save Configuration'}
                            </button>
                        </div>
                    </form>
                </div>
            </div>

            {/* Transaction Ledger Table Card */}
            <div className="card border-0 shadow-sm">
                <div className="card-header bg-transparent border-0 pt-3 pb-2">
                    <div className="d-flex flex-column flex-md-row justify-content-between align-items-md-center gap-3">
                        <div>
                            <div className="d-flex align-items-center gap-2">
                                <BiListUl size={20} className="text-primary" />
                                <h5 className="fw-bold mb-0">Transaction Audit Ledger</h5>
                            </div>
                            <p className="text-muted small mb-0 mt-0.5">
                                Immutable financial ledger records for recharges, deposits, refunds, and spend.
                            </p>
                        </div>

                        <div className="d-flex flex-wrap align-items-center gap-2">
                            <div className="input-group input-group-sm" style={{ width: '220px' }}>
                                <span className="input-group-text bg-light border-end-0">
                                    <BiSearch className="text-muted" />
                                </span>
                                <input
                                    type="text"
                                    placeholder="Search user / email..."
                                    value={search}
                                    onChange={(e) => setSearch(e.target.value)}
                                    onKeyDown={(e) => e.key === 'Enter' && fetchLedger()}
                                    className="form-control form-control-sm border-start-0"
                                />
                            </div>

                            <select
                                value={typeFilter}
                                onChange={(e) => setTypeFilter(e.target.value)}
                                className="form-select form-select-sm"
                                style={{ width: '150px' }}
                            >
                                <option value="ALL">All Types</option>
                                <option value="recharge">Recharge</option>
                                <option value="booking_payment">Booking Payment</option>
                                <option value="commitment_deposit">Commitment Deposit</option>
                                <option value="deposit_unlock">Deposit Unlock</option>
                                <option value="refund">Refund</option>
                                <option value="vip_purchase">VIP Purchase</option>
                                <option value="super_like_purchase">Super Likes</option>
                                <option value="boost_purchase">Profile Boost</option>
                                <option value="promotional_credit">Promotional Credit</option>
                                <option value="cashback_credit">Cashback Credit</option>
                                <option value="reward_credit">Reward Credit</option>
                                <option value="admin_credit">Admin Credit</option>
                                <option value="admin_debit">Admin Debit</option>
                            </select>

                            <select
                                value={statusFilter}
                                onChange={(e) => setStatusFilter(e.target.value)}
                                className="form-select form-select-sm"
                                style={{ width: '130px' }}
                            >
                                <option value="ALL">All Statuses</option>
                                <option value="success">Success</option>
                                <option value="locked">Locked</option>
                                <option value="pending">Pending</option>
                                <option value="failed">Failed</option>
                                <option value="cancelled">Cancelled</option>
                            </select>

                            <button
                                onClick={handleExportCSV}
                                className="btn btn-outline-secondary btn-sm d-flex align-items-center gap-1"
                            >
                                <BiDownload size={14} /> Export CSV
                            </button>
                        </div>
                    </div>
                </div>

                <div className="card-body p-0">
                    <div className="table-responsive">
                        <table className="table table-hover align-middle mb-0 small">
                            <thead className="table-light">
                                <tr>
                                    <th className="px-3 py-2">User</th>
                                    <th>Type</th>
                                    <th>Amount</th>
                                    <th>Opening Bal</th>
                                    <th>Closing Bal</th>
                                    <th>Status</th>
                                    <th>Reference</th>
                                    <th className="px-3">Date & Time</th>
                                </tr>
                            </thead>
                            <tbody>
                                {loading ? (
                                    <tr>
                                        <td colSpan={8} className="text-center py-5 text-muted">
                                            <div className="spinner-border spinner-border-sm text-primary mb-2" />
                                            <div>Loading financial ledger records...</div>
                                        </td>
                                    </tr>
                                ) : transactions.length === 0 ? (
                                    <tr>
                                        <td colSpan={8} className="text-center py-5 text-muted">
                                            No wallet transactions found matching filters.
                                        </td>
                                    </tr>
                                ) : (
                                    transactions.map((t) => {
                                        const isDebit = t.transactionType.includes('debit') ||
                                            t.transactionType.includes('purchase') ||
                                            t.transactionType === 'commitment_deposit';
                                        return (
                                            <tr key={t.id}>
                                                <td className="px-3">
                                                    <div className="fw-semibold">
                                                        {t.user ? `${t.user.firstName || ''} ${t.user.lastName || ''}`.trim() : 'System User'}
                                                    </div>
                                                    <div className="text-muted" style={{ fontSize: '0.75rem' }}>
                                                        {t.user?.email || t.userId}
                                                    </div>
                                                </td>
                                                <td>
                                                    <span className="badge bg-light text-dark border text-uppercase" style={{ fontSize: '0.68rem' }}>
                                                        {t.transactionType.replace(/_/g, ' ')}
                                                    </span>
                                                </td>
                                                <td className={`fw-bold ${isDebit ? 'text-danger' : 'text-success'}`}>
                                                    {isDebit ? `-₹${t.amount}` : `+₹${t.amount}`}
                                                </td>
                                                <td>₹{t.openingBalance}</td>
                                                <td className="fw-semibold">₹{t.closingBalance}</td>
                                                <td>
                                                    <span className={`badge rounded-pill ${
                                                        t.status === 'success' ? 'bg-success-subtle text-success' :
                                                        t.status === 'locked' ? 'bg-warning-subtle text-warning' :
                                                        'bg-danger-subtle text-danger'
                                                    }`}>
                                                        {t.status.toUpperCase()}
                                                    </span>
                                                </td>
                                                <td className="text-muted font-monospace" style={{ fontSize: '0.75rem' }}>
                                                    {t.reference || '—'}
                                                </td>
                                                <td className="px-3 text-muted" style={{ fontSize: '0.75rem' }}>
                                                    {new Date(t.createdAt).toLocaleString('en-IN')}
                                                </td>
                                            </tr>
                                        );
                                    })
                                )}
                            </tbody>
                        </table>
                    </div>
                </div>

                {/* Pagination */}
                <div className="card-footer bg-transparent border-0 d-flex justify-content-between align-items-center py-3">
                    <span className="text-muted small">
                        Page {page} of {totalPages || 1}
                    </span>
                    <div className="btn-group btn-group-sm">
                        <button
                            disabled={page <= 1}
                            onClick={() => setPage(page - 1)}
                            className="btn btn-outline-secondary"
                        >
                            Previous
                        </button>
                        <button
                            disabled={page >= totalPages}
                            onClick={() => setPage(page + 1)}
                            className="btn btn-outline-secondary"
                        >
                            Next
                        </button>
                    </div>
                </div>
            </div>

            {/* Manual Adjustment Modal */}
            {showAdjustModal && (
                <div className="modal show d-block" style={{ backgroundColor: 'rgba(0,0,0,0.5)' }} tabIndex={-1}>
                    <div className="modal-dialog modal-dialog-centered">
                        <div className="modal-content shadow-lg border-0" style={{ borderRadius: '16px' }}>
                            <div className="modal-header border-0 pb-0">
                                <h5 className="modal-title fw-bold">Manual Balance Adjustment</h5>
                                <button type="button" className="btn-close" onClick={() => setShowAdjustModal(false)} />
                            </div>
                            <div className="modal-body">
                                <div className="mb-3">
                                    <label className="form-label small fw-semibold text-muted">Target User ID (UUID)</label>
                                    <input
                                        type="text"
                                        placeholder="e.g. 550e8400-e29b-41d4-a716-446655440000"
                                        value={adjustUserId}
                                        onChange={(e) => setAdjustUserId(e.target.value)}
                                        className="form-control"
                                    />
                                </div>
                                <div className="row g-2 mb-3">
                                    <div className="col-6">
                                        <label className="form-label small fw-semibold text-muted">Adjustment Type</label>
                                        <select
                                            value={adjustType}
                                            onChange={(e) => setAdjustType(e.target.value as any)}
                                            className="form-select"
                                        >
                                            <option value="credit">Credit (+)</option>
                                            <option value="debit">Debit (-)</option>
                                        </select>
                                    </div>
                                    <div className="col-6">
                                        <label className="form-label small fw-semibold text-muted">Credit Category</label>
                                        <select
                                            value={adjustCategory}
                                            onChange={(e) => setAdjustCategory(e.target.value as any)}
                                            className="form-select"
                                        >
                                            <option value="regular">Regular Cash</option>
                                            <option value="promotional">Promotional</option>
                                            <option value="reward">Reward Credits</option>
                                        </select>
                                    </div>
                                </div>
                                <div className="mb-3">
                                    <label className="form-label small fw-semibold text-muted">Amount (₹)</label>
                                    <input
                                        type="number"
                                        placeholder="e.g. 500"
                                        value={adjustAmount}
                                        onChange={(e) => setAdjustAmount(e.target.value ? Number(e.target.value) : '')}
                                        className="form-control"
                                    />
                                </div>
                                <div className="mb-3">
                                    <label className="form-label small fw-semibold text-muted">Reason (Audit Trail Required)</label>
                                    <textarea
                                        placeholder="Enter specific audit reason for this adjustment..."
                                        value={adjustReason}
                                        onChange={(e) => setAdjustReason(e.target.value)}
                                        rows={3}
                                        className="form-control"
                                    />
                                </div>
                            </div>
                            <div className="modal-footer border-0 pt-0">
                                <button
                                    type="button"
                                    className="btn btn-light"
                                    onClick={() => setShowAdjustModal(false)}
                                >
                                    Cancel
                                </button>
                                <button
                                    type="button"
                                    className="btn btn-primary"
                                    onClick={handleExecuteAdjustment}
                                >
                                    Execute Adjustment
                                </button>
                            </div>
                        </div>
                    </div>
                </div>
            )}

            {/* Freeze / Unfreeze Modal */}
            {showFreezeModal && (
                <div className="modal show d-block" style={{ backgroundColor: 'rgba(0,0,0,0.5)' }} tabIndex={-1}>
                    <div className="modal-dialog modal-dialog-centered">
                        <div className="modal-content shadow-lg border-0" style={{ borderRadius: '16px' }}>
                            <div className="modal-header border-0 pb-0">
                                <h5 className="modal-title fw-bold">Wallet Lock / Freeze Controls</h5>
                                <button type="button" className="btn-close" onClick={() => setShowFreezeModal(false)} />
                            </div>
                            <div className="modal-body">
                                <div className="mb-3">
                                    <label className="form-label small fw-semibold text-muted">User ID (UUID)</label>
                                    <input
                                        type="text"
                                        placeholder="User UUID"
                                        value={freezeUserId}
                                        onChange={(e) => setFreezeUserId(e.target.value)}
                                        className="form-control"
                                    />
                                </div>
                                <div className="mb-3">
                                    <label className="form-label small fw-semibold text-muted">Action</label>
                                    <select
                                        value={freezeAction}
                                        onChange={(e) => setFreezeAction(e.target.value as any)}
                                        className="form-select"
                                    >
                                        <option value="freeze">Freeze Wallet</option>
                                        <option value="unfreeze">Unfreeze Wallet</option>
                                    </select>
                                </div>
                                {freezeAction === 'freeze' && (
                                    <div className="mb-3">
                                        <label className="form-label small fw-semibold text-muted">Freeze Reason</label>
                                        <input
                                            type="text"
                                            placeholder="Reason for suspension..."
                                            value={freezeReason}
                                            onChange={(e) => setFreezeReason(e.target.value)}
                                            className="form-control"
                                        />
                                    </div>
                                )}
                            </div>
                            <div className="modal-footer border-0 pt-0">
                                <button
                                    type="button"
                                    className="btn btn-light"
                                    onClick={() => setShowFreezeModal(false)}
                                >
                                    Cancel
                                </button>
                                <button
                                    type="button"
                                    className="btn btn-warning text-dark fw-semibold"
                                    onClick={handleToggleFreeze}
                                >
                                    Confirm Action
                                </button>
                            </div>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
};

export default WalletManagement;
