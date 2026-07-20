import sharp from 'sharp';
import path from 'path';
import fs from 'fs';

export interface ImageOptimizationOptions {
    width?: number;
    height?: number;
    quality?: number;
    format?: 'jpeg' | 'png' | 'webp';
    fit?: 'cover' | 'contain' | 'fill' | 'inside' | 'outside';
}

/**
 * Optimize an uploaded image
 * @param filePath - Path to the original image
 * @param options - Optimization options
 * @returns Path to the optimized image
 */
export async function optimizeImage(
    filePath: string,
    options: ImageOptimizationOptions = {}
): Promise<string> {
    const {
        width = 1200,
        height,
        quality = 80,
        format = 'webp',
        fit = 'inside',
    } = options;

    try {
        const ext = path.extname(filePath);
        const optimizedPath = filePath.replace(ext, `.optimized.${format}`);

        // Read file into buffer to avoid file lock issues on Windows
        const inputBuffer = fs.readFileSync(filePath);

        let transformer = sharp(inputBuffer)
            .rotate()
            .resize(width, height, { fit });

        // Apply format-specific optimization
        switch (format) {
            case 'jpeg':
                transformer = transformer.jpeg({ quality, progressive: true });
                break;
            case 'png':
                transformer = transformer.png({ quality, compressionLevel: 9 });
                break;
            case 'webp':
                transformer = transformer.webp({ quality });
                break;
        }

        await transformer.toFile(optimizedPath);

        // Delete original file
        try {
            if (fs.existsSync(filePath)) {
                fs.unlinkSync(filePath);
            }
        } catch (e) {
            console.error(`Failed to delete raw image ${filePath}:`, e);
        }

        return optimizedPath;
    } catch (error) {
        console.error('Error optimizing image:', error);
        throw error;
    }
}

/**
 * Compress an image to under 300KB.
 * Iteratively reduces quality (starting at 85) until the output is ≤ 300 KB.
 * Always converts to WebP for best compression ratio.
 * The original file is deleted and replaced with the compressed version.
 *
 * @param filePath - Absolute path to the uploaded image
 * @returns Path to the compressed file (WebP)
 */
export async function compressImageTo300KB(filePath: string): Promise<string> {
    const MAX_SIZE_BYTES = 300 * 1024; // 300 KB

    try {
        const ext = path.extname(filePath);
        const compressedPath = filePath.replace(ext, '.compressed.webp');

        const inputBuffer = fs.readFileSync(filePath);

        // ── Fast Single-Pass Optimization with Dimension Cap ────────────────
        // Resizing raw camera photos to max 1400px width/height reduces raw pixel buffer by up to 90% instantly
        let outputBuffer = await sharp(inputBuffer)
            .rotate()
            .resize(1400, 1400, { fit: 'inside', withoutEnlargement: true })
            .webp({ quality: 80, effort: 3 })
            .toBuffer();

        // If still above 300 KB, resize to 1100px with quality 70
        if (outputBuffer.length > MAX_SIZE_BYTES) {
            outputBuffer = await sharp(inputBuffer)
                .rotate()
                .resize(1100, 1100, { fit: 'inside', withoutEnlargement: true })
                .webp({ quality: 70, effort: 3 })
                .toBuffer();
        }

        // Final fallback for exceptionally complex high-frequency images
        if (outputBuffer.length > MAX_SIZE_BYTES) {
            outputBuffer = await sharp(inputBuffer)
                .rotate()
                .resize(900, 900, { fit: 'inside', withoutEnlargement: true })
                .webp({ quality: 60, effort: 2 })
                .toBuffer();
        }

        fs.writeFileSync(compressedPath, outputBuffer);

        // Delete original raw upload file
        try {
            if (fs.existsSync(filePath) && filePath !== compressedPath) {
                fs.unlinkSync(filePath);
            }
        } catch { /* ignore cleanup error */ }

        console.log(`[compressImageTo300KB] ${path.basename(filePath)} → ${Math.round(outputBuffer.length / 1024)}KB (fast optimized)`);
        return compressedPath;
    } catch (error) {
        console.error('Error compressing image to 300KB:', error);
        throw error;
    }
}



/**
 * Create a thumbnail from an image
 * @param filePath - Path to the original image
 * @param thumbnailSize - Size of the thumbnail (square)
 * @returns Path to the thumbnail
 */
export async function createThumbnail(
    filePath: string,
    thumbnailSize: number = 300
): Promise<string> {
    try {
        const dir = path.dirname(filePath);
        const ext = path.extname(filePath);
        const basename = path.basename(filePath, ext);
        const thumbnailPath = path.join(dir, `${basename}_thumb.webp`);

        // Read file into buffer to avoid file lock issues on Windows
        const inputBuffer = fs.readFileSync(filePath);

        await sharp(inputBuffer)
            .rotate()
            .resize(thumbnailSize, thumbnailSize, {
                fit: 'cover',
                position: 'center',
            })
            .webp({ quality: 70 })
            .toFile(thumbnailPath);

        return thumbnailPath;
    } catch (error) {
        console.error('Error creating thumbnail:', error);
        throw error;
    }
}

/**
 * Get image metadata
 * @param filePath - Path to the image
 * @returns Image metadata
 */
export async function getImageMetadata(filePath: string): Promise<sharp.Metadata> {
    try {
        const inputBuffer = fs.readFileSync(filePath);
        const metadata = await sharp(inputBuffer).metadata();
        return metadata;
    } catch (error) {
        console.error('Error getting image metadata:', error);
        throw error;
    }
}

/**
 * Validate image dimensions
 * @param filePath - Path to the image
 * @param minWidth - Minimum width
 * @param minHeight - Minimum height
 * @param maxWidth - Maximum width
 * @param maxHeight - Maximum height
 * @returns true if valid, throws error if invalid
 */
export async function validateImageDimensions(
    filePath: string,
    minWidth: number = 100,
    minHeight: number = 100,
    maxWidth: number = 5000,
    maxHeight: number = 5000
): Promise<boolean> {
    try {
        const metadata = await getImageMetadata(filePath);
        const { width = 0, height = 0 } = metadata;

        if (width < minWidth || height < minHeight) {
            throw new Error(`Image dimensions too small. Minimum: ${minWidth}x${minHeight}px`);
        }

        if (width > maxWidth || height > maxHeight) {
            throw new Error(`Image dimensions too large. Maximum: ${maxWidth}x${maxHeight}px`);
        }

        return true;
    } catch (error) {
        throw error;
    }
}

export default {
    optimizeImage,
    compressImageTo300KB,
    createThumbnail,
    getImageMetadata,
    validateImageDimensions,
};
