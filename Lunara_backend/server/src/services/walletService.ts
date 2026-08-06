import crypto from 'crypto';
import { Transaction } from 'sequelize';
import sequelize from '../config/database';
import { logger } from '../config/logger';
import User from '../models/User';
import SmartWallet from '../models/SmartWallet';
import SmartWalletConfig from '../models/SmartWalletConfig';
import WalletTransaction, { WalletTransactionType, WalletTransactionStatus } from '../models/WalletTransaction';
import WalletCashbackRule, { CashbackTriggerType, CashbackType } from '../models/WalletCashbackRule';
import AuditLog from '../models/AuditLog';
import Notification from '../models/Notification';

export interface SmartRechargeOptions {
    insufficientBalance: boolean;
    currentBalance: number;
    requiredPrice: number;
    neededAmount: number;
    suggestedRecharges: number[];
    minRecharge: number;
    maxRecharge: number;
}

export class WalletService {
    /**
     * Get or create a SmartWallet record for a user.
     * Keeps User.walletBalance in sync with SmartWallet totalAvailableBalance.
     */
    public static async getOrCreateWallet(userId: string, transaction?: Transaction): Promise<SmartWallet> {
        let wallet = await SmartWallet.findOne({ where: { userId }, transaction });
        if (!wallet) {
            const user = await User.findByPk(userId, { transaction });
            const initialBalance = user?.walletBalance ? Number(user.walletBalance) : 0.00;

            wallet = await SmartWallet.create(
                {
                    userId,
                    balance: initialBalance,
                    lockedBalance: 0.00,
                    pendingBalance: 0.00,
                    promotionalBalance: 0.00,
                    cashbackBalance: 0.00,
                    rewardBalance: 0.00,
                    lifetimeRecharged: 0.00,
                    lifetimeSpent: 0.00,
                    lifetimePromotional: 0.00,
                    lifetimeCashback: 0.00,
                    lifetimeRewards: 0.00,
                    lifetimeRefunds: 0.00,
                    isFrozen: false,
                },
                { transaction }
            );
        }
        return wallet;
    }

    /**
     * Get global wallet configuration settings.
     */
    public static async getGlobalConfig(): Promise<SmartWalletConfig> {
        let config = await SmartWalletConfig.findOne({ where: { scope: 'global' } });
        if (!config) {
            config = await SmartWalletConfig.create({
                scope: 'global',
                minRechargeAmount: 100.00,
                maxRechargeAmount: 50000.00,
                suggestedAmounts: [100, 250, 500, 1000, 2000],
                dailyRechargeLimit: 100000.00,
                monthlyRechargeLimit: 500000.00,
                isWalletActive: true,
            });
        }
        return config;
    }

    /**
     * Validate Feature or Booking Purchase before deducting credits.
     */
    public static async validateSpend(
        userId: string,
        requiredPrice: number
    ): Promise<{
        isValid: boolean;
        reason?: string;
        wallet?: SmartWallet;
        shortfallData?: SmartRechargeOptions;
    }> {
        const user = await User.findByPk(userId);
        if (!user || !user.isActive || user.isDeleted) {
            return { isValid: false, reason: 'User account is inactive or not found' };
        }

        const config = await this.getGlobalConfig();
        if (!config.isWalletActive) {
            return { isValid: false, reason: 'Smart Credit Wallet system is currently undergoing maintenance' };
        }

        const wallet = await this.getOrCreateWallet(userId);
        if (wallet.isFrozen) {
            return { isValid: false, reason: `Wallet is frozen: ${wallet.frozenReason || 'Contact Support'}` };
        }

        const available = wallet.totalAvailableBalance;
        if (available < requiredPrice) {
            const neededAmount = Math.ceil(requiredPrice - available);
            const suggestedRecharges = (config.suggestedAmounts || [100, 250, 500, 1000, 2000]).filter(
                (amt) => amt >= neededAmount || amt === 100
            );

            return {
                isValid: false,
                reason: 'INSUFFICIENT_BALANCE',
                wallet,
                shortfallData: {
                    insufficientBalance: true,
                    currentBalance: available,
                    requiredPrice,
                    neededAmount,
                    suggestedRecharges,
                    minRecharge: Number(config.minRechargeAmount),
                    maxRecharge: Number(config.maxRechargeAmount),
                },
            };
        }

        return { isValid: true, wallet };
    }

    /**
     * Recharges Smart Wallet via Razorpay. Idempotent & concurrency-safe.
     */
    public static async rechargeWalletWithRazorpay(params: {
        userId: string;
        amount: number;
        razorpayOrderId?: string;
        razorpayPaymentId: string;
        razorpaySignature?: string;
        autoContinueSession?: object | null;
    }): Promise<{ success: boolean; message: string; data?: any }> {
        const { userId, amount, razorpayOrderId, razorpayPaymentId, razorpaySignature, autoContinueSession } = params;

        if (!userId || !amount || amount <= 0) {
            throw new Error('Valid userId and positive amount are required');
        }

        const config = await this.getGlobalConfig();

        if (amount < Number(config.minRechargeAmount)) {
            throw new Error(`Minimum recharge amount is ₹${config.minRechargeAmount}`);
        }
        if (amount > Number(config.maxRechargeAmount)) {
            throw new Error(`Maximum recharge amount per transaction is ₹${config.maxRechargeAmount}`);
        }

        // Idempotency check on payment ID
        if (razorpayPaymentId) {
            const existingTxn = await WalletTransaction.findOne({
                where: { reference: razorpayPaymentId, status: WalletTransactionStatus.SUCCESS },
            });
            if (existingTxn) {
                const wallet = await this.getOrCreateWallet(userId);
                return {
                    success: true,
                    message: 'Recharge already processed (idempotent)',
                    data: {
                        userId,
                        rechargedAmount: Number(existingTxn.amount),
                        availableBalance: wallet.totalAvailableBalance,
                        transactionId: existingTxn.id,
                    },
                };
            }
        }

        // Signature Verification (if secret is configured)
        const secret = process.env.RAZORPAY_KEY_SECRET;
        if (secret && razorpayOrderId && razorpaySignature) {
            const expectedSig = crypto
                .createHmac('sha256', secret)
                .update(`${razorpayOrderId}|${razorpayPaymentId}`)
                .digest('hex');

            if (expectedSig !== razorpaySignature) {
                logger.error(`Razorpay signature mismatch for wallet recharge: ${razorpayPaymentId}`);
                throw new Error('Razorpay payment signature verification failed');
            }
        }

        // Atomic DB Transaction
        const result = await sequelize.transaction(async (t) => {
            let wallet = await SmartWallet.findOne({
                where: { userId },
                lock: Transaction.LOCK.UPDATE,
                transaction: t,
            });

            if (!wallet) {
                wallet = await SmartWallet.create(
                    { userId, balance: 0, lockedBalance: 0, pendingBalance: 0, promotionalBalance: 0, cashbackBalance: 0, rewardBalance: 0, lifetimeRecharged: 0, lifetimeSpent: 0 },
                    { transaction: t }
                );
            }

            if (wallet.isFrozen) {
                throw new Error(`Cannot recharge. Wallet is frozen: ${wallet.frozenReason || 'Suspended'}`);
            }

            // Cumulative daily recharge limit validation
            const startOfDay = new Date();
            startOfDay.setHours(0, 0, 0, 0);

            const Op = (await import('sequelize')).Op;
            const dailyRecharges = (await WalletTransaction.sum('amount', {
                where: {
                    userId,
                    transactionType: WalletTransactionType.RECHARGE,
                    status: WalletTransactionStatus.SUCCESS,
                    createdAt: { [Op.gte]: startOfDay },
                },
                transaction: t,
            })) || 0;

            if (Number(dailyRecharges) + amount > Number(config.dailyRechargeLimit)) {
                throw new Error(`Daily wallet recharge limit of ₹${config.dailyRechargeLimit} exceeded. Current today: ₹${dailyRecharges}`);
            }

            const openingBal = wallet.totalAvailableBalance;
            const newMainBal = Number(wallet.balance) + amount;
            const newLifetimeRecharged = Number(wallet.lifetimeRecharged) + amount;

            await wallet.update(
                {
                    balance: newMainBal,
                    lifetimeRecharged: newLifetimeRecharged,
                },
                { transaction: t }
            );

            // Sync User.walletBalance
            await User.update({ walletBalance: wallet.totalAvailableBalance }, { where: { id: userId }, transaction: t });

            // Immutable Ledger Entry
            const txn = await WalletTransaction.create(
                {
                    walletId: wallet.id,
                    userId,
                    amount,
                    openingBalance: openingBal,
                    closingBalance: wallet.totalAvailableBalance,
                    transactionType: WalletTransactionType.RECHARGE,
                    status: WalletTransactionStatus.SUCCESS,
                    reference: razorpayPaymentId || `RECHARGE_${Date.now()}`,
                    source: 'razorpay',
                    destination: 'wallet_available',
                    metadata: {
                        razorpayOrderId,
                        razorpayPaymentId,
                        autoContinueSession,
                    },
                },
                { transaction: t }
            );

            await AuditLog.create(
                {
                    userId,
                    action: 'Smart Wallet Recharged',
                    metadata: {
                        amount,
                        razorpayPaymentId,
                        newBalance: wallet.totalAvailableBalance,
                    },
                },
                { transaction: t }
            );

            return { wallet, txn };
        });

        // Evaluate Cashback Rules
        this.evaluateCashbackRules({
            userId,
            triggerType: CashbackTriggerType.RECHARGE,
            amountSpent: amount,
        }).catch((err) => logger.warn('Cashback evaluation warning:', err));

        // Create Notification
        try {
            await Notification.create({
                recipientUserId: userId,
                title: 'Wallet Recharged! 💳',
                body: `₹${amount} has been added to your Smart Credit Wallet. Available Balance: ₹${result.wallet.totalAvailableBalance}`,
                eventType: 'WALLET_RECHARGED',
                category: 'system' as any,
                metadata: { amount, transactionId: result.txn.id },
            });
        } catch (_) {}

        return {
            success: true,
            message: `Successfully recharged ₹${amount} to your Smart Credit Wallet!`,
            data: {
                userId,
                rechargedAmount: amount,
                availableBalance: result.wallet.totalAvailableBalance,
                transactionId: result.txn.id,
                autoContinueSession,
            },
        };
    }

    /**
     * Locks Commitment Deposit for Party Plans / Bookings.
     * Decreases Available Balance, Increases Locked Balance.
     */
    public static async lockDeposit(params: {
        userId: string;
        amount: number;
        partyPlanId?: string;
        bookingId?: string;
        reference?: string;
    }): Promise<{ success: boolean; wallet: SmartWallet; txn: WalletTransaction }> {
        const { userId, amount, partyPlanId, bookingId, reference } = params;

        const validation = await this.validateSpend(userId, amount);
        if (!validation.isValid) {
            if (validation.shortfallData) {
                const err: any = new Error('Insufficient balance for commitment deposit');
                err.statusCode = 402;
                err.shortfallData = validation.shortfallData;
                throw err;
            }
            throw new Error(validation.reason || 'Deposit lock validation failed');
        }

        const result = await sequelize.transaction(async (t) => {
            const wallet = await SmartWallet.findOne({ where: { userId }, lock: Transaction.LOCK.UPDATE, transaction: t });
            if (!wallet) throw new Error('Wallet not found');

            const openingBal = wallet.totalAvailableBalance;
            const newBalance = Math.max(0, Number(wallet.balance) - amount);
            const newLocked = Number(wallet.lockedBalance || 0) + amount;

            await wallet.update({ balance: newBalance, lockedBalance: newLocked }, { transaction: t });
            await User.update({ walletBalance: wallet.totalAvailableBalance }, { where: { id: userId }, transaction: t });

            const txn = await WalletTransaction.create(
                {
                    walletId: wallet.id,
                    userId,
                    partyPlanId,
                    bookingId,
                    amount,
                    openingBalance: openingBal,
                    closingBalance: wallet.totalAvailableBalance,
                    transactionType: WalletTransactionType.COMMITMENT_DEPOSIT,
                    status: WalletTransactionStatus.LOCKED,
                    reference: reference || `DEPOSIT_LOCK_${Date.now()}`,
                    source: 'wallet_available',
                    destination: 'wallet_locked',
                },
                { transaction: t }
            );

            await AuditLog.create(
                {
                    userId,
                    action: 'Commitment Deposit Locked',
                    metadata: { amount, partyPlanId, bookingId, newLockedBalance: newLocked },
                },
                { transaction: t }
            );

            return { wallet, txn };
        });

        return { success: true, ...result };
    }

    /**
     * Unlocks Deposit upon Event Completion or Cancellation Policy execution.
     */
    public static async unlockDeposit(params: {
        userId: string;
        amount: number;
        partyPlanId?: string;
        bookingId?: string;
        action: 'refund_to_wallet' | 'settle_party';
        reference?: string;
    }): Promise<{ success: boolean; wallet: SmartWallet; txn: WalletTransaction }> {
        const { userId, amount, partyPlanId, bookingId, action, reference } = params;

        const result = await sequelize.transaction(async (t) => {
            const wallet = await SmartWallet.findOne({ where: { userId }, lock: Transaction.LOCK.UPDATE, transaction: t });
            if (!wallet) throw new Error('Wallet not found');

            const openingBal = wallet.totalAvailableBalance;
            const currentLocked = Number(wallet.lockedBalance || 0);
            const unlockAmt = Math.min(currentLocked, amount);

            const newLocked = Math.max(0, currentLocked - unlockAmt);
            let newMainBal = Number(wallet.balance || 0);

            if (action === 'refund_to_wallet') {
                newMainBal += unlockAmt;
            }

            await wallet.update({ lockedBalance: newLocked, balance: newMainBal }, { transaction: t });
            await User.update({ walletBalance: wallet.totalAvailableBalance }, { where: { id: userId }, transaction: t });

            const txn = await WalletTransaction.create(
                {
                    walletId: wallet.id,
                    userId,
                    partyPlanId,
                    bookingId,
                    amount: unlockAmt,
                    openingBalance: openingBal,
                    closingBalance: wallet.totalAvailableBalance,
                    transactionType: WalletTransactionType.DEPOSIT_UNLOCK,
                    status: WalletTransactionStatus.SUCCESS,
                    reference: reference || `UNLOCK_${Date.now()}`,
                    source: 'wallet_locked',
                    destination: action === 'refund_to_wallet' ? 'wallet_available' : 'settled_venue',
                },
                { transaction: t }
            );

            await AuditLog.create(
                {
                    userId,
                    action: 'Commitment Deposit Unlocked',
                    metadata: { amount: unlockAmt, action, partyPlanId, bookingId },
                },
                { transaction: t }
            );

            return { wallet, txn };
        });

        return { success: true, ...result };
    }

    /**
     * Process Refund into Smart Credit Wallet (idempotent, no Razorpay charges).
     */
    public static async processRefund(params: {
        userId: string;
        amount: number;
        referenceId: string;
        reason: string;
        partyPlanId?: string;
        bookingId?: string;
    }): Promise<{ success: boolean; wallet: SmartWallet; txn: WalletTransaction }> {
        const { userId, amount, referenceId, reason, partyPlanId, bookingId } = params;

        if (amount <= 0) throw new Error('Refund amount must be positive');

        // Check duplicate refund reference
        const existingTxn = await WalletTransaction.findOne({
            where: { reference: referenceId, transactionType: WalletTransactionType.REFUND, status: WalletTransactionStatus.SUCCESS },
        });
        if (existingTxn) {
            const wallet = await this.getOrCreateWallet(userId);
            return { success: true, wallet, txn: existingTxn };
        }

        const result = await sequelize.transaction(async (t) => {
            const wallet = await SmartWallet.findOne({ where: { userId }, lock: Transaction.LOCK.UPDATE, transaction: t });
            if (!wallet) throw new Error('Wallet not found');

            const openingBal = wallet.totalAvailableBalance;
            const newBal = Number(wallet.balance) + amount;
            const newLifetimeRefunds = Number(wallet.lifetimeRefunds || 0) + amount;

            await wallet.update({ balance: newBal, lifetimeRefunds: newLifetimeRefunds }, { transaction: t });
            await User.update({ walletBalance: wallet.totalAvailableBalance }, { where: { id: userId }, transaction: t });

            const txn = await WalletTransaction.create(
                {
                    walletId: wallet.id,
                    userId,
                    partyPlanId,
                    bookingId,
                    amount,
                    openingBalance: openingBal,
                    closingBalance: wallet.totalAvailableBalance,
                    transactionType: WalletTransactionType.REFUND,
                    status: WalletTransactionStatus.SUCCESS,
                    reference: referenceId,
                    source: 'system_refund',
                    destination: 'wallet_available',
                    metadata: { reason },
                },
                { transaction: t }
            );

            await AuditLog.create(
                {
                    userId,
                    action: 'Refund Processed to Wallet',
                    metadata: { amount, reason, referenceId },
                },
                { transaction: t }
            );

            return { wallet, txn };
        });

        return { success: true, ...result };
    }

    /**
     * Executes feature / booking spending using Smart Credit Wallet.
     * Consumes promotional and cashback credits first, then main balance.
     */
    public static async purchaseFeatureWithCredit(params: {
        userId: string;
        price: number;
        transactionType: WalletTransactionType;
        reference: string;
        bookingId?: string;
        partyPlanId?: string;
        metadata?: object;
    }): Promise<{ success: boolean; message: string; data: any }> {
        const { userId, price, transactionType, reference, bookingId, partyPlanId, metadata } = params;

        if (price <= 0) throw new Error('Price must be greater than zero');

        const validation = await this.validateSpend(userId, price);
        if (!validation.isValid) {
            if (validation.shortfallData) {
                const err: any = new Error('Insufficient wallet balance');
                err.statusCode = 402;
                err.shortfallData = validation.shortfallData;
                throw err;
            }
            throw new Error(validation.reason || 'Spending validation failed');
        }

        const result = await sequelize.transaction(async (t) => {
            const wallet = await SmartWallet.findOne({ where: { userId }, lock: Transaction.LOCK.UPDATE, transaction: t });
            if (!wallet) throw new Error('Wallet not found');

            const openingBal = wallet.totalAvailableBalance;
            let remainingToDeduct = price;

            let currentPromo = Number(wallet.promotionalBalance || 0);
            let currentCashback = Number(wallet.cashbackBalance || 0);
            let currentReward = Number(wallet.rewardBalance || 0);
            let currentMain = Number(wallet.balance || 0);

            if (currentPromo > 0) {
                const promoDeduct = Math.min(currentPromo, remainingToDeduct);
                currentPromo -= promoDeduct;
                remainingToDeduct -= promoDeduct;
            }

            if (remainingToDeduct > 0 && currentCashback > 0) {
                const cashbackDeduct = Math.min(currentCashback, remainingToDeduct);
                currentCashback -= cashbackDeduct;
                remainingToDeduct -= cashbackDeduct;
            }

            if (remainingToDeduct > 0 && currentReward > 0) {
                const rewardDeduct = Math.min(currentReward, remainingToDeduct);
                currentReward -= rewardDeduct;
                remainingToDeduct -= rewardDeduct;
            }

            if (remainingToDeduct > 0) {
                if (currentMain < remainingToDeduct) {
                    throw new Error('Insufficient available balance');
                }
                currentMain -= remainingToDeduct;
                remainingToDeduct = 0;
            }

            const newLifetimeSpent = Number(wallet.lifetimeSpent || 0) + price;

            await wallet.update(
                {
                    promotionalBalance: currentPromo,
                    cashbackBalance: currentCashback,
                    rewardBalance: currentReward,
                    balance: currentMain,
                    lifetimeSpent: newLifetimeSpent,
                },
                { transaction: t }
            );

            await User.update({ walletBalance: wallet.totalAvailableBalance }, { where: { id: userId }, transaction: t });

            const txn = await WalletTransaction.create(
                {
                    walletId: wallet.id,
                    userId,
                    bookingId,
                    partyPlanId,
                    amount: price,
                    openingBalance: openingBal,
                    closingBalance: wallet.totalAvailableBalance,
                    transactionType,
                    status: WalletTransactionStatus.SUCCESS,
                    reference,
                    source: 'wallet_available',
                    destination: 'lunara_feature',
                    metadata: {
                        ...metadata,
                        pricePaid: price,
                        remainingBalance: wallet.totalAvailableBalance,
                    },
                },
                { transaction: t }
            );

            await AuditLog.create(
                {
                    userId,
                    action: `Smart Wallet Spend (${transactionType})`,
                    metadata: { price, reference, newBalance: wallet.totalAvailableBalance },
                },
                { transaction: t }
            );

            return { wallet, txn };
        });

        // Trigger Cashback Evaluation
        let cashbackTrigger = CashbackTriggerType.VIP_PURCHASE;
        if (transactionType === WalletTransactionType.SUPER_LIKE_PURCHASE) {
            cashbackTrigger = CashbackTriggerType.SUPER_LIKE_PURCHASE;
        } else if (transactionType === WalletTransactionType.BOOST_PURCHASE) {
            cashbackTrigger = CashbackTriggerType.BOOST_PURCHASE;
        }

        this.evaluateCashbackRules({
            userId,
            triggerType: cashbackTrigger,
            amountSpent: price,
        }).catch((err) => logger.warn('Cashback error:', err));

        return {
            success: true,
            message: 'Payment completed successfully using Smart Credit Wallet!',
            data: {
                userId,
                pricePaid: price,
                remainingBalance: result.wallet.totalAvailableBalance,
                transactionId: result.txn.id,
            },
        };
    }

    /**
     * Admin manual credit or debit adjustment with audit tracking.
     */
    public static async processAdminAdjustment(params: {
        userId: string;
        adminUserId: string;
        type: 'credit' | 'debit';
        amount: number;
        reason: string;
        creditCategory?: 'regular' | 'promotional' | 'reward';
    }): Promise<{ success: boolean; message: string; wallet: SmartWallet }> {
        const { userId, adminUserId, type, amount, reason, creditCategory = 'regular' } = params;

        if (amount <= 0) throw new Error('Amount must be positive');
        if (!reason || reason.trim().length < 3) throw new Error('Valid reason is required for admin wallet adjustment');

        const result = await sequelize.transaction(async (t) => {
            const wallet = await this.getOrCreateWallet(userId, t);
            const openingBal = wallet.totalAvailableBalance;

            let newBalance = wallet.balance;
            let newPromoBalance = wallet.promotionalBalance;
            let newRewardBalance = wallet.rewardBalance;
            let txnType = WalletTransactionType.ADMIN_CREDIT;

            if (type === 'credit') {
                if (creditCategory === 'promotional') {
                    newPromoBalance = Number(wallet.promotionalBalance) + amount;
                    txnType = WalletTransactionType.PROMOTIONAL_CREDIT;
                } else if (creditCategory === 'reward') {
                    newRewardBalance = Number(wallet.rewardBalance) + amount;
                    txnType = WalletTransactionType.REWARD_CREDIT;
                } else {
                    newBalance = Number(wallet.balance) + amount;
                    txnType = WalletTransactionType.ADMIN_CREDIT;
                }
            } else {
                if (wallet.totalAvailableBalance < amount) {
                    throw new Error(`Cannot debit ₹${amount}. User only has ₹${wallet.totalAvailableBalance} available.`);
                }
                newBalance = Math.max(0, Number(wallet.balance) - amount);
                txnType = WalletTransactionType.ADMIN_DEBIT;
            }

            await wallet.update(
                {
                    balance: newBalance,
                    promotionalBalance: newPromoBalance,
                    rewardBalance: newRewardBalance,
                    lifetimePromotional:
                        creditCategory === 'promotional'
                            ? Number(wallet.lifetimePromotional) + amount
                            : wallet.lifetimePromotional,
                    lifetimeRewards:
                        creditCategory === 'reward'
                            ? Number(wallet.lifetimeRewards) + amount
                            : wallet.lifetimeRewards,
                },
                { transaction: t }
            );

            await User.update({ walletBalance: wallet.totalAvailableBalance }, { where: { id: userId }, transaction: t });

            const txn = await WalletTransaction.create(
                {
                    walletId: wallet.id,
                    userId,
                    amount,
                    openingBalance: openingBal,
                    closingBalance: wallet.totalAvailableBalance,
                    transactionType: txnType,
                    status: WalletTransactionStatus.SUCCESS,
                    reference: `ADMIN_ADJ_${Date.now()}`,
                    source: 'admin_panel',
                    destination: 'user_wallet',
                    createdBy: adminUserId,
                    metadata: {
                        adminUserId,
                        reason,
                        adjustmentType: type,
                        creditCategory,
                    },
                },
                { transaction: t }
            );

            await AuditLog.create(
                {
                    userId,
                    action: `Admin Wallet Adjustment (${type.toUpperCase()})`,
                    metadata: { adminUserId, amount, reason, newBalance: wallet.totalAvailableBalance, txnId: txn.id },
                },
                { transaction: t }
            );

            return wallet;
        });

        return {
            success: true,
            message: `Successfully ${type === 'credit' ? 'credited' : 'debited'} ₹${amount} for user.`,
            wallet: result,
        };
    }

    /**
     * Evaluates active cashback rules and credits user wallet if criteria met.
     */
    private static async evaluateCashbackRules(params: {
        userId: string;
        triggerType: CashbackTriggerType;
        amountSpent: number;
    }): Promise<void> {
        try {
            const rules = await WalletCashbackRule.findAll({
                where: { triggerType: params.triggerType, isActive: true },
            });

            for (const rule of rules) {
                if (params.amountSpent >= Number(rule.minSpend)) {
                    let cashback = 0;
                    if (rule.cashbackType === CashbackType.PERCENTAGE) {
                        cashback = (params.amountSpent * Number(rule.cashbackValue)) / 100;
                    } else {
                        cashback = Number(rule.cashbackValue);
                    }
                    cashback = Math.min(cashback, Number(rule.maxCashback));

                    if (cashback > 0) {
                        await sequelize.transaction(async (t) => {
                            const wallet = await SmartWallet.findOne({ where: { userId: params.userId }, lock: Transaction.LOCK.UPDATE, transaction: t });
                            if (wallet && !wallet.isFrozen) {
                                const opening = wallet.totalAvailableBalance;
                                const newCashbackBal = Number(wallet.cashbackBalance) + cashback;
                                const newLifetimeCashback = Number(wallet.lifetimeCashback) + cashback;

                                await wallet.update({ cashbackBalance: newCashbackBal, lifetimeCashback: newLifetimeCashback }, { transaction: t });
                                await User.update({ walletBalance: wallet.totalAvailableBalance }, { where: { id: params.userId }, transaction: t });

                                await WalletTransaction.create(
                                    {
                                        walletId: wallet.id,
                                        userId: params.userId,
                                        amount: cashback,
                                        openingBalance: opening,
                                        closingBalance: wallet.totalAvailableBalance,
                                        transactionType: WalletTransactionType.CASHBACK_CREDIT,
                                        status: WalletTransactionStatus.SUCCESS,
                                        reference: `CASHBACK_${rule.id}_${Date.now()}`,
                                        source: 'cashback_engine',
                                        destination: 'wallet_cashback',
                                        metadata: { ruleId: rule.id, ruleName: rule.ruleName, amountSpent: params.amountSpent },
                                    },
                                    { transaction: t }
                                );
                            }
                        });
                        logger.info(`Cashback ₹${cashback} awarded to user ${params.userId} via rule '${rule.ruleName}'`);
                    }
                }
            }
        } catch (err) {
            logger.warn('Failed to process cashback rules:', err);
        }
    }
}

export default WalletService;
