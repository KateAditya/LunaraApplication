import { Request, Response } from 'express';
import { Op } from 'sequelize';
import { VenueStatus, VenueCategory } from '../models/Venue';
import { VenueImageType } from '../models/VenueImage';
import { Venue, VenueImage } from '../models';
import VenueComplianceLog, { ComplianceEventType } from '../models/VenueComplianceLog';
import { sendVenueConfirmationEmail } from '../services/emailService';
import { compressImageTo300KB } from '../utils/imageProcessor';
import path from 'path';
import fs from 'fs';
import crypto from 'crypto';

// ── Helper: build structured menu & media sections from flat images array ─────
const buildVenueMediaSections = (images: VenueImage[]) => {
    const getUrl = (img: VenueImage) => '/' + img.filePath.replace(/\\/g, '/');

    const byType = (type: VenueImageType) =>
        images
            .filter(img => img.imageType === type)
            .sort((a, b) => a.displayOrder - b.displayOrder)
            .map(img => ({
                id:           img.id,
                url:          getUrl(img),
                filePath:     img.filePath,
                fileSize:     img.fileSize,
                mimeType:     img.mimeType,
                isPrimary:    img.isPrimary,
                displayOrder: img.displayOrder,
                caption:      img.caption ?? null,
                uploadedAt:   img.uploadedAt,
            }));

    return {
        coverImage:    byType(VenueImageType.COVER)[0] ?? null,
        gallery:       [
            ...byType(VenueImageType.INTERIOR),
            ...byType(VenueImageType.EXTERIOR),
        ].sort((a, b) => a.displayOrder - b.displayOrder),
        menu: {
            foodMenu:     byType(VenueImageType.FOOD_MENU),
            barMenu:      byType(VenueImageType.BAR_MENU),
            beverageMenu: byType(VenueImageType.BEVERAGE_MENU),
            partyPackages: byType(VenueImageType.PARTY_PACKAGES),
        },
        videos:        byType(VenueImageType.VIDEO),
    };
};

// ── Helper: get caller IP ──────────────────────────────────────────────────
const getIp = (req: Request): string =>
    (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim() ||
    req.socket.remoteAddress ||
    'unknown';

// ── Create Venue ──────────────────────────────────────────────────────────
export const createVenue = async (req: Request, res: Response) => {
    try {
        let userId = req.user?.id || '00000000-0000-0000-0000-000000000000';
        const data = req.body;

        // ── Admin can override ownerId ──────────────────────────────────────
        if (req.user?.role === 'admin' && data.ownerId) {
            userId = data.ownerId;
        }

        // ── Helper to parse JSON or return default ───────────────────────────
        const parseJson = (val: any, def: any = []) => {
            if (!val) return def;
            if (typeof val === 'string') {
                try { return JSON.parse(val); } catch (e) {
                    if (Array.isArray(def)) return val.split(',').map((s: string) => s.trim());
                    return def;
                }
            }
            return val;
        };

        // ── Determine initial status from submitted value ────────────────────
        // Only 'pending' and 'approved' are valid on create; anything else defaults to pending.
        const submittedStatus = (data.status || 'pending').toLowerCase();
        const isApprovedDirect = submittedStatus === 'approved';
        const initialStatus = isApprovedDirect ? VenueStatus.LIVE : VenueStatus.PENDING_CONFIRMATION;

        // ── Validation: Display Order Area uniqueness ────────────────────────
        const displayOrder = data.displayOrder ? parseInt(data.displayOrder) : 0;
        if (displayOrder > 0 && data.area) {
            const existingVenue = await Venue.findOne({ where: { area: data.area, displayOrder } });
            if (existingVenue) {
                return res.status(400).json({ success: false, message: `Display Order ${displayOrder} is already in use for the ${data.area} area.` });
            }
        }

        const newVenue = await Venue.create({
            ownerId: userId,
            name: data.name,
            slug: data.name ? data.name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '') : '',
            tagline: data.tagline,
            description: data.description,
            category: data.category as VenueCategory,
            tags: parseJson(data.tags),
            addressLine1: data.addressLine1,
            addressLine2: data.addressLine2,
            area: data.area,
            city: data.city,
            state: data.state,
            postalCode: data.pincode || data.postalCode,
            country: data.country || 'India',
            latitude: data.latitude ? parseFloat(data.latitude) : undefined,
            longitude: data.longitude ? parseFloat(data.longitude) : undefined,
            displayOrder: displayOrder,
            nearestLandmark: data.nearestLandmark,
            directions: data.directions,
            phone: data.phone,
            mobile: data.mobile,
            whatsapp: data.whatsapp,
            email: data.email,
            website: data.website,
            instagram: data.instagram,
            facebook: data.facebook,
            cpName: data.cpName,
            cpDesignation: data.cpDesignation,
            cpMobile: data.cpMobile,
            cpEmail: data.cpEmail,
            altCpName: data.altCpName,
            altCpDesignation: data.altCpDesignation,
            altCpMobile: data.altCpMobile,
            altCpEmail: data.altCpEmail,
            capacity: parseInt(data.standingCapacity || data.seatingCapacity || '100'),
            seatingCapacity: data.seatingCapacity ? parseInt(data.seatingCapacity) : undefined,
            standingCapacity: data.standingCapacity ? parseInt(data.standingCapacity) : undefined,
            openingTime: data.openingTime || undefined,
            closingTime: data.closingTime || undefined,
            daysOpen: parseJson(data.daysOpen, ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']),
            ageLimit: data.ageLimit ? parseInt(data.ageLimit) : 21,
            coverChargeMale: data.coverChargeMale ? parseFloat(data.coverChargeMale) : undefined,
            coverChargeFemale: data.coverChargeFemale ? parseFloat(data.coverChargeFemale) : undefined,
            discountPercentage: data.discountPercentage ? parseFloat(data.discountPercentage) : undefined,
            tableBookingCharges: data.tableBookingCharges ? parseFloat(data.tableBookingCharges) : undefined,
            coupleEntryFee: data.coupleEntryFee ? parseFloat(data.coupleEntryFee) : 0,
            dressCode: data.dressCode,
            cuisineTypes: parseJson(data.cuisineTypes),
            musicTypes: parseJson(data.musicTypes),
            amenities: parseJson(data.amenities, {}),
            panNumber: data.panNumber,
            gstNumber: data.gstNumber,
            fssaiLicense: data.fssaiLicense,
            liquorLicense: data.liquorLicense,
            fireSafetyCert: data.fireSafetyCert,
            tradeLicense: data.tradeLicense,
            bankAccountNumber: data.bankAccountNumber,
            bankIFSC: data.bankIFSC,
            bankName: data.bankName,
            status: initialStatus,
            isActive: isApprovedDirect ? true : (data.isActive === 'true' || data.isActive === true || data.isActive === undefined),
            isVerified: isApprovedDirect ? true : (data.isVerified === 'true' || data.isVerified === true),
            featured: data.isFeatured === 'true' || data.isFeatured === true,
            isPremium: data.isPremium === 'true' || data.isPremium === true,
        } as any);

        // ── Auto-update user role to VENUE_OWNER ──────────────────────────────
        const UserModule = await import('../models/User');
        const User       = UserModule.default;
        const { UserRole } = UserModule;
        const ownerUser  = await User.findByPk(userId);
        if (ownerUser && ownerUser.role !== UserRole.VENUE_OWNER && ownerUser.role !== UserRole.ADMIN) {
            await (ownerUser as any).update({ role: UserRole.VENUE_OWNER });
            console.log(`[createVenue] User ${userId} role updated to ${UserRole.VENUE_OWNER}`);
        }

        // ── Branch: Approved → go Live immediately, no email ────────────────
        if (isApprovedDirect) {
            const now = new Date();
            await newVenue.update({ ownerConfirmedAt: now });

            await VenueComplianceLog.create({
                venueId:    newVenue.id,
                eventType:  ComplianceEventType.VENUE_LIVE,
                actorEmail: req.user?.email || data.cpEmail || data.email,
                ipAddress:  getIp(req),
                metadata: {
                    liveAt:    now.toISOString(),
                    venueName: newVenue.name,
                    reason:    'Admin set status to Approved on creation — venue made Live directly',
                },
            });

            console.log(`[createVenue] Venue ${newVenue.id} set to LIVE directly (approved by admin).`);

        // ── Branch: Pending → generate confirmation token and send email ─────
        } else {
            const tokenExpiryHours = parseInt(process.env.VENUE_CONFIRM_TOKEN_EXPIRY_HOURS || '72');
            const confirmationToken = crypto.randomBytes(32).toString('hex');
            const confirmationTokenExpiresAt = new Date(Date.now() + tokenExpiryHours * 60 * 60 * 1000);
            const termsAcceptedAt = new Date();

            await newVenue.update({ termsAcceptedAt, confirmationToken, confirmationTokenExpiresAt });

            await VenueComplianceLog.create({
                venueId:    newVenue.id,
                eventType:  ComplianceEventType.TERMS_ACCEPTED,
                actorEmail: req.user?.email || data.cpEmail || data.email,
                ipAddress:  getIp(req),
                metadata:   { userId, venueName: newVenue.name, termsAcceptedAt: termsAcceptedAt.toISOString() },
            });

            const serverUrl = process.env.SERVER_URL ||
                `http://${process.env.HOST || 'localhost'}:${process.env.PORT || '5000'}`;
            const confirmUrl    = `${serverUrl}/api/venues/confirm/${confirmationToken}`;
            const recipientEmail = data.cpEmail || data.email || '';
            const recipientName  = data.cpName  || data.name  || 'Venue Owner';

            if (recipientEmail) {
                try {
                    await sendVenueConfirmationEmail(recipientEmail, recipientName, newVenue.name, confirmUrl);
                    await newVenue.update({ ownerEmailSentAt: new Date() });

                    await VenueComplianceLog.create({
                        venueId:    newVenue.id,
                        eventType:  ComplianceEventType.CONFIRMATION_EMAIL_SENT,
                        actorEmail: recipientEmail,
                        ipAddress:  getIp(req),
                        metadata:   { recipientEmail, recipientName, confirmUrl, expiresAt: confirmationTokenExpiresAt.toISOString() },
                    });
                } catch (emailErr: any) {
                    console.error('Venue confirmation email failed (non-fatal):', emailErr.message || emailErr);
                }
            } else {
                console.warn(`[createVenue] No cpEmail or email set for venue ${newVenue.id} — confirmation email skipped`);
            }
        }

        // Handle File Uploads
        const files = req.files as { [fieldname: string]: Express.Multer.File[] };

        if (files) {
            // Move files from 'temp' to actual venue ID directory
            const moveToVenueDir = (file: Express.Multer.File): Express.Multer.File => {
                const normalizedPath = path.normalize(file.path);
                const tempMarker = path.normalize(path.join('venues', 'temp'));

                if (normalizedPath.includes(tempMarker)) {
                    const newDir = path.join(process.cwd(), process.env.UPLOAD_DIR || 'uploads', 'venues', newVenue.id, 'raw');
                    if (!fs.existsSync(newDir)) fs.mkdirSync(newDir, { recursive: true });
                    const newPath = path.join(newDir, file.filename);
                    fs.renameSync(file.path, newPath);
                    file.path = newPath;
                    file.destination = newDir;
                }
                return file;
            };

            // ── Helper: process an image field with 300KB compression ───────────
            const processImageField = async (
                fieldName: string,
                imageType: VenueImageType,
                displayOrderOffset: number = 0
            ) => {
                const fieldFiles = files[fieldName];
                if (!fieldFiles || fieldFiles.length === 0) return;
                for (let i = 0; i < fieldFiles.length; i++) {
                    try {
                        const imgFile = moveToVenueDir(fieldFiles[i]);
                        const compressedPath = await compressImageTo300KB(imgFile.path);
                        const compressedSize = fs.statSync(compressedPath).size;
                        await VenueImage.create({
                            venueId: newVenue.id,
                            filePath: path.relative(process.cwd(), compressedPath),
                            fileSize: compressedSize,
                            mimeType: 'image/webp',
                            imageType,
                            isPrimary: imageType === VenueImageType.COVER,
                            displayOrder: displayOrderOffset + i,
                            uploadedBy: userId,
                        });
                    } catch (imgErr: any) {
                        console.error(`Error processing ${fieldName}[${i}] (${fieldFiles[i].originalname}) in createVenue:`, imgErr.message || imgErr);
                    }
                }
            };

            // Process Cover Image
            await processImageField('coverImage', VenueImageType.COVER, 0);

            // Process Gallery Photos
            await processImageField('photos', VenueImageType.INTERIOR, 1);

            // Process Menus (legacy — backward compat)
            await processImageField('menus', VenueImageType.MENU, 1);

            // Process Food Menus
            await processImageField('foodMenus', VenueImageType.FOOD_MENU, 1);
            await processImageField('barMenus', VenueImageType.BAR_MENU, 2);
            await processImageField('beverageMenus', VenueImageType.BEVERAGE_MENU, 3);
            await processImageField('partyPackages', VenueImageType.PARTY_PACKAGES, 4);

            // Process Videos (no compression — store as-is)
            if (files['videos'] && files['videos'].length > 0) {
                for (let i = 0; i < files['videos'].length; i++) {
                    try {
                        const videoFile = moveToVenueDir(files['videos'][i]);

                        await VenueImage.create({
                            venueId: newVenue.id,
                            filePath: path.relative(process.cwd(), videoFile.path),
                            fileSize: videoFile.size,
                            mimeType: videoFile.mimetype,
                            imageType: VenueImageType.VIDEO,
                            isPrimary: false,
                            displayOrder: i + 1,
                            uploadedBy: userId,
                        });
                    } catch (imgErr: any) {
                        console.error(`Error processing venue video ${i + 1} (${files['videos'][i].originalname}) in createVenue:`, imgErr.message || imgErr);
                    }
                }
            }
        }

        // ── Refetch complete venue to return ─────────────────────────────────
        const completeVenue = await Venue.findByPk(newVenue.id, {
            include: [{ model: VenueImage, as: 'images' }],
        });

        return res.status(201).json({ success: true, venue: completeVenue });
    } catch (error: any) {
        console.error('Error creating venue:', error);
        console.error('Error stack:', error.stack);
        console.error('Error details:', error.errors);
        return res.status(500).json({ success: false, message: 'Server error creating venue', error: error.message });
    }
};

export const updateVenue = async (req: Request, res: Response) => {
    try {
        const { id } = req.params;
        const venue = await Venue.findByPk(id);

        if (!venue) {
            return res.status(404).json({ success: false, message: 'Venue not found' });
        }

        const userId = req.user?.id || '00000000-0000-0000-0000-000000000000';
        const data = req.body;

        // ── Status transition guard ──────────────────────────────────────────
        // Removed to allow admins to freely change the status from the admin panel
        if (data.status && data.status !== venue.status) {
            // Note: Admin can change status freely. 
        }

        const parseJson = (val: any, def: any = []) => {
            if (val === undefined) return undefined;
            if (!val) return def;
            if (typeof val === 'string') {
                try { return JSON.parse(val); } catch (e) {
                    if (Array.isArray(def)) return val.split(',').map(s => s.trim());
                    return def;
                }
            }
            return val;
        };

        const updateData: any = {};
        const fields = [
            'name', 'tagline', 'description', 'category', 'addressLine1', 'addressLine2',
            'area', 'city', 'state', 'country', 'nearestLandmark', 'directions',
            'phone', 'mobile', 'whatsapp', 'email', 'website', 'instagram', 'facebook',
            'cpName', 'cpDesignation', 'cpMobile', 'cpEmail',
            'altCpName', 'altCpDesignation', 'altCpMobile', 'altCpEmail',
            'openingTime', 'closingTime', 'dressCode', 'status',
            'panNumber', 'gstNumber', 'fssaiLicense', 'liquorLicense', 'fireSafetyCert', 'tradeLicense',
            'bankAccountNumber', 'bankIFSC', 'bankName'
        ];

        fields.forEach(f => { 
            if (data[f] !== undefined) {
                if ((f === 'openingTime' || f === 'closingTime') && data[f] === '') {
                    updateData[f] = null;
                } else {
                    updateData[f] = data[f]; 
                }
            } 
        });

        if (data.pincode !== undefined) updateData.postalCode = data.pincode;
        if (data.postalCode !== undefined) updateData.postalCode = data.postalCode;
        if (data.latitude !== undefined && data.latitude !== '') updateData.latitude = parseFloat(data.latitude);
        if (data.longitude !== undefined && data.longitude !== '') updateData.longitude = parseFloat(data.longitude);
        if (data.standingCapacity !== undefined && data.standingCapacity !== '') updateData.standingCapacity = parseInt(data.standingCapacity);
        if (data.seatingCapacity !== undefined && data.seatingCapacity !== '') updateData.seatingCapacity = parseInt(data.seatingCapacity);
        if ((data.standingCapacity !== undefined && data.standingCapacity !== '') || (data.seatingCapacity !== undefined && data.seatingCapacity !== ''))
            updateData.capacity = parseInt(data.standingCapacity || data.seatingCapacity || '100');

        if (data.ageLimit !== undefined && data.ageLimit !== '') updateData.ageLimit = parseInt(data.ageLimit);
        if (data.coverChargeMale !== undefined && data.coverChargeMale !== '') updateData.coverChargeMale = parseFloat(data.coverChargeMale);
        if (data.coverChargeFemale !== undefined && data.coverChargeFemale !== '') updateData.coverChargeFemale = parseFloat(data.coverChargeFemale);
        if (data.discountPercentage !== undefined && data.discountPercentage !== '') updateData.discountPercentage = parseFloat(data.discountPercentage);
        if (data.tableBookingCharges !== undefined && data.tableBookingCharges !== '') updateData.tableBookingCharges = parseFloat(data.tableBookingCharges);
        if (data.coupleEntryFee !== undefined && data.coupleEntryFee !== '') updateData.coupleEntryFee = parseFloat(data.coupleEntryFee);

        if (data.displayOrder !== undefined) {
            const parsedOrder = parseInt(data.displayOrder);
            updateData.displayOrder = isNaN(parsedOrder) ? 0 : parsedOrder;
        }

        // ── Validation: Display Order Area uniqueness ────────────────────────
        const checkArea = updateData.area !== undefined ? updateData.area : venue.area;
        const checkDisplayOrder = updateData.displayOrder !== undefined ? updateData.displayOrder : venue.displayOrder;

        if (checkDisplayOrder > 0 && checkArea) {
            const existingVenue = await Venue.findOne({ 
                where: { 
                    area: checkArea, 
                    displayOrder: checkDisplayOrder,
                    id: { [Op.ne]: venue.id } 
                } 
            });
            if (existingVenue) {
                return res.status(400).json({ success: false, message: `Display Order ${checkDisplayOrder} is already in use for the ${checkArea} area.` });
            }
        }

        if (data.isFeatured !== undefined) updateData.featured = data.isFeatured === 'true' || data.isFeatured === true;
        if (data.isActive !== undefined) updateData.isActive = data.isActive === 'true' || data.isActive === true;
        if (data.isVerified !== undefined) updateData.isVerified = data.isVerified === 'true' || data.isVerified === true;
        if (data.isPremium !== undefined) updateData.isPremium = data.isPremium === 'true' || data.isPremium === true;

        // Force isActive to false if suspended or deactivated
        if (updateData.status === VenueStatus.SUSPENDED || updateData.status === VenueStatus.DEACTIVATED) {
            updateData.isActive = false;
        }

        // ── Log status change if it happened ─────────────────────────────────
        if (updateData.status && updateData.status !== venue.status) {
            await VenueComplianceLog.create({
                venueId: venue.id,
                eventType: ComplianceEventType.STATUS_CHANGED,
                actorEmail: req.user?.email || 'admin@lunara.buzz',
                ipAddress: getIp(req),
                metadata: {
                    oldStatus: venue.status,
                    newStatus: updateData.status,
                    reason: `Admin updated status to ${updateData.status}`,
                },
            });
        }

        const jsonFields = ['tags', 'daysOpen', 'cuisineTypes', 'musicTypes', 'amenities'];
        jsonFields.forEach(f => {
            const parsed = parseJson(data[f], f === 'amenities' ? {} : []);
            if (parsed !== undefined) updateData[f] = parsed;
        });

        if (updateData.name && !updateData.slug) {
            updateData.slug = updateData.name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
        }

        await venue.update(updateData);

        // ── Helper: parse JSON lists of image URLs to keep ───────────────────
        const parseJsonArray = (val: any) => {
            if (!val) return [];
            if (typeof val === 'string') {
                try {
                    const parsed = JSON.parse(val);
                    return Array.isArray(parsed) ? parsed : [];
                } catch (e) {
                    return [];
                }
            }
            return Array.isArray(val) ? val : [];
        };

        const keepPhotos = parseJsonArray(data.keepPhotos);
        const keepVideos = parseJsonArray(data.keepVideos);
        const keepMenus = parseJsonArray(data.keepMenus);
        const keepFoodMenus = parseJsonArray(data.keepFoodMenus);
        const keepBarMenus = parseJsonArray(data.keepBarMenus);
        const keepBeverageMenus = parseJsonArray(data.keepBeverageMenus);
        const keepPartyPackages = parseJsonArray(data.keepPartyPackages);
        const keepCoverImage = data.keepCoverImage === 'true' || data.keepCoverImage === true;

        // ── Helper: clean up database/disk images that are no longer kept ────
        const cleanOldImages = async (imageType: VenueImageType, keepUrls: string[]) => {
            try {
                const existingImages = await VenueImage.findAll({
                    where: { venueId: venue.id, imageType }
                });

                const norm = (p: string) => p.replace(/\\/g, '/').toLowerCase();

                const normalizedKeepPaths = new Set(
                    keepUrls
                        .map(url => {
                            let relPath = url;
                            try {
                                if (url.startsWith('http://') || url.startsWith('https://')) {
                                    relPath = new URL(url).pathname;
                                }
                            } catch (e) {
                                // Fallback if URL parsing fails
                            }
                            if (relPath.startsWith('/')) {
                                relPath = relPath.substring(1);
                            }
                            return norm(relPath);
                        })
                        .filter(Boolean)
                );

                for (const img of existingImages) {
                    const normalizedFilePath = norm(img.filePath);
                    if (!normalizedKeepPaths.has(normalizedFilePath)) {
                        await img.destroy();
                        console.log(`[updateVenue] Deleted image not in keep list: ${img.filePath}`);
                    }
                }

                // Re-index remaining images to ensure sequential display orders
                const remainingImages = await VenueImage.findAll({
                    where: { venueId: venue.id, imageType },
                    order: [['displayOrder', 'ASC'], ['uploadedAt', 'DESC']]
                });
                for (let idx = 0; idx < remainingImages.length; idx++) {
                    await remainingImages[idx].update({ displayOrder: idx + 1 });
                }
            } catch (err: any) {
                console.error(`Error cleaning up images for type ${imageType}:`, err.message || err);
            }
        };

        // Clean up cover image if explicitly removed
        const files = req.files as { [fieldname: string]: Express.Multer.File[] } | undefined;
        const hasNewCover = files && files['coverImage'] && files['coverImage'].length > 0;
        if (!keepCoverImage || hasNewCover) {
            try {
                const existingCover = await VenueImage.findOne({ where: { venueId: venue.id, imageType: VenueImageType.COVER } });
                if (existingCover) {
                    await existingCover.destroy();
                    console.log(`[updateVenue] Deleted existing cover image: ${existingCover.filePath}`);
                }
            } catch (coverErr: any) {
                console.error('Error cleaning up existing cover image:', coverErr.message || coverErr);
            }
        }

        // Clean up other image categories
        await cleanOldImages(VenueImageType.INTERIOR, keepPhotos);
        await cleanOldImages(VenueImageType.VIDEO, keepVideos);
        await cleanOldImages(VenueImageType.MENU, keepMenus);
        await cleanOldImages(VenueImageType.FOOD_MENU, keepFoodMenus);
        await cleanOldImages(VenueImageType.BAR_MENU, keepBarMenus);
        await cleanOldImages(VenueImageType.BEVERAGE_MENU, keepBeverageMenus);
        await cleanOldImages(VenueImageType.PARTY_PACKAGES, keepPartyPackages);

        // Handle File Uploads for Updates
        if (files) {
            // ── Helper: append image files with 300KB compression ──────────────
            const appendImageField = async (fieldName: string, imageType: VenueImageType) => {
                const fieldFiles = files[fieldName];
                if (!fieldFiles || fieldFiles.length === 0) return;
                try {
                    const currentCount = await VenueImage.count({ where: { venueId: venue.id, imageType } });
                    for (let i = 0; i < fieldFiles.length; i++) {
                        const imgFile = fieldFiles[i];
                        const compressedPath = await compressImageTo300KB(imgFile.path);
                        const compressedSize = fs.statSync(compressedPath).size;
                        await VenueImage.create({
                            venueId: venue.id,
                            filePath: path.relative(process.cwd(), compressedPath),
                            fileSize: compressedSize,
                            mimeType: 'image/webp',
                            imageType,
                            isPrimary: false,
                            displayOrder: currentCount + i + 1,
                            uploadedBy: userId,
                        });
                    }
                } catch (imgErr: any) {
                    console.error(`Error updating ${fieldName} in updateVenue:`, imgErr.message || imgErr);
                }
            };

            // Update Cover Image
            if (hasNewCover) {
                try {
                    const coverFile = files['coverImage'][0];
                    const compressedPath = await compressImageTo300KB(coverFile.path);
                    const compressedSize = fs.statSync(compressedPath).size;

                    await VenueImage.create({
                        venueId: venue.id,
                        filePath: path.relative(process.cwd(), compressedPath),
                        fileSize: compressedSize,
                        mimeType: 'image/webp',
                        imageType: VenueImageType.COVER,
                        isPrimary: true,
                        displayOrder: 0,
                        uploadedBy: userId,
                    });
                } catch (imgErr) {
                    console.error('Error updating cover image in updateVenue:', imgErr);
                }
            }

            // Append Gallery Photos
            await appendImageField('photos', VenueImageType.INTERIOR);

            // Append Menus (legacy — backward compat)
            await appendImageField('menus', VenueImageType.MENU);

            // Append Food Menus
            await appendImageField('foodMenus', VenueImageType.FOOD_MENU);
            await appendImageField('barMenus', VenueImageType.BAR_MENU);
            await appendImageField('beverageMenus', VenueImageType.BEVERAGE_MENU);
            await appendImageField('partyPackages', VenueImageType.PARTY_PACKAGES);

            // Append Videos (no compression)
            if (files['videos'] && files['videos'].length > 0) {
                try {
                    const currentVideosCount = await VenueImage.count({ where: { venueId: venue.id, imageType: VenueImageType.VIDEO } });

                    for (let i = 0; i < files['videos'].length; i++) {
                        const videoFile = files['videos'][i];

                        await VenueImage.create({
                            venueId: venue.id,
                            filePath: path.relative(process.cwd(), videoFile.path),
                            fileSize: videoFile.size,
                            mimeType: videoFile.mimetype,
                            imageType: VenueImageType.VIDEO,
                            isPrimary: false,
                            displayOrder: currentVideosCount + i + 1,
                            uploadedBy: userId,
                        });
                    }
                } catch (imgErr: any) {
                    console.error(`Error updating venue videos in updateVenue:`, imgErr.message || imgErr);
                }
            }
        }

        // Reload venue with images to return complete data
        const completeVenue = await Venue.findByPk(venue.id, {
            include: [{ model: VenueImage, as: 'images' }]
        });

        return res.status(200).json({ success: true, venue: completeVenue });
    } catch (error) {
        console.error('Error updating venue:', error);
        return res.status(500).json({ success: false, message: 'Server error updating venue' });
    }
};

export const getVenues = async (req: Request, res: Response) => {
    try {
        const { city, status, category, featured, isActive } = req.query;

        // Build dynamic where clause
        const where: any = {};

        if (city) {
            where.city = { [Op.iLike]: `%${(city as string).trim()}%` };
        }
        if (status) {
            where.status = status;
        }
        if (category) {
            where.category = category;
        }
        if (featured !== undefined) {
            where.featured = featured === 'true';
        }
        if (isActive !== undefined) {
            where.isActive = isActive === 'true';
        }

        const venues = await Venue.findAll({
            where,
            include: [{ model: VenueImage, as: 'images' }],
            order: [['displayOrder', 'ASC'], ['createdAt', 'DESC']],
        });

        // Reshape each venue: attach structured media sections
        const venuesWithMedia = venues.map(venue => {
            const plain = venue.toJSON() as any;
            const images: VenueImage[] = (venue as any).images ?? [];
            const { coverImage, gallery, menu, videos } = buildVenueMediaSections(images);
            delete plain.images; // remove flat array
            return { ...plain, coverImage, gallery, menu, videos };
        });

        return res.status(200).json({
            success: true,
            total:   venuesWithMedia.length,
            filters: { city: city ?? null, status: status ?? null, category: category ?? null },
            venues:  venuesWithMedia,
        });
    } catch (error) {
        console.error('Error fetching venues:', error);
        return res.status(500).json({ success: false, message: 'Error fetching venues' });
    }
};

export const getVenueById = async (req: Request, res: Response) => {
    try {
        const { id } = req.params;
        const venue = await Venue.findByPk(id, {
            include: [{ model: VenueImage, as: 'images' }],
        });
        if (!venue) return res.status(404).json({ success: false, message: 'Venue not found' });

        const images: VenueImage[] = (venue as any).images ?? [];
        const { coverImage, gallery, menu, videos } = buildVenueMediaSections(images);

        const plain = venue.toJSON() as any;
        delete plain.images; // remove flat array

        return res.status(200).json({
            success: true,
            venue: { ...plain, coverImage, gallery, menu, videos },
        });
    } catch (error) {
        console.error('Error fetching venue:', error);
        return res.status(500).json({ success: false, message: 'Error fetching venue' });
    }
};

export const deleteVenue = async (req: Request, res: Response) => {
    try {
        const { id } = req.params;
        const venue = await Venue.findByPk(id);

        if (!venue) {
            return res.status(404).json({ success: false, message: 'Venue not found' });
        }

        // Destroy all VenueImage records — the model's beforeDestroy hook
        // automatically calls image.deleteFile() for each one.
        const images = await VenueImage.findAll({ where: { venueId: id } });
        for (const image of images) {
            await image.destroy();
        }

        // Remove the now-empty venue upload directory (best-effort)
        const venueDir = path.join(process.cwd(), process.env.UPLOAD_DIR || 'uploads', 'venues', id);
        try {
            if (fs.existsSync(venueDir)) fs.rmSync(venueDir, { recursive: true, force: true });
        } catch (dirErr) {
            console.error(`Failed to remove venue directory ${venueDir}:`, dirErr);
        }

        await venue.destroy();
        return res.status(200).json({ success: true, message: 'Venue deleted successfully' });
    } catch (error) {
        console.error('Error deleting venue:', error);
        return res.status(500).json({ success: false, message: 'Server error deleting venue' });
    }
};


// ── Public: Confirm venue via email token ─────────────────────────────────
export const confirmVenue = async (req: Request, res: Response) => {
    const renderPage = (title: string, icon: string, heading: string, body: string, color: string) => `
<!DOCTYPE html><html lang="en"><head>
<meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>${title} — Lunara</title>
<style>
  *{box-sizing:border-box;margin:0;padding:0}
  body{font-family:'Segoe UI',Arial,sans-serif;background:#0f0f14;display:flex;align-items:center;justify-content:center;min-height:100vh;padding:24px}
  .card{background:#1a1a2e;border:1px solid ${color}44;border-radius:20px;max-width:480px;width:100%;padding:48px 40px;text-align:center;box-shadow:0 24px 80px rgba(0,0,0,0.5)}
  .icon{font-size:64px;margin-bottom:20px}
  h1{color:${color};font-size:24px;margin-bottom:12px}
  p{color:#aaa;font-size:15px;line-height:1.7;margin-bottom:10px}
  .badge{display:inline-block;background:${color}22;border:1px solid ${color}55;color:${color};border-radius:8px;padding:6px 16px;font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:0.05em;margin-top:24px}
  .footer{margin-top:32px;color:#555;font-size:12px}
  .footer a{color:#7c3aed;text-decoration:none}
</style></head><body>
<div class="card">
  <div class="icon">${icon}</div>
  <h1>${heading}</h1>
  ${body}
  <div class="badge">${title}</div>
  <div class="footer"><p>Need help? <a href="mailto:support@lunara.com">support@lunara.com</a></p></div>
</div></body></html>`;

    try {
        const { token } = req.params;
        if (!token || token.length !== 64) {
            return res.status(400).send(renderPage(
                'Invalid Link', '🔗', 'Invalid Confirmation Link',
                '<p>The confirmation link is malformed. Please check your email and try again, or contact support.</p>',
                '#ef4444'
            ));
        }

        const venue = await Venue.findOne({ where: { confirmationToken: token } });

        if (!venue) {
            return res.status(404).send(renderPage(
                'Link Not Found', '🔍', 'Link Not Found or Already Used',
                '<p>This confirmation link has already been used or does not exist.</p><p>Your venue may already be live — check with the Lunara team.</p>',
                '#f59e0b'
            ));
        }

        // Check expiry
        if (venue.confirmationTokenExpiresAt && new Date() > venue.confirmationTokenExpiresAt) {
            return res.status(410).send(renderPage(
                'Link Expired', '⏰', 'Confirmation Link Expired',
                '<p>This confirmation link expired after 72 hours and is no longer valid.</p><p>Please contact <a href="mailto:support@lunara.com" style="color:#7c3aed">support@lunara.com</a> to request a new link.</p>',
                '#f59e0b'
            ));
        }

        const now = new Date();

        // ── Idempotency: if already live, just show the success page ─────────
        if (venue.status === VenueStatus.LIVE) {
            return res.status(200).send(renderPage(
                'Venue Confirmed', '🎉', `"${venue.name}" is already LIVE!`,
                `<p>Your venue has already been confirmed and is <strong style="color:#22c55e">live on Lunara</strong>.</p>
                 <p>Users can now discover, explore, and book your venue through the Lunara app.</p>
                 <p style="margin-top:16px;color:#666;font-size:13px">Confirmed on: ${venue.ownerConfirmedAt
                    ? new Date(venue.ownerConfirmedAt).toLocaleString('en-IN', { timeZone: 'Asia/Kolkata' })
                    : now.toLocaleString('en-IN', { timeZone: 'Asia/Kolkata' })} IST</p>`,
                '#22c55e'
            ));
        }

        // Mark venue as approved + live
        // NOTE: use null (not undefined) so Sequelize actually sets the DB column to NULL
        await venue.update({
            status:                    VenueStatus.LIVE,
            isActive:                  true,
            isVerified:                true,
            ownerConfirmedAt:          now,
            confirmationToken:         null as any,   // consume / invalidate the token
            confirmationTokenExpiresAt: null as any,
        });

        const ip = getIp(req);

        // Log: owner_confirmed
        await VenueComplianceLog.create({
            venueId:    venue.id,
            eventType:  ComplianceEventType.OWNER_CONFIRMED,
            actorEmail: venue.cpEmail || venue.email || undefined,
            ipAddress:  ip,
            metadata: {
                confirmedAt: now.toISOString(),
                userAgent:   req.headers['user-agent'],
                venueName:   venue.name,
            },
        });

        // Log: venue_live
        await VenueComplianceLog.create({
            venueId:    venue.id,
            eventType:  ComplianceEventType.VENUE_LIVE,
            actorEmail: venue.cpEmail || venue.email || undefined,
            ipAddress:  ip,
            metadata: { liveAt: now.toISOString(), venueName: venue.name },
        });

        return res.status(200).send(renderPage(
            'Venue Confirmed', '🎉', `"${venue.name}" is now LIVE!`,
            `<p>Congratulations! Your venue has been confirmed and is now <strong style="color:#22c55e">live on Lunara</strong>.</p>
             <p>Users can now discover, explore, and book your venue through the Lunara app.</p>
             <p style="margin-top:16px;color:#666;font-size:13px">Confirmed on: ${now.toLocaleString('en-IN', { timeZone: 'Asia/Kolkata' })} IST</p>`,
            '#22c55e'
        ));
    } catch (error) {
        console.error('Error confirming venue:', error);
        return res.status(500).send(renderPage(
            'Server Error', '⚠️', 'Something Went Wrong',
            '<p>An unexpected error occurred. Please try again later or contact support.</p>',
            '#ef4444'
        ));
    }
};

export default {
    createVenue,
    updateVenue,
    getVenues,
    getVenueById,
    deleteVenue,
    confirmVenue,
};
