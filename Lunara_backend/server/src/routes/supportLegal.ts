import express from 'express';
import {
    getHelpArticles,
    getHelpArticleById,
    createHelpArticle,
    updateHelpArticle,
    deleteHelpArticle,
    getCommunityGuidelines,
    getCommunityGuidelineById,
    createCommunityGuideline,
    updateCommunityGuideline,
    deleteCommunityGuideline,
    getLegalDocuments,
    getLegalDocumentById,
    createLegalDocument,
    updateLegalDocument,
    deleteLegalDocument,
} from '../controllers/supportLegalController';
import { authenticate, authorize } from '../middleware/auth';
import { UserRole } from '../models/User';

const router = express.Router();

// ── Help Center ──────────────────────────────────────────────────────────────
// Public: read
router.get('/help-center', getHelpArticles);
router.get('/help-center/:id', getHelpArticleById);

// Admin only: write
router.post('/help-center', authenticate, authorize(UserRole.ADMIN), createHelpArticle);
router.put('/help-center/:id', authenticate, authorize(UserRole.ADMIN), updateHelpArticle);
router.delete('/help-center/:id', authenticate, authorize(UserRole.ADMIN), deleteHelpArticle);

// ── Community Guidelines ─────────────────────────────────────────────────────
// Public: read
router.get('/community-guidelines', getCommunityGuidelines);
router.get('/community-guidelines/:id', getCommunityGuidelineById);

// Admin only: write
router.post('/community-guidelines', authenticate, authorize(UserRole.ADMIN), createCommunityGuideline);
router.put('/community-guidelines/:id', authenticate, authorize(UserRole.ADMIN), updateCommunityGuideline);
router.delete('/community-guidelines/:id', authenticate, authorize(UserRole.ADMIN), deleteCommunityGuideline);

// ── Legal Documents ──────────────────────────────────────────────────────────
// Public: read
router.get('/legal', getLegalDocuments);
router.get('/legal/:id', getLegalDocumentById);

// Admin only: write
router.post('/legal', authenticate, authorize(UserRole.ADMIN), createLegalDocument);
router.put('/legal/:id', authenticate, authorize(UserRole.ADMIN), updateLegalDocument);
router.delete('/legal/:id', authenticate, authorize(UserRole.ADMIN), deleteLegalDocument);

export default router;
