import winston from 'winston';
import path from 'path';

const logLevel = process.env.LOG_LEVEL || 'info';

const logFormat = winston.format.combine(
    winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
    winston.format.errors({ stack: true }),
    winston.format.splat(),
    winston.format.json()
);

const consoleFormat = winston.format.combine(
    winston.format.colorize(),
    winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
    winston.format.printf(({ timestamp, level, message, ...meta }) => {
        let msg = `${timestamp} [${level}]: ${message}`;
        if (Object.keys(meta).length > 0) {
            msg += ` ${JSON.stringify(meta)}`;
        }
        return msg;
    })
);

export const logger = winston.createLogger({
    level: logLevel,
    format: logFormat,
    transports: [
        // Console output
        new winston.transports.Console({
            format: consoleFormat,
        }),
        // Error log file
        new winston.transports.File({
            filename: path.join('logs', 'error.log'),
            level: 'error',
            // Without a cap these files grow without bound. On Azure App Service
            // the log directory is a network share, so appending to a very large
            // file adds latency to every request that writes one.
            maxsize: 10 * 1024 * 1024, // 10 MB per file
            maxFiles: 5,
            tailable: true,
        }),
        // Combined log file
        new winston.transports.File({
            filename: path.join('logs', 'combined.log'),
            maxsize: 10 * 1024 * 1024, // 10 MB per file
            maxFiles: 5,
            tailable: true,
        }),
    ],
});

// Create a stream object for Morgan
export const stream = {
    write: (message: string) => {
        logger.info(message.trim());
    },
};
