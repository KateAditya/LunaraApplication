import express from 'express';
import * as userController from '../controllers/userController';
import { authenticate, authorize } from '../middleware/auth';
import { UserRole } from '../models/User';

const router = express.Router();

/**
 * Param validator to ensure :id is a valid UUID
 */
router.param('id', (_req, res, next, id) => {
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!uuidRegex.test(id)) {
        res.status(400).json({
            success: false,
            message: 'Invalid ID format. Must be a valid UUID.'
        });
        return;
    }
    next();
});

/**
 * All routes in this file require Authentication and Admin Role
 */
router.use(authenticate);
router.use(authorize(UserRole.ADMIN));

// ─────────────────────────────────────────────────────────────────────────────
// User Management
// ─────────────────────────────────────────────────────────────────────────────

/**
 * @route   GET /api/users
 * @desc    Get all users with optional filtering
 * @access  Private (Admin)
 */
router.get('/', userController.getUsers);

/**
 * @route   GET /api/users/autoblocked
 * @desc    Get all autoblocked users
 * @access  Private (Admin)
 */
router.get('/autoblocked', userController.getAutoblockedUsers);

/**
 * @route   GET /api/users/reported
 * @desc    Get all reported users
 * @access  Private (Admin)
 */
router.get('/reported', userController.getReportedUsers);

// ─────────────────────────────────────────────────────────────────────────────
// Deleted Accounts Archive — must be registered BEFORE /:id routes to avoid
// the UUID param validator intercepting 'deleted-accounts' as an :id value.
// ─────────────────────────────────────────────────────────────────────────────

/**
 * @route   GET /api/users/deleted-accounts
 * @desc    List all permanently deleted accounts (audit log)
 * @access  Private (Admin)
 * @query   page, limit, search, from (ISO date), to (ISO date)
 */
router.get('/deleted-accounts', userController.getDeletedAccounts);

/**
 * @route   GET /api/users/deleted-accounts/:id
 * @desc    Get full details of a single deleted account archive record
 * @access  Private (Admin)
 */
router.get('/deleted-accounts/:id', userController.getDeletedAccountById);

/**
 * @route   PATCH /api/users/deleted-accounts/:id/notes
 * @desc    Update admin notes on a deleted account record
 * @access  Private (Admin)
 */
router.patch('/deleted-accounts/:id/notes', userController.updateDeletedAccountNotes);

/**
 * @route   POST /api/users/deleted-accounts/:id/restore
 * @desc    Restore (un-delete) a soft-deleted account
 * @access  Private (Admin)
 */
router.post('/deleted-accounts/:id/restore', userController.restoreDeletedAccount);

// ─────────────────────────────────────────────────────────────────────────────
// Individual User CRUD
// ─────────────────────────────────────────────────────────────────────────────

/**
 * @route   POST /api/users/:id/unblock
 * @desc    Unblock an autoblocked user
 * @access  Private (Admin)
 */
router.post('/:id/unblock', userController.unblockUserByAdmin);

/**
 * @route   GET /api/users/:id
 * @desc    Get a single user by ID
 * @access  Private (Admin)
 */
router.get('/:id', userController.getUserById);

/**
 * @route   POST /api/users
 * @desc    Create a new user manually
 * @access  Private (Admin)
 */
router.post('/', userController.createUser);

/**
 * @route   PUT /api/users/:id
 * @desc    Update an existing user's details
 * @access  Private (Admin)
 */
router.put('/:id', userController.updateUser);

/**
 * @route   DELETE /api/users/:id
 * @desc    Delete a user completely
 * @access  Private (Admin)
 */
router.delete('/:id', userController.deleteUser);

export default router;
