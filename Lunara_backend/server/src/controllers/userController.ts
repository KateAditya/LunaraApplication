import { Request, Response } from 'express';
import { User, UserProfile, UserPreference, UserRole, SocialConnection, Plan, PartyPlan, StrangersMeetRequest, PlanJoinRequest, PartyPlanRequest, UserPenalty } from '../models';
import { ConnectionStatus } from '../models/SocialConnection';
import DeletedAccount from '../models/DeletedAccount';
import bcrypt from 'bcryptjs';
import { Op } from 'sequelize';

/**
 * @desc    Get all users (Admin only)
 * @route   GET /api/users
 * @access  Private/Admin
 */
export const getUsers = async (req: Request, res: Response): Promise<void | Response> => {
    try {
        const page = Math.max(1, parseInt(req.query.page as string) || 1);
        const limit = Math.min(100, parseInt(req.query.limit as string) || 50);
        const offset = (page - 1) * limit;

        const { count, rows } = await User.findAndCountAll({
            attributes: { exclude: ['passwordHash', 'mfaSecret'] },
            include: [
                { model: UserProfile, as: 'profile', required: false },
                { model: UserPreference, as: 'preferences', required: false }
            ],
            limit,
            offset,
            order: [['createdAt', 'DESC']],
            distinct: true,
        });

        res.status(200).json({
            success: true,
            count,
            totalPages: Math.ceil(count / limit),
            currentPage: page,
            users: rows,
        });
    } catch (error: any) {
        console.error('Error fetching users:', error);
        res.status(500).json({
            success: false,
            message: error?.message || 'Server Error fetching users',
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

/**
 * @desc    Get all autoblocked users (Admin only)
 * @route   GET /api/users/autoblocked
 * @access  Private/Admin
 */
export const getAutoblockedUsers = async (req: Request, res: Response): Promise<void | Response> => {
    try {
        const page = Math.max(1, parseInt(req.query.page as string) || 1);
        const limit = Math.min(100, parseInt(req.query.limit as string) || 50);
        const offset = (page - 1) * limit;

        const { count, rows } = await User.findAndCountAll({
            where: { isAutoblocked: true },
            attributes: { exclude: ['passwordHash', 'mfaSecret'] },
            include: [
                { model: UserProfile, as: 'profile', required: false },
                { model: UserPreference, as: 'preferences', required: false }
            ],
            limit,
            offset,
            order: [['createdAt', 'DESC']],
            distinct: true,
        });

        res.status(200).json({
            success: true,
            count,
            totalPages: Math.ceil(count / limit),
            currentPage: page,
            users: rows,
        });
    } catch (error: any) {
        console.error('Error fetching autoblocked users:', error);
        res.status(500).json({
            success: false,
            message: error?.message || 'Server Error fetching autoblocked users',
        });
    }
};

/**
 * @desc    Get all reported users (Users with at least one UserPenalty)
 * @route   GET /api/users/reported
 * @access  Private/Admin
 */
export const getReportedUsers = async (req: Request, res: Response): Promise<void | Response> => {
    try {
        const page = parseInt(req.query.page as string) || 1;
        const limit = parseInt(req.query.limit as string) || 50;
        const offset = (page - 1) * limit;

        const { count, rows } = await UserPenalty.findAndCountAll({
            include: [
                { 
                    model: User, 
                    as: 'user', 
                    attributes: ['id', 'email', 'firstName', 'lastName', 'isActive', 'isAutoblocked', 'blockCount'],
                    include: [{ model: UserProfile, as: 'profile', attributes: ['displayName'] }]
                }
            ],
            limit,
            offset,
            order: [['createdAt', 'DESC']],
        });

        // Group by user if needed, but since penalties are individual events, 
        // we can return the penalty records which includes the user details.
        res.status(200).json({
            success: true,
            count,
            totalPages: Math.ceil(count / limit),
            currentPage: page,
            reports: rows,
        });
    } catch (error) {
        console.error('Error fetching reported users:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to fetch reported users.',
        });
    }
};

/**
 * @desc    Unblock an autoblocked user (Admin only)
 * @route   POST /api/users/:id/unblock
 * @access  Private/Admin
 */
export const unblockUserByAdmin = async (req: Request, res: Response): Promise<void | Response> => {
    try {
        const user = await User.findByPk(req.params.id);

        if (!user) {
            return res.status(404).json({
                success: false,
                message: 'User not found',
            });
        }

        user.isAutoblocked = false;
        user.autoblockedReason = null;
        user.blockCount = 0;
        user.isActive = true;
        await user.save();

        await SocialConnection.destroy({
            where: {
                receiverId: user.id,
                status: ConnectionStatus.BLOCKED
            }
        });

        res.status(200).json({
            success: true,
            message: 'User unblocked successfully by admin',
            user: {
                id: user.id,
                email: user.email,
                isAutoblocked: user.isAutoblocked,
                isActive: user.isActive,
                blockCount: user.blockCount
            }
        });
    } catch (error) {
        console.error('Error unblocking user by admin:', error);
        res.status(500).json({
            success: false,
            message: 'Server Error unblocking user',
        });
    }
};

// ============================================================================
// DELETED ACCOUNTS — Admin Management
// ============================================================================

/**
 * @desc    Get all permanently deleted accounts
 * @route   GET /api/users/deleted-accounts
 * @access  Private/Admin
 * Query: page, limit, search, from (ISO date), to (ISO date)
 */
export const getDeletedAccounts = async (req: Request, res: Response): Promise<void | Response> => {
    try {
        const page = Math.max(1, parseInt(req.query.page as string) || 1);
        const limit = Math.min(100, parseInt(req.query.limit as string) || 20);
        const offset = (page - 1) * limit;
        const search = (req.query.search as string)?.trim();
        const from = req.query.from as string;
        const to = req.query.to as string;

        const where: any = {};

        if (search) {
            where[Op.or] = [
                { firstName: { [Op.iLike]: `%${search}%` } },
                { lastName: { [Op.iLike]: `%${search}%` } },
                { email: { [Op.iLike]: `%${search}%` } },
                { phone: { [Op.iLike]: `%${search}%` } },
            ];
        }

        if (from || to) {
            where.createdAt = {};
            if (from) where.createdAt[Op.gte] = new Date(from);
            if (to) {
                const toDate = new Date(to);
                toDate.setHours(23, 59, 59, 999);
                where.createdAt[Op.lte] = toDate;
            }
        }

        const { count, rows } = await DeletedAccount.findAndCountAll({
            where,
            order: [['createdAt', 'DESC']],
            limit,
            offset,
        });

        res.status(200).json({
            success: true,
            count,
            totalPages: Math.ceil(count / limit),
            currentPage: page,
            deletedAccounts: rows,
        });
    } catch (error) {
        console.error('Error fetching deleted accounts:', error);
        res.status(500).json({ success: false, message: 'Server Error fetching deleted accounts' });
    }
};

/**
 * @desc    Get a single deleted account's full details
 * @route   GET /api/users/deleted-accounts/:id
 * @access  Private/Admin
 */
export const getDeletedAccountById = async (req: Request, res: Response): Promise<void | Response> => {
    try {
        const { id } = req.params;
        const record = await DeletedAccount.findByPk(id);

        if (!record) {
            return res.status(404).json({ success: false, message: 'Deleted account record not found' });
        }

        // Cross-reference the soft-deleted user record (may still exist in users table)
        const liveUser = await User.findOne({
            where: { id: record.originalUserId },
            attributes: { exclude: ['passwordHash', 'mfaSecret'] },
        }).catch(() => null);

        // Fetch historical activity using originalUserId
        const [plans, partyPlans, strangersMeets, sentPlanRequests, sentPartyRequests] = await Promise.all([
            Plan.findAll({ where: { userId: record.originalUserId }, order: [['createdAt', 'DESC']] }),
            PartyPlan.findAll({ where: { userId: record.originalUserId }, order: [['createdAt', 'DESC']] }),
            StrangersMeetRequest.findAll({ where: { userId: record.originalUserId }, order: [['createdAt', 'DESC']] }),
            PlanJoinRequest.findAll({ where: { requesterId: record.originalUserId }, order: [['createdAt', 'DESC']] }),
            PartyPlanRequest.findAll({ where: { requesterId: record.originalUserId }, order: [['createdAt', 'DESC']] })
        ]);

        res.status(200).json({
            success: true,
            deletedAccount: record,
            liveUserRecord: liveUser ?? null,
            activity: {
                plans,
                partyPlans,
                strangersMeets,
                sentPlanRequests,
                sentPartyRequests
            }
        });
    } catch (error) {
        console.error('Error fetching deleted account:', error);
        res.status(500).json({ success: false, message: 'Server Error fetching deleted account' });
    }
};

/**
 * @desc    Update admin notes on a deleted account archive record
 * @route   PATCH /api/users/deleted-accounts/:id/notes
 * @access  Private/Admin
 */
export const updateDeletedAccountNotes = async (req: Request, res: Response): Promise<void | Response> => {
    try {
        const { id } = req.params;
        const { adminNotes } = req.body;

        const record = await DeletedAccount.findByPk(id);
        if (!record) {
            return res.status(404).json({ success: false, message: 'Deleted account record not found' });
        }

        record.adminNotes = adminNotes ?? record.adminNotes;
        await record.save();

        res.status(200).json({
            success: true,
            message: 'Admin notes updated successfully',
            deletedAccount: record,
        });
    } catch (error) {
        console.error('Error updating admin notes:', error);
        res.status(500).json({ success: false, message: 'Server Error updating notes' });
    }
};

/**
 * @desc    Restore (un-delete) a soft-deleted account
 *          Archive record is kept for audit trail.
 * @route   POST /api/users/deleted-accounts/:id/restore
 * @access  Private/Admin
 */
export const restoreDeletedAccount = async (req: Request, res: Response): Promise<void | Response> => {
    try {
        const { id } = req.params;
        const { adminNotes } = req.body;

        const record = await DeletedAccount.findByPk(id);
        if (!record) {
            return res.status(404).json({ success: false, message: 'Deleted account archive record not found' });
        }

        const user = await User.findByPk(record.originalUserId);
        if (!user) {
            return res.status(404).json({
                success: false,
                message: 'Original user record not found. The user may have been hard-deleted.',
            });
        }

        try {
            await user.update({
                isDeleted: false,
                isActive: true,
                deletedAt: null,
                deletionReason: null,
                email: record.email,
                phone: record.phone,
            } as any);
        } catch (updateError: any) {
            if (updateError.name === 'SequelizeUniqueConstraintError') {
                return res.status(409).json({
                    success: false,
                    message: 'Cannot restore account because the original email or phone number has been registered by a new active user.'
                });
            }
            throw updateError;
        }

        if (adminNotes) {
            record.adminNotes = adminNotes;
            await record.save();
        }

        console.log(`[Admin] Restored deleted account: ${user.email} (originalUserId: ${record.originalUserId})`);

        res.status(200).json({
            success: true,
            message: `Account for ${user.firstName} ${user.lastName} (${user.email}) has been successfully restored.`,
            user: {
                id: user.id,
                email: user.email,
                firstName: user.firstName,
                lastName: user.lastName,
                isActive: user.isActive,
                isDeleted: (user as any).isDeleted,
            },
        });
    } catch (error) {
        console.error('Error restoring deleted account:', error);
        res.status(500).json({ success: false, message: 'Server Error restoring account' });
    }
};
