/**
 * Media Validation & Compression Utilities
 * Handles client-side validation and compression for venue media uploads.
 */

// ── Allowed types ──────────────────────────────────────────────────────────────
export const ALLOWED_IMAGE_TYPES = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp'] as const;
export const ALLOWED_VIDEO_TYPES = ['video/mp4', 'video/quicktime', 'video/x-msvideo'] as const;

export const ALLOWED_IMAGE_EXTENSIONS = ['JPG', 'JPEG', 'PNG', 'WEBP'];
export const ALLOWED_VIDEO_EXTENSIONS = ['MP4', 'MOV', 'AVI'];

const MAX_IMAGE_SIZE_KB = 300;

// ── Type guards ────────────────────────────────────────────────────────────────

/**
 * Returns true if the file is a valid image type (JPG/JPEG/PNG/WEBP).
 */
export const isValidImageType = (file: File): boolean => {
    // Check MIME type
    if (ALLOWED_IMAGE_TYPES.includes(file.type as any)) return true;
    // Fallback: check extension (some browsers report wrong MIME for .jpg)
    const ext = file.name.split('.').pop()?.toUpperCase() || '';
    return ALLOWED_IMAGE_EXTENSIONS.includes(ext);
};

/**
 * Returns true if the file is a valid video type (MP4/MOV/AVI).
 */
export const isValidVideoType = (file: File): boolean => {
    if (ALLOWED_VIDEO_TYPES.includes(file.type as any)) return true;
    const ext = file.name.split('.').pop()?.toUpperCase() || '';
    return ALLOWED_VIDEO_EXTENSIONS.includes(ext);
};

// ── Validation with human-readable errors ─────────────────────────────────────

export interface ValidationResult {
    valid: boolean;
    error?: string;
}

/**
 * Validate an image file for type only.
 * Returns { valid, error? }.
 */
export const validateImageFile = (file: File): ValidationResult => {
    if (!isValidImageType(file)) {
        return {
            valid: false,
            error: `"${file.name}" is not a supported image format. Please upload JPG, JPEG, PNG, or WEBP files only.`,
        };
    }
    return { valid: true };
};

/**
 * Validate a video file for type only.
 * Returns { valid, error? }.
 */
export const validateVideoFile = (file: File): ValidationResult => {
    if (!isValidVideoType(file)) {
        return {
            valid: false,
            error: `"${file.name}" is not a supported video format. Please upload MP4, MOV, or AVI files only.`,
        };
    }
    return { valid: true };
};

// ── Client-side image compression ─────────────────────────────────────────────

/**
 * Compress an image File to under maxSizeKB using Canvas.
 * Returns a new File (possibly smaller), or the original if already small enough.
 *
 * Strategy:
 *   1. Draw to canvas at full resolution.
 *   2. Export as JPEG/WEBP at decreasing quality until target size is met.
 *   3. Give up after 10 iterations (returns best result so far).
 */
export const compressImageIfNeeded = async (
    file: File,
    maxSizeKB: number = MAX_IMAGE_SIZE_KB
): Promise<File> => {
    const maxBytes = maxSizeKB * 1024;

    // Already within limit — return as-is
    if (file.size <= maxBytes) return file;

    // Determine output MIME (prefer webp for best compression; fallback jpeg)
    const outputMime: 'image/webp' | 'image/jpeg' =
        typeof document !== 'undefined' && document.createElement('canvas').toDataURL('image/webp').startsWith('data:image/webp')
            ? 'image/webp'
            : 'image/jpeg';

    return new Promise((resolve, reject) => {
        const img = new Image();
        const objectUrl = URL.createObjectURL(file);

        img.onload = () => {
            URL.revokeObjectURL(objectUrl);

            const canvas = document.createElement('canvas');
            canvas.width = img.naturalWidth;
            canvas.height = img.naturalHeight;
            const ctx = canvas.getContext('2d');
            if (!ctx) {
                resolve(file); // Can't compress — return original
                return;
            }
            ctx.drawImage(img, 0, 0);

            // Try quality from 0.9 down to 0.1
            let quality = 0.9;
            const tryCompress = () => {
                canvas.toBlob(
                    (blob) => {
                        if (!blob) {
                            resolve(file);
                            return;
                        }

                        if (blob.size <= maxBytes || quality <= 0.1) {
                            // Done — wrap blob in File
                            const ext = outputMime === 'image/webp' ? '.webp' : '.jpg';
                            const baseName = file.name.replace(/\.[^.]+$/, '');
                            const compressedFile = new File([blob], `${baseName}${ext}`, {
                                type: outputMime,
                                lastModified: Date.now(),
                            });
                            resolve(compressedFile);
                        } else {
                            quality = Math.max(0.1, quality - 0.1);
                            tryCompress();
                        }
                    },
                    outputMime,
                    quality
                );
            };

            tryCompress();
        };

        img.onerror = () => {
            URL.revokeObjectURL(objectUrl);
            reject(new Error(`Failed to load image: ${file.name}`));
        };

        img.src = objectUrl;
    });
};

/**
 * Validate + compress a list of image files.
 * Returns only valid files (after compression), plus an array of error messages.
 */
export const processImageFiles = async (
    files: File[],
    maxSizeKB: number = MAX_IMAGE_SIZE_KB
): Promise<{ validFiles: File[]; errors: string[] }> => {
    const validFiles: File[] = [];
    const errors: string[] = [];

    for (const file of files) {
        const validation = validateImageFile(file);
        if (!validation.valid) {
            errors.push(validation.error!);
            continue;
        }
        try {
            const compressed = await compressImageIfNeeded(file, maxSizeKB);
            validFiles.push(compressed);
        } catch {
            errors.push(`Failed to process "${file.name}". Please try again.`);
        }
    }

    return { validFiles, errors };
};

/**
 * Validate a list of video files.
 * Returns only valid files plus an array of error messages.
 */
export const processVideoFiles = (
    files: File[]
): { validFiles: File[]; errors: string[] } => {
    const validFiles: File[] = [];
    const errors: string[] = [];

    for (const file of files) {
        const validation = validateVideoFile(file);
        if (!validation.valid) {
            errors.push(validation.error!);
        } else {
            validFiles.push(file);
        }
    }

    return { validFiles, errors };
};
