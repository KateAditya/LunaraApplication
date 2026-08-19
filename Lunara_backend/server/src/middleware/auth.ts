import { Request, Response, NextFunction } from 'express';
import { verifyAccessToken } from '../utils/jwt';
import { logger } from '../config/logger';
import User, { UserRole } from '../models/User';

// Extend Express Request to include user
declare global {
    namespace Express {
        interface Request {
            user?: {
                id: string;
                email: string;
                role: UserRole;
            };
        }
    }
}

/**
 * Authentication middleware - verifies JWT token
 */
export async function authenticate(req: Request, res: Response, next: NextFunction): Promise<void | Response> {
    try {
        // Get token from header
        const authHeader = req.headers.authorization;
        if (!authHeader || !authHeader.startsWith('Bearer ')) {
            return res.status(401).json({
                success: false,
                message: 'No token provided. Please login.',
            });
        }

        const token = authHeader.substring(7); // Remove 'Bearer ' prefix

        // If in development mode and using demo-access-token, bypass verification and use a mock admin user.
        // Requires BOTH NODE_ENV=development AND an explicit opt-in flag, so a
        // misconfigured/unset NODE_ENV in production can never satisfy this alone.
        if (process.env.NODE_ENV === 'development' && process.env.ALLOW_DEMO_TOKEN === 'true' && token === 'demo-access-token') {
            const adminUser = await User.findOne({ where: { role: UserRole.ADMIN } });
            req.user = {
                id: adminUser?.id || 'demo-admin-001',
                email: adminUser?.email || 'admin@lunara.com',
                role: (adminUser?.role as UserRole) || UserRole.ADMIN,
            };
            return next();
        }

        // Verify token
        const decoded = verifyAccessToken(token);

        // Get user from database with lean attributes (fast index lookup)
        const user = await User.findByPk(decoded.userId, {
            attributes: ['id', 'email', 'role', 'isActive', 'isAutoblocked', 'autoblockedReason', 'lastLoginAt'],
        });
        if (!user) {
            return res.status(401).json({
                success: false,
                message: 'User not found. Please login again.',
            });
        }

        // Check if user is active or auto-blocked
        if (!user.isActive || user.isAutoblocked) {
            if (user.isAutoblocked) {
                return res.status(403).json({
                    success: false,
                    code: 'USER_AUTOBLOCKED',
                    message: `You are autoblocked due to: ${user.autoblockedReason || 'safety reports/guidelines violation'}.`,
                    autoblockedReason: user.autoblockedReason || 'safety reports/guidelines violation',
                });
            }
            return res.status(403).json({
                success: false,
                message: 'Account is deactivated. Please contact support.',
            });
        }

        // Attach user to request
        req.user = {
            id: user.id,
            email: user.email,
            role: user.role,
        };

        // Non-blocking, throttled last-active update (at most once every 15 minutes, fire-and-forget)
        const fifteenMinutesAgo = Date.now() - 15 * 60 * 1000;
        if (!user.lastLoginAt || new Date(user.lastLoginAt).getTime() < fifteenMinutesAgo) {
            User.update({ lastLoginAt: new Date() }, { where: { id: user.id } }).catch(() => {});
        }

        next();
    } catch (error: any) {
        logger.error('Authentication error:', error);

        if (error.message === 'Token expired') {
            return res.status(401).json({
                success: false,
                message: 'Token expired. Please login again.',
            });
        }

        return res.status(401).json({
            success: false,
            message: 'Invalid token. Please login again.',
        });
    }
}

/**
 * Optional authentication - doesn't fail if no token
 */
export async function optionalAuth(req: Request, _res: Response, next: NextFunction): Promise<void> {
    try {
        const authHeader = req.headers.authorization;
        if (authHeader && authHeader.startsWith('Bearer ')) {
            const token = authHeader.substring(7);
            const decoded = verifyAccessToken(token);

            const user = await User.findByPk(decoded.userId, {
                attributes: ['id', 'email', 'role', 'isActive'],
            });
            if (user && user.isActive) {
                req.user = {
                    id: user.id,
                    email: user.email,
                    role: user.role,
                };
            }
        }
    } catch (error) {
        // Silently fail for optional auth
        logger.debug('Optional auth failed:', error);
    }

    next();
}

/**
 * Authorization middleware - checks user role
 */
export function authorize(...allowedRoles: UserRole[]) {
    return (req: Request, res: Response, next: NextFunction): void | Response => {
        if (!req.user) {
            return res.status(401).json({
                success: false,
                message: 'Authentication required.',
            });
        }

        if (!allowedRoles.includes(req.user.role as UserRole)) {
            return res.status(403).json({
                success: false,
                message: 'You do not have permission to access this resource.',
            });
        }

        next();
    };
}

/**
 * Verify email middleware - checks if user has verified email
 */
export function requireEmailVerification(req: Request, res: Response, next: NextFunction): void | Response {
    if (!req.user) {
        return res.status(401).json({
            success: false,
            message: 'Authentication required.',
        });
    }

    // This would need to check the user's email verification status
    // For now, we'll assume it's checked in the authenticate middleware
    next();
}

export default {
    authenticate,
    optionalAuth,
    authorize,
    requireEmailVerification,
};
