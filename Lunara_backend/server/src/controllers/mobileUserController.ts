import { Request, Response } from 'express';
import path from 'path';
import fs from 'fs';
import crypto from 'crypto';
import sharp from 'sharp';
import { UserProfile, UserPreference, UserPhoto, UserMatch, Plan, Venue, PartyPlan, Booking, GroupParty, StrangersMeetRequest } from '../models';
import { RewardPointsService } from '../services/rewardPointsService';
import Notification from '../models/Notification';
import UserLike from '../models/UserLike';
import User, { UserRole } from '../models/User';
import DeletedAccount from '../models/DeletedAccount';
import UserSubscription, { SubscriptionStatus } from '../models/UserSubscription';
import SubscriptionPackage from '../models/SubscriptionPackage';
import bcrypt from 'bcryptjs';

import { logger } from '../config/logger';
import { Op, QueryTypes } from 'sequelize';
import sequelize from '../config/database';
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

        // Fetch updated profile (parallel — was sequential)
        const [updatedProfile, updatedPreferences] = await Promise.all([
            UserProfile.findOne({ where: { userId } }),
            UserPreference.findOne({ where: { userId } }),
        ]);

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

        // Fetch all profile components and metrics in a single parallel batch of 3-4 optimized queries
        const requesterUserId = req.user?.id || (req.query.currentUserId as string);
        const shouldCheckRequester = !!(requesterUserId && requesterUserId !== userId);

        const [
            userWithProfile,
            activeSub,
            metricsResult,
            matchedPartnersResult,
            existingSwipe,
            existingUserLike,
            existingUserSuperLike,
        ] = await Promise.all([
            User.findByPk(userId, {
                attributes: [
                    'id', 'firstName', 'lastName', 'email', 'phone', 'profileImageUrl',
                    'role', 'isVerified', 'isActive', 'mfaEnabled',
                    'createdAt', 'updatedAt', 'lastLoginAt', 'dateOfBirth', 'rewardPoints'
                ],
                include: [
                    { model: UserProfile, as: 'profile' },
                    { model: UserPreference, as: 'preferences' },
                    {
                        model: UserPhoto,
                        as: 'photos',
                        attributes: ['id', 'filePath', 'fileSize', 'mimeType', 'isPrimary', 'displayOrder', 'uploadedAt'],
                        required: false,
                    }
                ],
                order: [
                    [{ model: UserPhoto, as: 'photos' }, 'isPrimary', 'DESC'],
                    [{ model: UserPhoto, as: 'photos' }, 'displayOrder', 'ASC'],
                    [{ model: UserPhoto, as: 'photos' }, 'uploadedAt', 'DESC'],
                ]
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
            sequelize.query(`
                SELECT 
                    (SELECT COUNT(*)::int FROM user_likes WHERE target_user_id::text = :userId AND action_type = 'like') AS likes_count,
                    (
                        (SELECT COUNT(*)::int FROM user_likes WHERE target_user_id::text = :userId AND action_type = 'superlike') + 
                        (SELECT COUNT(*)::int FROM user_matches WHERE user2_id::text = :userId AND match_reason = 'superlike' AND status::text IN ('pending', 'connected'))
                    ) AS superlikes_count,
                    (SELECT COUNT(*)::int FROM party_plans WHERE user_id::text = :userId AND status::text != 'cancelled') AS party_plans_count,
                    (SELECT COUNT(*)::int FROM strangers_meet_requests WHERE user_id::text = :userId AND status::text NOT IN ('cancelled', 'rejected')) AS strangers_meet_count,
                    (SELECT COUNT(*)::int FROM group_parties WHERE user_id::text = :userId AND status::text NOT IN ('cancelled', 'rejected', 'expired')) AS group_party_count,
                    (
                        (SELECT COUNT(*)::int FROM tickets WHERE user_id::text = :userId) +
                        (SELECT COUNT(*)::int FROM bookings WHERE user_id::text = :userId) +
                        (SELECT COUNT(*)::int FROM group_parties WHERE user_id::text = :userId) +
                        (SELECT COUNT(*)::int FROM strangers_meet_requests WHERE user_id::text = :userId) +
                        (SELECT COUNT(*)::int FROM strangers_meet_joiners WHERE user_id::text = :userId AND status::text != 'rejected') +
                        (SELECT COUNT(*)::int FROM party_plans WHERE user_id::text = :userId AND status::text != 'cancelled') +
                        (SELECT COUNT(*)::int FROM party_plan_requests WHERE requester_id::text = :userId AND status::text = 'accepted')
                    ) AS total_bookings;
            `, { replacements: { userId }, type: QueryTypes.SELECT }).catch((err) => {
                logger.error('[MobileUser] Error fetching profile metrics:', err);
                return [{}];
            }),
            sequelize.query(`
                SELECT DISTINCT partner_id FROM (
                    SELECT CASE WHEN user1_id::text = :userId THEN user2_id::text ELSE user1_id::text END AS partner_id 
                    FROM user_matches 
                    WHERE (user1_id::text = :userId OR user2_id::text = :userId) 
                      AND status::text IN ('connected', 'matched')
                    UNION
                    SELECT CASE WHEN host_id::text = :userId THEN partner_id::text ELSE host_id::text END AS partner_id 
                    FROM night_partner_matches 
                    WHERE (host_id::text = :userId OR partner_id::text = :userId) 
                      AND status::text IN ('MATCHED', 'PAYMENT_PENDING', 'CONFIRMED')
                    UNION
                    SELECT ppr.requester_id::text AS partner_id 
                    FROM party_plan_requests ppr 
                    JOIN party_plans pp ON pp.id = ppr.plan_id 
                    WHERE pp.user_id::text = :userId 
                      AND ppr.status::text IN ('accepted', 'payment_pending')
                    UNION
                    SELECT pp.user_id::text AS partner_id 
                    FROM party_plan_requests ppr 
                    JOIN party_plans pp ON pp.id = ppr.plan_id 
                    WHERE ppr.requester_id::text = :userId 
                      AND ppr.status::text IN ('accepted', 'payment_pending')
                    UNION
                    SELECT CASE WHEN requester_id::text = :userId THEN receiver_id::text ELSE requester_id::text END AS partner_id 
                    FROM social_connections 
                    WHERE (requester_id::text = :userId OR receiver_id::text = :userId) 
                      AND status::text = 'accepted'
                    UNION
                    SELECT sm.user_id::text AS partner_id 
                    FROM strangers_meet_joiners smj 
                    JOIN strangers_meet_requests sm ON sm.id = smj.strangers_meet_request_id 
                    WHERE smj.user_id::text = :userId 
                      AND smj.status::text NOT IN ('rejected', 'cancelled')
                    UNION
                    SELECT smj.user_id::text AS partner_id 
                    FROM strangers_meet_joiners smj 
                    JOIN strangers_meet_requests sm ON sm.id = smj.strangers_meet_request_id 
                    WHERE sm.user_id::text = :userId 
                      AND smj.status::text NOT IN ('rejected', 'cancelled')
                ) partners 
                WHERE partner_id IS NOT NULL AND partner_id != :userId;
            `, { replacements: { userId }, type: QueryTypes.SELECT }).catch((err) => {
                logger.error('[MobileUser] Error fetching matched partners list:', err);
                return [];
            }),
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
                        targetUserId: userId,
                        actionType: 'like'
                    }
                }).catch(() => null)
                : Promise.resolve(null),
            shouldCheckRequester
                ? UserLike.findOne({
                    where: {
                        userId: requesterUserId,
                        targetUserId: userId,
                        actionType: 'superlike'
                    }
                }).catch(() => null)
                : Promise.resolve(null),
        ]);

        const user = userWithProfile;
        if (!user) {
            return res.status(404).json({ success: false, message: 'User not found' });
        }

        const profile = (user as any).profile || null;
        const preferences = (user as any).preferences || null;
        const allPhotos = (user as any).photos || [];

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
        const photos = allPhotos.map((p: any) => ({
            id: p.id,
            url: '/' + p.filePath.replace(/\\/g, '/'),
            filePath: p.filePath,
            fileSize: p.fileSize,
            mimeType: p.mimeType,
            isPrimary: p.isPrimary,
            displayOrder: p.displayOrder,
            uploadedAt: p.uploadedAt,
        }));

        const metricsRow = Array.isArray(metricsResult) && metricsResult.length > 0 ? (metricsResult[0] as any) : (metricsResult as any) || {};
        const likesCount = parseInt(metricsRow.likes_count || '0', 10);
        const receivedSuperLikes = parseInt(metricsRow.superlikes_count || '0', 10);
        const partyPlansCnt = parseInt(metricsRow.party_plans_count || '0', 10);
        const strangersMeetCnt = parseInt(metricsRow.strangers_meet_count || '0', 10);
        const groupPartyCnt = parseInt(metricsRow.group_party_count || '0', 10);
        const bookingsCount = parseInt(metricsRow.total_bookings || '0', 10);

        const partnersList = Array.isArray(matchedPartnersResult) ? matchedPartnersResult : [];
        const matchesCount = partnersList.length;

        // Process daily login streak and ensure dynamic points are properly awarded & calculated
        let currentRewardPoints = user.rewardPoints != null && user.rewardPoints >= 0 ? user.rewardPoints : 0;
        try {
            const streakRes = await RewardPointsService.checkDailyLoginStreak(userId);
            if (streakRes.claimed) {
                currentRewardPoints += streakRes.pointsEarned;
            }
        } catch (_) { }

        // If user has 0 points, award baseline activity points for existing bookings & matches
        if (currentRewardPoints <= 0) {
            const basePoints = 100 + (bookingsCount * 50) + (matchesCount * 25);
            try {
                const awardRes = await RewardPointsService.awardPoints({
                    userId,
                    points: basePoints,
                    reason: 'Lunara Activity & Profile Engagement Points',
                    reference: `INITIAL_PTS_${userId}`,
                });
                currentRewardPoints = awardRes.newBalance;
            } catch (_) {
                currentRewardPoints = basePoints;
            }
        }
        const pointsCount = currentRewardPoints;

        const plansCount = (partyPlansCnt || 0) + (strangersMeetCnt || 0) + (groupPartyCnt || 0);

        const subscriptionTier: string = (activeSub as any)?.package?.tier ?? 'FREE';
        const planSuperlikesMap: Record<string, number> = { FREE: 0, CORE: 3, PLUS: 10, PRO: 14, ELITE: 50 };
        const planSuperlikesBase = planSuperlikesMap[subscriptionTier] ?? 0;
        const superLikesCount = receivedSuperLikes + planSuperlikesBase;

        // Check if the requesting user has already liked/superliked target user independently
        let isLiked = false;
        let isSuperLiked = false;
        let swipeStatus: string | null = null;
        if (shouldCheckRequester) {
            isLiked = !!existingUserLike || (!!existingSwipe && ['pending', 'connected'].includes(existingSwipe.status as string) && existingSwipe.matchReason !== 'superlike');
            isSuperLiked = !!existingUserSuperLike || (!!existingSwipe && ['pending', 'connected'].includes(existingSwipe.status as string) && existingSwipe.matchReason === 'superlike');
            if (existingSwipe) {
                swipeStatus = existingSwipe.status;
            } else if (isLiked || isSuperLiked) {
                swipeStatus = 'pending';
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
                likesCount,
                likeCount: likesCount,
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
            : Math.min(1000, parseInt(req.query.limit as string) || 500);
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
        const totalPages = Math.ceil(count / limit) || 1;

        // Fast path for invite list / large lookups / direct target search: bypass heavy 8-table ranking scan
        const shouldComputeRanking = req.query.ranking !== 'false' && limit <= 60 && !targetUserId;

        let paginatedUserIds: string[] = [];
        let scoredUsersMap = new Map<string, any>();

        if (shouldComputeRanking) {
            // Bound candidate scoring window to max 50 items
            const candidateWindow = allUserIds.slice(offset, offset + Math.min(limit, 50));
            const rankingExplanations = await RankingService.computeRankings(candidateWindow);
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
            const paginatedScoredUsers = scoredUsers.slice(0, limit);
            paginatedUserIds = paginatedScoredUsers.map(u => u.id);
            paginatedScoredUsers.forEach(u => scoredUsersMap.set(u.id, u));
        } else {
            paginatedUserIds = targetUserId
                ? allUserIds
                : allUserIds.slice(offset, offset + limit);

            for (const uid of paginatedUserIds) {
                scoredUsersMap.set(uid, {
                    id: uid,
                    rankScore: 100,
                    priorityTier: 5,
                    likes: 0,
                    superlikes: 0,
                    plans: 0,
                    boosts: 0,
                    vipTier: 'FREE',
                    explainScore: {},
                });
            }
        }

        const likedUserIdsSet = new Set<string>();
        const superlikedUserIdsSet = new Set<string>();
        const mySwipesMap: Record<string, { status: string; matchReason: string }> = {};

        if (paginatedUserIds.length > 0 && currentUserId) {
            const [mySwipes, myUserLikes] = await Promise.all([
                UserMatch.findAll({
                    where: {
                        user1Id: currentUserId,
                        user2Id: { [Op.in]: paginatedUserIds }
                    }
                }),
                UserLike.findAll({
                    where: {
                        userId: currentUserId,
                        targetUserId: { [Op.in]: paginatedUserIds }
                    }
                })
            ]);

            if (mySwipes && Array.isArray(mySwipes)) {
                mySwipes.forEach((s: any) => {
                    mySwipesMap[s.user2Id] = {
                        status: s.status,
                        matchReason: s.matchReason || 'like'
                    };
                    if (['pending', 'connected'].includes(s.status)) {
                        if (s.matchReason === 'superlike') {
                            superlikedUserIdsSet.add(s.user2Id);
                        } else {
                            likedUserIdsSet.add(s.user2Id);
                        }
                    }
                });
            }

            // Merge UserLike rows independently
            if (myUserLikes && Array.isArray(myUserLikes)) {
                myUserLikes.forEach((l: any) => {
                    if (l && l.targetUserId) {
                        if (l.actionType === 'like') {
                            likedUserIdsSet.add(l.targetUserId);
                        } else if (l.actionType === 'superlike') {
                            superlikedUserIdsSet.add(l.targetUserId);
                        }
                    }
                });
            }
        }

        // PHASE 2: Hydration (Only loads the paginated slice of IDs)
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

        const tierRankMap: Record<string, number> = { FREE: 0, CORE: 1, PLUS: 2, PRO: 3, ELITE: 4 };

        const data = paginatedUserIds.map(uid => {
            const user: any = userRowMap.get(uid);
            if (!user) return null;
            const scoredUser = scoredUsersMap.get(uid) || { rankScore: 100, priorityTier: 5, likes: 0, superlikes: 0, plans: 0, boosts: 0, vipTier: 'FREE', explainScore: {} };

            const age = user.dateOfBirth
                ? Math.floor((Date.now() - new Date(user.dateOfBirth).getTime()) / (365.25 * 24 * 60 * 60 * 1000))
                : null;

            const photo = user.photos?.[0];
            const photoUrl = photo
                ? '/' + photo.filePath.replace(/\\/g, '/')
                : (user.profileImageUrl ?? null);

            const mySwipe = mySwipesMap[user.id];
            const isLiked = likedUserIdsSet.has(user.id);
            const isSuperLiked = superlikedUserIdsSet.has(user.id);

            const fallbackFullName = `${user.firstName || ''} ${user.lastName || ''}`.trim();
            const fallbackName = fallbackFullName || user.profile?.displayName || user.firstName || 'User';
            const resolvedFirstName = user.firstName || user.profile?.displayName || fallbackName;

            return {
                id: user.id,
                firstName: resolvedFirstName,
                lastName: user.lastName || '',
                fullName: fallbackName,
                name: fallbackName,
                displayName: user.profile?.displayName || fallbackName,
                city: user.profile?.city ?? null,
                bio: user.profile?.bio ?? null,
                gender: user.profile?.gender ?? null,
                email: user.email,
                phone: user.phone,
                age,
                dateOfBirth: user.dateOfBirth,
                role: user.role,
                isVerified: user.isVerified,
                isActive: user.isActive,
                profilePhotoUrl: photoUrl,
                photoUrl: photoUrl,
                profilePhoto: photoUrl,
                imageUrl: photoUrl,
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
                tier: scoredUser.vipTier,
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

        const isNopeRecord = (swipe: any) => swipe && swipe.status === 'declined';

        // 1. If duplicate swipe action on existing record, retain it permanently (do NOT re-consume or delete).
        if (action === 'like') {
            const existingLike = await UserLike.findOne({ where: { userId, targetUserId, actionType: 'like' } });
            if (existingLike) {
                const hasSuper = !!(await UserLike.findOne({ where: { userId, targetUserId, actionType: 'superlike' } }));
                return res.status(200).json({
                    success: true,
                    message: 'Already liked',
                    data: existingMySwipe,
                    matched: existingMySwipe?.status === 'connected',
                    action: 'retained',
                    isLiked: true,
                    isSuperLiked: hasSuper,
                });
            }
        } else if (action === 'superlike') {
            const existingSuper = await UserLike.findOne({ where: { userId, targetUserId, actionType: 'superlike' } });
            if (existingSuper) {
                const hasLike = !!(await UserLike.findOne({ where: { userId, targetUserId, actionType: 'like' } }));
                return res.status(200).json({
                    success: true,
                    message: 'Already superliked',
                    data: existingMySwipe,
                    matched: existingMySwipe?.status === 'connected',
                    action: 'retained',
                    isLiked: hasLike,
                    isSuperLiked: true,
                });
            }
        } else if (action === 'nope' && existingMySwipe && isNopeRecord(existingMySwipe)) {
            return res.status(200).json({
                success: true,
                message: 'Already noped',
                data: existingMySwipe,
                matched: false,
                action: 'retained',
                isLiked: false,
                isSuperLiked: false,
            });
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
            const consumption = await EntitlementService.consumeFeatureEntitlement(userId, 'daily_likes', 1, {
                requestId: `LIKE_${userId}_${targetUserId}_${Date.now()}`,
                metadata: { targetUserId },
            });

            if (!consumption.success) {
                return res.status(403).json({
                    success: false,
                    code: consumption.code || 'LIMIT_REACHED',
                    limitReached: true,
                    message: consumption.message || 'You have reached your daily likes limit. Upgrade to Lunara VIP for unlimited likes!',
                    availableAddons: consumption.availableAddons || [],
                });
            }

            if (consumption.source === 'PLAN' && typeof consumption.planRemaining === 'number' && consumption.planRemaining >= 0 && consumption.planRemaining < 9999) {
                const limit = await SubscriptionService.getLimit(userId, 'daily_likes');
                if (typeof limit === 'number' && limit > 0 && limit < 9999) {
                    const remaining = consumption.planRemaining;
                    const used = Math.max(0, limit - remaining);
                    const percentage = Math.round((used / limit) * 100);

                    // If user has used >= 70% of daily likes:
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

            // Persist like in UserLike table
            await UserLike.upsert({
                userId,
                targetUserId,
                actionType: 'like',
            });
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
                    status: SubscriptionStatus.ACTIVE,
                    endDate: { [Op.gt]: new Date() },
                },
                include: [{ model: SubscriptionPackage, as: 'package' }],
                order: [['createdAt', 'DESC']],
            });

            const isEliteTier = (activeSub as any)?.package?.tier === 'ELITE' || consumption.totalRemaining === 9999;
            // Use combined plan+addon total for accurate usage warning
            const planGranted = (activeSub as any)?.package?.superlikesPerCycle || 0;
            const totalRemaining = consumption.totalRemaining ?? 0;
            // totalOriginal = plan allotment + addon quantities purchased; use consumption metadata if available
            const totalGranted = (consumption as any).totalGranted || planGranted;

            if (!isEliteTier && totalGranted > 0 && totalGranted < 9999) {
                const used = Math.max(0, totalGranted - totalRemaining);
                const percentage = Math.round((used / totalGranted) * 100);

                if (percentage >= 66) {
                    usageWarning = {
                        triggered: true,
                        feature: 'superlike',
                        used,
                        limit: totalGranted,
                        remaining: totalRemaining,
                        percentage,
                        message: `You've used ${used} of ${totalGranted} Super Likes for this cycle. ${totalRemaining > 0 ? `Only ${totalRemaining} remaining!` : 'None remaining.'}`,
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
                                body: `You've used ${used} of ${totalGranted} Super Likes (plan + add-ons). Top up credits or upgrade to Plus/Pro for more!`,
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

            // Persist superlike in UserLike table
            await UserLike.upsert({
                userId,
                targetUserId,
                actionType: 'superlike',
            });
        }

        // 2. If action is nope (declining/ignoring)
        if (action === 'nope') {
            if (existingMySwipe) {
                // Update to nope
                existingMySwipe.status = 'declined' as any;
                existingMySwipe.compatibilityScore = 0;
                existingMySwipe.matchReason = undefined;
                await existingMySwipe.save();
                return res.status(200).json({ success: true, data: existingMySwipe, matched: false, isLiked: false, isSuperLiked: false });
            } else {
                const match = await UserMatch.create({
                    user1Id: userId,
                    user2Id: targetUserId,
                    compatibilityScore: 0,
                    status: 'declined' as any,
                    expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000)
                });
                return res.status(200).json({ success: true, data: match, matched: false, isLiked: false, isSuperLiked: false });
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
                // Update existing swipe without destroying previous superlike matchReason
                existingMySwipe.status = 'connected' as any;
                existingMySwipe.compatibilityScore = action === 'superlike' ? 95 : (existingOppositeSwipe.compatibilityScore || 85);
                if (action === 'superlike' || existingMySwipe.matchReason === 'superlike') {
                    existingMySwipe.matchReason = 'superlike';
                }
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
                    const [currentUser, targetUser] = await Promise.all([
                        User.findByPk(userId),
                        User.findByPk(targetUserId),
                    ]);
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

                const [finalLikeRow, finalSuperRow] = await Promise.all([
                    UserLike.findOne({ where: { userId, targetUserId, actionType: 'like' } }),
                    UserLike.findOne({ where: { userId, targetUserId, actionType: 'superlike' } }),
                ]);

                return res.status(200).json({
                    success: true,
                    data: mySwipe,
                    matched: true,
                    conversationId: conversation.id,
                    usageWarning,
                    isLiked: !!finalLikeRow,
                    isSuperLiked: !!finalSuperRow,
                });
            } catch (chatErr) {
                logger.error('[swipeUser] Failed to init free chat, but match still created:', chatErr);
            }

            const [finalLikeRow, finalSuperRow] = await Promise.all([
                UserLike.findOne({ where: { userId, targetUserId, actionType: 'like' } }),
                UserLike.findOne({ where: { userId, targetUserId, actionType: 'superlike' } }),
            ]);

            return res.status(200).json({
                success: true,
                data: mySwipe,
                matched: true,
                usageWarning,
                isLiked: !!finalLikeRow,
                isSuperLiked: !!finalSuperRow,
            });
        }

        // 4. Otherwise (no mutual match yet), create/update to pending match record
        let match;
        const score = action === 'superlike' ? 95 : 75;
        if (existingMySwipe) {
            existingMySwipe.status = 'pending' as any;
            existingMySwipe.compatibilityScore = score;
            if (action === 'superlike' || existingMySwipe.matchReason === 'superlike') {
                existingMySwipe.matchReason = 'superlike';
            }
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
            const [currentUser, targetUser] = await Promise.all([
                User.findByPk(userId),
                User.findByPk(targetUserId),
            ]);
            if (currentUser && targetUser) {
                const { SubscriptionService } = require('../services/subscriptionService');
                const canSeeWhoLikedTarget = await SubscriptionService.hasAccess(targetUserId, 'who_liked_me');

                const senderName = `${currentUser.firstName || ''} ${currentUser.lastName || ''}`.trim() || 'Someone';
                const isSuper = action === 'superlike';

                // Superlike is strictly excluded from masking: always visible to receiver regardless of tier
                const title = isSuper
                    ? `⭐ ${senderName} Super Liked You!`
                    : (canSeeWhoLikedTarget ? `💖 ${senderName} liked your profile!` : '❤️ Someone liked your profile');

                const body = isSuper
                    ? `${senderName} sent you a Super Like! 💜`
                    : (canSeeWhoLikedTarget ? `${senderName} liked your profile ❤️` : 'Someone liked your profile! Upgrade to VIP to see who!');

                let postedPlans: any[] = [];
                if (isSuper || canSeeWhoLikedTarget) {
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
                const isRecipientVipOrSuper = isSuper || canSeeWhoLikedTarget;

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
                            actionType: isRecipientVipOrSuper ? 'view_profile' : 'open_vip_upgrade',
                            entityType: 'user_match',
                            entityId: match.id,
                            isRead: false,
                            priority: (isSuper ? 'HIGH' : 'NORMAL') as any,
                            deepLink: isRecipientVipOrSuper ? `/profile/${currentUser.id}` : '/vip-membership',
                            idempotencyKey: dedupeKey,
                            metadata: isRecipientVipOrSuper ? {
                                matchId: match.id,
                                senderId: currentUser.id,
                                senderName,
                                senderImage: currentUser.profileImageUrl || '',
                                postedPlans,
                                action: isSuper ? 'superlike' : 'like',
                            } : {
                                matchId: match.id,
                                isMasked: true,
                                action: 'like',
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
                        sender: isRecipientVipOrSuper ? {
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
                        data: isRecipientVipOrSuper ? {
                            matchId: match.id,
                            senderId: currentUser.id,
                            senderName,
                            senderImage: currentUser.profileImageUrl || '',
                            postedPlans,
                            action: isSuper ? 'superlike' : 'like',
                        } : {
                            matchId: match.id,
                            isMasked: true,
                            action: 'like',
                        }
                    });

                    // Emit real-time like_received event for live UI synchronization
                    io.to(`user_${targetUserId}`).emit('like_received', {
                        matchId: match.id,
                        likerId: isRecipientVipOrSuper ? currentUser.id : 'masked',
                        isSuper,
                        timestamp: new Date().toISOString(),
                    });
                }

                if (targetUser.fcmToken) {
                    const { sendPushNotification } = require('../services/fcmService');
                    await sendPushNotification(targetUser.fcmToken, {
                        title,
                        body,
                        data: isRecipientVipOrSuper ? {
                            type: isSuper ? 'superlike' : 'like',
                            senderId: currentUser.id,
                            senderName,
                            senderImage: currentUser.profileImageUrl || '',
                        } : {
                            type: 'like',
                            isMasked: 'true',
                        }
                    });
                }
            }
        } catch (fcmErr) {
            logger.error('[swipeUser] Failed to send push notification/socket:', fcmErr);
        }

        const [finalLikeRow, finalSuperRow] = await Promise.all([
            UserLike.findOne({ where: { userId, targetUserId, actionType: 'like' } }),
            UserLike.findOne({ where: { userId, targetUserId, actionType: 'superlike' } }),
        ]);

        return res.status(200).json({
            success: true,
            data: match,
            matched: false,
            usageWarning,
            isLiked: !!finalLikeRow,
            isSuperLiked: !!finalSuperRow,
        });

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

        // Delete ONLY the 'like' record from UserLike table (preserve superlike if present)
        await UserLike.destroy({
            where: { userId, targetUserId, actionType: 'like' }
        });

        // Check if superlike record still exists
        const remainingSuperLike = await UserLike.findOne({
            where: { userId, targetUserId, actionType: 'superlike' }
        });

        // Update UserMatch record if present
        const existingMatch = await UserMatch.findOne({
            where: { user1Id: userId, user2Id: targetUserId }
        });

        if (existingMatch) {
            if (remainingSuperLike) {
                existingMatch.status = 'pending' as any;
                existingMatch.matchReason = 'superlike';
                await existingMatch.save();
            } else {
                existingMatch.status = 'declined' as any;
                existingMatch.matchReason = undefined;
                await existingMatch.save();
            }
        }

        // Log engagement event
        try {
            const { EngagementService } = await import('../services/engagementService');
            await EngagementService.logLikeRemoved(userId, targetUserId);
        } catch (_) { }

        // Unlike is 100% silent to the target user (no push/socket/in-app alert)

        return res.status(200).json({
            success: true,
            message: 'Like removed successfully',
            isLiked: false,
            isSuperLiked: !!remainingSuperLike,
        });
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

        // Strictly protect Free users from receiving sender identity for normal Likes (Superlikes are excluded)
        const processed = matches.map((m: any) => {
            const json = m.toJSON();
            const isIncomingPendingLike = json.user2Id === userId && json.status === 'pending';
            const isSuper = json.matchReason === 'superlike' || json.isSuperLike;

            if (isIncomingPendingLike && !canSeeWhoLiked && !isSuper) {
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

        // Count incoming likes from user_likes table within 7 days where receiver is this user concurrently
        const [count, superlikesCount] = await Promise.all([
            UserLike.count({
                where: {
                    targetUserId: userId,
                    actionType: { [Op.in]: ['like', 'superlike'] },
                    createdAt: { [Op.gte]: sevenDaysAgo },
                },
            }),
            UserLike.count({
                where: {
                    targetUserId: userId,
                    actionType: 'superlike',
                    createdAt: { [Op.gte]: sevenDaysAgo },
                },
            }),
        ]);

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

        // Check UserLike table independently for like and superlike
        const [likeRecord, superLikeRecord, existingSwipe] = await Promise.all([
            UserLike.findOne({ where: { userId, targetUserId, actionType: 'like' } }),
            UserLike.findOne({ where: { userId, targetUserId, actionType: 'superlike' } }),
            UserMatch.findOne({ where: { user1Id: userId, user2Id: targetUserId } }),
        ]);

        const alreadyLiked = !!likeRecord || (!!existingSwipe && ['pending', 'connected'].includes(existingSwipe.status as string) && existingSwipe.matchReason !== 'superlike');
        const alreadySuperLiked = !!superLikeRecord || (!!existingSwipe && ['pending', 'connected'].includes(existingSwipe.status as string) && existingSwipe.matchReason === 'superlike');
        const alreadyNoped = !alreadyLiked && !alreadySuperLiked && !!existingSwipe && existingSwipe.status === 'declined';

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
        let dailyBacktracksLimit = 3;
        let dailyBacktracksRemaining = 3;

        // Fetch subscription limits and entitlement summary in parallel (was 3 sequential awaits + duplicate summary call)
        const { SubscriptionService: SwipeSS } = require('../services/subscriptionService');
        const [swipeLimitResult, swipeRemainingResult, entitlementSummary] = await Promise.allSettled([
            SwipeSS.getLimit(userId, 'daily_likes'),
            SwipeSS.getRemainingUsage(userId, 'daily_likes'),
            EntitlementService.getEntitlementsSummary(userId),
        ]);

        if (swipeLimitResult.status === 'fulfilled' && swipeRemainingResult.status === 'fulfilled') {
            const limit = swipeLimitResult.value;
            const remaining = swipeRemainingResult.value;
            dailyLikesLimit = limit === 'unlimited' ? 999999 : limit;
            const remainingNum = remaining === 'unlimited' ? dailyLikesLimit : remaining;
            todayLikeCount = Math.max(0, dailyLikesLimit - remainingNum);
        } else {
            logger.warn('[swipeStatus] Could not fetch daily like limits');
        }

        if (entitlementSummary.status === 'fulfilled') {
            const summary = entitlementSummary.value;
            // Superlikes
            const rawSuper = summary.totals.superlikesAvailable as any;
            superlikesRemaining = rawSuper === 'unlimited' ? 999999 : (Number(rawSuper) || 0);
            const superlikeItem = summary.planBenefits.find((b: any) => b.featureKey === 'superlike');
            const addonSuperCount = (summary.activeAddons || [])
                .filter((a: any) => a.featureKey === 'superlike' || a.featureKey === 'super_likes' || a.featureKey === 'super_like')
                .reduce((sum: number, a: any) => sum + (Number(a.remainingQuantity) || 0), 0);
            superlikesPerCycle = (superlikeItem?.includedQuantity || 0) + addonSuperCount;
            // Backtracks (reuse same summary — no second DB round-trip)
            const rawBacktracks = summary.totals.backtracksAvailable as any;
            dailyBacktracksRemaining = rawBacktracks === 'unlimited' ? 999999 : (Number(rawBacktracks) || 0);
            const backtrackItem = summary.planBenefits.find((b: any) => b.featureKey === 'backtrack');
            dailyBacktracksLimit = backtrackItem?.includedQuantity === -1 ? 999999 : (backtrackItem?.includedQuantity || 3);
        } else {
            logger.warn('[swipeStatus] Could not fetch entitlement summary');
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
                superLimitReached: superlikesRemaining <= 0,
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

        const consumption = await EntitlementService.consumeFeatureEntitlement(userId, 'backtrack', 1, {
            requestId: `BACKTRACK_${userId}_${targetUserId}_${Date.now()}`,
            metadata: { targetUserId },
        });

        if (!consumption.success) {
            return res.status(403).json({
                success: false,
                code: consumption.code || 'LIMIT_REACHED',
                limitReached: true,
                message: consumption.message || 'You have reached your daily backtrack limit. Upgrade your plan or get a Backtrack add-on!',
                availableAddons: consumption.availableAddons || [],
            });
        }

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
                    // Revert the other party's swipe back to pending
                    oppositeSwipe.status = 'pending' as any;
                    oppositeSwipe.matchReason = undefined; // clear superlike reason too
                    await oppositeSwipe.save();
                }
            }
            await mySwipe.destroy();
        }

        return res.status(200).json({
            success: true,
            data: {
                remaining: consumption.totalRemaining,
                consumed: consumption.consumed,
                source: consumption.source,
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
