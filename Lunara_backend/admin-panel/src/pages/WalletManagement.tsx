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
        <div className="p-6 max-w-7xl mx-auto space-y-6">
            {/* Header */}
            <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 bg-gradient-to-r from-purple-900 via-indigo-900 to-slate-900 p-6 rounded-2xl text-white shadow-xl">
                <div>
                    <div className="flex items-center gap-3">
                        <BiWallet className="text-3xl text-purple-300" />
                        <h1 className="text-2xl font-bold">Smart Credit Wallet & Financial Engine</h1>
                    </div>
                    <p className="text-purple-200 text-sm mt-1">
                        Central financial ledger for Lunara. Track recharges, locked commitment deposits, wallet refunds, and rewards.
                    </p>
                </div>
                <div className="flex items-center gap-3">
                    <button
                        onClick={() => { setShowAdjustModal(true); setAdjustUserId(''); }}
                        className="flex items-center gap-2 bg-purple-600 hover:bg-purple-500 px-4 py-2 rounded-xl text-sm font-semibold transition"
                    >
                        <BiPlusCircle className="text-lg" /> Adjust User Balance
                    </button>
                    <button
                        onClick={() => { setShowFreezeModal(true); setFreezeUserId(''); }}
                        className="flex items-center gap-2 bg-amber-600 hover:bg-amber-500 px-4 py-2 rounded-xl text-sm font-semibold transition"
                    >
                        <BiLock className="text-lg" /> Freeze / Unfreeze
                    </button>
                </div>
            </div>

            {notification && (
                <div className={`p-4 rounded-xl text-sm font-medium flex items-center gap-2 ${notification.type === 'success' ? 'bg-emerald-900/40 border border-emerald-500 text-emerald-200' : 'bg-rose-900/40 border border-rose-500 text-rose-200'}`}>
                    {notification.type === 'success' ? <BiCheckCircle className="text-lg text-emerald-400" /> : <BiXCircle className="text-lg text-rose-400" />}
                    {notification.message}
                </div>
            )}

            {/* Metrics Grid */}
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
                <div className="bg-slate-900/60 border border-slate-800 p-5 rounded-2xl">
                    <div className="flex items-center justify-between text-slate-400 text-xs font-semibold uppercase">
                        <span>Total Recharged</span>
                        <BiWallet className="text-xl text-emerald-400" />
                    </div>
                    <div className="text-2xl font-bold text-white mt-2">₹{metrics.totalRecharge.toLocaleString()}</div>
                    <span className="text-xs text-emerald-400 font-medium">Lifetime User Deposits</span>
                </div>

                <div className="bg-slate-900/60 border border-slate-800 p-5 rounded-2xl">
                    <div className="flex items-center justify-between text-slate-400 text-xs font-semibold uppercase">
                        <span>Total Platform Spend</span>
                        <BiSolidZap className="text-xl text-purple-400" />
                    </div>
                    <div className="text-2xl font-bold text-white mt-2">₹{metrics.totalSpent.toLocaleString()}</div>
                    <span className="text-xs text-purple-400 font-medium">Bookings, VIP & Boosts</span>
                </div>

                <div className="bg-slate-900/60 border border-slate-800 p-5 rounded-2xl">
                    <div className="flex items-center justify-between text-slate-400 text-xs font-semibold uppercase">
                        <span>Locked Deposits</span>
                        <BiLockAlt className="text-xl text-amber-400" />
                    </div>
                    <div className="text-2xl font-bold text-white mt-2">₹{metrics.totalLockedDeposits.toLocaleString()}</div>
                    <span className="text-xs text-amber-400 font-medium">Active Party Deposits</span>
                </div>

                <div className="bg-slate-900/60 border border-slate-800 p-5 rounded-2xl">
                    <div className="flex items-center justify-between text-slate-400 text-xs font-semibold uppercase">
                        <span>Processed Refunds</span>
                        <BiUndo className="text-xl text-cyan-400" />
                    </div>
                    <div className="text-2xl font-bold text-white mt-2">₹{metrics.totalRefunds.toLocaleString()}</div>
                    <span className="text-xs text-cyan-400 font-medium">Wallet Refunds Credited</span>
                </div>

                <div className="bg-slate-900/60 border border-slate-800 p-5 rounded-2xl">
                    <div className="flex items-center justify-between text-slate-400 text-xs font-semibold uppercase">
                        <span>Promotional Grants</span>
                        <BiGift className="text-xl text-pink-400" />
                    </div>
                    <div className="text-2xl font-bold text-white mt-2">₹{metrics.totalPromotional.toLocaleString()}</div>
                    <span className="text-xs text-pink-400 font-medium">Admin & Campaign Credits</span>
                </div>

                <div className="bg-slate-900/60 border border-slate-800 p-5 rounded-2xl">
                    <div className="flex items-center justify-between text-slate-400 text-xs font-semibold uppercase">
                        <span>Cashback & Rewards</span>
                        <BiCoinStack className="text-xl text-yellow-400" />
                    </div>
                    <div className="text-2xl font-bold text-white mt-2">₹{(metrics.totalCashback + metrics.totalRewards).toLocaleString()}</div>
                    <span className="text-xs text-yellow-400 font-medium">Earned Rewards & Cashback</span>
                </div>

                <div className="bg-slate-900/60 border border-slate-800 p-5 rounded-2xl">
                    <div className="flex items-center justify-between text-slate-400 text-xs font-semibold uppercase">
                        <span>Total Available Pool</span>
                        <BiWallet className="text-xl text-indigo-400" />
                    </div>
                    <div className="text-2xl font-bold text-white mt-2">₹{metrics.totalAvailablePool.toLocaleString()}</div>
                    <span className="text-xs text-indigo-400 font-medium">System Unspent Pool</span>
                </div>

                <div className="bg-slate-900/60 border border-slate-800 p-5 rounded-2xl">
                    <div className="flex items-center justify-between text-slate-400 text-xs font-semibold uppercase">
                        <span>Active / Frozen Wallets</span>
                        <BiDetail className="text-xl text-slate-400" />
                    </div>
                    <div className="text-2xl font-bold text-white mt-2">{metrics.activeWalletsCount} <span className="text-xs text-rose-400">/ {metrics.frozenWalletsCount} Frozen</span></div>
                    <span className="text-xs text-slate-400 font-medium">Total Registered Wallets</span>
                </div>
            </div>

            {/* Config & Controls Section */}
            <div className="bg-slate-900/60 border border-slate-800 rounded-2xl p-6">
                <h2 className="text-lg font-bold text-white mb-4">Recharge & Wallet Controls</h2>
                <form onSubmit={handleSaveConfig} className="grid grid-cols-1 md:grid-cols-3 gap-6">
                    <div>
                        <label className="block text-xs font-semibold text-slate-400 mb-1">Minimum Recharge (₹)</label>
                        <input
                            type="number"
                            value={config.minRechargeAmount}
                            onChange={(e) => setConfig({ ...config, minRechargeAmount: Number(e.target.value) })}
                            className="w-full bg-slate-950 border border-slate-800 rounded-xl px-4 py-2 text-white text-sm focus:outline-none focus:border-purple-500"
                        />
                    </div>

                    <div>
                        <label className="block text-xs font-semibold text-slate-400 mb-1">Maximum Recharge (₹)</label>
                        <input
                            type="number"
                            value={config.maxRechargeAmount}
                            onChange={(e) => setConfig({ ...config, maxRechargeAmount: Number(e.target.value) })}
                            className="w-full bg-slate-950 border border-slate-800 rounded-xl px-4 py-2 text-white text-sm focus:outline-none focus:border-purple-500"
                        />
                    </div>

                    <div>
                        <label className="block text-xs font-semibold text-slate-400 mb-1">Suggested Chips (comma separated)</label>
                        <input
                            type="text"
                            value={config.suggestedAmounts ? config.suggestedAmounts.join(', ') : ''}
                            onChange={(e) => setConfig({
                                ...config,
                                suggestedAmounts: e.target.value.split(',').map((s) => Number(s.trim())).filter((n) => !isNaN(n) && n > 0),
                            })}
                            className="w-full bg-slate-950 border border-slate-800 rounded-xl px-4 py-2 text-white text-sm focus:outline-none focus:border-purple-500"
                        />
                    </div>

                    <div>
                        <label className="block text-xs font-semibold text-slate-400 mb-1">Daily Recharge Limit per User (₹)</label>
                        <input
                            type="number"
                            value={config.dailyRechargeLimit}
                            onChange={(e) => setConfig({ ...config, dailyRechargeLimit: Number(e.target.value) })}
                            className="w-full bg-slate-950 border border-slate-800 rounded-xl px-4 py-2 text-white text-sm focus:outline-none focus:border-purple-500"
                        />
                    </div>

                    <div>
                        <label className="block text-xs font-semibold text-slate-400 mb-1">Monthly Recharge Limit per User (₹)</label>
                        <input
                            type="number"
                            value={config.monthlyRechargeLimit}
                            onChange={(e) => setConfig({ ...config, monthlyRechargeLimit: Number(e.target.value) })}
                            className="w-full bg-slate-950 border border-slate-800 rounded-xl px-4 py-2 text-white text-sm focus:outline-none focus:border-purple-500"
                        />
                    </div>

                    <div className="flex items-end">
                        <label className="flex items-center gap-3 cursor-pointer">
                            <input
                                type="checkbox"
                                checked={config.isWalletActive}
                                onChange={(e) => setConfig({ ...config, isWalletActive: e.target.checked })}
                                className="w-5 h-5 accent-purple-600 rounded"
                            />
                            <span className="text-sm font-semibold text-white">Smart Wallet Enabled</span>
                        </label>
                    </div>

                    <div className="md:col-span-3 flex justify-end">
                        <button
                            type="submit"
                            disabled={savingConfig}
                            className="bg-purple-600 hover:bg-purple-500 text-white text-sm font-semibold px-6 py-2.5 rounded-xl transition disabled:opacity-50"
                        >
                            {savingConfig ? 'Saving Settings...' : 'Save Configuration'}
                        </button>
                    </div>
                </form>
            </div>

            {/* Transaction Ledger Table */}
            <div className="bg-slate-900/60 border border-slate-800 rounded-2xl p-6">
                <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 mb-6">
                    <div>
                        <h2 className="text-lg font-bold text-white">Transaction Audit Ledger</h2>
                        <p className="text-slate-400 text-xs mt-0.5">Immutable financial ledger records for recharges, deposits, refunds, and feature spend.</p>
                    </div>

                    <div className="flex flex-wrap items-center gap-3">
                        <div className="relative">
                            <BiSearch className="absolute left-3 top-2.5 text-slate-400" />
                            <input
                                type="text"
                                placeholder="Search user name or email..."
                                value={search}
                                onChange={(e) => setSearch(e.target.value)}
                                onKeyDown={(e) => e.key === 'Enter' && fetchLedger()}
                                className="bg-slate-950 border border-slate-800 text-white text-xs rounded-xl pl-9 pr-4 py-2 focus:outline-none focus:border-purple-500 w-60"
                            />
                        </div>

                        <select
                            value={typeFilter}
                            onChange={(e) => setTypeFilter(e.target.value)}
                            className="bg-slate-950 border border-slate-800 text-white text-xs rounded-xl px-3 py-2 focus:outline-none focus:border-purple-500"
                        >
                            <option value="ALL">All Types</option>
                            <option value="recharge">Recharge</option>
                            <option value="booking_payment">Booking Payment</option>
                            <option value="commitment_deposit">Commitment Deposit Lock</option>
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
                            className="bg-slate-950 border border-slate-800 text-white text-xs rounded-xl px-3 py-2 focus:outline-none focus:border-purple-500"
                        >
                            <option value="ALL">All Statuses</option>
                            <option value="success">Success</option>
                            <option value="locked">Locked</option>
                            <option value="pending">Pending</option>
                            <option value="failed">Failed</option>
                            <option value="cancelled">Cancelled</option>
                        </select>

                        <button
                            onClick={fetchLedger}
                            className="p-2 bg-slate-800 hover:bg-slate-700 text-white rounded-xl transition"
                            title="Refresh"
                        >
                            <BiRefresh className={`text-lg ${loading ? 'animate-spin' : ''}`} />
                        </button>

                        <button
                            onClick={handleExportCSV}
                            className="flex items-center gap-2 bg-slate-800 hover:bg-slate-700 text-white text-xs font-semibold px-3 py-2 rounded-xl transition"
                        >
                            <BiDownload className="text-base" /> Export CSV
                        </button>
                    </div>
                </div>

                <div className="overflow-x-auto">
                    <table className="w-full text-left text-xs text-slate-300">
                        <thead className="bg-slate-950 text-slate-400 font-semibold uppercase border-b border-slate-800">
                            <tr>
                                <th className="p-3">User</th>
                                <th className="p-3">Type</th>
                                <th className="p-3">Amount</th>
                                <th className="p-3">Opening Bal</th>
                                <th className="p-3">Closing Bal</th>
                                <th className="p-3">Status</th>
                                <th className="p-3">Reference</th>
                                <th className="p-3">Date</th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-slate-800/50">
                            {loading ? (
                                <tr>
                                    <td colSpan={8} className="p-8 text-center text-slate-500">Loading financial ledger...</td>
                                </tr>
                            ) : transactions.length === 0 ? (
                                <tr>
                                    <td colSpan={8} className="p-8 text-center text-slate-500">No transactions found matching filters.</td>
                                </tr>
                            ) : (
                                transactions.map((t) => (
                                    <tr key={t.id} className="hover:bg-slate-800/30 transition">
                                        <td className="p-3">
                                            <div className="font-semibold text-white">{t.user ? `${t.user.firstName} ${t.user.lastName}` : 'System User'}</div>
                                            <div className="text-[11px] text-slate-400">{t.user?.email || t.userId}</div>
                                        </td>
                                        <td className="p-3">
                                            <span className="px-2 py-1 rounded-md text-[10px] font-bold bg-slate-800 text-purple-300 uppercase">
                                                {t.transactionType}
                                            </span>
                                        </td>
                                        <td className={`p-3 font-semibold ${t.transactionType.includes('debit') || t.transactionType.includes('purchase') || t.transactionType.includes('deposit') ? 'text-rose-400' : 'text-emerald-400'}`}>
                                            {t.transactionType.includes('debit') || t.transactionType.includes('purchase') || t.transactionType === 'commitment_deposit' ? `-₹${t.amount}` : `+₹${t.amount}`}
                                        </td>
                                        <td className="p-3">₹{t.openingBalance}</td>
                                        <td className="p-3 font-semibold text-white">₹{t.closingBalance}</td>
                                        <td className="p-3">
                                            <span className={`px-2 py-0.5 rounded text-[10px] font-bold ${t.status === 'success' ? 'bg-emerald-900/40 text-emerald-400 border border-emerald-800' : t.status === 'locked' ? 'bg-amber-900/40 text-amber-400 border border-amber-800' : 'bg-rose-900/40 text-rose-400 border border-rose-800'}`}>
                                                {t.status.toUpperCase()}
                                            </span>
                                        </td>
                                        <td className="p-3 text-slate-400 font-mono text-[11px]">{t.reference || 'N/A'}</td>
                                        <td className="p-3 text-slate-400">{new Date(t.createdAt).toLocaleString()}</td>
                                    </tr>
                                ))
                            )}
                        </tbody>
                    </table>
                </div>

                {/* Pagination Controls */}
                <div className="flex items-center justify-between mt-4 text-xs text-slate-400">
                    <div>Page {page} of {totalPages}</div>
                    <div className="flex gap-2">
                        <button
                            disabled={page <= 1}
                            onClick={() => setPage(page - 1)}
                            className="px-3 py-1 bg-slate-800 hover:bg-slate-700 text-white rounded-lg disabled:opacity-40"
                        >
                            Previous
                        </button>
                        <button
                            disabled={page >= totalPages}
                            onClick={() => setPage(page + 1)}
                            className="px-3 py-1 bg-slate-800 hover:bg-slate-700 text-white rounded-lg disabled:opacity-40"
                        >
                            Next
                        </button>
                    </div>
                </div>
            </div>

            {/* Adjust Modal */}
            {showAdjustModal && (
                <div className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4 z-50">
                    <div className="bg-slate-900 border border-slate-800 rounded-2xl max-w-md w-full p-6 space-y-4 shadow-2xl">
                        <h3 className="text-lg font-bold text-white">Manual Balance Adjustment</h3>
                        <div>
                            <label className="block text-xs text-slate-400 mb-1">Target User ID</label>
                            <input
                                type="text"
                                placeholder="UUID of the user"
                                value={adjustUserId}
                                onChange={(e) => setAdjustUserId(e.target.value)}
                                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-4 py-2 text-white text-sm focus:outline-none focus:border-purple-500"
                            />
                        </div>
                        <div className="grid grid-cols-2 gap-3">
                            <div>
                                <label className="block text-xs text-slate-400 mb-1">Adjustment Type</label>
                                <select
                                    value={adjustType}
                                    onChange={(e) => setAdjustType(e.target.value as any)}
                                    className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-white text-sm focus:outline-none focus:border-purple-500"
                                >
                                    <option value="credit">Credit (+)</option>
                                    <option value="debit">Debit (-)</option>
                                </select>
                            </div>
                            <div>
                                <label className="block text-xs text-slate-400 mb-1">Credit Category</label>
                                <select
                                    value={adjustCategory}
                                    onChange={(e) => setAdjustCategory(e.target.value as any)}
                                    className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-white text-sm focus:outline-none focus:border-purple-500"
                                >
                                    <option value="regular">Regular Cash</option>
                                    <option value="promotional">Promotional</option>
                                    <option value="reward">Reward Credits</option>
                                </select>
                            </div>
                        </div>
                        <div>
                            <label className="block text-xs text-slate-400 mb-1">Amount (₹)</label>
                            <input
                                type="number"
                                placeholder="e.g. 500"
                                value={adjustAmount}
                                onChange={(e) => setAdjustAmount(e.target.value ? Number(e.target.value) : '')}
                                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-4 py-2 text-white text-sm focus:outline-none focus:border-purple-500"
                            />
                        </div>
                        <div>
                            <label className="block text-xs text-slate-400 mb-1">Reason (Mandatory Audit Log)</label>
                            <textarea
                                placeholder="Enter specific reason for this adjustment..."
                                value={adjustReason}
                                onChange={(e) => setAdjustReason(e.target.value)}
                                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-4 py-2 text-white text-sm focus:outline-none focus:border-purple-500 h-20"
                            />
                        </div>
                        <div className="flex justify-end gap-3 pt-2">
                            <button
                                onClick={() => setShowAdjustModal(false)}
                                className="px-4 py-2 text-xs font-semibold text-slate-400 hover:text-white"
                            >
                                Cancel
                            </button>
                            <button
                                onClick={handleExecuteAdjustment}
                                className="bg-purple-600 hover:bg-purple-500 text-white text-xs font-semibold px-4 py-2 rounded-xl"
                            >
                                Execute Adjustment
                            </button>
                        </div>
                    </div>
                </div>
            )}

            {/* Freeze Modal */}
            {showFreezeModal && (
                <div className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4 z-50">
                    <div className="bg-slate-900 border border-slate-800 rounded-2xl max-w-md w-full p-6 space-y-4 shadow-2xl">
                        <h3 className="text-lg font-bold text-white">Wallet Lock / Freeze Controls</h3>
                        <div>
                            <label className="block text-xs text-slate-400 mb-1">User ID</label>
                            <input
                                type="text"
                                placeholder="User UUID"
                                value={freezeUserId}
                                onChange={(e) => setFreezeUserId(e.target.value)}
                                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-4 py-2 text-white text-sm focus:outline-none focus:border-purple-500"
                            />
                        </div>
                        <div>
                            <label className="block text-xs text-slate-400 mb-1">Action</label>
                            <select
                                value={freezeAction}
                                onChange={(e) => setFreezeAction(e.target.value as any)}
                                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-3 py-2 text-white text-sm focus:outline-none focus:border-purple-500"
                            >
                                <option value="freeze">Freeze Wallet</option>
                                <option value="unfreeze">Unfreeze Wallet</option>
                            </select>
                        </div>
                        {freezeAction === 'freeze' && (
                            <div>
                                <label className="block text-xs text-slate-400 mb-1">Freeze Reason</label>
                                <input
                                    type="text"
                                    placeholder="Reason for suspension..."
                                    value={freezeReason}
                                    onChange={(e) => setFreezeReason(e.target.value)}
                                    className="w-full bg-slate-950 border border-slate-800 rounded-xl px-4 py-2 text-white text-sm focus:outline-none focus:border-purple-500"
                                />
                            </div>
                        )}
                        <div className="flex justify-end gap-3 pt-2">
                            <button
                                onClick={() => setShowFreezeModal(false)}
                                className="px-4 py-2 text-xs font-semibold text-slate-400 hover:text-white"
                            >
                                Cancel
                            </button>
                            <button
                                onClick={handleToggleFreeze}
                                className="bg-amber-600 hover:bg-amber-500 text-white text-xs font-semibold px-4 py-2 rounded-xl"
                            >
                                Confirm Action
                            </button>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
};

export default WalletManagement;
