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
            },
            { transaction }
        );

        // Update or Create UserPreference
        const [preference] = await UserPreference.findOrCreate({
            where: { userId },
            defaults: { userId },
            transaction
        });

        await preference.update(
            {
                musicPreference: data.musicPreference,
                smokingPreference: data.smokingPreference,
                drinkPreference: data.drinkPreference,
                preferredGenders: data.preferredGenders,
                minAgePreference: data.minAgePreference,
                maxAgePreference: data.maxAgePreference,
                minBudget: data.minBudget,
                maxBudget: data.maxBudget,
                showMeInMatching: data.invisibleMode !== undefined ? !data.invisibleMode : undefined,
                matchDistanceKm: data.matchDistanceKm,
                bookingAlertsEnabled: data.bookingAlertsEnabled,
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
        const userId = req.user?.id;
        const { id } = req.params;

        if (!userId) {
            return res.status(401).json({ success: false, message: 'Unauthorized' });
        }

        const photo = await UserPhoto.findOne({ where: { id, userId } });
        if (!photo) {
            return res.status(404).json({ success: false, message: 'Photo not found' });
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
                nextPhoto.isPrimary = true;
                await nextPhoto.save();
                await User.update(
                    { profileImageUrl: '/' + nextPhoto.filePath.replace(/\\/g, '/') },
                    { where: { id: userId } }
                );
            } else {
                await User.update(
                    { profileImageUrl: null as any },
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
        return res.status(500).json({ success: false, message: 'Failed to delete photo' });
    }
};

export const setPrimaryPhoto = async (req: Request, res: Response): Promise<Response> => {
    try {
        const userId = req.user?.id;
        const { id } = req.params;

        if (!userId) {
            return res.status(401).json({ success: false, message: 'Unauthorized' });
        }

        const photo = await UserPhoto.findOne({ where: { id, userId } });
        if (!photo) {
            return res.status(404).json({ success: false, message: 'Photo not found' });
        }

        await UserPhoto.setAsPrimary(id, userId);

        await User.update(
            { profileImageUrl: '/' + photo.filePath.replace(/\\/g, '/') },
            { where: { id: userId } }
        );

        return res.status(200).json({
            success: true,
            message: 'Primary photo updated successfully',
        });
    } catch (error: any) {
        logger.error('[Profile] Error setting primary photo:', error);
        return res.status(500).json({ success: false, message: 'Failed to update primary photo' });
    }
};
