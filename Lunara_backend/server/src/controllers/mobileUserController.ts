import { Request, Response } from 'express';
import path from 'path';
import fs from 'fs';
import crypto from 'crypto';
import sharp from 'sharp';
import { UserProfile, UserPreference, UserPhoto, UserMatch, PartyPlan, GroupParty, StrangersMeetRequest, Booking } from '../models';
import User, { UserRole } from '../models/User';
import sequelize from '../config/database';
import DeletedAccount from '../models/DeletedAccount';
import UserSubscription, { SubscriptionStatus } from '../models/UserSubscription';
import SubscriptionPackage from '../models/SubscriptionPackage';
import bcrypt from 'bcryptjs';

import { logger } from '../config/logger';
import { Op } from 'sequelize';
import { getUserGalleryDir } from '../middleware/upload';
import SocialConnection, { ConnectionStatus } from '../models/SocialConnection';
import UserPenalty from '../models/UserPenalty';

// ─── Image compression constants ──────────────────────────────────────────────
const PHOTO_MAX_WIDTH = 1080;   // px
const PHOTO_MAX_HEIGHT = 1080;   // px
const PHOTO_QUALITY = 80;     // JPEG quality (0-100)

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/user/photos
// ─────────────────────────────────────────────────────────────────────────────
export const uploadPhotos = async (req: Request, res: Response): Promise<Response> => {
    try {
        const userId = req.body.userId || req.user?.id;
        if (!userId) {
            return res.status(401).json({ success: false, message: 'Unauthorized: userId is required in body' });
        }

        const files = req.files as Express.Multer.File[];

        if (!files || files.length < 1) {
            return res.status(400).json({ success: false, message: 'Please upload at least 1 photo' });
        }

        // Validate that each uploaded file is not more than 500KB
        for (const file of files) {
            if (file.size > 500 * 1024) {
                // Clean up all temp files created by multer for this request
                for (const f of files) {
                    if (f.path && fs.existsSync(f.path)) {
                        try { fs.unlinkSync(f.path); } catch {}
                    }
                }
                return res.status(400).json({
                    success: false,
                    message: `Profile picture "${file.originalname}" size should not be more than 500KB.`
                });
            }
        }

        const galleryDir = getUserGalleryDir(userId);
        const createdPhotos = [];

        // Check if user already has a primary photo
        const hasPrimary = await UserPhoto.findOne({ where: { userId, isPrimary: true } });
        
        // Decide if the first uploaded file in this request should be primary
        // It should be primary if:
        // 1. the client explicitly requested isPrimary (req.body.isPrimary === 'true')
        // 2. OR the user does not have any primary photo yet
        const makePrimary = (req.body.isPrimary === 'true') || !hasPrimary;

        if (makePrimary) {
            // Remove primary flag from all existing user photos
            await UserPhoto.update(
                { isPrimary: false },
                { where: { userId } }
            );
        }

        for (let i = 0; i < files.length; i++) {
            const file = files[i];

            const fileBuffer = file.buffer || fs.readFileSync(file.path);

            // ── Compress with sharp ──────────────────────────────────────────
            const randomHex = crypto.randomBytes(8).toString('hex');
            const filename = `${Date.now()}_${randomHex}.jpg`;
            const absolutePath = path.join(galleryDir, filename);

            const compressedBuffer = await sharp(fileBuffer)
                .rotate() // Auto-rotates image based on EXIF orientation data
                .resize({
                    width: PHOTO_MAX_WIDTH,
                    height: PHOTO_MAX_HEIGHT,
                    fit: 'inside',          // preserve aspect ratio, never upscale beyond box
                    withoutEnlargement: true,  // skip resize if image is already smaller
                })
                .jpeg({ quality: PHOTO_QUALITY, progressive: true })
                .toBuffer();

            fs.writeFileSync(absolutePath, compressedBuffer);

            // Store relative path (forward-slash, no leading slash) in DB
            const uploadsBase = process.env.UPLOAD_DIR || 'uploads';
            const relativePath = path
                .join(uploadsBase, 'users', userId, 'gallery', filename)
                .replace(/\\/g, '/');

            // Upload compressed image to Azure Blob Storage if configured
            if (process.env.AZURE_STORAGE_CONNECTION_STRING) {
                try {
                    const { BlobServiceClient } = require('@azure/storage-blob');
                    const blobServiceClient = BlobServiceClient.fromConnectionString(process.env.AZURE_STORAGE_CONNECTION_STRING);
                    const containerName = process.env.AZURE_STORAGE_CONTAINER_NAME || 'uploads';
                    const containerClient = blobServiceClient.getContainerClient(containerName);
                    
                    const blobName = relativePath.startsWith('uploads/') 
                        ? relativePath.substring(8) 
                        : relativePath;

                    const blockBlobClient = containerClient.getBlockBlobClient(blobName);
                    await blockBlobClient.upload(compressedBuffer, compressedBuffer.length, {
                        blobHTTPHeaders: { blobContentType: 'image/jpeg' }
                    });
                    logger.info(`[Azure Blob] Successfully uploaded user photo ${blobName} to container ${containerName}`);
                } catch (azureErr) {
                    logger.error('[Azure Blob] Error uploading user photo to Azure:', azureErr);
                }
            }

            const photoIsPrimary = makePrimary && (i === 0);

            const photo = await UserPhoto.create({
                userId,
                filePath: relativePath,
                fileSize: compressedBuffer.length,   // compressed size, not original
                mimeType: 'image/jpeg',
                isPrimary: photoIsPrimary,
                displayOrder: i,
            });

            if (photoIsPrimary) {
                await User.update(
                    { profileImageUrl: '/' + relativePath.replace(/\\/g, '/') },
                    { where: { id: userId } }
                );
            }

            if (file.path && fs.existsSync(file.path)) {
                fs.unlinkSync(file.path);
            }

            createdPhotos.push(photo);
        }

        return res.status(201).json({
            success: true,
            message: 'Photos uploaded successfully',
            data: {
                photos: createdPhotos.map(p => ({
                    id: p.id,
                    url: p.getUrl(),
                    isPrimary: p.isPrimary,
                    displayOrder: p.displayOrder,
                    sizeKb: Math.round(p.fileSize / 1024),  // handy for debugging
                }))
            }
        });
    } catch (error: any) {
        logger.error('[MobileUser] Error uploading photos:', error);
        return res.status(500).json({ success: false, message: 'Failed to upload photos' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// PUT /api/mobile/user/profile-setup
// ─────────────────────────────────────────────────────────────────────────────
interface ProfileSetupBody {
    // Step 2: Bio, Intent & Interests
    bio?: string;
    lookingFor?: string[];
    nightlifePreference?: string[];
    interests?: string[];
    // Step 3: Music & Budget
    musicPreference?: string[];
    smokingPreference?: string;
    drinkPreference?: string[];
    occupation?: string;
    education?: string;
    budgetRange?: string;
    // Step 4: Privacy Settings
    preferredGenders?: string[];
    minAgePreference?: number;
    maxAgePreference?: number;
    showMeInMatching?: boolean;
    matchDistanceKm?: number;
    bookingAlertsEnabled?: boolean;
}

export const completeProfileSetup = async (req: Request, res: Response): Promise<Response> => {
    try {
        const userId = req.body.userId || req.user?.id;
        if (!userId) {
            return res.status(401).json({ success: false, message: 'Unauthorized: userId is required in body' });
        }

        const data = req.body as ProfileSetupBody;

        // Parallel update of Profile and Preferences
        await Promise.all([
            UserProfile.update(
                {
                    bio: data.bio,
                    lookingFor: data.lookingFor,
                    nightlifePreference: data.nightlifePreference,
                    interests: data.interests,
                    occupation: data.occupation,
                    education: data.education,
                },
                { where: { userId } }
            ),
            UserPreference.update(
                {
                    musicPreference: data.musicPreference,
                    smokingPreference: data.smokingPreference,
                    drinkPreference: data.drinkPreference,
                    budgetRange: data.budgetRange,
                    preferredGenders: data.preferredGenders,
                    minAgePreference: data.minAgePreference,
                    maxAgePreference: data.maxAgePreference,
                    showMeInMatching: data.showMeInMatching,
                    matchDistanceKm: data.matchDistanceKm,
                    bookingAlertsEnabled: data.bookingAlertsEnabled,
                },
                { where: { userId } }
            )
        ]);

        // Fetch updated profile
        const updatedProfile = await UserProfile.findOne({ where: { userId } });
        const updatedPreferences = await UserPreference.findOne({ where: { userId } });

        return res.status(200).json({
            success: true,
            message: 'Profile setup completed successfully',
            data: {
                profile: updatedProfile,
                preferences: updatedPreferences
            }
        });
    } catch (error: any) {
        logger.error('[MobileUser] Error in profile setup:', error);
        return res.status(500).json({ success: false, message: 'Failed to save profile details' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/user/me
// Returns the authenticated user's name and profile photo.
// ─────────────────────────────────────────────────────────────────────────────
export const getMyProfile = async (req: Request, res: Response): Promise<Response> => {
    try {
        let rawQueryId = req.query.userId as string;
        if (rawQueryId === 'undefined' || rawQueryId === 'null' || !rawQueryId?.trim()) {
            rawQueryId = '';
        }
        const userId = rawQueryId || req.user?.id;
        if (!userId) {
            return res.status(401).json({ success: false, message: 'Unauthorized: userId query param is required' });
        }

        // Fetch user base info — include all relevant fields for a complete profile response
        const user = await User.findByPk(userId, {
            attributes: [
                'id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl',
                'role', 'isVerified', 'isActive', 'mfaEnabled',
                'createdAt', 'updatedAt', 'lastLoginAt', 'dateOfBirth',
            ],
        });

        if (!user) {
            return res.status(404).json({ success: false, message: 'User not found' });
        }

        // Fetch extended profile (all fields)
        const profile = await UserProfile.findOne({ where: { userId } });

        // Fetch user preferences (all fields)
        const preferences = await UserPreference.findOne({ where: { userId } });

        // Fetch primary/best profile photo
        // Priority: 1) isPrimary=true  2) lowest displayOrder  3) most recent uploadedAt
        const photoRecord = await UserPhoto.findOne({
            where: { userId },
            order: [
                ['isPrimary', 'DESC'],
                ['displayOrder', 'ASC'],
                ['uploadedAt', 'DESC'],
            ],
            attributes: ['id', 'filePath', 'isPrimary', 'displayOrder', 'uploadedAt'],
        });

        // Fetch ALL gallery photos ordered for display
        const allPhotos = await UserPhoto.findAll({
            where: { userId },
            order: [
                ['isPrimary', 'DESC'],
                ['displayOrder', 'ASC'],
                ['uploadedAt', 'DESC'],
            ],
            attributes: ['id', 'filePath', 'fileSize', 'mimeType', 'isPrimary', 'displayOrder', 'uploadedAt'],
        });

        // Build primary profile photo URL
        let profilePhotoUrl: string | null = null;
        let profilePhotoPath: string | null = null;

        if (photoRecord) {
            profilePhotoPath = photoRecord.filePath;
            profilePhotoUrl = '/' + photoRecord.filePath.replace(/\\/g, '/');
        } else if (user.profileImageUrl) {
            profilePhotoUrl = user.profileImageUrl;
        }

        // Compute age from dateOfBirth
        const age = (user as any).dateOfBirth
            ? Math.floor(
                (Date.now() - new Date((user as any).dateOfBirth).getTime()) /
                (365.25 * 24 * 60 * 60 * 1000)
            )
            : null;

        // Map gallery photos to URL-ready objects
        const photos = allPhotos.map(p => ({
            id: p.id,
            url: '/' + p.filePath.replace(/\\/g, '/'),
            filePath: p.filePath,
            fileSize: p.fileSize,
            mimeType: p.mimeType,
            isPrimary: p.isPrimary,
            displayOrder: p.displayOrder,
            uploadedAt: p.uploadedAt,
        }));

        // Fetch actual superLikesCount and plansCount
        const superLikesCount = await UserMatch.count({
            where: {
                user2Id: userId,
                matchReason: 'superlike',
                status: { [Op.in]: ['pending', 'connected'] }
            }
        });

        const plansCount = await PartyPlan.count({
            where: {
                userId,
                status: 'active'
            }
        });

        const bookingsCount = await Booking.count({
            where: { userId }
        });

        const matchesCount = await UserMatch.count({
            where: {
                [Op.or]: [
                    { user1Id: userId, status: 'connected' },
                    { user2Id: userId, status: 'connected' }
                ]
            }
        });

        const pointsCount = 1000 + (bookingsCount * 250) + (matchesCount * 50);

        // Fetch active subscription tier for golden ring / badge rendering
        const activeSub = await UserSubscription.findOne({
            where: {
                userId,
                status: SubscriptionStatus.ACTIVE,
                endDate: { [Op.gt]: new Date() },
            },
            include: [{ model: SubscriptionPackage, as: 'package', attributes: ['tier'] }],
            order: [['createdAt', 'DESC']],
        });
        const subscriptionTier: string = (activeSub as any)?.package?.tier ?? 'FREE';

        return res.status(200).json({
            success: true,
            data: {
                // ── Core user fields ─────────────────────────────────────────
                id: user.id,
                superLikesCount,
                plansCount,
                subscriptionTier,
                bookingsCount,
                matchesCount,
                pointsCount,
                firstName: user.firstName,
                lastName: user.lastName,
                fullName: `${user.firstName} ${user.lastName}`,
                email: user.email,
                phone: user.phone,
                role: user.role,
                isVerified: user.isVerified,
                isActive: user.isActive,
                mfaEnabled: user.mfaEnabled,
                dateOfBirth: (user as any).dateOfBirth ?? null,
                age,
                createdAt: user.createdAt,
                updatedAt: user.updatedAt,
                lastLoginAt: (user as any).lastLoginAt ?? null,

                // ── Profile photo (primary / best) ────────────────────────────
                profilePhotoUrl,
                profilePhotoPath,
                photoSource: photoRecord
                    ? (photoRecord.isPrimary ? 'primary' : 'latest')
                    : (user.profileImageUrl ? 'profileImageUrl' : 'none'),

                // ── All gallery photos ────────────────────────────────────────
                photos,

                // ── Extended profile ──────────────────────────────────────────
                profile: profile ? {
                    id: profile.id,
                    displayName: profile.displayName ?? null,
                    bio: profile.bio ?? null,
                    gender: profile.gender ?? null,
                    city: profile.city ?? null,
                    occupation: profile.occupation ?? null,
                    company: profile.company ?? null,
                    education: profile.education ?? null,
                    relationshipStatus: profile.relationshipStatus ?? null,
                    lookingFor: profile.lookingFor ?? [],
                    nightlifePreference: profile.nightlifePreference ?? [],
                    interests: profile.interests ?? [],
                    instagramHandle: profile.instagramHandle ?? null,
                    spotifyProfile: profile.spotifyProfile ?? null,
                    profileCompletionPct: profile.getCompletionPercentage(),
                    isProfileComplete: profile.isProfileComplete(),
                    createdAt: profile.createdAt,
                    updatedAt: profile.updatedAt,
                } : null,

                // ── Preferences ───────────────────────────────────────────────
                preferences: preferences ? {
                    id: preferences.id,
                    preferredVenues: preferences.preferredVenues ?? [],
                    preferredCrowdSize: preferences.preferredCrowdSize ?? null,
                    musicPreference: preferences.musicPreference ?? [],
                    drinkPreference: preferences.drinkPreference ?? [],
                    smokingPreference: preferences.smokingPreference ?? null,
                    preferredGenders: preferences.preferredGenders ?? [],
                    minAgePreference: preferences.minAgePreference ?? null,
                    maxAgePreference: preferences.maxAgePreference ?? null,
                    budgetRange: preferences.budgetRange ?? null,
                    partyTimePreference: preferences.partyTimePreference ?? null,
                    groupSizePreference: preferences.groupSizePreference ?? null,
                    matchDistanceKm: preferences.matchDistanceKm,
                    showMeInMatching: preferences.showMeInMatching,
                    bookingAlertsEnabled: preferences.bookingAlertsEnabled,
                    isConfigured: preferences.isConfigured(),
                    createdAt: preferences.createdAt,
                    updatedAt: preferences.updatedAt,
                } : null,
            },
        });
    } catch (error: any) {
        logger.error('[MobileUser] Error fetching profile:', error);
        return res.status(500).json({ success: false, message: 'Failed to retrieve profile' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/user/customers
// Returns all users with role = customer, with full profile data.
// Query params:
//   page     - page number (default: 1)
//   limit    - results per page (default: 20, max: 100)
//   search   - filter by name, email, or phone
//   city     - filter by profile city
// ─────────────────────────────────────────────────────────────────────────────
export const getAllCustomers = async (req: Request, res: Response): Promise<Response> => {
    try {
        const page = Math.max(1, parseInt(req.query.page as string) || 1);
        const limit = Math.min(100, parseInt(req.query.limit as string) || 20);
        const offset = (page - 1) * limit;
        const search = (req.query.search as string)?.trim();
        const city = (req.query.city as string)?.trim();

        const currentUserId = req.user?.id || (req.query.currentUserId as string) || (req.query.userId as string);

        // Build User-level where clause
        const userWhere: any = { role: UserRole.CUSTOMER, isActive: true };

        const excludeUserIds: string[] = [];
        if (currentUserId) {
            excludeUserIds.push(currentUserId);
            const blocks = await SocialConnection.findAll({
                where: {
                    status: ConnectionStatus.BLOCKED,
                    [Op.or]: [
                        { requesterId: currentUserId },
                        { receiverId: currentUserId }
                    ]
                }
            });
            blocks.forEach(b => {
                if (b.requesterId === currentUserId) {
                    excludeUserIds.push(b.receiverId);
                } else {
                    excludeUserIds.push(b.requesterId);
                }
            });
        }

        if (excludeUserIds.length > 0) {
            userWhere.id = { [Op.notIn]: excludeUserIds };
        }
        if (search) {
            userWhere[Op.or] = [
                { firstName: { [Op.iLike]: `%${search}%` } },
                { lastName: { [Op.iLike]: `%${search}%` } },
                { email: { [Op.iLike]: `%${search}%` } },
                { phone: { [Op.iLike]: `%${search}%` } },
            ];
        }

        // Exclude hidden profiles, but allow those without preference records or with true
        const prefConditions = {
            [Op.or]: [
                { '$preferences.show_me_in_matching$': { [Op.ne]: false } },
                { '$preferences.id$': null }
            ]
        };
        if (userWhere[Op.and]) {
            userWhere[Op.and].push(prefConditions);
        } else {
            userWhere[Op.and] = [prefConditions];
        }

        // Build Profile-level where clause (for city filter)
        const profileWhere: any = {};
        if (city) profileWhere.city = { [Op.iLike]: `%${city}%` };

        const { count, rows } = await User.findAndCountAll({
            where: userWhere,
            attributes: [
                'id', 'firstName', 'lastName', 'email', 'phone',
                'dateOfBirth', 'profileImageUrl', 'role',
                'isVerified', 'isActive', 'createdAt', 'lastLoginAt',
            ],
            include: [
                {
                    model: UserProfile,
                    as: 'profile',
                    attributes: [
                        'displayName', 'bio', 'gender', 'city',
                        'occupation', 'education', 'lookingFor',
                        'instagramHandle', 'spotifyProfile',
                        'relationshipStatus', 'company',
                    ],
                    where: Object.keys(profileWhere).length ? profileWhere : undefined,
                    required: Object.keys(profileWhere).length > 0, // INNER JOIN only if city filter active
                },
                {
                    model: UserPreference,
                    as: 'preferences',
                    attributes: [
                        'musicPreference', 'drinkPreference', 'smokingPreference',
                        'budgetRange', 'preferredGenders',
                        'minAgePreference', 'maxAgePreference',
                        'showMeInMatching', 'matchDistanceKm', 'bookingAlertsEnabled',
                    ],
                    required: false,
                },
                {
                    model: UserPhoto,
                    as: 'photos',
                    attributes: ['id', 'filePath', 'isPrimary', 'displayOrder'],
                    required: false,
                    where: { isPrimary: true },   // Only fetch primary photo for list
                },
            ],
            order: [['createdAt', 'DESC']],
            limit,
            offset,
            distinct: true,   // Needed for correct count with includes
            subQuery: false,
        });

        const totalPages = Math.ceil(count / limit);

        const userIds = rows.map(u => u.id);
        const superLikesMap: Record<string, number> = {};
        const plansMap: Record<string, number> = {};

        if (userIds.length > 0) {
            const superLikesCounts = await UserMatch.findAll({
                attributes: [
                    'user2Id',
                    [sequelize.fn('COUNT', sequelize.col('id')), 'count']
                ],
                where: {
                    user2Id: { [Op.in]: userIds },
                    matchReason: 'superlike',
                    status: { [Op.in]: ['pending', 'connected'] }
                },
                group: ['user2Id']
            });

            const plansCounts = await PartyPlan.findAll({
                attributes: [
                    'userId',
                    [sequelize.fn('COUNT', sequelize.col('id')), 'count']
                ],
                where: {
                    userId: { [Op.in]: userIds },
                    status: 'active'
                },
                group: ['userId']
            });

            const groupPartyCounts = await GroupParty.findAll({
                attributes: [
                    'userId',
                    [sequelize.fn('COUNT', sequelize.col('id')), 'count']
                ],
                where: {
                    userId: { [Op.in]: userIds }
                },
                group: ['userId']
            });

            const strangersMeetCounts = await StrangersMeetRequest.findAll({
                attributes: [
                    'userId',
                    [sequelize.fn('COUNT', sequelize.col('id')), 'count']
                ],
                where: {
                    userId: { [Op.in]: userIds }
                },
                group: ['userId']
            });

            superLikesCounts.forEach((c: any) => {
                const u2Id = c.getDataValue('user2Id');
                superLikesMap[u2Id] = parseInt(c.getDataValue('count')) || 0;
            });

            plansCounts.forEach((c: any) => {
                const uId = c.getDataValue('userId');
                plansMap[uId] = (plansMap[uId] || 0) + (parseInt(c.getDataValue('count')) || 0);
            });

            groupPartyCounts.forEach((c: any) => {
                const uId = c.getDataValue('userId');
                plansMap[uId] = (plansMap[uId] || 0) + (parseInt(c.getDataValue('count')) || 0);
            });

            strangersMeetCounts.forEach((c: any) => {
                const uId = c.getDataValue('userId');
                plansMap[uId] = (plansMap[uId] || 0) + (parseInt(c.getDataValue('count')) || 0);
            });
        }

        const data = rows.map(user => {
            const u = user as any;
            const age = user.dateOfBirth
                ? Math.floor((Date.now() - new Date(user.dateOfBirth).getTime()) / (365.25 * 24 * 60 * 60 * 1000))
                : null;

            const photo = u.photos?.[0];
            const photoUrl = photo
                ? '/' + photo.filePath.replace(/\\/g, '/')
                : (user.profileImageUrl ?? null);

            return {
                id: user.id,
                firstName: user.firstName,
                lastName: user.lastName,
                fullName: `${user.firstName} ${user.lastName}`.trim(),
                email: user.email,
                phone: user.phone,
                age,
                dateOfBirth: user.dateOfBirth,
                role: user.role,
                isVerified: user.isVerified,
                isActive: user.isActive,
                profilePhotoUrl: photoUrl,
                createdAt: user.createdAt,
                lastLoginAt: (user as any).lastLoginAt ?? null,
                profile: u.profile ?? null,
                preferences: u.preferences ?? null,
                superLikesCount: superLikesMap[user.id] || 0,
                plansCount: plansMap[user.id] || 0,
                subscriptionTier: 'FREE', // Individual fetch avoided in list; resolved per user in profile detail
            };
        });

        return res.status(200).json({
            success: true,
            total: count,
            page,
            limit,
            totalPages,
            data,
        });
    } catch (error: any) {
        logger.error('[MobileUser] Error fetching customers:', error);
        return res.status(500).json({ success: false, message: 'Failed to retrieve customer list' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/user/:id/status
// Returns the online status and last active timestamp for a specific user
// ─────────────────────────────────────────────────────────────────────────────
export const getUserStatus = async (req: Request, res: Response): Promise<Response> => {
    try {
        const { id } = req.params;
        const user = await User.findByPk(id, {
            attributes: ['id', 'isOnline', 'lastActiveAt'],
        });

        if (!user) {
            return res.status(404).json({ success: false, message: 'User not found' });
        }

        return res.status(200).json({
            success: true,
            data: {
                id: user.id,
                isOnline: user.isOnline,
                lastActiveAt: (user as any).lastActiveAt ?? null,
            },
        });
    } catch (error: any) {
        logger.error('[MobileUser] Error fetching user status:', error);
        return res.status(500).json({ success: false, message: 'Failed to retrieve user status' });
    }
};


// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/user/fcm-token
// Save the FCM device token so the backend can send push notifications.
// Body: { userId, token, platform }
// ─────────────────────────────────────────────────────────────────────────────
export const registerFcmToken = async (req: Request, res: Response): Promise<Response> => {
    try {
        const { userId, token, platform } = req.body;

        if (!userId || !token) {
            return res.status(400).json({ success: false, message: 'userId and token are required' });
        }

        const user = await User.findByPk(userId);
        if (!user) {
            return res.status(404).json({ success: false, message: 'User not found' });
        }

        await (user as any).update({ fcmToken: token });

        logger.info(`[FCM] Token registered for user ${userId} (platform: ${platform ?? 'unknown'})`);
        return res.status(200).json({ success: true, message: 'FCM token registered successfully' });
    } catch (error: any) {
        logger.error('[MobileUser] Error registering FCM token:', error);
        return res.status(500).json({ success: false, message: 'Failed to register FCM token' });
    }
};


// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/user/block
// ─────────────────────────────────────────────────────────────────────────────
export const blockUser = async (req: Request, res: Response): Promise<Response> => {
    try {
        const userId = req.body.userId || req.user?.id;
        const targetUserId = req.body.targetUserId;

        if (!userId || !targetUserId) return res.status(400).json({ success: false, message: 'userId and targetUserId required' });

        // Destroy any existing connection first to ensure clean block state
        await SocialConnection.destroy({
            where: {
                [Op.or]: [
                    { requesterId: userId, receiverId: targetUserId },
                    { requesterId: targetUserId, receiverId: userId },
                ]
            }
        });

        // Create the block connection (Blocker is requester, Blocked is receiver)
        await SocialConnection.create({
            requesterId: userId,
            receiverId: targetUserId,
            status: ConnectionStatus.BLOCKED
        });

        // Recalculate block count
        const count = await SocialConnection.count({
            where: {
                receiverId: targetUserId,
                status: ConnectionStatus.BLOCKED
            }
        });

        const targetUser = await User.findByPk(targetUserId);
        if (targetUser) {
            targetUser.blockCount = count;
            if (count >= 10) {
                targetUser.isAutoblocked = true;
                targetUser.autoblockedReason = `Autoblocked due to receiving ${count} blocks from other users.`;
                targetUser.isActive = false;
            }
            await targetUser.save();

            // Emit socket to log out target user immediately
            if (targetUser.isAutoblocked) {
                try {
                    const { io } = require('../server');
                    io.to(`user_${targetUserId}`).emit('user_autoblocked', {
                        userId: targetUserId,
                        reason: targetUser.autoblockedReason,
                    });
                } catch (socketErr) {
                    logger.warn('[MobileUser] Could not emit user_autoblocked socket event:', socketErr);
                }
            }
        }

        return res.status(200).json({ success: true, message: 'User blocked' });
    } catch (error: any) {
        logger.error('[MobileUser] blockUser error:', error);
        return res.status(500).json({ success: false, message: 'Failed to block user' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/user/unblock
// ─────────────────────────────────────────────────────────────────────────────
export const unblockUser = async (req: Request, res: Response): Promise<Response> => {
    try {
        const userId = req.body.userId || req.user?.id;
        const targetUserId = req.body.targetUserId;

        if (!userId || !targetUserId) return res.status(400).json({ success: false, message: 'userId and targetUserId required' });

        const conn = await SocialConnection.findOne({
            where: {
                status: ConnectionStatus.BLOCKED,
                requesterId: userId,
                receiverId: targetUserId
            }
        });

        if (conn) {
            await conn.destroy();
        }

        // Recalculate block count
        const count = await SocialConnection.count({
            where: {
                receiverId: targetUserId,
                status: ConnectionStatus.BLOCKED
            }
        });

        const targetUser = await User.findByPk(targetUserId);
        if (targetUser) {
            targetUser.blockCount = count;
            await targetUser.save();
        }

        return res.status(200).json({ success: true, message: 'User unblocked' });
    } catch (error: any) {
        logger.error('[MobileUser] unblockUser error:', error);
        return res.status(500).json({ success: false, message: 'Failed to unblock user' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/user/report
// ─────────────────────────────────────────────────────────────────────────────
export const reportUser = async (req: Request, res: Response): Promise<Response> => {
    try {
        const userId = req.body.userId || req.user?.id;
        const targetUserId = req.body.targetUserId;
        const reason = req.body.reason || 'No reason provided';

        if (!userId || !targetUserId) return res.status(400).json({ success: false, message: 'userId and targetUserId required' });

        await UserPenalty.create({
            userId: targetUserId,
            reason: `Reported by ${userId}: ${reason}`
        });

        // Destroy any existing connection first
        await SocialConnection.destroy({
            where: {
                [Op.or]: [
                    { requesterId: userId, receiverId: targetUserId },
                    { requesterId: targetUserId, receiverId: userId },
                ]
            }
        });

        // Create the block connection
        await SocialConnection.create({
            requesterId: userId,
            receiverId: targetUserId,
            status: ConnectionStatus.BLOCKED
        });

        // Recalculate block count
        const count = await SocialConnection.count({
            where: {
                receiverId: targetUserId,
                status: ConnectionStatus.BLOCKED
            }
        });

        const targetUser = await User.findByPk(targetUserId);
        if (targetUser) {
            targetUser.blockCount = count;
            if (count >= 10) {
                targetUser.isAutoblocked = true;
                targetUser.autoblockedReason = `Autoblocked due to receiving ${count} blocks from other users.`;
                targetUser.isActive = false;
            }
            await targetUser.save();

            // Emit socket to log out target user immediately
            if (targetUser.isAutoblocked) {
                try {
                    const { io } = require('../server');
                    io.to(`user_${targetUserId}`).emit('user_autoblocked', {
                        userId: targetUserId,
                        reason: targetUser.autoblockedReason,
                    });
                } catch (socketErr) {
                    logger.warn('[MobileUser] Could not emit user_autoblocked socket event:', socketErr);
                }
            }
        }

        return res.status(200).json({ success: true, message: 'User reported and blocked' });
    } catch (error: any) {
        logger.error('[MobileUser] reportUser error:', error);
        return res.status(500).json({ success: false, message: 'Failed to report user' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/user/blocks
// ─────────────────────────────────────────────────────────────────────────────
export const getBlockedUsers = async (req: Request, res: Response): Promise<Response> => {
    try {
        const userId = (req.query.userId as string) || req.user?.id;
        if (!userId) return res.status(401).json({ success: false, message: 'userId query param required' });

        const blocks = await SocialConnection.findAll({
            where: {
                status: ConnectionStatus.BLOCKED,
                [Op.or]: [
                    { requesterId: userId },
                    { receiverId: userId },
                ]
            }
        });

        const blockedUserIds = blocks.map(b => b.requesterId === userId ? b.receiverId : b.requesterId);

        return res.status(200).json({ success: true, data: blockedUserIds });
    } catch (error: any) {
        logger.error('[MobileUser] getBlockedUsers error:', error);
        return res.status(500).json({ success: false, message: 'Failed to get blocks' });
    }
};

export const getBlockedUsersDetails = async (req: Request, res: Response): Promise<Response> => {
    try {
        const userId = (req.query.userId as string) || req.user?.id;
        if (!userId) return res.status(401).json({ success: false, message: 'userId required' });

        // Retrieve connections where the current user blocked the receiver user
        const blocks = await SocialConnection.findAll({
            where: {
                status: ConnectionStatus.BLOCKED,
                requesterId: userId
            }
        });

        const blockedUserIds = blocks.map(b => b.receiverId);
        if (blockedUserIds.length === 0) {
            return res.status(200).json({ success: true, data: [] });
        }

        const users = await User.findAll({
            where: {
                id: {
                    [Op.in]: blockedUserIds
                }
            },
            attributes: ['id', 'firstName', 'lastName', 'profileImageUrl']
        });

        return res.status(200).json({ success: true, data: users });
    } catch (error: any) {
        logger.error('[MobileUser] getBlockedUsersDetails error:', error);
        return res.status(500).json({ success: false, message: 'Failed to get blocked contacts details' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/user/swipe
// Processes a user swipe (like, superlike, nope) and handles mutual matching
// ─────────────────────────────────────────────────────────────────────────────
export const swipeUser = async (req: Request, res: Response): Promise<Response> => {
    try {
        const { userId, targetUserId, action } = req.body;
        if (!userId || !targetUserId || !action) {
            return res.status(400).json({ success: false, message: 'userId, targetUserId, and action are required' });
        }

        if (action !== 'like' && action !== 'superlike' && action !== 'nope') {
            return res.status(400).json({ success: false, message: 'Invalid action. Must be like, superlike, or nope' });
        }

        // Check if there is already a swipe from this user to target
        const existingMySwipe = await UserMatch.findOne({
            where: {
                user1Id: userId,
                user2Id: targetUserId,
            }
        });

        // Check if there is already a swipe from the target user back to this user
        const existingOppositeSwipe = await UserMatch.findOne({
            where: {
                user1Id: targetUserId,
                user2Id: userId,
            }
        });

        // Helper to check swipe types
        const isSuperlikeRecord = (swipe: any) => swipe && swipe.matchReason === 'superlike';
        const isLikeRecord = (swipe: any) => swipe && swipe.status !== 'declined' && swipe.matchReason !== 'superlike';
        const isNopeRecord = (swipe: any) => swipe && swipe.status === 'declined';

        // 1. Handle toggle/remove swipe if they click the same button again
        if (existingMySwipe) {
            const isDuplicateLike = (action === 'like' && isLikeRecord(existingMySwipe));
            const isDuplicateSuperlike = (action === 'superlike' && isSuperlikeRecord(existingMySwipe));
            const isDuplicateNope = (action === 'nope' && isNopeRecord(existingMySwipe));

            if (isDuplicateLike || isDuplicateSuperlike || isDuplicateNope) {
                // If it was connected, downgrade the opposite swipe back to pending
                if (existingMySwipe.status === 'connected' && existingOppositeSwipe) {
                    existingOppositeSwipe.status = 'pending' as any;
                    await existingOppositeSwipe.save();
                }
                await existingMySwipe.destroy();
                return res.status(200).json({ success: true, message: 'Swipe removed', data: null, matched: false, action: 'removed' });
            }
        }

        // 1.5 Enforce subscription limit checks for Like / Superlike
        if (action === 'like') {
            const SubscriptionService = require('../services/subscriptionService').default || require('../services/subscriptionService').SubscriptionService;
            const consume = await SubscriptionService.consumeUsage(userId, 'daily_likes');
            if (!consume.success) {
                return res.status(403).json({
                    success: false,
                    code: 'LIMIT_REACHED',
                    message: consume.message || 'You have reached your daily likes limit. Upgrade to Lunara VIP for unlimited likes!'
                });
            }
        } else if (action === 'superlike') {
            const activeSub = await UserSubscription.findOne({
                where: {
                    userId,
                    status: 'active',
                    endDate: { [Op.gt]: new Date() },
                },
                include: [{ model: SubscriptionPackage, as: 'package' }],
                order: [['createdAt', 'DESC']],
            });

            if (!activeSub || activeSub.superlikesRemaining <= 0) {
                return res.status(403).json({
                    success: false,
                    code: 'LIMIT_REACHED',
                    message: 'You have no super likes remaining. Upgrade your plan or purchase more super likes!'
                });
            }

            // Consume/decrement superlike credit if not unlimited (unlimited is >= 9999)
            if (activeSub.superlikesRemaining < 9999) {
                activeSub.superlikesRemaining = activeSub.superlikesRemaining - 1;
                await activeSub.save();
            }
        }

        // 2. If action is nope (declining/ignoring)
        if (action === 'nope') {
            if (existingMySwipe) {
                // Update to nope
                existingMySwipe.status = 'declined' as any;
                existingMySwipe.compatibilityScore = 0;
                existingMySwipe.matchReason = undefined;
                await existingMySwipe.save();
                return res.status(200).json({ success: true, data: existingMySwipe, matched: false });
            } else {
                const match = await UserMatch.create({
                    user1Id: userId,
                    user2Id: targetUserId,
                    compatibilityScore: 0,
                    status: 'declined' as any,
                    expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000)
                });
                return res.status(200).json({ success: true, data: match, matched: false });
            }
        }

        // 3. Handle like / superlike (including updates/upgrades from existing swipe)
        const isMutualMatch = existingOppositeSwipe && (existingOppositeSwipe.status === 'pending' || existingOppositeSwipe.status === 'connected');

        if (isMutualMatch) {
            // Update opposite swipe to connected
            existingOppositeSwipe.status = 'connected' as any;
            if (action === 'superlike') {
                existingOppositeSwipe.matchReason = 'superlike';
            }
            await existingOppositeSwipe.save();

            let mySwipe;
            if (existingMySwipe) {
                // Update existing swipe
                existingMySwipe.status = 'connected' as any;
                existingMySwipe.compatibilityScore = action === 'superlike' ? 95 : (existingOppositeSwipe.compatibilityScore || 85);
                existingMySwipe.matchReason = action === 'superlike' ? 'superlike' : undefined;
                mySwipe = await existingMySwipe.save();
            } else {
                // Create new connected swipe
                mySwipe = await UserMatch.create({
                    user1Id: userId,
                    user2Id: targetUserId,
                    compatibilityScore: action === 'superlike' ? 95 : (existingOppositeSwipe.compatibilityScore || 85),
                    status: 'connected' as any,
                    matchReason: action === 'superlike' ? 'superlike' : undefined,
                    expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000)
                });
            }

            // ── Auto-init free chat subscription on mutual match ──────────────
            try {
                const { getChatSettings } = await import('./chatSubscriptionController');
                const { Conversation: Conv, ChatSubscription: ChatSub } = await import('../models');
                const ChatSubscriptionModel = ChatSub as any;
                const ConversationModel = Conv as any;

                let conversation = await ConversationModel.findOne({
                    where: {
                        [Op.or]: [
                            { participantOne: userId, participantTwo: targetUserId },
                            { participantOne: targetUserId, participantTwo: userId },
                        ]
                    }
                });

                if (!conversation) {
                    conversation = await ConversationModel.create({
                        participantOne: userId,
                        participantTwo: targetUserId,
                        contextType: 'match',
                    });
                }

                const existingFreeSub = await ChatSubscriptionModel.findOne({
                    where: { conversationId: conversation.id, subscriptionType: 'free' }
                });

                if (!existingFreeSub) {
                    const settings = getChatSettings();
                    const freeDays = settings.freeDays;
                    const validUntil = new Date();
                    validUntil.setDate(validUntil.getDate() + freeDays);

                    await ChatSubscriptionModel.create({
                        conversationId: conversation.id,
                        paidById: userId,
                        amount: 0,
                        daysGranted: freeDays,
                        validUntil,
                        status: 'active',
                        subscriptionType: 'free',
                    });
                }

                // Emit live new_match events
                try {
                    const currentUser = await User.findByPk(userId);
                    const targetUser = await User.findByPk(targetUserId);
                    if (currentUser && targetUser) {
                        const { io } = require('../server');
                        io.to(`user_${userId}`).emit('new_match', {
                            matchedUser: targetUser.get({ plain: true }),
                            conversationId: conversation.id
                        });
                        io.to(`user_${targetUserId}`).emit('new_match', {
                            matchedUser: currentUser.get({ plain: true }),
                            conversationId: conversation.id
                        });

                        // Emit notification_created to the target user
                        io.to(`user_${targetUserId}`).emit('notification_created', {
                            id: `match_${mySwipe.id}`,
                            title: 'New Match!',
                            body: `You and ${currentUser.firstName} are a match! 🎉`,
                            createdAt: new Date().toISOString(),
                            read: false,
                            sender: {
                                id: currentUser.id,
                                firstName: currentUser.firstName,
                                lastName: currentUser.lastName,
                                profileImageUrl: currentUser.profileImageUrl,
                            }
                        });

                        if (targetUser.fcmToken) {
                            const { sendPushNotification } = require('../services/fcmService');
                            await sendPushNotification(targetUser.fcmToken, {
                                title: 'New Match!',
                                body: `You and ${currentUser.firstName} are a match! 🎉`,
                                data: {
                                    type: 'match',
                                    senderId: currentUser.id,
                                    senderName: `${currentUser.firstName} ${currentUser.lastName}`,
                                    senderImage: currentUser.profileImageUrl || '',
                                    conversationId: conversation.id,
                                }
                            });
                        }
                    }
                } catch (emitErr) {
                    logger.error('[swipeUser] Failed to emit new_match socket event / push notification:', emitErr);
                }

                return res.status(200).json({
                    success: true,
                    data: mySwipe,
                    matched: true,
                    conversationId: conversation.id,
                });
            } catch (chatErr) {
                logger.error('[swipeUser] Failed to init free chat, but match still created:', chatErr);
            }

            return res.status(200).json({ success: true, data: mySwipe, matched: true });
        }

        // 4. Otherwise (no mutual match yet), create/update to pending match record
        let match;
        const score = action === 'superlike' ? 95 : 75;
        if (existingMySwipe) {
            existingMySwipe.status = 'pending' as any;
            existingMySwipe.compatibilityScore = score;
            existingMySwipe.matchReason = action === 'superlike' ? 'superlike' : undefined;
            match = await existingMySwipe.save();
        } else {
            match = await UserMatch.create({
                user1Id: userId,
                user2Id: targetUserId,
                compatibilityScore: score,
                status: 'pending' as any,
                matchReason: action === 'superlike' ? 'superlike' : undefined,
                expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000)
            });
        }

        // Send push notification & socket event for Like or Super Like
        try {
            const currentUser = await User.findByPk(userId);
            const targetUser = await User.findByPk(targetUserId);
            if (currentUser && targetUser) {
                const senderName = `${currentUser.firstName} ${currentUser.lastName}`;
                const isSuper = action === 'superlike';
                const title = isSuper ? 'Super Like' : 'Like';
                const body = isSuper 
                    ? `${senderName} super liked your profile 🌟`
                    : `${senderName} liked your profile ❤️`;

                const { io } = require('../server');
                io.to(`user_${targetUserId}`).emit('notification_created', {
                    id: `match_${match.id}`,
                    title,
                    body,
                    createdAt: new Date().toISOString(),
                    read: false,
                    sender: {
                        id: currentUser.id,
                        firstName: currentUser.firstName,
                        lastName: currentUser.lastName,
                        profileImageUrl: currentUser.profileImageUrl,
                    }
                });

                if (targetUser.fcmToken) {
                    const { sendPushNotification } = require('../services/fcmService');
                    await sendPushNotification(targetUser.fcmToken, {
                        title,
                        body,
                        data: {
                            type: isSuper ? 'superlike' : 'like',
                            senderId: currentUser.id,
                            senderName: senderName,
                            senderImage: currentUser.profileImageUrl || '',
                        }
                    });
                }
            }
        } catch (fcmErr) {
            logger.error('[swipeUser] Failed to send push notification/socket:', fcmErr);
        }

        return res.status(200).json({ success: true, data: match, matched: false });

    } catch (error: any) {
        logger.error('[MobileUser] Error processing swipe:', error);
        return res.status(500).json({ success: false, message: 'Failed to process swipe' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/user/likes-matches
// Returns a list of swipes/matches involving this user
// ─────────────────────────────────────────────────────────────────────────────
export const getMyLikesAndMatches = async (req: Request, res: Response): Promise<Response> => {
    try {
        const { userId } = req.query;
        if (!userId) {
            return res.status(400).json({ success: false, message: 'userId is required' });
        }

        const matches = await UserMatch.findAll({
            where: {
                [Op.or]: [
                    { user1Id: userId as string },
                    { user2Id: userId as string }
                ]
            }
        });

        return res.status(200).json({ success: true, data: matches });
    } catch (error: any) {
        logger.error('[MobileUser] Error fetching matches:', error);
        return res.status(500).json({ success: false, message: 'Failed to fetch matches' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/user/swipe-status
// Returns whether the current user has already liked/superliked a target today,
// and the plan's daily limits so the UI can enforce them dynamically.
// ─────────────────────────────────────────────────────────────────────────────
export const getSwipeStatus = async (req: Request, res: Response): Promise<Response> => {
    try {
        const userId = (req.query.userId as string) || req.user?.id;
        const targetUserId = req.query.targetUserId as string;

        if (!userId || !targetUserId) {
            return res.status(400).json({ success: false, message: 'userId and targetUserId are required' });
        }

        // Check today's swipe on this specific target
        const todayStart = new Date();
        todayStart.setHours(0, 0, 0, 0);

        const existingSwipe = await UserMatch.findOne({
            where: {
                user1Id: userId,
                user2Id: targetUserId,
                createdAt: { [Op.gte]: todayStart },
            }
        });

        const alreadyLiked = !!existingSwipe && ['pending', 'connected'].includes(existingSwipe.status as string);
        const alreadySuperLiked = alreadyLiked && existingSwipe?.matchReason === 'superlike';
        const alreadyNoped = !!existingSwipe && existingSwipe.status === 'declined';

        // Get today's total like count for this user
        const todayLikeCount = await UserMatch.count({
            where: {
                user1Id: userId,
                status: { [Op.in]: ['pending', 'connected'] },
                createdAt: { [Op.gte]: todayStart },
            }
        });

        // Get subscription limits
        let dailyLikesLimit = 7;
        let superlikesRemaining = 0;
        let superlikesPerCycle = 0;

        try {
            const UserSubscription = require('../models/UserSubscription').default;
            const SubscriptionPackage = require('../models/SubscriptionPackage').default;

            const activeSub = await UserSubscription.findOne({
                where: {
                    userId,
                    status: 'active',
                    endDate: { [Op.gt]: new Date() },
                },
                include: [{ model: SubscriptionPackage, as: 'package' }],
                order: [['createdAt', 'DESC']],
            });

            if (activeSub) {
                const pkg = (activeSub as any).package;
                if (pkg) {
                    dailyLikesLimit = pkg.dailyLikes === -1 ? 999999 : (pkg.dailyLikes || 7);
                }
                superlikesRemaining = activeSub.superlikesRemaining || 0;
                superlikesPerCycle = (activeSub as any).package?.superlikesPerCycle || 0;
            }
        } catch (subErr) {
            logger.warn('[swipeStatus] Could not fetch subscription limits:', subErr);
        }

        // Get backtrack usage and limits
        let dailyBacktracksLimit = 3;
        let dailyBacktracksRemaining = 3;
        try {
            const SubscriptionService = require('../services/subscriptionService').default || require('../services/subscriptionService').SubscriptionService;
            const limit = await SubscriptionService.getLimit(userId, 'daily_backtracks');
            const remaining = await SubscriptionService.getRemainingUsage(userId, 'daily_backtracks');
            dailyBacktracksLimit = limit === 'unlimited' ? 999999 : limit;
            dailyBacktracksRemaining = remaining === 'unlimited' ? 999999 : remaining;
        } catch (backtrackErr) {
            logger.warn('[swipeStatus] Could not fetch backtrack limits:', backtrackErr);
        }

        return res.status(200).json({
            success: true,
            data: {
                alreadyLiked,
                alreadySuperLiked,
                alreadyNoped,
                dailyLikesLimit,
                dailyLikesUsed: todayLikeCount,
                dailyLikesRemaining: Math.max(0, dailyLikesLimit - todayLikeCount),
                superlikesRemaining,
                superlikesPerCycle,
                limitReached: todayLikeCount >= dailyLikesLimit,
                superLimitReached: superlikesRemaining <= 0 && superlikesPerCycle > 0,
                dailyBacktracksLimit,
                dailyBacktracksRemaining,
                dailyBacktracksUsed: Math.max(0, dailyBacktracksLimit - dailyBacktracksRemaining)
            },
        });
    } catch (error: any) {
        logger.error('[MobileUser] getSwipeStatus error:', error);
        return res.status(500).json({ success: false, message: 'Failed to get swipe status' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/user/backtrack
// Processes a backtrack/undo swipe
// ─────────────────────────────────────────────────────────────────────────────
export const backtrackSwipe = async (req: Request, res: Response): Promise<Response> => {
    try {
        const userId = req.body.userId || req.user?.id;
        const { targetUserId } = req.body;

        if (!userId || !targetUserId) {
            return res.status(400).json({ success: false, message: 'userId and targetUserId are required' });
        }

        const SubscriptionService = require('../services/subscriptionService').default || require('../services/subscriptionService').SubscriptionService;
        const remaining = await SubscriptionService.getRemainingUsage(userId, 'daily_backtracks');

        if (remaining !== 'unlimited' && remaining <= 0) {
            return res.status(403).json({
                success: false,
                code: 'LIMIT_REACHED',
                message: 'You have reached your daily backtrack limit. Upgrade your plan to get more backtracks!'
            });
        }

        // Consume 1 backtrack usage
        const consume = await SubscriptionService.consumeUsage(userId, 'daily_backtracks');

        // Find the swipe record and destroy it
        const mySwipe = await UserMatch.findOne({
            where: {
                user1Id: userId,
                user2Id: targetUserId
            }
        });

        if (mySwipe) {
            if (mySwipe.status === 'connected') {
                const oppositeSwipe = await UserMatch.findOne({
                    where: {
                        user1Id: targetUserId,
                        user2Id: userId
                    }
                });
                if (oppositeSwipe) {
                    oppositeSwipe.status = 'pending' as any;
                    await oppositeSwipe.save();
                }
            }
            await mySwipe.destroy();
        }

        return res.status(200).json({
            success: true,
            data: {
                remaining: consume.remaining,
                limit: consume.limit,
                used: consume.used
            },
            message: 'Swipe backtracked successfully'
        });
    } catch (error: any) {
        logger.error('[MobileUser] backtrackSwipe error:', error);
        return res.status(500).json({ success: false, message: 'Failed to backtrack swipe' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/user/delete-account
// ─────────────────────────────────────────────────────────────────────────────

export const deleteAccount = async (req: Request, res: Response): Promise<Response> => {
    try {
        const userId = req.body.userId || req.user?.id;
        const { password, reason } = req.body;

        if (!userId) {
            return res.status(401).json({ success: false, message: 'Authentication required' });
        }

        // ── 1. Fetch the user ──────────────────────────────────────────────────
        const user = await User.findByPk(userId, {
            attributes: [
                'id', 'email', 'phone', 'firstName', 'lastName', 'dateOfBirth', 'role',
                'isVerified', 'blockCount', 'isAutoblocked', 'autoblockedReason',
                'noShowCount', 'lastLoginAt', 'createdAt', 'profileImageUrl', 'passwordHash',
                'isDeleted', 'fcmToken',
            ]
        });

        if (!user) {
            return res.status(404).json({ success: false, message: 'User not found' });
        }

        // ── 2. Check if already deleted ────────────────────────────────────────
        if ((user as any).isDeleted) {
            return res.status(409).json({
                success: false,
                code: 'ALREADY_DELETED',
                message: 'This account has already been deleted',
            });
        }

        // ── 3. Password re-authentication gate ─────────────────────────────────
        if (user.passwordHash) {
            if (!password) {
                return res.status(400).json({
                    success: false,
                    code: 'PASSWORD_REQUIRED',
                    message: 'Please confirm your password to delete your account',
                });
            }
            const isPasswordValid = await bcrypt.compare(password, user.passwordHash);
            if (!isPasswordValid) {
                return res.status(401).json({
                    success: false,
                    code: 'INVALID_PASSWORD',
                    message: 'Incorrect password. Please try again.',
                });
            }
        }

        // ── 4. Gather snapshot counts ──────────────────────────────────────────
        const [bookingsCount, subscriptionsCount, photosCount, profileData] = await Promise.all([
            Booking.count({ where: { userId } }),
            UserSubscription.count({ where: { userId } }),
            UserPhoto.count({ where: { userId } }),
            UserProfile.findOne({ where: { userId }, attributes: ['gender', 'city', 'bio', 'occupation', 'education'] }),
        ]);

        // ── 5. Archive a full snapshot into deleted_accounts ───────────────────
        const ipAddress = (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim()
            || req.socket?.remoteAddress
            || 'unknown';

        await DeletedAccount.create({
            originalUserId: userId,
            email: user.email,
            phone: user.phone,
            firstName: user.firstName,
            lastName: user.lastName,
            dateOfBirth: user.dateOfBirth,
            role: user.role,
            gender: (profileData as any)?.gender ?? null,
            city: (profileData as any)?.city ?? null,
            bio: (profileData as any)?.bio ?? null,
            profileImageUrl: user.profileImageUrl ?? null,
            occupation: (profileData as any)?.occupation ?? null,
            education: (profileData as any)?.education ?? null,
            isVerified: user.isVerified,
            blockCount: user.blockCount,
            isAutoblocked: user.isAutoblocked,
            autoblockedReason: user.autoblockedReason ?? null,
            noShowCount: user.noShowCount,
            lastLoginAt: (user as any).lastLoginAt ?? null,
            registeredAt: (user as any).createdAt ?? null,
            deletionReason: reason?.trim() ?? null,
            deletedByUser: true,
            ipAddress,
            bookingsCount,
            subscriptionsCount,
            photosCount,
        });

        // ── 6. Soft-delete: mark as deleted, deactivate, clear sensitive tokens ─
        await user.update({
            isDeleted: true,
            isActive: false,
            deletedAt: new Date(),
            deletionReason: reason?.trim() ?? null,
            fcmToken: null,   // Stop all push notifications immediately
        } as any);

        logger.info(`[DeleteAccount] User ${userId} (${user.email}) self-deleted their account. Reason: ${reason ?? 'N/A'}`);

        return res.status(200).json({
            success: true,
            code: 'ACCOUNT_DELETED',
            message: 'Your account has been permanently deleted. We are sorry to see you go.',
        });

    } catch (error: any) {
        logger.error('[DeleteAccount] Error:', error);
        return res.status(500).json({
            success: false,
            code: 'SERVER_ERROR',
            message: 'Failed to delete account. Please try again or contact support.',
        });
    }
};

export default {
    uploadPhotos,
    completeProfileSetup,
    getMyProfile,
    getAllCustomers,
    getUserStatus,
    registerFcmToken,
    blockUser,
    unblockUser,
    reportUser,
    getBlockedUsers,
    getBlockedUsersDetails,
    swipeUser,
    getMyLikesAndMatches,
    getSwipeStatus,
    backtrackSwipe,
    deleteAccount,
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/user/delete-account
// Permanently soft-deletes the user's account:
//   1. Validates password (security re-auth gate)
//   2. Snapshots all user data into deleted_accounts archive
//   3. Soft-deletes the user: sets isDeleted=true, isActive=false
//   4. Clears FCM token so no more push notifications
//   5. Returns ACCOUNT_DELETED so client clears local state
// ─────────────────────────────────────────────────────────────────────────────
// NOTE: This function is defined outside the default export to keep the file
// structure clean. It is referenced in the export above.
