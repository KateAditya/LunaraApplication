import express from 'express';
import { createVenue, updateVenue, getVenues, getVenueById, deleteVenue, confirmVenue } from '../controllers/venueController';
import multer from 'multer';
import path from 'path';
import crypto from 'crypto';
import fs from 'fs';
import { authenticate, authorize } from '../middleware/auth';
import { UserRole } from '../models/User';

const router = express.Router();

// Define custom storage for these specific form uploads
const uploadsDir = process.env.UPLOAD_DIR || 'uploads';
const storage = multer.diskStorage({
    destination: (req, _file, cb) => {
        const venueId = req.params.id || 'temp';
        // Use absolute path (rooted at process.cwd()) so fs.renameSync in the controller
        // can always locate the temp files regardless of the working directory.
        const uploadPath = path.join(process.cwd(), uploadsDir, 'venues', venueId, 'raw');

        if (!fs.existsSync(uploadPath)) {
            fs.mkdirSync(uploadPath, { recursive: true });
        }
        cb(null, uploadPath);
    },
    filename: (_req, file, cb) => {
        const timestamp = Date.now();
        const randomString = crypto.randomBytes(8).toString('hex');
        const ext = path.extname(file.originalname);
        cb(null, `${timestamp}_${randomString}${ext}`);
    }
});

// ── Allowed MIME types ─────────────────────────────────────────────────────────
const ALLOWED_IMAGE_MIMES = new Set([
    'image/jpeg',
    'image/jpg',
    'image/png',
    'image/webp',
]);

const ALLOWED_VIDEO_MIMES = new Set([
    'video/mp4',
    'video/quicktime',   // MOV
    'video/x-msvideo',  // AVI
]);

const ALLOWED_IMAGE_EXTS = new Set(['.jpg', '.jpeg', '.png', '.webp']);
const ALLOWED_VIDEO_EXTS = new Set(['.mp4', '.mov', '.avi']);

const upload = multer({
    storage,
    fileFilter: (_req, file, cb) => {
        const ext = path.extname(file.originalname).toLowerCase();
        const isImage = ALLOWED_IMAGE_MIMES.has(file.mimetype) || ALLOWED_IMAGE_EXTS.has(ext);
        const isVideo = ALLOWED_VIDEO_MIMES.has(file.mimetype) || ALLOWED_VIDEO_EXTS.has(ext);

        if (isImage || isVideo) {
            cb(null, true);
        } else {
            // Determine which kind of file was expected based on field name
            const imageFields = ['coverImage', 'photos', 'menus', 'foodMenus', 'barMenus', 'beverageMenus', 'partyPackages'];
            const videoFields = ['videos'];

            if (imageFields.includes(file.fieldname)) {
                cb(new Error(
                    `Invalid image format for "${file.originalname}". ` +
                    `Allowed formats: JPG, JPEG, PNG, WEBP.`
                ));
            } else if (videoFields.includes(file.fieldname)) {
                cb(new Error(
                    `Invalid video format for "${file.originalname}". ` +
                    `Allowed formats: MP4, MOV, AVI.`
                ));
            } else {
                cb(new Error(
                    `Invalid file format for "${file.originalname}". ` +
                    `Images: JPG, JPEG, PNG, WEBP. Videos: MP4, MOV, AVI.`
                ));
            }
        }
    },
    limits: { fileSize: 200 * 1024 * 1024 } // 200MB limit per file (server compresses before storing)
}).fields([
    { name: 'coverImage', maxCount: 1 },
    { name: 'photos', maxCount: 20 },
    { name: 'videos', maxCount: 20 },
    { name: 'menus', maxCount: 20 }, // kept for backward compat
    { name: 'foodMenus', maxCount: 20 },
    { name: 'barMenus', maxCount: 20 },
    { name: 'beverageMenus', maxCount: 20 },
    { name: 'partyPackages', maxCount: 20 },
]);

// Protected routes
router.post('/', authenticate, authorize(UserRole.ADMIN, UserRole.VENUE_OWNER), upload, createVenue);
router.put('/:id', authenticate, authorize(UserRole.ADMIN, UserRole.VENUE_OWNER), upload, updateVenue);
router.delete('/:id', authenticate, authorize(UserRole.ADMIN, UserRole.VENUE_OWNER), deleteVenue);

// Public routes
// NOTE: /confirm/:token must come BEFORE /:id to avoid being caught by the ID matcher
router.get('/confirm/:token', confirmVenue);
router.get('/', getVenues);
router.get('/:id', getVenueById);

export default router;
