import express from 'express';
import { getAreas, createArea } from '../controllers/areaController';

const router = express.Router();

// GET /api/areas - Fetch all areas
router.get('/', getAreas);

// POST /api/areas - Create a new area
router.post('/', createArea);

export default router;
