import { Router, Request, Response } from 'express';
import sequelize from '../config/database';

const router = Router();

/**
 * POST /api/db-restore
 * Temporary endpoint to restore DB from SQL dump.
 * Protected by BOOTSTRAP_SECRET.
 * REMOVE THIS FILE AFTER USE.
 */
router.post('/restore', async (req: Request, res: Response) => {
    try {
        const { secret, sql } = req.body;
        const bootstrapSecret = process.env.BOOTSTRAP_SECRET || 'lunara-bootstrap-2026';
        if (!secret || secret !== bootstrapSecret) {
            return res.status(403).json({ success: false, message: 'Invalid secret' });
        }
        if (!sql || typeof sql !== 'string') {
            return res.status(400).json({ success: false, message: 'sql field required' });
        }

        // Split on semicolons that end SQL statements (not inside strings)
        // Execute each statement individually to isolate errors
        const statements = sql
            .split(/;\s*\n/)
            .map((s: string) => s.trim())
            .filter((s: string) => s.length > 0 && !s.startsWith('--') && !s.startsWith('\\'));

        const errors: string[] = [];
        let executed = 0;

        for (const stmt of statements) {
            try {
                await sequelize.query(stmt + ';');
                executed++;
            } catch (err: any) {
                // Skip duplicate object errors and "already exists" — idempotent restore
                const msg = err.message || '';
                if (
                    msg.includes('already exists') ||
                    msg.includes('duplicate key') ||
                    msg.includes('relation') ||
                    msg.includes('does not exist')  // some DROP IF EXISTS
                ) {
                    // ignore — safe to continue
                } else {
                    errors.push(`STMT[${executed}]: ${msg.substring(0, 200)}`);
                }
            }
        }

        return res.json({
            success: true,
            executed,
            totalStatements: statements.length,
            errors: errors.slice(0, 20),
        });
    } catch (err: any) {
        return res.status(500).json({ success: false, message: err.message });
    }
});

export default router;
