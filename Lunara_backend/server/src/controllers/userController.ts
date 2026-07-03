import { Request, Response } from 'express';
import { User, UserProfile, UserPreference, UserRole } from '../models';
import bcrypt from 'bcryptjs';

/**
 * @desc    Get all users (Admin only)
 * @route   GET /api/users
 * @access  Private/Admin
 */
export const getUsers = async (req: Request, res: Response): Promise<void | Response> => {
    try {
        const page = parseInt(req.query.page as string) || 1;
        const limit = parseInt(req.query.limit as string) || 50;
        const offset = (page - 1) * limit;

        const { count, rows } = await User.findAndCountAll({
            attributes: { exclude: ['passwordHash', 'mfaSecret'] },
            include: [
                { model: UserProfile, as: 'profile' },
                { model: UserPreference, as: 'preferences' }
            ],
            limit,
            offset,
            order: [['createdAt', 'DESC']],
        });

        res.status(200).json({
            success: true,
            count,
            totalPages: Math.ceil(count / limit),
            currentPage: page,
            users: rows,
        });
    } catch (error) {
        console.error('Error fetching users:', error);
        res.status(500).json({
            success: false,
            message: 'Server Error fetching users',
        });
    }
};

/**
 * @desc    Get single user by ID
 * @route   GET /api/users/:id
 * @access  Private/Admin
 */
export const getUserById = async (req: Request, res: Response): Promise<void | Response> => {
    try {
        const user = await User.findByPk(req.params.id, {
            attributes: { exclude: ['passwordHash', 'mfaSecret'] },
            include: [
                { model: UserProfile, as: 'profile' },
                { model: UserPreference, as: 'preferences' }
            ],
        });

        if (!user) {
            return res.status(404).json({
                success: false,
                message: 'User not found',
            });
        }

        res.status(200).json({
            success: true,
            user,
        });
    } catch (error) {
        console.error('Error fetching user:', error);
        res.status(500).json({
            success: false,
            message: 'Server Error fetching user',
        });
    }
};

/**
 * @desc    Create a new user manually
 * @route   POST /api/users
 * @access  Private/Admin
 */
export const createUser = async (req: Request, res: Response): Promise<void | Response> => {
    try {
        const { email, password, role, isVerified, isActive, firstName, lastName, phone, dateOfBirth } = req.body;

        const existingUser = await User.findOne({ where: { email } });
        if (existingUser) {
            return res.status(400).json({
                success: false,
                message: 'User already exists',
            });
        }

        const hashedPassword = await bcrypt.hash(password, 10);

        const user = await User.create({
            email,
            passwordHash: hashedPassword,
            firstName: firstName || 'Admin',
            lastName: lastName || 'Created',
            phone: phone || `+00${Math.floor(Math.random() * 1000000000)}`,
            dateOfBirth: dateOfBirth || new Date('1990-01-01'),
            role: role || UserRole.CUSTOMER,
            isVerified: isVerified !== undefined ? isVerified : true,
            isActive: isActive !== undefined ? isActive : true,
            mfaEnabled: false,
        });

        res.status(201).json({
            success: true,
            message: 'User created successfully',
            user: {
                id: user.id,
                email: user.email,
                role: user.role,
                isActive: user.isActive,
                isVerified: user.isVerified
            }
        });
    } catch (error) {
        console.error('Error creating user:', error);
        res.status(500).json({
            success: false,
            message: 'Server Error creating user',
        });
    }
};

/**
 * @desc    Update user (e.g. status, role)
 * @route   PUT /api/users/:id
 * @access  Private/Admin
 */
export const updateUser = async (req: Request, res: Response): Promise<void | Response> => {
    try {
        const user = await User.findByPk(req.params.id);

        if (!user) {
            return res.status(404).json({
                success: false,
                message: 'User not found',
            });
        }

        // Only allow updating certain fields by Admin on the root User model
        const allowedUpdates = ['role', 'isActive', 'isVerified', 'email', 'firstName', 'lastName', 'phone'];
        const updates: any = {};

        allowedUpdates.forEach((field) => {
            if (req.body[field] !== undefined) {
                updates[field] = req.body[field];
            }
        });

        await user.update(updates);

        // Map frontend "social" or "identity" back to the correct models if they exist in the payload
        // The frontend will send a 'profile' object and a 'preferences' object instead.
        if (req.body.profile) {
             let userProfile = await UserProfile.findOne({ where: { userId: user.id } });
             if (userProfile) {
                 await userProfile.update(req.body.profile);
             } else {
                 await UserProfile.create({ userId: user.id, ...req.body.profile });
             }
        }

        if (req.body.preferences) {
             let userPref = await UserPreference.findOne({ where: { userId: user.id } });
             if (userPref) {
                 await userPref.update(req.body.preferences);
             } else {
                 await UserPreference.create({ userId: user.id, ...req.body.preferences });
             }
        }

        // Fetch the fully updated user to return to the admin panel
        const updatedUser = await User.findByPk(user.id, {
            attributes: { exclude: ['passwordHash', 'mfaSecret'] },
            include: [
                { model: UserProfile, as: 'profile' },
                { model: UserPreference, as: 'preferences' }
            ],
        });

        res.status(200).json({
            success: true,
            message: 'User updated successfully',
            user: updatedUser
        });
    } catch (error) {
        console.error('Error updating user:', error);
        res.status(500).json({
            success: false,
            message: 'Server Error updating user',
        });
    }
};

/**
 * @desc    Delete user
 * @route   DELETE /api/users/:id
 * @access  Private/Admin
 */
export const deleteUser = async (req: Request, res: Response): Promise<void | Response> => {
    try {
        const user = await User.findByPk(req.params.id);

        if (!user) {
            return res.status(404).json({
                success: false,
                message: 'User not found',
            });
        }

        await user.destroy();

        res.status(200).json({
            success: true,
            message: 'User deleted successfully',
        });
    } catch (error) {
        console.error('Error deleting user:', error);
        res.status(500).json({
            success: false,
            message: 'Server Error deleting user',
        });
    }
};
