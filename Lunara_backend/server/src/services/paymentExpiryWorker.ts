import { GroupPartyService } from './GroupPartyService';
import { logger } from '../config/logger';

let isRunning = false;

/**
 * Sweeps abandoned group party orders that have remained in PENDING status
 * for > 10 minutes without payment completion, cancelling them to release TimeLocks.
 */
export const sweepAbandonedGroupParties = async (): Promise<void> => {
    if (isRunning) return;
    isRunning = true;

    try {
        const expiredCount = await GroupPartyService.expireAbandonedPendingOrders();
        if (expiredCount > 0) {
            logger.info(`[PaymentExpiryWorker] Successfully swept and expired ${expiredCount} abandoned group party pending orders.`);
        }
    } catch (err) {
        logger.error('[PaymentExpiryWorker] Error sweeping abandoned orders:', err);
    } finally {
        isRunning = false;
    }
};

/**
 * Starts periodic background scheduler for abandoned order cleanup (e.g. every 5 minutes).
 */
export const startPaymentExpiryWorker = (intervalMs: number = 5 * 60 * 1000): NodeJS.Timeout => {
    logger.info('[PaymentExpiryWorker] Starting background payment expiry worker...');
    // Initial run
    sweepAbandonedGroupParties();
    return setInterval(sweepAbandonedGroupParties, intervalMs);
};
