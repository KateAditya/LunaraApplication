import { Router } from 'express';
import { MobileTicketController } from '../controllers/mobileTicketController';

const router = Router();

/**
 * GET /api/mobile/tickets
 * Query: userId, tab ('upcoming' | 'active' | 'used' | 'expired' | 'cancelled')
 */
router.get('/', MobileTicketController.getUserTickets);

/**
 * GET /api/mobile/tickets/share/:token
 * Public preview endpoint for ticket share links
 */
router.get('/share/:token', MobileTicketController.getShareTicketPreview);

/**
 * POST /api/mobile/tickets/verify
 * Gate scanner verification endpoint for venue staff
 */
router.post('/verify', MobileTicketController.verifyGateScanTicket);

/**
 * GET /api/mobile/tickets/:id
 * Get single ticket metadata
 */
router.get('/:id', MobileTicketController.getTicketById);

/**
 * GET /api/mobile/tickets/:id/download
 * Generate time-limited signed PDF download URL
 */
router.get('/:id/download', MobileTicketController.getTicketDownloadUrl);

/**
 * POST /api/mobile/tickets/:id/share
 * Generate/retrieve secure share link token
 */
router.post('/:id/share', MobileTicketController.createShareToken);

export default router;
