import { Request, Response } from 'express';
import User from '../models/User';
import { UserProfile, UserPreference, UserPhoto } from '../models';
import sequelize from '../config/database';
import { logger } from '../config/logger';

export const updateProfile = async (req: Request, res: Response): Promise<Response> => {
    const transaction = await sequelize.transaction();
    try {
        const userId = req.user?.id;
        if (!userId) {
            await transaction.rollback();
            return res.status(401).json({ success: false, message: 'Unauthorized' });
        }

        const data = req.body;

        if (data.phone) {
            const existingPhone = await User.findOne({ where: { phone: data.phone }, transaction });
            if (existingPhone && existingPhone.id !== userId) {
                await transaction.rollback();
                return res.status(400).json({ success: false, message: 'Phone number is already in use' });
            }
        }

        // Update User
        await User.update(
            {
                firstName: data.firstName,
                lastName: data.lastName,
                phone: data.phone,
                dateOfBirth: data.dateOfBirth,
            },
            { where: { id: userId }, transaction }
        );

        // Update or Create UserProfile
        const [profile] = await UserProfile.findOrCreate({
            where: { userId },
            defaults: { userId },
            transaction
        });

        await profile.update(
            {
                gender: data.gender,
                city: data.city,
                bio: data.bio,
                lookingFor: data.lookingFor,
                occupation: data.occupation,
                education: data.education,
                interests: data.interests,
            },
            { transaction }
        );

        // Update or Create UserPreference
        const [preference] = await UserPreference.findOrCreate({
            where: { userId },
            defaults: { userId },
            transaction
        });

        // Compute budgetRange if minBudget or maxBudget is provided
        let computedBudgetRange = data.budgetRange;
        if (!computedBudgetRange && (data.minBudget !== undefined || data.maxBudget !== undefined)) {
            if (data.minBudget !== undefined && data.maxBudget !== undefined) {
                computedBudgetRange = `₹${data.minBudget} - ₹${data.maxBudget}`;
            } else if (data.minBudget !== undefined) {
                computedBudgetRange = `₹${data.minBudget}+`;
            } else if (data.maxBudget !== undefined) {
                computedBudgetRange = `Up to ₹${data.maxBudget}`;
            }
        }

        await preference.update(
            {
                musicPreference: data.musicPreference ?? preference.musicPreference,
                smokingPreference: data.smokingPreference ?? preference.smokingPreference,
                drinkPreference: data.drinkPreference ?? preference.drinkPreference,
                preferredGenders: data.preferredGenders ?? preference.preferredGenders,
                minAgePreference: data.minAgePreference !== undefined ? data.minAgePreference : preference.minAgePreference,
                maxAgePreference: data.maxAgePreference !== undefined ? data.maxAgePreference : preference.maxAgePreference,
                minBudget: data.minBudget !== undefined ? data.minBudget : preference.minBudget,
                maxBudget: data.maxBudget !== undefined ? data.maxBudget : preference.maxBudget,
                budgetRange: computedBudgetRange ?? preference.budgetRange,
                showMeInMatching: data.invisibleMode !== undefined ? !data.invisibleMode : (data.showMeInMatching !== undefined ? data.showMeInMatching : preference.showMeInMatching),
                matchDistanceKm: data.matchDistanceKm !== undefined ? data.matchDistanceKm : preference.matchDistanceKm,
                bookingAlertsEnabled: data.bookingAlertsEnabled !== undefined ? data.bookingAlertsEnabled : preference.bookingAlertsEnabled,
            },
            { transaction }
        );

        await transaction.commit();

        return res.status(200).json({
            success: true,
            message: 'Profile updated successfully',
        });
    } catch (error: any) {
        await transaction.rollback();
        logger.error('[Profile] Error updating profile:', error);
        return res.status(500).json({ success: false, message: 'Failed to update profile' });
    }
};

export const changePassword = async (req: Request, res: Response): Promise<Response> => {
    try {
        const userId = req.user?.id;
        if (!userId) {
            return res.status(401).json({ success: false, message: 'Unauthorized' });
        }

        const { currentPassword, newPassword } = req.body;

        const user = await User.findByPk(userId);
        if (!user) {
            return res.status(404).json({ success: false, message: 'User not found' });
        }

        const isMatch = await user.comparePassword(currentPassword);
        if (!isMatch) {
            return res.status(400).json({ success: false, message: 'Incorrect current password' });
        }

        user.passwordHash = newPassword; // the hook in User model will hash it
        await user.save();

        return res.status(200).json({
            success: true,
            message: 'Password changed successfully',
        });
    } catch (error: any) {
        logger.error('[Profile] Error changing password:', error);
        return res.status(500).json({ success: false, message: 'Failed to change password' });
    }
};

export const deletePhoto = async (req: Request, res: Response): Promise<Response> => {
    try {
        const userId = req.user?.id || (req.body && req.body.userId);
        const { id } = req.params;

        if (!userId) {
            return res.status(401).json({ success: false, message: 'Unauthorized' });
        }

        const photo = await UserPhoto.findOne({ where: { id, userId } });
        if (!photo) {
            return res.status(404).json({ success: false, message: 'Photo not found' });
        }

        const totalPhotos = await UserPhoto.count({ where: { userId } });
        if (totalPhotos <= 3) {
            return res.status(400).json({
                success: false,
                message: 'Minimum 3 profile pictures are required. Please upload a new photo before deleting this one.',
            });
        }

        const wasPrimary = photo.isPrimary;
        await photo.destroy();

        if (wasPrimary) {
            // Find the next photo to set as primary
            const nextPhoto = await UserPhoto.findOne({
                where: { userId },
                order: [['displayOrder', 'ASC'], ['uploadedAt', 'DESC']],
            });

            if (nextPhoto) {
                await UserPhoto.update(
                    { isPrimary: true },
                    { where: { id: nextPhoto.id, userId } }
                );
                const rawFilePath = nextPhoto.filePath || (nextPhoto as any).dataValues?.filePath || (nextPhoto as any).dataValues?.file_path || '';
                const rawPath = String(rawFilePath).replace(/\\/g, '/');
                const newProfileUrl = rawPath.startsWith('http') || rawPath.startsWith('/')
                    ? rawPath
                    : (rawPath ? '/' + rawPath : null);
                if (newProfileUrl) {
                    await (User as any).update(
                        { profileImageUrl: newProfileUrl },
                        { where: { id: userId } }
                    );
                }
            } else {
                await (User as any).update(
                    { profileImageUrl: null },
                    { where: { id: userId } }
                );
            }
        }

        return res.status(200).json({
            success: true,
            message: 'Photo deleted successfully',
        });
    } catch (error: any) {
        logger.error('[Profile] Error deleting photo:', error);
        return res.status(500).json({ success: false, message: 'Failed to delete photo', error: error?.message });
    }
};

export const setPrimaryPhoto = async (req: Request, res: Response): Promise<Response> => {
    try {
        const userId = req.user?.id || (req.body && req.body.userId);
        const { id } = req.params;

        if (!userId) {
            return res.status(401).json({ success: false, message: 'Unauthorized' });
        }

        const photo = await UserPhoto.findOne({ where: { id, userId } });
        if (!photo) {
            return res.status(404).json({ success: false, message: 'Photo not found' });
        }

        // Set all photos of user to non-primary
        await UserPhoto.update(
            { isPrimary: false },
            { where: { userId } }
        );

        // Mark this photo as primary using static / model update to avoid full instance validation errors
        await UserPhoto.update(
            { isPrimary: true },
            { where: { id: photo.id, userId } }
        );

        const rawFilePath = photo.filePath || (photo as any).dataValues?.filePath || (photo as any).dataValues?.file_path || '';
        const rawPath = String(rawFilePath).replace(/\\/g, '/');
        const newProfileUrl = rawPath.startsWith('http') || rawPath.startsWith('/')
            ? rawPath
            : (rawPath ? '/' + rawPath : null);

        if (newProfileUrl) {
            await (User as any).update(
                { profileImageUrl: newProfileUrl },
                { where: { id: userId } }
            );
        }

        try {
            const { RealtimeEventBroker } = require('../services/RealtimeEventBroker');
            if (newProfileUrl) {
                RealtimeEventBroker.emitToUser(userId, 'profile_photo_updated', 'user', userId, {
                    userId,
                    profileImageUrl: newProfileUrl,
                });
                RealtimeEventBroker.emitToLiveFeed('profile_photo_updated', 'user', userId, {
                    userId,
                    profileImageUrl: newProfileUrl,
                });
            }
        } catch (_) {}

        return res.status(200).json({
            success: true,
            message: 'Primary photo updated successfully',
            data: {
                photoId: id,
                profileImageUrl: newProfileUrl,
            }
        });
    } catch (error: any) {
        logger.error('[Profile] Error setting primary photo:', error);
        return res.status(500).json({ success: false, message: 'Failed to update primary photo', error: error?.message });
    }
};
