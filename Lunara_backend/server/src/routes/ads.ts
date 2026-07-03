import { Router } from 'express';
import adController from '../controllers/adController';
import { authenticate, authorize } from '../middleware/auth';
import { UserRole } from '../models/User';
import { uploadVenuePhoto } from '../middleware/upload';

const router = Router();

// ── Public / App Endpoints ───────────────────────────────────────────────────

/**
 * @route   GET /api/ads/active
 * @desc    Get all active ads filtered by date and status for mobile app
 * @access  Public (or require authentication based on app needs)
 */
router.get('/active', adController.getActiveAds);

// ── Admin Endpoints ──────────────────────────────────────────────────────────

// All routes below require Admin authentication
router.use(authenticate);
router.use(authorize(UserRole.ADMIN));

/**
 * @route   GET /api/ads
 * @desc    Get all ads
 * @access  Private (Admin)
 */
router.get('/', adController.getAds);

/**
 * @route   POST /api/ads
 * @desc    Create a new ad
 * @access  Private (Admin)
 */
router.post('/', uploadVenuePhoto.single('image'), adController.createAd);

/**
 * @route   PUT /api/ads/:id
 * @desc    Update an existing ad
 * @access  Private (Admin)
 */
router.put('/:id', uploadVenuePhoto.single('image'), adController.updateAd);

/**
 * @route   DELETE /api/ads/:id
 * @desc    Delete an ad
 * @access  Private (Admin)
 */
router.delete('/:id', adController.deleteAd);

export default router;
