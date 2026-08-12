import { Request, Response } from 'express';
import { Op } from 'sequelize';
import fs from 'fs';
import Ad from '../models/Ad';
import Venue from '../models/Venue';
import User from '../models/User';
import { sendMulticastPushNotification } from '../services/fcmService';
import { compressImageTo300KB } from '../utils/imageProcessor';
import { logger } from '../config/logger';

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/ads
// Returns all ads (for Admin panel).
// ─────────────────────────────────────────────────────────────────────────────
export const getAds = async (_req: Request, res: Response): Promise<Response> => {
    try {
        const ads = await Ad.findAll({
            include: [{ model: Venue, as: 'venue', attributes: ['id', 'name'] }],
            order: [['createdAt', 'DESC']],
        });

        // Format dates correctly as strings and parse socialLinks
        const data = ads.map(ad => {
            const json = ad.toJSON();
            // Handle socialLinks if stored as string accidentally
            if (typeof json.socialLinks === 'string') {
                try {
                    json.socialLinks = JSON.parse(json.socialLinks);
                } catch {
                    json.socialLinks = [];
                }
            }
            return json;
        });

        res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0');
        return res.status(200).json({ success: true, data });
    } catch (error) {
        logger.error('[AdController] Error fetching ads:', error);
        return res.status(500).json({ success: false, message: 'Failed to fetch ads.' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/ads/active
// Returns active ads for mobile app, filtered by date and status.
// Optionally filter by city and area via query params.
// ─────────────────────────────────────────────────────────────────────────────
export const getActiveAds = async (req: Request, res: Response): Promise<Response> => {
    try {
        const { city, area, venueId, type } = req.query;
        const now = new Date();

        const whereClause: any = {
            isActive: true,
            fromDate: { [Op.lte]: now },
            toDate: { [Op.gte]: now },
        };

        const isValidString = (val: any) => typeof val === 'string' && val.trim() !== '' && val !== 'null' && val !== 'undefined';

        if (isValidString(city)) {
            whereClause.city = { [Op.iLike]: city };
        }
        if (isValidString(area)) {
            whereClause.area = { [Op.iLike]: area };
        }
        if (isValidString(venueId)) {
            whereClause.venueId = venueId;
        }
        if (isValidString(type)) {
            // Validate type is either 'Ads' or 'Party'
            const validTypes = ['Ads', 'Party'];
            if (validTypes.includes(type as string)) {
                whereClause.type = type;
            } else {
                return res.status(400).json({ success: false, message: 'Invalid type parameter. Allowed values: Ads, Party' });
            }
        }

        const ads = await Ad.findAll({
            where: whereClause,
            include: [{ model: Venue, as: 'venue', attributes: ['id', 'name', 'city', 'area', 'addressLine1', 'category'] }],
            order: [['createdAt', 'DESC']],
        });

        // Add full URL prefix for imagePath and parse socialLinks
        const data = ads.map(ad => {
            const adJson = ad.toJSON();
            
            // Handle socialLinks if stored as string accidentally
            if (typeof adJson.socialLinks === 'string') {
                try {
                    adJson.socialLinks = JSON.parse(adJson.socialLinks);
                } catch {
                    adJson.socialLinks = [];
                }
            }
            
            let finalImagePath = adJson.imagePath;
            if (finalImagePath && !finalImagePath.startsWith('http')) {
                finalImagePath = `/${finalImagePath.replace(/\\/g, '/')}`;
            }
            
            return {
                ...adJson,
                imagePath: finalImagePath,
            };
        });

        res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0');
        return res.status(200).json({ success: true, data });
    } catch (error) {
        logger.error('[AdController] Error fetching active ads:', error);
        return res.status(500).json({ success: false, message: 'Failed to fetch active ads.' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/ads
// Create a new ad. Expects multipart/form-data.
// ─────────────────────────────────────────────────────────────────────────────
export const createAd = async (req: Request, res: Response): Promise<Response> => {
    try {
        const { type, venueId, city, area, title, fromDate, toDate, isActive, aboutEvent } = req.body;
        let socialLinks = [];
        
        try {
            if (req.body.socialLinks) {
                socialLinks = typeof req.body.socialLinks === 'string' ? JSON.parse(req.body.socialLinks) : req.body.socialLinks;
            }
        } catch (e) {
            return res.status(400).json({ success: false, message: 'Invalid socialLinks format' });
        }

        const getValidValue = (val: any) => {
            if (typeof val === 'string') {
                const trimmed = val.trim();
                if (trimmed === '' || trimmed === 'null' || trimmed === 'undefined') return null;
                return trimmed;
            }
            return val || null;
        };

        const parsedVenueId = getValidValue(venueId);
        const parsedCity = getValidValue(city);
        const parsedArea = getValidValue(area);

        if (!type || !fromDate || !toDate) {
            return res.status(400).json({ success: false, message: 'Missing required fields' });
        }
        if (type === 'Party' && (!parsedVenueId || !parsedCity || !parsedArea)) {
            return res.status(400).json({ success: false, message: 'Missing required fields for Party ads' });
        }

        const file = req.file;
        if (!file) {
            return res.status(400).json({ success: false, message: 'Image file is required' });
        }

        // Handle Azure Blob Storage vs Local Disk
        let imagePath = '';
        if ((file as any).url) {
            imagePath = (file as any).url.split('?')[0];
        } else if (file.path) {
            const compressedPath = await compressImageTo300KB(file.path);
            imagePath = compressedPath.replace(/\\/g, '/');
        } else {
            return res.status(400).json({ success: false, message: 'Invalid file upload state' });
        }

        const newAd = await Ad.create({
            type,
            venueId: parsedVenueId,
            city: parsedCity,
            area: parsedArea,
            title: getValidValue(title),
            imagePath: imagePath,
            fromDate: new Date(fromDate),
            toDate: new Date(toDate),
            isActive: isActive === 'true' || isActive === true,
            aboutEvent: getValidValue(aboutEvent),
            socialLinks,
        });

        // Broadcast real-time WebSocket event and System Notification
        try {
            const { io } = require('../server');
            if (io) {
                const broadcastPayload = {
                    id: `ad_${newAd.id}`,
                    type: newAd.type === 'Party' ? 'new_party_event' : 'new_ad_banner',
                    title: newAd.title || (newAd.type === 'Party' ? '🎉 Live Party Event!' : '📢 Special Announcement'),
                    body: newAd.aboutEvent || (newAd.type === 'Party' ? `Exclusive Party Event in ${newAd.city || 'your area'}!` : 'New special offer available on Lunara!'),
                    ad: {
                        id: newAd.id,
                        type: newAd.type,
                        title: newAd.title,
                        venueId: newAd.venueId,
                        city: newAd.city,
                        area: newAd.area,
                        imagePath: newAd.imagePath,
                        fromDate: newAd.fromDate,
                        toDate: newAd.toDate,
                        aboutEvent: newAd.aboutEvent,
                        socialLinks: newAd.socialLinks,
                    },
                    createdAt: new Date().toISOString(),
                };
                io.emit('new_ad_published', broadcastPayload);
            }
        } catch (socketErr: any) {
            logger.warn('[AdController] Socket broadcast warning:', socketErr.message);
        }

        // Trigger Multicast Push Notification & persist DB Notifications for active users
        setImmediate(async () => {
            try {
                const activeUsers = await User.findAll({
                    attributes: ['id', 'fcmToken'],
                    where: {
                        isActive: true
                    },
                });

                const notifTitle = newAd.type === 'Party' ? '🎉 Live Party Event Announced!' : '📢 Special App Announcement';
                const notifBody = newAd.title || newAd.aboutEvent || 'Check out the new offer on Lunara!';

                // 1. Bulk Create DB Notifications for all users
                try {
                    const NotificationModel = (await import('../models/Notification')).default;
                    const notifRecords = activeUsers.map(u => ({
                        recipientUserId: u.id,
                        eventType: 'new_ad_published',
                        category: 'announcements' as any,
                        entityType: 'ad',
                        entityId: newAd.id,
                        title: notifTitle,
                        body: notifBody,
                        imageUrl: newAd.imagePath,
                        priority: 'HIGH' as any,
                        isRead: false,
                        metadata: {
                            adId: newAd.id,
                            adType: newAd.type,
                            venueId: newAd.venueId,
                            city: newAd.city,
                            area: newAd.area,
                            liveCountdownTarget: new Date(newAd.toDate).getTime()
                        }
                    }));

                    await NotificationModel.bulkCreate(notifRecords, { ignoreDuplicates: true }).catch(() => {});
                } catch (dbErr: any) {
                    logger.warn('[AdController] Bulk DB notification creation warning: ' + dbErr.message);
                }

                // 2. Multicast Push Notification to mobile devices
                const tokens = activeUsers.map(u => u.fcmToken).filter(t => t && t.trim() !== '') as string[];
                if (tokens.length > 0) {
                    await sendMulticastPushNotification(tokens, {
                        title: notifTitle,
                        body: notifBody,
                        data: {
                            type: 'new_ad_published',
                            adId: newAd.id,
                            adType: newAd.type,
                            venueId: newAd.venueId || '',
                        },
                    });
                }
            } catch (pushErr: any) {
                logger.warn('[AdController] Multicast push warning:', pushErr.message);
            }
        });

        return res.status(201).json({ success: true, message: 'Ad created successfully', data: newAd });
    } catch (error) {
        logger.error('[AdController] Error creating ad:', error);
        return res.status(500).json({ success: false, message: 'Failed to create ad.' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// PUT /api/ads/:id
// Update an ad. Expects multipart/form-data.
// ─────────────────────────────────────────────────────────────────────────────
export const updateAd = async (req: Request, res: Response): Promise<Response> => {
    try {
        const { id } = req.params;
        const ad = await Ad.findByPk(id);
        
        if (!ad) {
            return res.status(404).json({ success: false, message: 'Ad not found' });
        }

        const { type, venueId, city, area, title, fromDate, toDate, isActive, aboutEvent } = req.body;
        
        const getValidValue = (val: any) => {
            if (typeof val === 'string') {
                const trimmed = val.trim();
                if (trimmed === '' || trimmed === 'null' || trimmed === 'undefined') return null;
                return trimmed;
            }
            return val || null;
        };

        if (type) ad.type = type;
        if (venueId !== undefined) ad.venueId = getValidValue(venueId);
        if (city !== undefined) ad.city = getValidValue(city);
        if (area !== undefined) ad.area = getValidValue(area);
        if (title !== undefined) ad.title = getValidValue(title);
        if (fromDate) ad.fromDate = new Date(fromDate);
        if (toDate) ad.toDate = new Date(toDate);
        if (isActive !== undefined) ad.isActive = isActive === 'true' || isActive === true;
        if (aboutEvent !== undefined) ad.aboutEvent = getValidValue(aboutEvent);

        if (req.body.socialLinks) {
            try {
                ad.socialLinks = typeof req.body.socialLinks === 'string' ? JSON.parse(req.body.socialLinks) : req.body.socialLinks;
            } catch (e) {
                // Ignore parsing errors for social links update
            }
        }

        const file = req.file;
        if (file) {
            const oldPath = ad.imagePath;
            
            if ((file as any).url) {
                ad.imagePath = (file as any).url.split('?')[0];
            } else if (file.path) {
                const compressedPath = await compressImageTo300KB(file.path);
                ad.imagePath = compressedPath.replace(/\\/g, '/');
            } else {
                return res.status(400).json({ success: false, message: 'Invalid file upload state' });
            }
            
            // Delete old file if it exists and is different (and not an HTTP URL)
            if (oldPath && !oldPath.startsWith('http') && fs.existsSync(oldPath) && oldPath !== ad.imagePath) {
                fs.unlink(oldPath, (err) => {
                    if (err) logger.warn(`[AdController] Failed to delete old ad image: ${oldPath}`, err);
                });
            }
        }

        await ad.save();

        return res.status(200).json({ success: true, message: 'Ad updated successfully', data: ad });
    } catch (error) {
        logger.error('[AdController] Error updating ad:', error);
        return res.status(500).json({ success: false, message: 'Failed to update ad.' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// DELETE /api/ads/:id
// ─────────────────────────────────────────────────────────────────────────────
export const deleteAd = async (req: Request, res: Response): Promise<Response> => {
    try {
        const { id } = req.params;
        const ad = await Ad.findByPk(id);
        
        if (!ad) {
            return res.status(404).json({ success: false, message: 'Ad not found' });
        }

        const oldPath = ad.imagePath;
        await ad.destroy();

        if (oldPath && !oldPath.startsWith('http') && fs.existsSync(oldPath)) {
            fs.unlink(oldPath, (err) => {
                if (err) logger.warn(`[AdController] Failed to delete ad image: ${oldPath}`, err);
            });
        }

        return res.status(200).json({ success: true, message: 'Ad deleted successfully' });
    } catch (error) {
        logger.error('[AdController] Error deleting ad:', error);
        return res.status(500).json({ success: false, message: 'Failed to delete ad.' });
    }
};

export default { getAds, getActiveAds, createAd, updateAd, deleteAd };
