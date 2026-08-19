import { Router } from 'express';
import { authenticate } from '../middleware/auth';
import { MobileTicketController } from '../controllers/mobileTicketController';

const router = Router();

/**
 * GET /api/mobile/tickets
 * Query: userId, tab ('upcoming' | 'active' | 'used' | 'expired' | 'cancelled')
 */
router.get('/', authenticate, MobileTicketController.getUserTickets);

/**
 * GET /api/mobile/tickets/share/:token
 * Public HTML ticket preview page for share link recipients
 */
router.get('/share/:token', MobileTicketController.getShareTicketPreview);

/**
 * GET /api/mobile/tickets/share/:token/pdf
 * Redirect/serve the actual PDF file for a share token
 */
router.get('/share/:token/pdf', MobileTicketController.getShareTicketPdf);

/**
 * POST /api/mobile/tickets/verify
 * Gate scanner verification endpoint for venue staff
 */
router.post('/verify', authenticate, MobileTicketController.verifyGateScanTicket);

/**
 * GET /api/mobile/tickets/:id
 * Get single ticket metadata
 */
router.get('/:id', authenticate, MobileTicketController.getTicketById);

/**
 * GET /api/mobile/tickets/:id/download
 * Generate time-limited signed PDF download URL
 */
router.get('/:id/download', authenticate, MobileTicketController.getTicketDownloadUrl);

/**
 * POST /api/mobile/tickets/:id/share
 * Generate/retrieve secure share link token
 */
router.post('/:id/share', authenticate, MobileTicketController.createShareToken);

export default router;
