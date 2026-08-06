import apiClient from './client';

export interface WalletConfig {
    id?: string;
    scope: string;
    minRechargeAmount: number;
    maxRechargeAmount: number;
    suggestedAmounts: number[];
    dailyRechargeLimit: number;
    monthlyRechargeLimit: number;
    isWalletActive: boolean;
}

export interface WalletTransactionItem {
    id: string;
    userId: string;
    amount: number;
    openingBalance: number;
    closingBalance: number;
    transactionType: string;
    status: string;
    reference?: string;
    source?: string;
    destination?: string;
    createdAt: string;
    user?: {
        id: string;
        email: string;
        firstName: string;
        lastName: string;
        phone: string;
    };
}

export interface WalletLedgerMetrics {
    totalRecharge: number;
    totalSpent: number;
    totalPromotional: number;
    totalCashback: number;
    totalRewards: number;
    totalRefunds: number;
    totalLockedDeposits: number;
    totalAvailablePool: number;
    activeWalletsCount: number;
    frozenWalletsCount: number;
}

export interface WalletLedgerResponse {
    success: boolean;
    data: {
        transactions: WalletTransactionItem[];
        pagination: {
            total: number;
            page: number;
            totalPages: number;
            limit: number;
        };
        metrics: WalletLedgerMetrics;
    };
}

export const walletApi = {
    getConfig: (): Promise<{ success: boolean; data: WalletConfig }> => {
        return apiClient.get('/api/admin/wallet/config');
    },

    updateConfig: (configData: Partial<WalletConfig>): Promise<{ success: boolean; data: WalletConfig }> => {
        return apiClient.put('/api/admin/wallet/config', configData);
    },

    getLedger: (params?: {
        page?: number;
        limit?: number;
        userId?: string;
        transactionType?: string;
        status?: string;
        search?: string;
        startDate?: string;
        endDate?: string;
    }): Promise<WalletLedgerResponse> => {
        return apiClient.get('/api/admin/wallet/transactions', { params });
    },

    freezeWallet: (userId: string, reason: string): Promise<any> => {
        return apiClient.post(`/api/admin/wallet/users/${userId}/freeze`, { reason });
    },

    unfreezeWallet: (userId: string): Promise<any> => {
        return apiClient.post(`/api/admin/wallet/users/${userId}/unfreeze`);
    },

    manualCredit: (userId: string, amount: number, reason: string, creditCategory = 'regular'): Promise<any> => {
        return apiClient.post(`/api/admin/wallet/users/${userId}/manual-credit`, { amount, reason, creditCategory });
    },

    manualDebit: (userId: string, amount: number, reason: string): Promise<any> => {
        return apiClient.post(`/api/admin/wallet/users/${userId}/manual-debit`, { amount, reason });
    },

    getCampaigns: (): Promise<{ success: boolean; data: any[] }> => {
        return apiClient.get('/api/admin/wallet/campaigns');
    },

    createCampaign: (campaign: any): Promise<any> => {
        return apiClient.post('/api/admin/wallet/campaigns', campaign);
    },

    getCashbackRules: (): Promise<{ success: boolean; data: any[] }> => {
        return apiClient.get('/api/admin/wallet/cashback-rules');
    },

    createCashbackRule: (rule: any): Promise<any> => {
        return apiClient.post('/api/admin/wallet/cashback-rules', rule);
    },
};

export default walletApi;
