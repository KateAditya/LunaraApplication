import { Router } from 'express';
import { param, body } from 'express-validator';
import { validate } from '../middleware/validate';
import * as ctrl from '../controllers/adminBookingController';

const router = Router();

// GET /api/admin/bookings/large-party-requests
router.get('/large-party-requests', ctrl.getLargePartyRequests);

// POST /api/admin/bookings/:id/approve-party-request
router.post(
    '/:id/approve-party-request',
    [
        param('id').isUUID().withMessage('id must be a UUID'),
        body('status').isIn(['approved', 'rejected']).withMessage('status must be approved or rejected'),
        validate,
    ],
    ctrl.approveLargePartyRequest
);

export default router;
