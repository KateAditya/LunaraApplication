import { Request, Response } from 'express';
import HelpArticle from '../models/HelpArticle';
import CommunityGuideline from '../models/CommunityGuideline';
import LegalDocument, { LegalDocumentType } from '../models/LegalDocument';

// ============================================================================
// HELP CENTER
// ============================================================================

export const getHelpArticles = async (req: Request, res: Response): Promise<void> => {
    try {
        const { category, published } = req.query;
        const where: any = {};

        if (category) where.category = category;
        if (published !== undefined) where.isPublished = published === 'true';

        const articles = await HelpArticle.findAll({
            where,
            order: [['displayOrder', 'ASC'], ['createdAt', 'DESC']],
        });

        res.json({ success: true, articles, total: articles.length });
    } catch (error: any) {
        res.status(500).json({ success: false, message: 'Failed to fetch help articles', error: error.message });
    }
};

export const getHelpArticleById = async (req: Request, res: Response): Promise<void> => {
    try {
        const article = await HelpArticle.findByPk(req.params.id);
        if (!article) {
            res.status(404).json({ success: false, message: 'Help article not found' });
            return;
        }
        res.json({ success: true, article });
    } catch (error: any) {
        res.status(500).json({ success: false, message: 'Failed to fetch help article', error: error.message });
    }
};

export const createHelpArticle = async (req: Request, res: Response): Promise<void> => {
    try {
        const { title, content, category, isPublished, displayOrder } = req.body;

        if (!title?.trim()) {
            res.status(400).json({ success: false, message: 'Title is required' });
            return;
        }
        if (!content?.trim()) {
            res.status(400).json({ success: false, message: 'Content is required' });
            return;
        }
        if (!category?.trim()) {
            res.status(400).json({ success: false, message: 'Category is required' });
            return;
        }

        const article = await HelpArticle.create({
            title: title.trim(),
            content: content.trim(),
            category: category.trim(),
            isPublished: isPublished === true || isPublished === 'true',
            displayOrder: displayOrder ? parseInt(displayOrder) : 0,
        });

        res.status(201).json({ success: true, message: 'Help article created successfully', article });
    } catch (error: any) {
        if (error.name === 'SequelizeValidationError') {
            res.status(400).json({ success: false, message: error.errors[0]?.message || 'Validation error' });
        } else {
            res.status(500).json({ success: false, message: 'Failed to create help article', error: error.message });
        }
    }
};

export const updateHelpArticle = async (req: Request, res: Response): Promise<void> => {
    try {
        const article = await HelpArticle.findByPk(req.params.id);
        if (!article) {
            res.status(404).json({ success: false, message: 'Help article not found' });
            return;
        }

        const { title, content, category, isPublished, displayOrder } = req.body;

        if (title !== undefined && !title.trim()) {
            res.status(400).json({ success: false, message: 'Title cannot be empty' });
            return;
        }
        if (content !== undefined && !content.trim()) {
            res.status(400).json({ success: false, message: 'Content cannot be empty' });
            return;
        }
        if (category !== undefined && !category.trim()) {
            res.status(400).json({ success: false, message: 'Category cannot be empty' });
            return;
        }

        await article.update({
            ...(title !== undefined && { title: title.trim() }),
            ...(content !== undefined && { content: content.trim() }),
            ...(category !== undefined && { category: category.trim() }),
            ...(isPublished !== undefined && { isPublished: isPublished === true || isPublished === 'true' }),
            ...(displayOrder !== undefined && { displayOrder: parseInt(displayOrder) }),
        });

        res.json({ success: true, message: 'Help article updated successfully', article });
    } catch (error: any) {
        if (error.name === 'SequelizeValidationError') {
            res.status(400).json({ success: false, message: error.errors[0]?.message || 'Validation error' });
        } else {
            res.status(500).json({ success: false, message: 'Failed to update help article', error: error.message });
        }
    }
};

export const deleteHelpArticle = async (req: Request, res: Response): Promise<void> => {
    try {
        const article = await HelpArticle.findByPk(req.params.id);
        if (!article) {
            res.status(404).json({ success: false, message: 'Help article not found' });
            return;
        }
        await article.destroy();
        res.json({ success: true, message: 'Help article deleted successfully' });
    } catch (error: any) {
        res.status(500).json({ success: false, message: 'Failed to delete help article', error: error.message });
    }
};

// ============================================================================
// COMMUNITY GUIDELINES
// ============================================================================

export const getCommunityGuidelines = async (req: Request, res: Response): Promise<void> => {
    try {
        const { category, active } = req.query;
        const where: any = {};

        if (category) where.category = category;
        if (active !== undefined) where.isActive = active === 'true';

        const guidelines = await CommunityGuideline.findAll({
            where,
            order: [['displayOrder', 'ASC'], ['createdAt', 'DESC']],
        });

        res.json({ success: true, guidelines, total: guidelines.length });
    } catch (error: any) {
        res.status(500).json({ success: false, message: 'Failed to fetch community guidelines', error: error.message });
    }
};

export const getCommunityGuidelineById = async (req: Request, res: Response): Promise<void> => {
    try {
        const guideline = await CommunityGuideline.findByPk(req.params.id);
        if (!guideline) {
            res.status(404).json({ success: false, message: 'Community guideline not found' });
            return;
        }
        res.json({ success: true, guideline });
    } catch (error: any) {
        res.status(500).json({ success: false, message: 'Failed to fetch community guideline', error: error.message });
    }
};

export const createCommunityGuideline = async (req: Request, res: Response): Promise<void> => {
    try {
        const { title, content, category, isActive, displayOrder } = req.body;

        if (!title?.trim()) {
            res.status(400).json({ success: false, message: 'Title is required' });
            return;
        }
        if (!content?.trim()) {
            res.status(400).json({ success: false, message: 'Content is required' });
            return;
        }
        if (!category?.trim()) {
            res.status(400).json({ success: false, message: 'Category is required' });
            return;
        }

        const guideline = await CommunityGuideline.create({
            title: title.trim(),
            content: content.trim(),
            category: category.trim(),
            isActive: isActive === true || isActive === 'true' || isActive === undefined,
            displayOrder: displayOrder ? parseInt(displayOrder) : 0,
        });

        res.status(201).json({ success: true, message: 'Community guideline created successfully', guideline });
    } catch (error: any) {
        if (error.name === 'SequelizeValidationError') {
            res.status(400).json({ success: false, message: error.errors[0]?.message || 'Validation error' });
        } else {
            res.status(500).json({ success: false, message: 'Failed to create community guideline', error: error.message });
        }
    }
};

export const updateCommunityGuideline = async (req: Request, res: Response): Promise<void> => {
    try {
        const guideline = await CommunityGuideline.findByPk(req.params.id);
        if (!guideline) {
            res.status(404).json({ success: false, message: 'Community guideline not found' });
            return;
        }

        const { title, content, category, isActive, displayOrder } = req.body;

        if (title !== undefined && !title.trim()) {
            res.status(400).json({ success: false, message: 'Title cannot be empty' });
            return;
        }
        if (content !== undefined && !content.trim()) {
            res.status(400).json({ success: false, message: 'Content cannot be empty' });
            return;
        }
        if (category !== undefined && !category.trim()) {
            res.status(400).json({ success: false, message: 'Category cannot be empty' });
            return;
        }

        await guideline.update({
            ...(title !== undefined && { title: title.trim() }),
            ...(content !== undefined && { content: content.trim() }),
            ...(category !== undefined && { category: category.trim() }),
            ...(isActive !== undefined && { isActive: isActive === true || isActive === 'true' }),
            ...(displayOrder !== undefined && { displayOrder: parseInt(displayOrder) }),
        });

        res.json({ success: true, message: 'Community guideline updated successfully', guideline });
    } catch (error: any) {
        if (error.name === 'SequelizeValidationError') {
            res.status(400).json({ success: false, message: error.errors[0]?.message || 'Validation error' });
        } else {
            res.status(500).json({ success: false, message: 'Failed to update community guideline', error: error.message });
        }
    }
};

export const deleteCommunityGuideline = async (req: Request, res: Response): Promise<void> => {
    try {
        const guideline = await CommunityGuideline.findByPk(req.params.id);
        if (!guideline) {
            res.status(404).json({ success: false, message: 'Community guideline not found' });
            return;
        }
        await guideline.destroy();
        res.json({ success: true, message: 'Community guideline deleted successfully' });
    } catch (error: any) {
        res.status(500).json({ success: false, message: 'Failed to delete community guideline', error: error.message });
    }
};

// ============================================================================
// LEGAL DOCUMENTS
// ============================================================================

export const getLegalDocuments = async (req: Request, res: Response): Promise<void> => {
    try {
        const { type, active } = req.query;
        const where: any = {};

        if (type) {
            if (!Object.values(LegalDocumentType).includes(type as LegalDocumentType)) {
                res.status(400).json({ success: false, message: `Invalid type. Must be one of: ${Object.values(LegalDocumentType).join(', ')}` });
                return;
            }
            where.type = type;
        }
        if (active !== undefined) where.isActive = active === 'true';

        const documents = await LegalDocument.findAll({
            where,
            order: [['effectiveDate', 'DESC'], ['createdAt', 'DESC']],
        });

        res.json({ success: true, documents, total: documents.length });
    } catch (error: any) {
        res.status(500).json({ success: false, message: 'Failed to fetch legal documents', error: error.message });
    }
};

export const getLegalDocumentById = async (req: Request, res: Response): Promise<void> => {
    try {
        const document = await LegalDocument.findByPk(req.params.id);
        if (!document) {
            res.status(404).json({ success: false, message: 'Legal document not found' });
            return;
        }
        res.json({ success: true, document });
    } catch (error: any) {
        res.status(500).json({ success: false, message: 'Failed to fetch legal document', error: error.message });
    }
};

export const createLegalDocument = async (req: Request, res: Response): Promise<void> => {
    try {
        const { title, type, content, version, isActive, effectiveDate } = req.body;

        if (!title?.trim()) {
            res.status(400).json({ success: false, message: 'Title is required' });
            return;
        }
        if (!type || !Object.values(LegalDocumentType).includes(type as LegalDocumentType)) {
            res.status(400).json({ success: false, message: `Type is required and must be one of: ${Object.values(LegalDocumentType).join(', ')}` });
            return;
        }
        if (!content?.trim()) {
            res.status(400).json({ success: false, message: 'Content is required' });
            return;
        }
        if (!version?.trim()) {
            res.status(400).json({ success: false, message: 'Version is required' });
            return;
        }
        if (!effectiveDate) {
            res.status(400).json({ success: false, message: 'Effective date is required' });
            return;
        }

        const document = await LegalDocument.create({
            title: title.trim(),
            type: type as LegalDocumentType,
            content: content.trim(),
            version: version.trim(),
            isActive: isActive === true || isActive === 'true' || isActive === undefined,
            effectiveDate: new Date(effectiveDate),
        });

        res.status(201).json({ success: true, message: 'Legal document created successfully', document });
    } catch (error: any) {
        if (error.name === 'SequelizeValidationError') {
            res.status(400).json({ success: false, message: error.errors[0]?.message || 'Validation error' });
        } else {
            res.status(500).json({ success: false, message: 'Failed to create legal document', error: error.message });
        }
    }
};

export const updateLegalDocument = async (req: Request, res: Response): Promise<void> => {
    try {
        const document = await LegalDocument.findByPk(req.params.id);
        if (!document) {
            res.status(404).json({ success: false, message: 'Legal document not found' });
            return;
        }

        const { title, type, content, version, isActive, effectiveDate } = req.body;

        if (title !== undefined && !title.trim()) {
            res.status(400).json({ success: false, message: 'Title cannot be empty' });
            return;
        }
        if (type !== undefined && !Object.values(LegalDocumentType).includes(type as LegalDocumentType)) {
            res.status(400).json({ success: false, message: `Invalid type. Must be one of: ${Object.values(LegalDocumentType).join(', ')}` });
            return;
        }
        if (content !== undefined && !content.trim()) {
            res.status(400).json({ success: false, message: 'Content cannot be empty' });
            return;
        }
        if (version !== undefined && !version.trim()) {
            res.status(400).json({ success: false, message: 'Version cannot be empty' });
            return;
        }

        await document.update({
            ...(title !== undefined && { title: title.trim() }),
            ...(type !== undefined && { type: type as LegalDocumentType }),
            ...(content !== undefined && { content: content.trim() }),
            ...(version !== undefined && { version: version.trim() }),
            ...(isActive !== undefined && { isActive: isActive === true || isActive === 'true' }),
            ...(effectiveDate !== undefined && { effectiveDate: new Date(effectiveDate) }),
        });

        res.json({ success: true, message: 'Legal document updated successfully', document });
    } catch (error: any) {
        if (error.name === 'SequelizeValidationError') {
            res.status(400).json({ success: false, message: error.errors[0]?.message || 'Validation error' });
        } else {
            res.status(500).json({ success: false, message: 'Failed to update legal document', error: error.message });
        }
    }
};

export const deleteLegalDocument = async (req: Request, res: Response): Promise<void> => {
    try {
        const document = await LegalDocument.findByPk(req.params.id);
        if (!document) {
            res.status(404).json({ success: false, message: 'Legal document not found' });
            return;
        }
        await document.destroy();
        res.json({ success: true, message: 'Legal document deleted successfully' });
    } catch (error: any) {
        res.status(500).json({ success: false, message: 'Failed to delete legal document', error: error.message });
    }
};
