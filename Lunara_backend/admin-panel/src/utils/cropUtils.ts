/**
 * Image Crop Utilities with Advanced Features
 */

/**
 * Convert File to Data URL
 */
export const fileToDataUrl = (file: File): Promise<string> => {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(reader.result as string);
        reader.onerror = reject;
        reader.readAsDataURL(file);
    });
};

/**
 * Create Data URL from blob
 */
export const blobToDataUrl = (blob: Blob): Promise<string> => {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(reader.result as string);
        reader.onerror = reject;
        reader.readAsDataURL(blob);
    });
};

/**
 * Get image dimensions
 */
export const getImageDimensions = (imageSrc: string): Promise<{ width: number; height: number }> => {
    return new Promise((resolve, reject) => {
        const img = new Image();
        img.onload = () => {
            resolve({ width: img.width, height: img.height });
        };
        img.onerror = reject;
        img.src = imageSrc;
    });
};

/**
 * Calculate default crop area based on aspect ratio
 */
export const calculateDefaultCropArea = (
    imageWidth: number,
    imageHeight: number,
    aspectRatio: number
): { x: number; y: number; width: number; height: number } => {
    let width = imageWidth;
    let height = imageHeight;

    // Adjust dimensions to match aspect ratio
    if (width / height > aspectRatio) {
        width = height * aspectRatio;
    } else {
        height = width / aspectRatio;
    }

    // Center the crop area
    const x = (imageWidth - width) / 2;
    const y = (imageHeight - height) / 2;

    return { x, y, width, height };
};

/**
 * Validate image file
 */
export const validateImageFile = (file: File, maxSizeMB: number = 10): {
    valid: boolean;
    error?: string;
} => {
    const validTypes = ['image/jpeg', 'image/png', 'image/gif', 'image/webp'];

    if (!validTypes.includes(file.type)) {
        return {
            valid: false,
            error: 'Invalid file type. Please upload an image file (JPEG, PNG, GIF, or WebP).',
        };
    }

    const fileSizeMB = file.size / (1024 * 1024);
    if (fileSizeMB > maxSizeMB) {
        return {
            valid: false,
            error: `File size exceeds ${maxSizeMB}MB. Please choose a smaller image.`,
        };
    }

    return { valid: true };
};

/**
 * Apply image transformations
 */
export interface ImageTransformations {
    rotation?: number; // 0-360
    brightness?: number; // 50-150
    contrast?: number; // 50-150
    flipH?: boolean;
    flipV?: boolean;
}

export const applyImageTransformations = (
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    _canvas: HTMLCanvasElement,
    ctx: CanvasRenderingContext2D,
    img: HTMLImageElement,
    width: number,
    height: number,
    transformations: ImageTransformations = {}
): void => {
    const {
        rotation = 0,
        brightness = 100,
        contrast = 100,
        flipH = false,
        flipV = false,
    } = transformations;

    // Apply filter effects
    ctx.filter = `brightness(${brightness}%) contrast(${contrast}%)`;

    // Save context state
    ctx.save();

    // Move to center
    ctx.translate(width / 2, height / 2);

    // Apply rotation
    ctx.rotate((rotation * Math.PI) / 180);

    // Apply flips
    ctx.scale(flipH ? -1 : 1, flipV ? -1 : 1);

    // Draw image centered
    ctx.drawImage(img, -width / 2, -height / 2, width, height);

    // Restore context
    ctx.restore();
};

/**
 * Get formatted dimension string
 */
export const formatDimensions = (width: number, height: number): string => {
    return `${Math.round(width)} x ${Math.round(height)}px`;
};

/**
 * Calculate aspect ratio label
 */
export const getAspectRatioLabel = (ratio: number): string => {
    const ratios: Record<number, string> = {
        1.777777: '16:9',
        1: '1:1',
        1.333333: '4:3',
        1.5: '3:2',
    };

    for (const [value, label] of Object.entries(ratios)) {
        if (Math.abs(parseFloat(value) - ratio) < 0.01) {
            return label;
        }
    }

    return 'Custom';
};
