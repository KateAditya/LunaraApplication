import { Request, Response, NextFunction } from 'express';
import { validationResult } from 'express-validator';

/**
 * Validation middleware to check for express-validator errors
 */
export function validate(req: Request, res: Response, next: NextFunction): void | Response {
    const errors = validationResult(req);

    if (!errors.isEmpty()) {
        const errorMessages = errors.array().map((error: any) => ({
            field: error.param || error.path,
            message: error.msg,
        }));

        return res.status(400).json({
            success: false,
            message: 'Validation failed',
            errors: errorMessages,
        });
    }

    next();
}

export default validate;
