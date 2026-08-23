import VenueImage, { VenueImageType } from '../models/VenueImage';

/**
 * Checks if a string (imageType, category, caption, or file URL/path) represents a menu card.
 */
export function isMenuImageType(input?: string | null): boolean {
    if (!input) return false;
    const clean = String(input).toLowerCase().trim();
    if (
        clean.includes('menu') ||
        clean.includes('food_menu') ||
        clean.includes('bar_menu') ||
        clean.includes('beverage_menu') ||
        clean.includes('party_packages') ||
        clean.includes('menucard') ||
        clean.includes('menu_card') ||
        clean.includes('/menus/') ||
        clean.includes('/menu/')
    ) {
        return true;
    }
    return false;
}

/**
 * Filters out menu card images from a list of venue image objects or strings.
 */
export function filterNonMenuVenueImages(images?: any[] | null): any[] {
    if (!images || !Array.isArray(images)) return [];
    return images.filter((img) => {
        if (!img) return false;
        if (typeof img === 'string') {
            return !isMenuImageType(img);
        }
        if (typeof img === 'object') {
            const type = img.imageType || img.type || img.category || '';
            const path = img.filePath || img.url || img.imageUrl || '';
            return !isMenuImageType(type) && !isMenuImageType(path);
        }
        return true;
    });
}

/**
 * Extracts the best non-menu cover image URL/path from a venue object.
 */
export function getPrimaryVenueCoverImage(venue?: any): string | null {
    if (!venue || typeof venue !== 'object') return null;

    const normalize = (path: any): string | null => {
        if (!path || typeof path !== 'string' || !path.trim()) return null;
        const clean = path.trim().replace(/\\/g, '/');
        if (isMenuImageType(clean)) return null;
        if (clean.startsWith('http://') || clean.startsWith('https://') || clean.startsWith('assets/')) {
            return clean;
        }
        return clean.startsWith('/') ? clean : '/' + clean;
    };

    // 1. Direct explicit non-menu fields
    for (const key of ['coverImageUrl', 'cover_image_url', 'profilePhotoUrl', 'imageUrl', 'image']) {
        const candidate = venue[key];
        if (typeof candidate === 'string') {
            const norm = normalize(candidate);
            if (norm) return norm;
        }
    }

    // 2. Cover image object
    if (venue.coverImage) {
        if (typeof venue.coverImage === 'string') {
            const norm = normalize(venue.coverImage);
            if (norm) return norm;
        } else if (typeof venue.coverImage === 'object') {
            const path = venue.coverImage.url || venue.coverImage.filePath || venue.coverImage.imageUrl;
            const norm = normalize(path);
            if (norm) return norm;
        }
    }

    // 3. Scan images / gallery lists for primary or non-menu image
    for (const listKey of ['images', 'gallery', 'photos']) {
        const list = venue[listKey];
        if (Array.isArray(list) && list.length > 0) {
            const nonMenu = filterNonMenuVenueImages(list);
            if (nonMenu.length > 0) {
                // Prefer isPrimary or cover
                const primary = nonMenu.find((img) => {
                    if (typeof img === 'object') {
                        const type = String(img.imageType || img.type || '').toLowerCase();
                        return img.isPrimary || type.includes('cover');
                    }
                    return false;
                }) || nonMenu[0];

                if (typeof primary === 'string') {
                    const norm = normalize(primary);
                    if (norm) return norm;
                } else if (typeof primary === 'object') {
                    const path = primary.filePath || primary.url || primary.imageUrl;
                    const norm = normalize(path);
                    if (norm) return norm;
                }
            }
        }
    }

    return null;
}

/**
 * Queries the database for the primary non-menu venue cover image.
 */
export async function getVenueCoverImageFromDb(venueId: string): Promise<string | null> {
    if (!venueId) return null;
    try {
        const images = await VenueImage.findAll({
            where: { venueId },
            order: [['isPrimary', 'DESC'], ['displayOrder', 'ASC'], ['createdAt', 'DESC']],
        });

        if (!images || images.length === 0) return null;

        const nonMenu = images.filter((img) => !isMenuImageType(img.imageType) && !isMenuImageType(img.filePath));
        if (nonMenu.length === 0) return null;

        const primary = nonMenu.find((img) => img.isPrimary || img.imageType === VenueImageType.COVER) || nonMenu[0];
        const clean = primary.filePath.replace(/\\/g, '/');
        return clean.startsWith('/') ? clean : '/' + clean;
    } catch (_) {
        return null;
    }
}
