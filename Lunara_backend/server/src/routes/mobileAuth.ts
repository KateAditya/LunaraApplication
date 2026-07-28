import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { mobileRegister, mobileSendOTP, mobileVerifyOTP, mobileForgotPassword, mobileResetPassword, mobileLogout, mobileCheckEmail, mobileVerifyFace, mobileDetectFace, mobileFacebookLogin } from '../controllers/mobileAuthController';

const router = Router();

// ── Stricter rate limit for auth endpoints (prevent brute-force / bot abuse) ──
const authLimiter = process.env.NODE_ENV === 'development'
    ? (_req: any, _res: any, next: any) => next()
    : rateLimit({
        windowMs: 15 * 60 * 1000,   // 15 minutes
        max:      20,                 // max 20 registration attempts per window per IP
        message: {
            success: false,
            code:    'RATE_LIMIT_EXCEEDED',
            message: 'Too many requests. Please try again after 15 minutes.',
        },
        standardHeaders: true,
        legacyHeaders:   false,
        keyGenerator: (req: any): string => {
            const raw = req.ip || req.socket?.remoteAddress || 'unknown';
            // Azure LB may forward 'IP:PORT' — strip port to get a valid key
            return raw.includes(':') && !raw.startsWith('::') ? raw.split(':')[0] : raw;
        },
    });

// ── Routes ────────────────────────────────────────────────────────────────────

/**
 * POST /api/mobile/auth/send-otp
 */
router.post('/send-otp', authLimiter, mobileSendOTP);

/**
 * POST /api/mobile/auth/check-email
 */
router.post('/check-email', authLimiter, mobileCheckEmail);

/**
 * POST /api/mobile/auth/verify-otp
 */
router.post('/verify-otp', authLimiter, mobileVerifyOTP);

/**
 * POST /api/mobile/auth/forgot-password
 */
router.post('/forgot-password', authLimiter, mobileForgotPassword);

/**
 * POST /api/mobile/auth/reset-password
 */
router.post('/reset-password', authLimiter, mobileResetPassword);

/**
 * POST /api/mobile/auth/register
 *
 * Public — no authentication required.
 * Registers a new mobile app user.
 *
 * Body (JSON):
 *   firstName   string  required
 *   lastName    string  required
 *   email       string  required
 *   phone       string  required  (10-digit Indian number)
 *   password    string  required  (min 8 chars, upper+lower+digit+special)
 *   dateOfBirth string  required  (YYYY-MM-DD)
 *   gender      string  optional
 *   city        string  optional
 *   biometricEnabled boolean optional
 *
 * Responses:
 *   201  { success, message, data: { user, accessToken, refreshToken, expiresIn } }
 *   400  { success, code, message, [fields] }   — validation error
 *   409  { success, code, message, field }       — duplicate email/phone
 *   429  { success, code, message }              — rate limit
 *   500  { success, code, message }              — server error
 */
router.post('/register', authLimiter, mobileRegister);

/**
 * POST /api/mobile/auth/verify-face
 * Perform Azure AI Face verification (Selfie vs Profile Photo)
 */
router.post('/verify-face', authLimiter, mobileVerifyFace);

/**
 * POST /api/mobile/auth/detect-face
 * Single image human face detection
 */
router.post('/detect-face', authLimiter, mobileDetectFace);

/**
 * POST /api/mobile/auth/logout
 */
router.post('/logout', authLimiter, mobileLogout);

/**
 * POST /api/mobile/auth/facebook-login
 */
router.post('/facebook-login', authLimiter, mobileFacebookLogin);

export default router;
