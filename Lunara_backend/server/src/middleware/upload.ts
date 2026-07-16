import multer from 'multer';
import path from 'path';
import fs from 'fs';
import crypto from 'crypto';


// Re-export crypto so controllers can use the same random-name helper
export { crypto };

// Create uploads directory if it doesn't exist
const uploadsDir = process.env.UPLOAD_DIR || 'uploads';
if (!fs.existsSync(uploadsDir)) {
    fs.mkdirSync(uploadsDir, { recursive: true });
}

// ── Allowed types ─────────────────────────────────────────────────────────────
const ALLOWED_IMAGE_MIMES = new Set(['image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'image/avif']);
const ALLOWED_VIDEO_MIMES = new Set(['video/mp4', 'video/quicktime', 'video/x-msvideo']);
const ALLOWED_IMAGE_EXTENSIONS = new Set(['.jpg', '.jpeg', '.png', '.webp', '.avif']);
const ALLOWED_VIDEO_EXTENSIONS = new Set(['.mp4', '.mov', '.avi']);

// ── File filter for images only ────────────────────────────────────────────────
export const imageFileFilter = (_req: any, file: Express.Multer.File, cb: multer.FileFilterCallback) => {
    const ext = path.extname(file.originalname).toLowerCase();
    if (ALLOWED_IMAGE_MIMES.has(file.mimetype) || ALLOWED_IMAGE_EXTENSIONS.has(ext)) {
        cb(null, true);
    } else {
        cb(new Error(
            `Invalid image format: "${file.originalname}". Allowed formats: JPG, JPEG, PNG, WEBP, AVIF.`
        ));
    }
};

// ── File filter for videos only ────────────────────────────────────────────────
export const videoFileFilter = (_req: any, file: Express.Multer.File, cb: multer.FileFilterCallback) => {
    const ext = path.extname(file.originalname).toLowerCase();
    if (ALLOWED_VIDEO_MIMES.has(file.mimetype) || ALLOWED_VIDEO_EXTENSIONS.has(ext)) {
        cb(null, true);
    } else {
        cb(new Error(
            `Invalid video format: "${file.originalname}". Allowed formats: MP4, MOV, AVI.`
        ));
    }
};

// ── Combined filter (images + videos) for venue uploads ────────────────────────
export const imageOrVideoFileFilter = (_req: any, file: Express.Multer.File, cb: multer.FileFilterCallback) => {
    const ext = path.extname(file.originalname).toLowerCase();
    const mimeOk = ALLOWED_IMAGE_MIMES.has(file.mimetype) || ALLOWED_VIDEO_MIMES.has(file.mimetype);
    const extOk = ALLOWED_IMAGE_EXTENSIONS.has(ext) || ALLOWED_VIDEO_EXTENSIONS.has(ext);
    if (mimeOk || extOk) {
        cb(null, true);
    } else {
        cb(new Error(
            `Invalid file format: "${file.originalname}". ` +
            `Images: JPG, JPEG, PNG, WEBP, AVIF. Videos: MP4, MOV, AVI.`
        ));
    }
};

// ─── Azure Storage Configuration ───────────────────────────────────────────────
import { MulterAzureStorage } from 'multer-azure-blob-storage';

export const azureConfigured = !!process.env.AZURE_STORAGE_CONNECTION_STRING;

export const azureStorageHelper = (folderPathFn: (req: any) => string) => {
    return new MulterAzureStorage({
        connectionString: process.env.AZURE_STORAGE_CONNECTION_STRING || '',
        accessKey: process.env.AZURE_STORAGE_ACCESS_KEY || '',
        accountName: process.env.AZURE_STORAGE_ACCOUNT_NAME || '',
        containerName: process.env.AZURE_STORAGE_CONTAINER_NAME || 'uploads',
        containerAccessLevel: 'blob',
        urlExpirationTime: -1, // No expiration, public blob
        blobName: (req: any, file: Express.Multer.File) => {
            return new Promise((resolve) => {
                const folder = folderPathFn(req);
                const timestamp = Date.now();
                const randomString = crypto.randomBytes(8).toString('hex');
                const ext = path.extname(file.originalname);
                // Windows-style paths (from path.join) must be converted to forward slashes for Azure Blob
                const blobPath = `${folder}/${timestamp}_${randomString}${ext}`.replace(/\\/g, '/');
                resolve(blobPath);
            });
        }
    });
};

// Storage configuration for user photos
const userPhotoStorageLocal = multer.diskStorage({
    destination: (req: any, _file, cb) => {
        const userId = req.user?.id || 'anonymous';
        const uploadPath = path.join(uploadsDir, 'users', userId, 'gallery');

        // Create directory if it doesn't exist
        if (!fs.existsSync(uploadPath)) {
            fs.mkdirSync(uploadPath, { recursive: true });
        }

        cb(null, uploadPath);
    },
    filename: (_req, file, cb) => {
        // Generate unique filename: timestamp + random + extension
        const timestamp = Date.now();
        const randomString = crypto.randomBytes(8).toString('hex');
        const ext = path.extname(file.originalname);
        cb(null, `${timestamp}_${randomString}${ext}`);
    },
});

const userPhotoStorage = azureConfigured
    ? azureStorageHelper((req) => `users/${req.user?.id || 'anonymous'}/gallery`)
    : userPhotoStorageLocal;

// Storage configuration for venue photos
const venuePhotoStorageLocal = multer.diskStorage({
    destination: (req: any, _file, cb) => {
        const venueId = req.params.venueId || req.body.venueId || 'temp';
        const imageType = req.body.imageType || 'gallery';
        const uploadPath = path.join(uploadsDir, 'venues', venueId, imageType);

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
    },
});

const venuePhotoStorage = azureConfigured
    ? azureStorageHelper((req) => {
          const venueId = req.params.venueId || req.body.venueId || 'temp';
          const imageType = req.body.imageType || 'gallery';
          return `venues/${venueId}/${imageType}`;
      })
    : venuePhotoStorageLocal;

// Size limits
const maxPhotoSize = 52428800; // 50MB limit to ensure high-res selfies don't fail

// User photo upload middleware
export const uploadUserPhoto = multer({
    storage: userPhotoStorage,
    fileFilter: imageFileFilter,
    limits: {
        fileSize: maxPhotoSize,
        files: 1,
    },
});

// Multiple user photos upload middleware (disk — legacy, kept for reference)
export const uploadUserPhotos = multer({
    storage: userPhotoStorage,
    fileFilter: imageFileFilter,
    limits: {
        fileSize: maxPhotoSize,
        files: parseInt(process.env.MAX_USER_PHOTOS || '6'),
    },
});

// ─── Temp disk-storage variant ───────────────────────────────────────────────────
// Use this to prevent memory exhaustion and large file limits on memory storage.
export const uploadTempPhotos = multer({
    dest: path.join(uploadsDir, 'temp'),
    fileFilter: imageFileFilter,
    limits: {
        fileSize: 52428800, // 50MB
    },
});

// Helper: build the user gallery directory path (mirrors diskStorage logic)
export const getUserGalleryDir = (userId: string): string => {
    const uploadsBase = process.env.UPLOAD_DIR || 'uploads';
    const dir = path.join(uploadsBase, 'users', userId, 'gallery');
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    return dir;
};

// Venue photo upload middleware
export const uploadVenuePhoto = multer({
    storage: venuePhotoStorage,
    fileFilter: imageFileFilter,
    limits: {
        fileSize: maxPhotoSize * 2, // 10MB for venue photos
        files: 1,
    },
});

// Multiple venue photos upload middleware
export const uploadVenuePhotos = multer({
    storage: venuePhotoStorage,
    fileFilter: imageFileFilter,
    limits: {
        fileSize: maxPhotoSize * 2,
        files: parseInt(process.env.MAX_VENUE_PHOTOS || '20'),
    },
});

// Helper function to delete a file
export const deleteFile = (filePath: string): void => {
    const fullPath = path.join(process.cwd(), filePath);
    if (fs.existsSync(fullPath)) {
        try {
            fs.unlinkSync(fullPath);
        } catch (error) {
            console.error(`Error deleting file ${filePath}:`, error);
        }
    }
};

// Helper function to ensure directory exists
export const ensureDirectoryExists = (dirPath: string): void => {
    if (!fs.existsSync(dirPath)) {
        fs.mkdirSync(dirPath, { recursive: true });
    }
};

export default {
    uploadUserPhoto,
    uploadUserPhotos,
    uploadTempPhotos,
    getUserGalleryDir,
    uploadVenuePhoto,
    uploadVenuePhotos,
    deleteFile,
    ensureDirectoryExists,
    imageFileFilter,
    videoFileFilter,
    imageOrVideoFileFilter,
};
