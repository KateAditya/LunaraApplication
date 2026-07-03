import express from 'express';
import * as userController from '../controllers/userController';
import { authenticate, authorize } from '../middleware/auth';
import { UserRole } from '../models/User';

const router = express.Router();

/**
 * All routes in this file require Authentication and Admin Role
 */
router.use(authenticate);
router.use(authorize(UserRole.ADMIN));

/**
 * @route   GET /api/users
 * @desc    Get all users with optional filtering
 * @access  Private (Admin)
 */
router.get('/', userController.getUsers);

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
