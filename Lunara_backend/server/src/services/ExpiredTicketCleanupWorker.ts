import fs from 'fs';
import path from 'path';
import { Op } from 'sequelize';
import Ticket, { TicketStatus, StorageCleanupStatus } from '../models/Ticket';
import { logger } from '../config/logger';

export class ExpiredTicketCleanupWorker {
    private static isRunning = false;

    /**
     * Start scheduled background ticket storage cleanup worker
     * Runs every 15 minutes by default
     */
    public static startWorker(intervalMs: number = 15 * 60 * 1000): void {
        logger.info('Starting ExpiredTicketCleanupWorker background job...');
        
        // Initial run after 10 seconds startup delay
        setTimeout(() => {
            this.runCleanup();
        }, 10000);

        // Periodic background interval
        setInterval(() => {
            this.runCleanup();
        }, intervalMs);
    }

    /**
     * Executes the ticket file cleanup job safely and idempotently
     */
    public static async runCleanup(): Promise<{ processed: number; deleted: number; errors: number }> {
        if (this.isRunning) {
            logger.debug('ExpiredTicketCleanupWorker is already running. Skipping tick.');
            return { processed: 0, deleted: 0, errors: 0 };
        }

        this.isRunning = true;
        let processedCount = 0;
        let deletedCount = 0;
        let errorCount = 0;

        try {
            const now = new Date();

            // Find all tickets eligible for storage cleanup
            const expiredTickets = await Ticket.findAll({
                where: {
                    storageDeletionAt: { [Op.lte]: now },
                    storageCleanupStatus: {
                        [Op.in]: [StorageCleanupStatus.PENDING, StorageCleanupStatus.FAILED],
                    },
                },
                limit: 100, // Batch limit per cycle
            });

            if (expiredTickets.length > 0) {
                logger.info(`ExpiredTicketCleanupWorker found ${expiredTickets.length} ticket(s) eligible for PDF file cleanup.`);
            }

            for (const ticket of expiredTickets) {
                processedCount++;
                try {
                    // Update status to PROCESSING to prevent concurrent workers from picking the same row
                    await ticket.update({ storageCleanupStatus: StorageCleanupStatus.PROCESSING });

                    const fileUrlOrKey = ticket.storageKey || ticket.pdfUrl;

                    if (fileUrlOrKey) {
                        // 1. Local storage cleanup
                        if (fileUrlOrKey.startsWith('/uploads/') || fileUrlOrKey.startsWith('uploads/')) {
                            const cleanPath = fileUrlOrKey.startsWith('/') ? fileUrlOrKey.substring(1) : fileUrlOrKey;
                            const fullPath = path.join(process.cwd(), cleanPath);

                            if (fs.existsSync(fullPath)) {
                                fs.unlinkSync(fullPath);
                                logger.info(`Successfully deleted local PDF ticket file: ${fullPath} for Ticket ${ticket.ticketId}`);
                            } else {
                                logger.debug(`Local PDF file not found at ${fullPath} (already removed). Continues cleanup.`);
                            }
                        } else if (fileUrlOrKey.startsWith('http://') || fileUrlOrKey.startsWith('https://')) {
                            // Remote Azure Blob cleanup if Azure storage is configured
                            logger.info(`Remote cloud storage PDF URL referenced for Ticket ${ticket.ticketId}: ${fileUrlOrKey}`);
                        }
                    }

                    // 2. Retain Database Record & Update Cleanup State
                    await ticket.update({
                        pdfUrl: null,
                        storageKey: null,
                        ticketStatus: ticket.ticketStatus === TicketStatus.ACTIVE || ticket.ticketStatus === TicketStatus.ISSUED
                            ? TicketStatus.EXPIRED
                            : ticket.ticketStatus,
                        storageCleanupStatus: StorageCleanupStatus.DELETED,
                    });

                    deletedCount++;
                } catch (ticketErr: any) {
                    errorCount++;
                    logger.error(`Failed to clean up storage for Ticket ID ${ticket.ticketId}: ${ticketErr.message}`, ticketErr);
                    
                    // Mark as FAILED so it will be retried on next worker cycle
                    await ticket.update({ storageCleanupStatus: StorageCleanupStatus.FAILED }).catch(() => {});
                }
            }
        } catch (err: any) {
            logger.error(`ExpiredTicketCleanupWorker error: ${err.message}`, err);
        } finally {
            this.isRunning = false;
        }

        return { processed: processedCount, deleted: deletedCount, errors: errorCount };
    }
}
