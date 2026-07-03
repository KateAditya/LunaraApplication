import express from 'express';
import HelpArticle from '../models/HelpArticle';
import CommunityGuideline from '../models/CommunityGuideline';
import LegalDocument, { LegalDocumentType } from '../models/LegalDocument';

const router = express.Router();

// ============================================================================
// Mobile Support Routes — /api/mobile/support
// All routes are PUBLIC (no auth required for mobile app consumption)
// ============================================================================

/**
 * GET /api/mobile/support/help-center
 * Returns published help articles only, grouped by category.
 * Query params:
 *   category  — filter by category (optional)
 *   search    — search in title/content (optional)
 */
router.get('/help-center', async (req, res): Promise<void> => {
    try {
        const { category, search } = req.query;
        const where: any = { isPublished: true };
        if (category) where.category = category;

        const articles = await HelpArticle.findAll({
            where,
            order: [['displayOrder', 'ASC'], ['createdAt', 'DESC']],
            attributes: ['id', 'title', 'content', 'category', 'displayOrder', 'createdAt', 'updatedAt'],
        });

        // Optional search filter (in-memory for simplicity)
        let result = articles;
        if (search) {
            const q = (search as string).toLowerCase();
            result = articles.filter(
                a =>
                    a.title.toLowerCase().includes(q) ||
                    a.content.toLowerCase().includes(q) ||
                    a.category.toLowerCase().includes(q)
            );
        }

        // Group by category
        const grouped: Record<string, any[]> = {};
        result.forEach(a => {
            if (!grouped[a.category]) grouped[a.category] = [];
            grouped[a.category].push({
                id: a.id,
                title: a.title,
                content: a.content,
                category: a.category,
                displayOrder: a.displayOrder,
                updatedAt: a.updatedAt,
            });
        });

        res.json({
            success: true,
            total: result.length,
            articles: result.map(a => ({
                id: a.id,
                title: a.title,
                content: a.content,
                category: a.category,
                displayOrder: a.displayOrder,
                updatedAt: a.updatedAt,
            })),
            grouped,
        });
    } catch (error: any) {
        res.status(500).json({ success: false, message: 'Failed to fetch help articles', error: error.message });
    }
});

/**
 * GET /api/mobile/support/help-center/:id
 * Returns a single published help article by ID.
 */
router.get('/help-center/:id', async (req, res): Promise<void> => {
    try {
        const article = await HelpArticle.findOne({
            where: { id: req.params.id, isPublished: true },
            attributes: ['id', 'title', 'content', 'category', 'displayOrder', 'createdAt', 'updatedAt'],
        });
        if (!article) {
            res.status(404).json({ success: false, message: 'Help article not found' });
            return;
        }
        res.json({ success: true, article });
    } catch (error: any) {
        res.status(500).json({ success: false, message: 'Failed to fetch help article', error: error.message });
    }
});

/**
 * GET /api/mobile/support/help-center/categories
 * Returns a list of all unique help categories (published only).
 */
router.get('/help-categories', async (_req, res): Promise<void> => {
    try {
        const articles = await HelpArticle.findAll({
            where: { isPublished: true },
            attributes: ['category'],
        });
        const categories = [...new Set(articles.map(a => a.category))].sort();
        res.json({ success: true, categories });
    } catch (error: any) {
        res.status(500).json({ success: false, message: 'Failed to fetch categories', error: error.message });
    }
});

/**
 * GET /api/mobile/support/community-guidelines
 * Returns active community guidelines, grouped by category.
 * Query params:
 *   category  — filter by category (optional)
 */
router.get('/community-guidelines', async (req, res): Promise<void> => {
    try {
        const { category } = req.query;
        const where: any = { isActive: true };
        if (category) where.category = category;

        const guidelines = await CommunityGuideline.findAll({
            where,
            order: [['displayOrder', 'ASC'], ['createdAt', 'DESC']],
            attributes: ['id', 'title', 'content', 'category', 'displayOrder', 'createdAt', 'updatedAt'],
        });

        // Group by category
        const grouped: Record<string, any[]> = {};
        guidelines.forEach(g => {
            if (!grouped[g.category]) grouped[g.category] = [];
            grouped[g.category].push({
                id: g.id,
                title: g.title,
                content: g.content,
                category: g.category,
                displayOrder: g.displayOrder,
                updatedAt: g.updatedAt,
            });
        });

        res.json({
            success: true,
            total: guidelines.length,
            guidelines: guidelines.map(g => ({
                id: g.id,
                title: g.title,
                content: g.content,
                category: g.category,
                displayOrder: g.displayOrder,
                updatedAt: g.updatedAt,
            })),
            grouped,
        });
    } catch (error: any) {
        res.status(500).json({ success: false, message: 'Failed to fetch community guidelines', error: error.message });
    }
});

/**
 * GET /api/mobile/support/community-guidelines/:id
 * Returns a single active community guideline by ID.
 */
router.get('/community-guidelines/:id', async (req, res): Promise<void> => {
    try {
        const guideline = await CommunityGuideline.findOne({
            where: { id: req.params.id, isActive: true },
            attributes: ['id', 'title', 'content', 'category', 'displayOrder', 'createdAt', 'updatedAt'],
        });
        if (!guideline) {
            res.status(404).json({ success: false, message: 'Community guideline not found' });
            return;
        }
        res.json({ success: true, guideline });
    } catch (error: any) {
        res.status(500).json({ success: false, message: 'Failed to fetch community guideline', error: error.message });
    }
});

/**
 * GET /api/mobile/support/legal
 * Returns active legal documents.
 * Query params:
 *   type — filter by type: terms_of_service | privacy_policy | refund_policy | other (optional)
 *
 * Common usage in app:
 *   GET /api/mobile/support/legal?type=terms_of_service
 *   GET /api/mobile/support/legal?type=privacy_policy
 */
router.get('/legal', async (req, res): Promise<void> => {
    try {
        const { type } = req.query;
        const where: any = { isActive: true };

        if (type) {
            const validTypes = Object.values(LegalDocumentType);
            if (!validTypes.includes(type as LegalDocumentType)) {
                res.status(400).json({
                    success: false,
                    message: `Invalid type. Must be one of: ${validTypes.join(', ')}`,
                });
                return;
            }
            where.type = type;
        }

        const documents = await LegalDocument.findAll({
            where,
            order: [['effectiveDate', 'DESC'], ['createdAt', 'DESC']],
            attributes: ['id', 'title', 'type', 'content', 'version', 'effectiveDate', 'createdAt', 'updatedAt'],
        });

        res.json({
            success: true,
            total: documents.length,
            documents: documents.map(d => ({
                id: d.id,
                title: d.title,
                type: d.type,
                content: d.content,
                version: d.version,
                effectiveDate: d.effectiveDate,
                updatedAt: d.updatedAt,
            })),
        });
    } catch (error: any) {
        res.status(500).json({ success: false, message: 'Failed to fetch legal documents', error: error.message });
    }
});

/**
 * GET /api/mobile/support/legal/:id
 * Returns a single active legal document by ID.
 */
router.get('/legal/:id', async (req, res): Promise<void> => {
    try {
        const document = await LegalDocument.findOne({
            where: { id: req.params.id, isActive: true },
            attributes: ['id', 'title', 'type', 'content', 'version', 'effectiveDate', 'createdAt', 'updatedAt'],
        });
        if (!document) {
            res.status(404).json({ success: false, message: 'Legal document not found' });
            return;
        }
        res.json({ success: true, document });
    } catch (error: any) {
        res.status(500).json({ success: false, message: 'Failed to fetch legal document', error: error.message });
    }
});

/**
 * GET /api/mobile/support/legal/type/:type
 * Convenience shortcut — returns the latest active document of a given type.
 * E.g.  GET /api/mobile/support/legal/type/terms_of_service
 */
router.get('/legal/type/:type', async (req, res): Promise<void> => {
    try {
        const { type } = req.params;
        const validTypes = Object.values(LegalDocumentType);
        if (!validTypes.includes(type as LegalDocumentType)) {
            res.status(400).json({
                success: false,
                message: `Invalid type. Must be one of: ${validTypes.join(', ')}`,
            });
            return;
        }

        const document = await LegalDocument.findOne({
            where: { type, isActive: true },
            order: [['effectiveDate', 'DESC']],
            attributes: ['id', 'title', 'type', 'content', 'version', 'effectiveDate', 'createdAt', 'updatedAt'],
        });

        if (!document) {
            res.status(404).json({ success: false, message: `No active ${type} document found` });
            return;
        }
        res.json({ success: true, document });
    } catch (error: any) {
        res.status(500).json({ success: false, message: 'Failed to fetch legal document', error: error.message });
    }
});

export default router;
