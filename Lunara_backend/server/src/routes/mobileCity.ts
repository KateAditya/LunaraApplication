import express from 'express';
import City from '../models/City';

const router = express.Router();

// ============================================================================
// Mobile City Routes — /api/mobile/cities
// All routes are PUBLIC (no auth required)
// ============================================================================

/**
 * GET /api/mobile/cities
 * Returns all active cities ordered by displayOrder then name.
 */
router.get('/', async (_req, res): Promise<void> => {
    try {
        const cities = await City.findAll({
            where: { isActive: true },
            order: [['displayOrder', 'ASC'], ['name', 'ASC']],
            attributes: ['id', 'name', 'state'],
        });

        res.json({
            success: true,
            data: cities.map(c => ({
                id: c.id,
                name: c.name,
                state: c.state,
            })),
        });
    } catch (error) {
        console.error('Error fetching cities:', error);
        res.status(500).json({ success: false, message: 'Failed to fetch cities' });
    }
});

export default router;
