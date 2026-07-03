import express from 'express';
import {
    getFeaturedVenues,
    getPartyTonight,
    getPartyPartners,
    getNearbyVenues
} from '../controllers/dashboardController';

const router = express.Router();

router.get('/featured', getFeaturedVenues);
router.get('/tonight', getPartyTonight);
router.get('/partners', getPartyPartners);
router.get('/nearby', getNearbyVenues);

export default router;
