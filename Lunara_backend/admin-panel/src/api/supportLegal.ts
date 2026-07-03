import apiClient from './client';

// ── Types ────────────────────────────────────────────────────────────────────

export interface HelpArticle {
    id: string;
    title: string;
    content: string;
    category: string;
    isPublished: boolean;
    displayOrder: number;
    createdAt: string;
    updatedAt: string;
}

export interface CommunityGuideline {
    id: string;
    title: string;
    content: string;
    category: string;
    isActive: boolean;
    displayOrder: number;
    createdAt: string;
    updatedAt: string;
}

export type LegalDocumentType =
    | 'terms_of_service'
    | 'privacy_policy'
    | 'refund_policy'
    | 'other';

export interface LegalDocument {
    id: string;
    title: string;
    type: LegalDocumentType;
    content: string;
    version: string;
    isActive: boolean;
    effectiveDate: string;
    createdAt: string;
    updatedAt: string;
}

// ── Help Center API ───────────────────────────────────────────────────────────

export const helpCenterApi = {
    getAll: (): Promise<{ success: boolean; articles: HelpArticle[]; total: number }> =>
        apiClient.get('/api/support/help-center'),

    getById: (id: string): Promise<{ success: boolean; article: HelpArticle }> =>
        apiClient.get(`/api/support/help-center/${id}`),

    create: (data: Partial<HelpArticle>): Promise<{ success: boolean; article: HelpArticle; message: string }> =>
        apiClient.post('/api/support/help-center', data),

    update: (id: string, data: Partial<HelpArticle>): Promise<{ success: boolean; article: HelpArticle; message: string }> =>
        apiClient.put(`/api/support/help-center/${id}`, data),

    delete: (id: string): Promise<{ success: boolean; message: string }> =>
        apiClient.delete(`/api/support/help-center/${id}`),
};

// ── Community Guidelines API ──────────────────────────────────────────────────

export const communityGuidelinesApi = {
    getAll: (): Promise<{ success: boolean; guidelines: CommunityGuideline[]; total: number }> =>
        apiClient.get('/api/support/community-guidelines'),

    getById: (id: string): Promise<{ success: boolean; guideline: CommunityGuideline }> =>
        apiClient.get(`/api/support/community-guidelines/${id}`),

    create: (data: Partial<CommunityGuideline>): Promise<{ success: boolean; guideline: CommunityGuideline; message: string }> =>
        apiClient.post('/api/support/community-guidelines', data),

    update: (id: string, data: Partial<CommunityGuideline>): Promise<{ success: boolean; guideline: CommunityGuideline; message: string }> =>
        apiClient.put(`/api/support/community-guidelines/${id}`, data),

    delete: (id: string): Promise<{ success: boolean; message: string }> =>
        apiClient.delete(`/api/support/community-guidelines/${id}`),
};

// ── Legal Documents API ───────────────────────────────────────────────────────

export const legalApi = {
    getAll: (): Promise<{ success: boolean; documents: LegalDocument[]; total: number }> =>
        apiClient.get('/api/support/legal'),

    getById: (id: string): Promise<{ success: boolean; document: LegalDocument }> =>
        apiClient.get(`/api/support/legal/${id}`),

    create: (data: Partial<LegalDocument>): Promise<{ success: boolean; document: LegalDocument; message: string }> =>
        apiClient.post('/api/support/legal', data),

    update: (id: string, data: Partial<LegalDocument>): Promise<{ success: boolean; document: LegalDocument; message: string }> =>
        apiClient.put(`/api/support/legal/${id}`, data),

    delete: (id: string): Promise<{ success: boolean; message: string }> =>
        apiClient.delete(`/api/support/legal/${id}`),
};
