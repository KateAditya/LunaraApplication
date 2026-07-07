import { Request, Response } from 'express';
import path from 'path';
import fs from 'fs';
import crypto from 'crypto';
import sharp from 'sharp';
import { UserProfile, UserPreference, UserPhoto, UserMatch } from '../models';
import User, { UserRole } from '../models/User';

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

        const galleryDir = getUserGalleryDir(userId);
        const createdPhotos = [];

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

            const photo = await UserPhoto.create({
                userId,
                filePath: relativePath,
                fileSize: compressedBuffer.length,   // compressed size, not original
                mimeType: 'image/jpeg',
                isPrimary: i === 0,
                displayOrder: i,
            });

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
        const userId = (req.query.userId as string) || req.user?.id;
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

        return res.status(200).json({
            success: true,
            data: {
                // ── Core user fields ─────────────────────────────────────────
                id: user.id,
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

        // Build User-level where clause
        const userWhere: any = { role: UserRole.CUSTOMER, isActive: true };
        if (search) {
            userWhere[Op.or] = [
                { firstName: { [Op.iLike]: `%${search}%` } },
                { lastName: { [Op.iLike]: `%${search}%` } },
                { email: { [Op.iLike]: `%${search}%` } },
                { phone: { [Op.iLike]: `%${search}%` } },
            ];
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
                    where: { showMeInMatching: { [Op.ne]: false } }, // Exclude hidden profiles, but allow those without preference records or with true
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
        });

        const totalPages = Math.ceil(count / limit);

        const data = rows.map(user => {
            const u = user as any;
            // Compute age from dateOfBirth
            const age = user.dateOfBirth
                ? Math.floor((Date.now() - new Date(user.dateOfBirth).getTime()) / (365.25 * 24 * 60 * 60 * 1000))
                : null;

            // Build photo URL
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

        let conn = await SocialConnection.findOne({
            where: {
                [Op.or]: [
                    { requesterId: userId, receiverId: targetUserId },
                    { requesterId: targetUserId, receiverId: userId },
                ]
            }
        });

        if (conn) {
            conn.status = ConnectionStatus.BLOCKED;
            await conn.save();
        } else {
            await SocialConnection.create({
                requesterId: userId,
                receiverId: targetUserId,
                status: ConnectionStatus.BLOCKED
            });
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
                [Op.or]: [
                    { requesterId: userId, receiverId: targetUserId },
                    { requesterId: targetUserId, receiverId: userId },
                ]
            }
        });

        if (conn) {
            await conn.destroy();
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

        let conn = await SocialConnection.findOne({
            where: {
                [Op.or]: [
                    { requesterId: userId, receiverId: targetUserId },
                    { requesterId: targetUserId, receiverId: userId },
                ]
            }
        });

        if (conn) {
            conn.status = ConnectionStatus.BLOCKED;
            await conn.save();
        } else {
            await SocialConnection.create({
                requesterId: userId,
                receiverId: targetUserId,
                status: ConnectionStatus.BLOCKED
            });
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

        // Check if there is already a swipe from the target user back to this user
        const existingOppositeSwipe = await UserMatch.findOne({
            where: {
                user1Id: targetUserId,
                user2Id: userId,
            }
        });

        if (action === 'nope') {
            // Create a declined match record
            const match = await UserMatch.create({
                user1Id: userId,
                user2Id: targetUserId,
                compatibilityScore: 0,
                status: 'declined' as any,
                expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000)
            });
            return res.status(200).json({ success: true, data: match, matched: false });
        }

        // If the opposite user has liked or superliked this user, we have a mutual match!
        if (existingOppositeSwipe && (existingOppositeSwipe.status === 'pending' || existingOppositeSwipe.status === 'connected')) {
            existingOppositeSwipe.status = 'connected' as any;
            if (action === 'superlike') {
                existingOppositeSwipe.matchReason = 'superlike';
            }
            await existingOppositeSwipe.save();

            // Also ensure we create/update the reverse record for easy querying
            const mySwipe = await UserMatch.create({
                user1Id: userId,
                user2Id: targetUserId,
                compatibilityScore: existingOppositeSwipe.compatibilityScore || 85,
                status: 'connected' as any,
                matchReason: action === 'superlike' ? 'superlike' : undefined,
                expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000)
            });

            // ── Auto-init free chat subscription on mutual match ──────────────
            try {
                const { getChatSettings } = await import('./chatSubscriptionController');
                const { Conversation: Conv, ChatSubscription: ChatSub } = await import('../models');
                const ChatSubscriptionModel = ChatSub as any;
                const ConversationModel = Conv as any;

                // Find or create a conversation between both users
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

                // Only create free subscription if one doesn't already exist
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

        // Otherwise, create a pending match record
        const score = action === 'superlike' ? 95 : 75;
        const match = await UserMatch.create({
            user1Id: userId,
            user2Id: targetUserId,
            compatibilityScore: score,
            status: 'pending' as any,
            matchReason: action === 'superlike' ? 'superlike' : undefined,
            expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000)
        });

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
    swipeUser,
    getMyLikesAndMatches
};
