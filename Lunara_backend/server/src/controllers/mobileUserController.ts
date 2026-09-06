import { Request, Response } from 'express';
import path from 'path';
import fs from 'fs';
import crypto from 'crypto';
import sharp from 'sharp';
import { UserProfile, UserPreference, UserPhoto, UserMatch, PartyPlan, GroupParty, StrangersMeetRequest, Booking, Plan, Venue } from '../models';
import { PartyPlanStatus } from '../models/PartyPlan';
import { StrangersMeetStatus } from '../models/StrangersMeetRequest';
import { GroupPartyStatus } from '../models/GroupParty';
import Notification from '../models/Notification';
import UserLike from '../models/UserLike';
import User, { UserRole } from '../models/User';
import DeletedAccount from '../models/DeletedAccount';
import UserSubscription, { SubscriptionStatus } from '../models/UserSubscription';
import SubscriptionPackage from '../models/SubscriptionPackage';
import bcrypt from 'bcryptjs';

import { logger } from '../config/logger';
import { Op } from 'sequelize';
import { getUserGalleryDir } from '../middleware/upload';
import SocialConnection, { ConnectionStatus } from '../models/SocialConnection';
import UserPenalty from '../models/UserPenalty';

import { azureFaceService } from '../services/azureFaceService';
import { RankingService } from '../services/rankingService';
import { RealtimeEventBroker } from '../services/RealtimeEventBroker';
import { SubscriptionService } from '../services/subscriptionService';
import { EntitlementService } from '../services/EntitlementService';

// ─── Image compression constants ──────────────────────────────────────────────
// Target HD/2K quality (~3-4 MB max target size, ultra-sharp & unblurred)
const PHOTO_MAX_WIDTH = 2400;   // px
const PHOTO_MAX_HEIGHT = 2400;  // px
const PHOTO_QUALITY = 92;       // High JPEG quality (92/100) to prevent blur & artifacts

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/user/photos
// ─────────────────────────────────────────────────────────────────────────────
export const uploadPhotos = async (req: Request, res: Response): Promise<Response> => {
    try {
        const userId = req.user?.id || req.body.userId;
        if (!userId) {
            return res.status(400).json({ success: false, message: 'userId is required' });
        }

        const files = req.files as Express.Multer.File[];

        if (!files || files.length < 1) {
            return res.status(400).json({ success: false, message: 'Please upload at least 1 photo' });
        }

        const galleryDir = getUserGalleryDir(userId);
        const createdPhotos = [];

        // Check if user already has a primary photo
        const hasPrimary = await UserPhoto.findOne({ where: { userId, isPrimary: true } });
        
        // Decide if the first uploaded file in this request should be primary
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
            const fileSizeMB = fileBuffer.length / (1024 * 1024);

            // ── Auto-Compress with sharp (if > 3MB, compress down to <= 3MB, otherwise upload directly) ──
            const randomHex = crypto.randomBytes(8).toString('hex');
            const filename = `${Date.now()}_${randomHex}.jpg`;
            const absolutePath = path.join(galleryDir, filename);

            let finalBuffer: Buffer;

            if (fileSizeMB <= 3.0) {
                // If original image is already <= 3 MB, upload directly without compressing
                try {
                    // Normalize EXIF orientation if needed without lowering quality
                    finalBuffer = await sharp(fileBuffer)
                        .rotate()
                        .jpeg({ quality: 98, progressive: true })
                        .toBuffer();
                } catch {
                    finalBuffer = fileBuffer;
                }
            } else {
                // If original image is larger than 3 MB, auto-compress down to <= 3 MB
                let compressed = await sharp(fileBuffer)
                    .rotate()
                    .resize({
                        width: PHOTO_MAX_WIDTH,
                        height: PHOTO_MAX_HEIGHT,
                        fit: 'inside',
                        withoutEnlargement: true,
                    })
                    .jpeg({ quality: PHOTO_QUALITY, progressive: true })
                    .toBuffer();

                // If still > 3MB, perform an additional pass to guarantee <= 3MB
                if (compressed.length > 3 * 1024 * 1024) {
                    compressed = await sharp(compressed)
                        .resize({
                            width: 1920,
                            height: 1920,
                            fit: 'inside',
                            withoutEnlargement: true,
                        })
                        .jpeg({ quality: 82, progressive: true })
                        .toBuffer();
                }
                finalBuffer = compressed;
            }

            // ── Perform Backend Face Verification Scan ────────────────────────
            try {
                const faceScan = await azureFaceService.detectFace(finalBuffer);
                logger.info(`[PhotoUpload] Face verification scan for "${file.originalname}": hasFace=${faceScan.hasFace}, faces=${faceScan.faceCount}`);
            } catch (faceErr: any) {
                logger.warn(`[PhotoUpload] Face verification scan warning for "${file.originalname}": ${faceErr.message}`);
            }

            fs.writeFileSync(absolutePath, finalBuffer);

            // Store relative path (forward-slash, no leading slash) in DB
            const uploadsBase = process.env.UPLOAD_DIR || 'uploads';
            const relativePath = path
                .join(uploadsBase, 'users', userId, 'gallery', filename)
                .replace(/\\/g, '/');

            // Upload to Azure Blob Storage if configured
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
                    await blockBlobClient.upload(finalBuffer, finalBuffer.length, {
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
                fileSize: finalBuffer.length,
                mimeType: 'image/jpeg',
                isPrimary: photoIsPrimary,
                displayOrder: i,
            });

            if (photoIsPrimary) {
                const newProfileUrl = '/' + relativePath.replace(/\\/g, '/');
                await User.update(
                    { profileImageUrl: newProfileUrl },
                    { where: { id: userId } }
                );
                RealtimeEventBroker.emitToUser(userId, 'profile_photo_updated', 'user', userId, {
                    userId,
                    profileImageUrl: newProfileUrl,
                });
                RealtimeEventBroker.emitToLiveFeed('profile_photo_updated', 'user', userId, {
                    userId,
                    profileImageUrl: newProfileUrl,
                });
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
    minBudget?: number;
    maxBudget?: number;
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
        const userId = req.user?.id || req.body.userId;
        if (!userId) {
            return res.status(401).json({ success: false, message: 'Unauthorized: userId is required in body' });
        }

        const data = req.body as ProfileSetupBody;

        if (data.showMeInMatching === false) {
            const canHide = await SubscriptionService.hasAccess(userId, 'hide_profile');
            if (!canHide) {
                return res.status(403).json({
                    success: false,
                    code: 'UPGRADE_REQUIRED',
                    message: 'Hiding your profile from matching requires a PLUS, PRO, or ELITE subscription tier.'
                });
            }
        }

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
                    minBudget: data.minBudget,
                    maxBudget: data.maxBudget,
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

        RealtimeEventBroker.emitToUser(userId, 'profile_updated', 'user', userId, {
            userId,
            profile: updatedProfile,
            preferences: updatedPreferences,
        });
        RealtimeEventBroker.emitToLiveFeed('profile_updated', 'user', userId, {
            userId,
            profile: updatedProfile,
        });

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
        // The userId query param names WHICH profile is being viewed — it must
        // stay authoritative, since this endpoint is used both for "my own
        // profile" and for viewing any other user's profile (e.g. tapping a
        // card in Discovery/All Profiles). The verified token identity is only
        // the fallback target when no explicit profile was requested.
        const viewerId = req.user?.id;
        const userId = rawQueryId || viewerId || '';
        if (!userId) {
            return res.status(401).json({ success: false, message: 'Unauthorized: userId query param is required' });
        }
        const isOwnProfile = !!viewerId && viewerId === userId;

        // Fetch all profile components concurrently in parallel
        const [user, profile, preferences, allPhotos] = await Promise.all([
            User.findByPk(userId, {
                attributes: [
                    'id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl',
                    'role', 'isVerified', 'isActive', 'mfaEnabled',
                    'createdAt', 'updatedAt', 'lastLoginAt', 'dateOfBirth',
                ],
            }),
            UserProfile.findOne({ where: { userId } }),
            UserPreference.findOne({ where: { userId } }),
            UserPhoto.findAll({
                where: { userId },
                order: [
                    ['isPrimary', 'DESC'],
                    ['displayOrder', 'ASC'],
                    ['uploadedAt', 'DESC'],
                ],
                attributes: ['id', 'filePath', 'fileSize', 'mimeType', 'isPrimary', 'displayOrder', 'uploadedAt'],
            }),
        ]);

        if (!user) {
            return res.status(404).json({ success: false, message: 'User not found' });
        }

        const photoRecord = allPhotos.length > 0 ? allPhotos[0] : null;

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

        // Fetch all profile metrics, superlikes, subscription, and requester like/superlike status in a single parallel batch
        const requesterUserId = req.user?.id || (req.query.currentUserId as string);
        const shouldCheckRequester = !!(requesterUserId && requesterUserId !== userId);

        const [
            superLikesFromMatches,
            superLikesFromLikes,
            partyPlansCnt,
            strangersMeetCnt,
            groupPartyCnt,
            bookingsCount,
            matchesCount,
            activeSub,
            existingSwipe,
            existingUserLike,
        ] = await Promise.all([
            UserMatch.count({
                where: {
                    user2Id: userId,
                    matchReason: 'superlike',
                    status: { [Op.in]: ['pending', 'connected'] }
                }
            }),
            UserLike.count({
                where: {
                    targetUserId: userId,
                    actionType: 'superlike'
                }
            }),
            PartyPlan.count({
                where: {
                    userId,
                    status: { [Op.ne]: PartyPlanStatus.CANCELLED }
                }
            }),
            StrangersMeetRequest.count({
                where: {
                    userId,
                    status: { [Op.notIn]: [StrangersMeetStatus.CANCELLED, StrangersMeetStatus.REJECTED] }
                }
            }),
            GroupParty.count({
                where: {
                    userId,
                    status: { [Op.notIn]: [GroupPartyStatus.CANCELLED, GroupPartyStatus.REJECTED, GroupPartyStatus.EXPIRED] }
                }
            }),
            Booking.count({
                where: { userId }
            }),
            UserMatch.count({
                where: {
                    [Op.or]: [
                        { user1Id: userId, status: 'connected' },
                        { user2Id: userId, status: 'connected' }
                    ]
                }
            }),
            UserSubscription.findOne({
                where: {
                    userId,
                    status: SubscriptionStatus.ACTIVE,
                    endDate: { [Op.gt]: new Date() },
                },
                include: [{ model: SubscriptionPackage, as: 'package', attributes: ['tier'] }],
                order: [['createdAt', 'DESC']],
            }).catch(() => null),
            shouldCheckRequester
                ? UserMatch.findOne({
                    where: {
                        user1Id: requesterUserId,
                        user2Id: userId
                    }
                }).catch(() => null)
                : Promise.resolve(null),
            shouldCheckRequester
                ? UserLike.findOne({
                    where: {
                        userId: requesterUserId,
                        targetUserId: userId
                    }
                }).catch(() => null)
                : Promise.resolve(null),
        ]);

        const receivedSuperLikes = Math.max(superLikesFromMatches, superLikesFromLikes);
        const plansCount = partyPlansCnt + strangersMeetCnt + groupPartyCnt;
        const pointsCount = 1000 + (bookingsCount * 250) + (matchesCount * 50);

        const subscriptionTier: string = (activeSub as any)?.package?.tier ?? 'FREE';
        const planSuperlikesMap: Record<string, number> = { FREE: 0, CORE: 3, PLUS: 10, PRO: 14, ELITE: 50 };
        const planSuperlikesBase = planSuperlikesMap[subscriptionTier] ?? 0;
        const superLikesCount = receivedSuperLikes + planSuperlikesBase;

        // Check if the requesting user has already liked/superliked target user
        let isLiked = false;
        let isSuperLiked = false;
        let swipeStatus: string | null = null;
        if (shouldCheckRequester) {
            const userLikeAction = existingUserLike?.actionType;
            if (userLikeAction === 'superlike') {
                isLiked = true;
                isSuperLiked = true;
                swipeStatus = existingSwipe?.status || 'pending';
            } else if (userLikeAction === 'like') {
                isLiked = true;
                isSuperLiked = false;
                swipeStatus = existingSwipe?.status || 'pending';
            } else if (existingSwipe) {
                isLiked = ['pending', 'connected'].includes(existingSwipe.status as string);
                isSuperLiked = isLiked && existingSwipe.matchReason === 'superlike';
                swipeStatus = existingSwipe.status;
            }
        }

        return res.status(200).json({
            success: true,
            data: {
                // ── Core user fields ─────────────────────────────────────────
                id: user.id,
                isLiked,
                isSuperLiked,
                swipeStatus,
                superLikesCount,
                plansCount,
                subscriptionTier,
                bookingsCount,
                matchesCount,
                pointsCount,
                firstName: user.firstName,
                lastName: user.lastName,
                fullName: `${user.firstName} ${user.lastName}`,
                // Private contact/security fields are only ever returned to
                // the profile's own owner — never to another viewer.
                email: isOwnProfile ? user.email : null,
                phone: isOwnProfile ? user.phone : null,
                role: user.role,
                isVerified: user.isVerified,
                isActive: user.isActive,
                mfaEnabled: isOwnProfile ? user.mfaEnabled : null,
                dateOfBirth: (user as any).dateOfBirth ?? null,
                age,
                createdAt: user.createdAt,
                updatedAt: user.updatedAt,
                lastLoginAt: isOwnProfile ? ((user as any).lastLoginAt ?? null) : null,

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
                    profileCompletionPct: typeof profile.getCompletionPercentage === 'function' ? profile.getCompletionPercentage() : 0,
                    isProfileComplete: typeof profile.isProfileComplete === 'function' ? profile.isProfileComplete() : false,
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
                    minBudget: preferences.minBudget ?? null,
                    maxBudget: preferences.maxBudget ?? null,
                    budgetRange: preferences.budgetRange ?? null,
                    partyTimePreference: preferences.partyTimePreference ?? null,
                    groupSizePreference: preferences.groupSizePreference ?? null,
                    matchDistanceKm: preferences.matchDistanceKm,
                    showMeInMatching: preferences.showMeInMatching,
                    bookingAlertsEnabled: preferences.bookingAlertsEnabled,
                    isConfigured: typeof preferences.isConfigured === 'function' ? preferences.isConfigured() : false,
                    createdAt: preferences.createdAt,
                    updatedAt: preferences.updatedAt,
                } : null,
            },
        });
    } catch (error: any) {
        logger.error('[MobileUser] Error fetching profile for userId:', req.query.userId || req.user?.id, error?.stack || error?.message || error);
        return res.status(500).json({ success: false, message: 'Failed to retrieve profile', error: error?.message });
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
        const limitQuery = (req.query.limit as string)?.toLowerCase();
        const limit = (limitQuery === 'all' || limitQuery === '0')
            ? 1000
            : Math.min(1000, parseInt(req.query.limit as string) || 200);
        const offset = (page - 1) * limit;
        const search = (req.query.search as string)?.trim();
        const city = (req.query.city as string)?.trim();
        const isAllCities = req.query.allCities === 'true' || req.query.all_cities === 'true' || city === 'all';

        const currentUserId = req.user?.id || (req.query.currentUserId as string);
        const targetUserId = (req.query.userId as string)?.trim();

        // Build User-level where clause: include customers who are not soft-deleted
        const userWhere: any = {
            role: UserRole.CUSTOMER,
            isDeleted: false,
            isActive: { [Op.ne]: false },
        };

        // Exclude self or blocked users
        if (targetUserId && targetUserId !== 'undefined' && targetUserId !== 'null') {
            userWhere.id = targetUserId;
        } else {
            const excludeUserIds: string[] = [];
            const excludeSelf = req.query.excludeSelf === 'true' || req.query.excludeMe === 'true';
            if (excludeSelf && currentUserId) {
                excludeUserIds.push(currentUserId);
            }
            if (currentUserId) {
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
        }
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
        if (city && !isAllCities) {
            profileWhere[Op.or] = [
                { city: { [Op.iLike]: `%${city}%` } },
                { city: null },
                { city: '' }
            ];
        }

        // PHASE 1: Scoping and Scoring
        const matchingUsersRaw = await User.findAll({
            where: userWhere,
            attributes: ['id'],
            include: [
                {
                    model: UserProfile,
                    as: 'profile',
                    attributes: ['id'],
                    where: Object.keys(profileWhere).length ? profileWhere : undefined,
                    required: false,
                },
                {
                    model: UserPreference,
                    as: 'preferences',
                    attributes: ['id', 'showMeInMatching'],
                    required: false,
                },
            ],
            raw: true,
        });

        // Filter out users who hid their profile (showMeInMatching === false)
        // If targetUserId is explicitly requested (e.g. direct profile lookup), do not filter
        const visibleMatchingUsers = targetUserId
            ? matchingUsersRaw
            : matchingUsersRaw.filter((u: any) => {
                const show = u['preferences.showMeInMatching'] !== undefined
                    ? u['preferences.showMeInMatching']
                    : u.showMeInMatching;
                return show !== false && show !== 0 && show !== 'false';
            });

        const allUserIds = [...new Set(visibleMatchingUsers.map((u: any) => u.id))];
        const count = allUserIds.length;
        const totalPages = Math.ceil(count / limit);

        const mySwipesMap: Record<string, { status: string; matchReason: string }> = {};

        if (allUserIds.length > 0 && currentUserId) {
            const [mySwipes, myUserLikes] = await Promise.all([
                UserMatch.findAll({
                    where: {
                        user1Id: currentUserId,
                        user2Id: { [Op.in]: allUserIds }
                    }
                }),
                UserLike.findAll({
                    where: {
                        userId: currentUserId,
                        targetUserId: { [Op.in]: allUserIds }
                    }
                })
            ]);

            if (mySwipes && Array.isArray(mySwipes)) {
                mySwipes.forEach((s: any) => {
                    mySwipesMap[s.user2Id] = {
                        status: s.status,
                        matchReason: s.matchReason || 'like'
                    };
                });
            }

            // Merge UserLike rows into mySwipesMap
            if (myUserLikes && Array.isArray(myUserLikes)) {
                myUserLikes.forEach((l: any) => {
                    if (l && l.targetUserId) {
                        const existing = mySwipesMap[l.targetUserId];
                        const isSuper = l.actionType === 'superlike';
                        mySwipesMap[l.targetUserId] = {
                            status: existing?.status || 'pending',
                            matchReason: isSuper ? 'superlike' : (existing?.matchReason || 'like'),
                        };
                    }
                });
            }
        }

        const tierRankMap: Record<string, number> = { FREE: 0, CORE: 1, PLUS: 2, PRO: 3, ELITE: 4 };
        const rankingExplanations = await RankingService.computeRankings(allUserIds);
        const scoredUsers = rankingExplanations.map((exp) => ({
            id: exp.userId,
            rankScore: exp.finalRankScore,
            priorityTier: exp.priorityTier,
            likes: exp.rawMetrics.likesCount,
            superlikes: exp.rawMetrics.superlikesCount,
            plans: exp.rawMetrics.plansCount,
            boosts: exp.rawMetrics.hasActiveBoost ? 1 : 0,
            vipTier: exp.rawMetrics.vipTier || 'FREE',
            explainScore: exp.breakdown,
        }));

        const paginatedScoredUsers = scoredUsers.slice(offset, offset + limit);
        const paginatedUserIds = paginatedScoredUsers.map(u => u.id);

        // PHASE 2: Hydration
        let fullRows: any[] = [];
        if (paginatedUserIds.length > 0) {
            fullRows = await User.findAll({
                where: { id: { [Op.in]: paginatedUserIds } },
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
                    },
                    {
                        model: UserPhoto,
                        as: 'photos',
                        attributes: ['id', 'filePath', 'isPrimary', 'displayOrder'],
                        required: false,
                        where: { isPrimary: true },
                    },
                ],
            });
        }

        const userRowMap = new Map(fullRows.map((r: any) => [r.id, r]));

        const data = paginatedScoredUsers.map(scoredUser => {
            const user: any = userRowMap.get(scoredUser.id);
            if (!user) return null; // Shouldn't happen

            const age = user.dateOfBirth
                ? Math.floor((Date.now() - new Date(user.dateOfBirth).getTime()) / (365.25 * 24 * 60 * 60 * 1000))
                : null;

            const photo = user.photos?.[0];
            const photoUrl = photo
                ? '/' + photo.filePath.replace(/\\/g, '/')
                : (user.profileImageUrl ?? null);

            const mySwipe = mySwipesMap[user.id];
            const isLiked = !!mySwipe && ['pending', 'connected'].includes(mySwipe.status as string);
            const isSuperLiked = isLiked && mySwipe.matchReason === 'superlike';

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
                lastLoginAt: user.lastLoginAt ?? null,
                profile: user.profile ?? null,
                preferences: user.preferences ?? null,
                likesCount: scoredUser.likes,
                likeCount: scoredUser.likes,
                superLikesCount: scoredUser.superlikes,
                superLikeCount: scoredUser.superlikes,
                boostCount: scoredUser.boosts,
                boostsRemaining: scoredUser.boosts,
                isBoosted: scoredUser.boosts > 0,
                isVipActive: scoredUser.vipTier !== 'FREE',
                plansCount: scoredUser.plans ?? 0,
                activePartyPlanCount: scoredUser.plans ?? 0,
                doostCount: scoredUser.plans ?? 0,
                doost: scoredUser.plans ?? 0,
                points: undefined,
                rankScore: scoredUser.rankScore,
                rankingPriority: scoredUser.priorityTier,
                subscriptionTier: scoredUser.vipTier,
                tierRank: tierRankMap[scoredUser.vipTier] ?? 0,
                isLiked,
                isSuperLiked,
                swipeStatus: mySwipe?.status ?? null,
            };
        }).filter(Boolean); // Remove nulls if any

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

        // Unbind this device FCM token from any other accounts that used it previously
        await User.update(
            { fcmToken: null } as any,
            { where: { fcmToken: token, id: { [Op.ne]: userId } } }
        );

        await (user as any).update({ fcmToken: token });

        logger.info(`[FCM] Token registered for user ${userId} (platform: ${platform ?? 'unknown'})`);
        return res.status(200).json({ success: true, message: 'FCM token registered successfully' });
    } catch (error: any) {
        logger.error('[MobileUser] Error registering FCM token:', error);
        return res.status(500).json({ success: false, message: 'Failed to register FCM token' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/user/unregister-fcm-token
// ─────────────────────────────────────────────────────────────────────────────
export const unregisterFcmToken = async (req: Request, res: Response): Promise<Response> => {
    try {
        const { userId, token } = req.body;
        if (userId) {
            const user = await User.findByPk(userId);
            if (user) {
                await (user as any).update({ fcmToken: null });
            }
        }
        if (token) {
            await User.update(
                { fcmToken: null } as any,
                { where: { fcmToken: token } }
            );
        }
        logger.info(`[FCM] Token unregistered for user ${userId || 'unknown'}`);
        return res.status(200).json({ success: true, message: 'FCM token unregistered successfully' });
    } catch (error: any) {
        logger.error('[MobileUser] Error unregistering FCM token:', error);
        return res.status(500).json({ success: false, message: 'Failed to unregister FCM token' });
    }
};


// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/user/block
// ─────────────────────────────────────────────────────────────────────────────
export const blockUser = async (req: Request, res: Response): Promise<Response> => {
    try {
        const userId = req.user?.id || req.body.userId;
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
            } else {
                targetUser.isAutoblocked = false;
                targetUser.autoblockedReason = null;
                if (!targetUser.isDeleted) {
                    targetUser.isActive = true;
                }
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
        const userId = req.user?.id || req.body.userId;
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
            if (count >= 10) {
                targetUser.isAutoblocked = true;
                targetUser.autoblockedReason = `Autoblocked due to receiving ${count} blocks from other users.`;
                targetUser.isActive = false;
            } else {
                targetUser.isAutoblocked = false;
                targetUser.autoblockedReason = null;
                if (!targetUser.isDeleted) {
                    targetUser.isActive = true;
                }
            }
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
        const userId = req.user?.id || req.body.userId;
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
            } else {
                targetUser.isAutoblocked = false;
                targetUser.autoblockedReason = null;
                if (!targetUser.isDeleted) {
                    targetUser.isActive = true;
                }
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
        const userId = req.user?.id || (req.query.userId as string);
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
        const userId = req.user?.id || (req.query.userId as string);
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

        // 0. Parallel initial lookups: Block validation, permanent like record, and existing swipe lookups
        const [isBlocked, existingMySwipe, existingOppositeSwipe] = await Promise.all([
            SocialConnection.findOne({
                where: {
                    [Op.or]: [
                        { requesterId: userId, receiverId: targetUserId, status: ConnectionStatus.BLOCKED },
                        { requesterId: targetUserId, receiverId: userId, status: ConnectionStatus.BLOCKED },
                    ]
                }
            }).catch(blockErr => {
                logger.warn('[swipeUser] Failed to check block status:', blockErr);
                return null;
            }),
            UserMatch.findOne({
                where: {
                    user1Id: userId,
                    user2Id: targetUserId,
                }
            }),
            UserMatch.findOne({
                where: {
                    user1Id: targetUserId,
                    user2Id: userId,
                }
            }),
        ]);

        if (isBlocked) {
            return res.status(403).json({ success: false, message: 'Cannot interact with this user.' });
        }

        // 0.5 Save permanent profile like/superlike record in UserLike table asynchronously
        UserLike.upsert({
            userId,
            targetUserId,
            actionType: action,
        }).catch(dbErr => {
            logger.warn('[swipeUser] Failed to upsert UserLike:', dbErr);
        });

        // Helper to check swipe types
        const isSuperlikeRecord = (swipe: any) => swipe && swipe.matchReason === 'superlike';
        const isLikeRecord = (swipe: any) => swipe && swipe.status !== 'declined' && swipe.matchReason !== 'superlike';
        const isNopeRecord = (swipe: any) => swipe && swipe.status === 'declined';

        // 1. If duplicate swipe action on existing record, retain it permanently (do NOT delete)
        if (existingMySwipe) {
            const isDuplicateLike = (action === 'like' && (isLikeRecord(existingMySwipe) || isSuperlikeRecord(existingMySwipe)));
            const isDuplicateSuperlike = (action === 'superlike' && isSuperlikeRecord(existingMySwipe));
            const isDuplicateNope = (action === 'nope' && isNopeRecord(existingMySwipe));

            if (isDuplicateLike || isDuplicateSuperlike || isDuplicateNope) {
                return res.status(200).json({
                    success: true,
                    message: `Already ${action}d`,
                    data: existingMySwipe,
                    matched: existingMySwipe.status === 'connected',
                    action: 'retained',
                });
            }
        }

        // 1.5 Enforce subscription limit checks for Like / Superlike with 75% Threshold Alert
        let usageWarning: {
            triggered: boolean;
            feature: string;
            used: number;
            limit: number | string;
            remaining: number | string;
            percentage: number;
            message: string;
        } | null = null;

        if (action === 'like') {
            const SubscriptionService = require('../services/subscriptionService').default || require('../services/subscriptionService').SubscriptionService;
            const isUnlimitedLikes = (await SubscriptionService.getLimit(userId, 'daily_likes')) === 'unlimited';
            if (isUnlimitedLikes) {
                // Unlimited VIP like: background tracking, zero limits, zero warnings
                SubscriptionService.incrementUsage(userId, 'daily_likes', 'DAILY', 1).catch(() => {});
            } else {
                const consume = await SubscriptionService.consumeUsage(userId, 'daily_likes');
                if (!consume.success) {
                    return res.status(403).json({
                        success: false,
                        code: 'LIMIT_REACHED',
                        limitReached: true,
                        message: consume.message || 'You have reached your daily likes limit. Upgrade to Lunara VIP for unlimited likes!'
                    });
                }

                if (typeof consume.limit === 'number' && consume.limit > 0 && consume.limit < 9999) {
                    const used = consume.used;
                    const limit = consume.limit;
                    const remaining = typeof consume.remaining === 'number' ? consume.remaining : limit - used;
                    const percentage = Math.round((used / limit) * 100);

                    // If user has used >= 70% of daily likes (e.g. 5 of 7 is 71.4%):
                    if (percentage >= 70 && remaining > 0) {
                        usageWarning = {
                            triggered: true,
                            feature: 'daily_likes',
                            used,
                            limit,
                            remaining,
                            percentage,
                            message: `You've used ${used} of ${limit} Daily Likes today. Only ${remaining} remaining!`,
                        };

                        // Persist In-App Notification (throttled once per day)
                        try {
                            const NotificationModel = (await import('../models/Notification')).default;
                            const todayStr = new Date().toISOString().split('T')[0];
                            const idempotencyKey = `limit_warn_like_${userId}_${todayStr}`;
                            const existingNotif = await NotificationModel.findOne({ where: { idempotencyKey } });
                            if (!existingNotif) {
                                await NotificationModel.create({
                                    recipientUserId: userId,
                                    eventType: 'LIMIT_WARNING',
                                    category: 'system' as any,
                                    title: '❤️ Daily Likes Warning',
                                    body: `You've used ${used} of ${limit} daily likes today. Upgrade to Lunara VIP for unlimited likes!`,
                                    actionType: 'open_vip_upgrade',
                                    deepLink: '/vip-membership',
                                    isRead: false,
                                    priority: 'NORMAL' as any,
                                    idempotencyKey,
                                });
                            }
                        } catch (notifErr) {
                            logger.warn('[swipeUser] Failed to create like limit notification:', notifErr);
                        }
                    }
                }
            }
        } else if (action === 'superlike') {
            const consumption = await EntitlementService.consumeFeatureEntitlement(userId, 'superlike', 1, {
                requestId: `SUPERLIKE_${userId}_${targetUserId}_${Date.now()}`,
                metadata: { targetUserId },
            });

            if (!consumption.success) {
                return res.status(403).json({
                    success: false,
                    code: consumption.code || 'ADDON_REQUIRED',
                    limitReached: true,
                    message: consumption.message || 'You have no super likes remaining. Upgrade your plan or purchase more super likes!',
                    availableAddons: consumption.availableAddons || [],
                });
            }

            const activeSub = await UserSubscription.findOne({
                where: {
                    userId,
                    status: { [Op.in]: [SubscriptionStatus.ACTIVE, 'ACTIVE', 'active'] },
                    endDate: { [Op.gt]: new Date() },
                },
                include: [{ model: SubscriptionPackage, as: 'package' }],
                order: [['createdAt', 'DESC']],
            });

            const isEliteTier = (activeSub as any)?.package?.tier === 'ELITE' || consumption.totalRemaining === 9999;
            const totalGranted = (activeSub as any)?.package?.superlikesPerCycle || 0;
            const remaining = consumption.totalRemaining ?? 0;

            if (!isEliteTier && totalGranted > 0 && totalGranted < 9999) {
                const used = Math.max(0, totalGranted - remaining);
                const percentage = Math.round((used / totalGranted) * 100);

                if (percentage >= 66) {
                    usageWarning = {
                        triggered: true,
                        feature: 'superlike',
                        used,
                        limit: totalGranted,
                        remaining,
                        percentage,
                        message: `You've used ${used} of ${totalGranted} Super Likes for this cycle. ${remaining > 0 ? `Only ${remaining} remaining!` : 'None remaining.'}`,
                    };

                    // Create In-App Notification
                    try {
                        const NotificationModel = (await import('../models/Notification')).default;
                        const cycleKey = `limit_warn_superlike_${userId}_${activeSub?.id || 'cycle'}_${used}`;
                        const existingNotif = await NotificationModel.findOne({ where: { idempotencyKey: cycleKey } });
                        if (!existingNotif) {
                            await NotificationModel.create({
                                recipientUserId: userId,
                                eventType: 'LIMIT_WARNING',
                                category: 'system' as any,
                                title: '⭐ Super Likes Usage Alert',
                                body: `You've used ${used} of ${totalGranted} Super Likes for your current plan. Top up credits or upgrade to Plus/Pro for more!`,
                                actionType: 'open_vip_upgrade',
                                deepLink: '/vip-membership',
                                isRead: false,
                                priority: 'NORMAL' as any,
                                idempotencyKey: cycleKey,
                            });
                        }
                    } catch (notifErr) {
                        logger.warn('[swipeUser] Failed to create superlike limit notification:', notifErr);
                    }
                }
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
                    usageWarning,
                });
            } catch (chatErr) {
                logger.error('[swipeUser] Failed to init free chat, but match still created:', chatErr);
            }

            return res.status(200).json({ success: true, data: mySwipe, matched: true, usageWarning });
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
                const { SubscriptionService } = require('../services/subscriptionService');
                const canSeeWhoLikedTarget = await SubscriptionService.hasAccess(targetUserId, 'who_liked_me');
                
                const senderName = `${currentUser.firstName || ''} ${currentUser.lastName || ''}`.trim() || 'Someone';
                const isSuper = action === 'superlike';
                
                const title = isSuper
                    ? (canSeeWhoLikedTarget ? `⭐ ${senderName} Super Liked You!` : '⭐ Someone Super Liked You')
                    : (canSeeWhoLikedTarget ? `💖 ${senderName} liked your profile!` : '❤️ Someone liked your profile');
                    
                const body = isSuper 
                    ? (canSeeWhoLikedTarget ? `${senderName} sent you a Super Like! 💜` : 'Someone sent you a Super Like! Upgrade to VIP to see who!')
                    : (canSeeWhoLikedTarget ? `${senderName} liked your profile ❤️` : 'Someone liked your profile! Upgrade to VIP to see who!');

                let postedPlans: any[] = [];
                if (isSuper && canSeeWhoLikedTarget) {
                    try {
                        const activePlans = await PartyPlan.findAll({
                            where: {
                                userId: currentUser.id,
                                status: 'active',
                                isLive: true,
                                planDateTime: { [Op.gte]: new Date() },
                                visibility: 'public',
                            },
                            include: [{ model: Venue, as: 'venue', attributes: ['id', 'name', 'addressLine1', 'area', 'city'] }],
                            order: [['planDateTime', 'ASC']],
                            limit: 3,
                        });
                        postedPlans = activePlans.map((p: any) => ({
                            id: p.id,
                            title: `Let's party at ${p.venue?.name || 'Venue'}! 🚀`,
                            venueName: p.venue?.name || 'Venue',
                            planDateTime: p.planDateTime,
                            status: p.status,
                            isLive: p.isLive,
                        }));
                    } catch (planErr) {
                        logger.warn('[swipeUser] Failed to fetch sender posted plans:', planErr);
                    }
                }

                const dedupeKey = isSuper ? `SUPERLIKE:${match.id}` : `LIKE:${match.id}`;

                try {
                    await Notification.findOrCreate({
                        where: {
                            recipientUserId: targetUserId,
                            entityType: 'user_match',
                            entityId: match.id,
                        },
                        defaults: {
                            recipientUserId: targetUserId,
                            actorUserId: currentUser.id,
                            title,
                            body,
                            category: isSuper ? 'super_like' : 'likes',
                            eventType: isSuper ? 'super_like' : 'like',
                            actionType: canSeeWhoLikedTarget ? 'view_profile' : 'open_vip_upgrade',
                            entityType: 'user_match',
                            entityId: match.id,
                            isRead: false,
                            priority: (isSuper ? 'HIGH' : 'NORMAL') as any,
                            deepLink: canSeeWhoLikedTarget ? `/profile/${currentUser.id}` : '/vip-membership',
                            idempotencyKey: dedupeKey,
                            metadata: canSeeWhoLikedTarget ? {
                                matchId: match.id,
                                senderId: currentUser.id,
                                senderName,
                                senderImage: currentUser.profileImageUrl || '',
                                postedPlans,
                                action: isSuper ? 'superlike' : 'like',
                            } : {
                                matchId: match.id,
                                isMasked: true,
                                action: isSuper ? 'superlike' : 'like',
                            },
                        }
                    });
                } catch (dbNotifErr) {
                    logger.warn('[swipeUser] Failed to persist like/superlike notification:', dbNotifErr);
                }

                const { io } = require('../server');
                if (io) {
                    io.to(`user_${targetUserId}`).emit('notification_created', {
                        id: `match_${match.id}`,
                        title,
                        body,
                        category: isSuper ? 'super_like' : 'likes',
                        type: isSuper ? 'super_like' : 'like',
                        createdAt: new Date().toISOString(),
                        read: false,
                        sender: canSeeWhoLikedTarget ? {
                            id: currentUser.id,
                            firstName: currentUser.firstName,
                            lastName: currentUser.lastName,
                            profileImageUrl: currentUser.profileImageUrl,
                        } : {
                            id: 'masked',
                            firstName: 'Someone',
                            lastName: '',
                            profileImageUrl: 'https://placehold.co/400x400/2a1b38/e0a0ff.png?text=Upgrade+to+See',
                        },
                        data: canSeeWhoLikedTarget ? {
                            matchId: match.id,
                            senderId: currentUser.id,
                            senderName,
                            senderImage: currentUser.profileImageUrl || '',
                            postedPlans,
                            action: isSuper ? 'superlike' : 'like',
                        } : {
                            matchId: match.id,
                            isMasked: true,
                            action: isSuper ? 'superlike' : 'like',
                        }
                    });

                    // Emit real-time like_received event for live UI synchronization
                    io.to(`user_${targetUserId}`).emit('like_received', {
                        matchId: match.id,
                        likerId: canSeeWhoLikedTarget ? currentUser.id : 'masked',
                        isSuper,
                        timestamp: new Date().toISOString(),
                    });
                }

                if (targetUser.fcmToken) {
                    const { sendPushNotification } = require('../services/fcmService');
                    await sendPushNotification(targetUser.fcmToken, {
                        title,
                        body,
                        data: canSeeWhoLikedTarget ? {
                            type: isSuper ? 'superlike' : 'like',
                            senderId: currentUser.id,
                            senderName,
                            senderImage: currentUser.profileImageUrl || '',
                        } : {
                            type: isSuper ? 'superlike' : 'like',
                            isMasked: 'true',
                        }
                    });
                }
            }
        } catch (fcmErr) {
            logger.error('[swipeUser] Failed to send push notification/socket:', fcmErr);
        }

        return res.status(200).json({ success: true, data: match, matched: false, usageWarning });

    } catch (error: any) {
        logger.error('[MobileUser] Error processing swipe:', error);
        return res.status(500).json({ success: false, message: 'Failed to process swipe' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/user/unlike
// ─────────────────────────────────────────────────────────────────────────────
export const unlikeUser = async (req: Request, res: Response): Promise<Response> => {
    try {
        const userId = req.user?.id || req.body.userId;
        const { targetUserId } = req.body;

        if (!userId || !targetUserId) {
            return res.status(400).json({ success: false, message: 'userId and targetUserId are required' });
        }

        if (String(userId) === String(targetUserId)) {
            return res.status(400).json({ success: false, message: 'Cannot target yourself' });
        }

        // Delete UserLike record
        await UserLike.destroy({
            where: { userId, targetUserId }
        });

        // Update UserMatch record if present
        const existingMatch = await UserMatch.findOne({
            where: { user1Id: userId, user2Id: targetUserId }
        });

        if (existingMatch) {
            existingMatch.status = 'declined' as any;
            await existingMatch.save();
        }

        // Log engagement event
        const { EngagementService } = await import('../services/engagementService');
        await EngagementService.logLikeRemoved(userId, targetUserId);

        // Emit Socket event to target user
        try {
            const { io } = require('../server');
            if (io) {
                io.to(`user_${targetUserId}`).emit('like_removed', {
                    senderId: userId,
                    targetUserId,
                });
            }
        } catch (_) {}

        return res.status(200).json({ success: true, message: 'Like removed successfully' });
    } catch (error: any) {
        logger.error('[MobileUser] Error in unlikeUser:', error);
        return res.status(500).json({ success: false, message: 'Server error' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/user/likes-matches
// Returns a list of swipes/matches involving this user
// ─────────────────────────────────────────────────────────────────────────────
export const getMyLikesAndMatches = async (req: Request, res: Response): Promise<Response> => {
    try {
        const userId = req.user?.id || (req.query.userId as string);
        if (!userId) {
            return res.status(400).json({ success: false, message: 'userId is required' });
        }

        const { SubscriptionService } = require('../services/subscriptionService');
        const canSeeWhoLiked = await SubscriptionService.hasAccess(userId, 'who_liked_me');

        const matches = await UserMatch.findAll({
            where: {
                [Op.or]: [
                    { user1Id: userId },
                    { user2Id: userId }
                ]
            },
            include: [
                {
                    model: User,
                    as: 'user1',
                    attributes: ['id', 'firstName', 'lastName', 'profileImageUrl']
                },
                {
                    model: User,
                    as: 'user2',
                    attributes: ['id', 'firstName', 'lastName', 'profileImageUrl']
                }
            ],
            order: [['createdAt', 'DESC']],
        });

        // Strictly protect Free users from receiving sender identity
        const processed = matches.map((m: any) => {
            const json = m.toJSON();
            const isIncomingPendingLike = json.user2Id === userId && json.status === 'pending';

            if (isIncomingPendingLike && !canSeeWhoLiked) {
                return {
                    ...json,
                    user1Id: 'masked',
                    isMasked: true,
                    user1: {
                        id: 'masked',
                        firstName: 'Someone',
                        lastName: '',
                        profileImageUrl: 'https://placehold.co/400x400/2a1b38/e0a0ff.png?text=Upgrade+to+See',
                    }
                };
            }
            return {
                ...json,
                isMasked: false,
            };
        });

        return res.status(200).json({ success: true, data: processed, canSeeWhoLiked });
    } catch (error: any) {
        logger.error('[MobileUser] Error fetching matches:', error);
        return res.status(500).json({ success: false, message: 'Failed to fetch matches' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/user/who-liked-summary
// Returns teaser count of people who liked the current user in the last 7 days
// ─────────────────────────────────────────────────────────────────────────────
export const getWhoLikedSummary = async (req: Request, res: Response): Promise<Response> => {
    try {
        const userId = req.user?.id || (req.query.userId as string);
        if (!userId) {
            return res.status(400).json({ success: false, message: 'userId is required' });
        }

        const { SubscriptionService } = require('../services/subscriptionService');
        const canSeeWhoLiked = await SubscriptionService.hasAccess(userId, 'who_liked_me');

        const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);

        // Count incoming likes from user_likes table within 7 days where receiver is this user
        const count = await UserLike.count({
            where: {
                targetUserId: userId,
                actionType: { [Op.in]: ['like', 'superlike'] },
                createdAt: { [Op.gte]: sevenDaysAgo },
            },
        });

        const superlikesCount = await UserLike.count({
            where: {
                targetUserId: userId,
                actionType: 'superlike',
                createdAt: { [Op.gte]: sevenDaysAgo },
            },
        });

        return res.status(200).json({
            success: true,
            data: {
                count,
                superlikesCount,
                periodDays: 7,
                canSeeWhoLiked,
            },
        });
    } catch (error: any) {
        logger.error('[MobileUser] Error in getWhoLikedSummary:', error);
        return res.status(500).json({ success: false, message: 'Server error' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/user/who-liked-me
// Dedicated endpoint for VIP users to view people who liked them
// ─────────────────────────────────────────────────────────────────────────────
export const getPeopleWhoLikedMe = async (req: Request, res: Response): Promise<Response> => {
    try {
        const userId = req.user?.id || (req.query.userId as string);
        if (!userId) {
            return res.status(400).json({ success: false, message: 'userId is required' });
        }

        const { SubscriptionService } = require('../services/subscriptionService');
        const canSeeWhoLiked = await SubscriptionService.hasAccess(userId, 'who_liked_me');

        if (!canSeeWhoLiked) {
            return res.status(403).json({
                success: false,
                code: 'VIP_REQUIRED',
                message: 'Upgrade to Lunara VIP to see who liked you!',
            });
        }

        const page = parseInt(req.query.page as string) || 1;
        const limit = parseInt(req.query.limit as string) || 20;
        const offset = (page - 1) * limit;

        const { count, rows } = await UserLike.findAndCountAll({
            where: {
                targetUserId: userId,
                actionType: { [Op.in]: ['like', 'superlike'] },
            },
            include: [
                {
                    model: User,
                    as: 'user',
                    attributes: ['id', 'firstName', 'lastName', 'profileImageUrl', 'city', 'age', 'occupation', 'interests', 'bio'],
                },
            ],
            order: [['createdAt', 'DESC']],
            limit,
            offset,
        });

        // Check mutual match state for each profile
        const senderIds = rows.map((r: any) => r.userId);
        const myLikes = await UserLike.findAll({
            where: {
                userId,
                targetUserId: { [Op.in]: senderIds },
            },
        });
        const myLikedSet = new Set(myLikes.map((l: any) => l.targetUserId));

        const data = rows.map((r: any) => {
            const senderUser = (r as any).user;
            const senderId = r.userId;
            const isMutual = myLikedSet.has(senderId);

            return {
                id: senderUser?.id || senderId,
                name: `${senderUser?.firstName || ''} ${senderUser?.lastName || ''}`.trim().toUpperCase() || 'LUNARA MEMBER',
                firstName: senderUser?.firstName || '',
                lastName: senderUser?.lastName || '',
                age: senderUser?.age || 25,
                city: senderUser?.city || '',
                vibe: (senderUser?.occupation || 'Night Owl').toUpperCase(),
                image: senderUser?.profileImageUrl || 'https://picsum.photos/400/600',
                interests: senderUser?.interests || [],
                bio: senderUser?.bio || '',
                actionType: r.actionType,
                likedAt: r.createdAt,
                isSuperLike: r.actionType === 'superlike',
                isMutualMatch: isMutual,
            };
        });

        return res.status(200).json({
            success: true,
            data,
            pagination: {
                page,
                limit,
                total: count,
                totalPages: Math.ceil(count / limit),
            },
        });
    } catch (error: any) {
        logger.error('[MobileUser] Error in getPeopleWhoLikedMe:', error);
        return res.status(500).json({ success: false, message: 'Server error' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/user/swipe-status
// Returns whether the current user has already liked/superliked a target today,
// and the plan's daily limits so the UI can enforce them dynamically.
// ─────────────────────────────────────────────────────────────────────────────
export const getSwipeStatus = async (req: Request, res: Response): Promise<Response> => {
    try {
        const userId = req.user?.id || (req.query.userId as string);
        const targetUserId = req.query.targetUserId as string;

        if (!userId || !targetUserId) {
            return res.status(400).json({ success: false, message: 'userId and targetUserId are required' });
        }

        // Check UserLike table for permanent persistent like/superlike state
        const swipeActionRecord = await UserLike.findOne({
            where: {
                userId,
                targetUserId,
            }
        });

        // Check all-time swipe on this specific target (persists across days & refreshes)
        const existingSwipe = await UserMatch.findOne({
            where: {
                user1Id: userId,
                user2Id: targetUserId,
            }
        });

        const actionType = swipeActionRecord?.actionType || (existingSwipe?.matchReason === 'superlike' ? 'superlike' : existingSwipe?.status === 'declined' ? 'nope' : existingSwipe ? 'like' : null);
        const alreadyLiked = actionType === 'like' || actionType === 'superlike' || (!!existingSwipe && ['pending', 'connected'].includes(existingSwipe.status as string));
        const alreadySuperLiked = actionType === 'superlike' || (alreadyLiked && existingSwipe?.matchReason === 'superlike');
        const alreadyNoped = actionType === 'nope' || actionType === 'dislike' || (!!existingSwipe && existingSwipe.status === 'declined');

        // Daily likes: use the exact same SubscriptionService accessors that
        // swipeUser's consumeUsage('daily_likes') gate enforces, so the
        // displayed remaining count never drifts from what will actually be
        // allowed (previously this recomputed usage independently by
        // counting today's UserMatch rows, which could disagree with the
        // SubscriptionUsage-tracked count consumeUsage relies on).
        let dailyLikesLimit = 3;
        let todayLikeCount = 0;
        let superlikesRemaining = 0;
        let superlikesPerCycle = 0;

        try {
            const { SubscriptionService } = require('../services/subscriptionService');
            const limit = await SubscriptionService.getLimit(userId, 'daily_likes');
            const remaining = await SubscriptionService.getRemainingUsage(userId, 'daily_likes');
            dailyLikesLimit = limit === 'unlimited' ? 999999 : limit;
            const remainingNum = remaining === 'unlimited' ? dailyLikesLimit : remaining;
            todayLikeCount = Math.max(0, dailyLikesLimit - remainingNum);
        } catch (limitErr) {
            logger.warn('[swipeStatus] Could not fetch daily like limits:', limitErr);
        }

        try {
            const summary = await EntitlementService.getEntitlementsSummary(userId);
            const rawSuper = summary.totals.superlikesAvailable as any;
            superlikesRemaining = rawSuper === 'unlimited' ? 999999 : (Number(rawSuper) || 0);
            const superlikeItem = summary.planBenefits.find(b => b.featureKey === 'superlike');
            superlikesPerCycle = superlikeItem?.includedQuantity || 0;
        } catch (subErr) {
            logger.warn('[swipeStatus] Could not fetch entitlement summary:', subErr);
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
        const userId = req.user?.id || req.body.userId;
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

        // Destroy UserLike record on backtrack
        try {
            await UserLike.destroy({
                where: {
                    userId,
                    targetUserId,
                }
            });
        } catch (delErr) {
            logger.warn('[backtrackSwipe] Failed to destroy UserLike:', delErr);
        }

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
        const userId = req.user?.id || req.body.userId;
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

        // ── 3.5. Check for any pending/active plans ────────────────────────────
        const pendingPartyPlan = await PartyPlan.findOne({ where: { userId, status: 'active' } });
        const pendingPlan = await Plan.findOne({ where: { userId, status: { [Op.in]: ['active', 'full', 'secured'] } } });
        const pendingBooking = await Booking.findOne({ where: { userId, status: { [Op.in]: ['pending', 'confirmed'] } } });
        const pendingGroupParty = await GroupParty.findOne({ where: { userId, status: { [Op.in]: ['pending', 'approved', 'confirmed'] } } });
        const pendingStrangersMeet = await StrangersMeetRequest.findOne({ where: { userId, status: { [Op.in]: ['pending', 'approved'] } } });

        if (pendingPartyPlan || pendingPlan || pendingBooking || pendingGroupParty || pendingStrangersMeet) {
            return res.status(400).json({
                success: false,
                code: 'PENDING_PLANS',
                message: 'You have active plans or bookings. Please complete or cancel them before deleting your account.',
            });
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

        // ── 6. Soft-delete: mark as deleted, deactivate, clear sensitive tokens, release email/phone ─
        const deleteTimestamp = Date.now();
        await user.update({
            isDeleted: true,
            isActive: false,
            deletedAt: new Date(),
            deletionReason: reason?.trim() ?? null,
            fcmToken: null,   // Stop all push notifications immediately
            email: `deleted_${deleteTimestamp}_${user.email}`,
            phone: `deleted_${deleteTimestamp}_${user.phone}`,
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
    unregisterFcmToken,
    blockUser,
    unblockUser,
    reportUser,
    getBlockedUsers,
    getBlockedUsersDetails,
    swipeUser,
    unlikeUser,
    getMyLikesAndMatches,
    getWhoLikedSummary,
    getPeopleWhoLikedMe,
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
