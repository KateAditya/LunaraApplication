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
