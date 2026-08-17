import express from 'express';
import { getPartyEvents, getEventSummary, getEventBookings } from '../controllers/adminEventBookingController';
import { authenticate, authorize } from '../middleware/auth';
import { UserRole } from '../models/User';

const router = express.Router();

// All routes require Admin authentication
router.use(authenticate);
router.use(authorize(UserRole.ADMIN, UserRole.VENUE_OWNER));

router.get('/events', getPartyEvents);
router.get('/:eventId/summary', getEventSummary);
router.get('/:eventId/bookings', getEventBookings);

export default router;
