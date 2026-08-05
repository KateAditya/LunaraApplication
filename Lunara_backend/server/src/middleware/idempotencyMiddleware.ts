import { Request, Response, NextFunction } from 'express';
import { logger } from '../config/logger';

// In-memory cache for idempotency keys (can be swapped with Redis in production)
const idempotencyCache = new Map<string, { status: number; body: any; timestamp: number }>();

// TTL: 24 Hours
const CACHE_TTL_MS = 24 * 60 * 60 * 1000;

export const idempotencyGuard = (req: Request, res: Response, next: NextFunction): void => {
    try {
        const key = (req.headers['idempotency-key'] || req.headers['x-idempotency-key']) as string | undefined;

        if (!key) {
            // If no idempotency key provided, proceed normally
            next();
            return;
        }

        const cached = idempotencyCache.get(key);
        if (cached) {
            const age = Date.now() - cached.timestamp;
            if (age < CACHE_TTL_MS) {
                logger.info(`[IdempotencyGuard] Idempotent key match found: ${key}. Returning cached response.`);
                res.status(cached.status).json(cached.body);
                return;
            }
            // Expired cache
            idempotencyCache.delete(key);
        }

        // Intercept response write to cache result
        const originalJson = res.json.bind(res);
        res.json = (body: any): Response => {
            if (res.statusCode >= 200 && res.statusCode < 300) {
                idempotencyCache.set(key, {
                    status: res.statusCode,
                    body,
                    timestamp: Date.now(),
                });
            }
            return originalJson(body);
        };

        next();
    } catch (err: any) {
        logger.error('[IdempotencyGuard] Middleware error:', err);
        next();
    }
};
