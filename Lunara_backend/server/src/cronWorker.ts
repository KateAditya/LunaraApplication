/**
 * Dedicated process for every scheduled job.
 *
 * WHY THIS EXISTS
 * ---------------
 * The cron jobs used to run inside the HTTP process. node-cron reported
 * "missed execution ... Possible blocking IO or high CPU user at the same
 * process used by node-cron", which is the event loop being held past a
 * scheduled tick. The same stall stops Node accepting sockets: the kernel
 * accept queue overflows, SYNs are dropped, and the client waits out TCP
 * retransmission backoff. Measured from outside, that showed up as 13-21 second
 * hangs on requests the server answered in under 100ms — including `/health`,
 * which performs no I/O whatsoever. Removing the jobs from the web process cut
 * the stall rate roughly fourfold.
 *
 * Running them here gives them their own event loop, so however long a job
 * takes it can no longer delay an HTTP request.
 *
 * WHY IT IMPORTS ./server
 * -----------------------
 * The jobs reach Socket.IO through a lazy `require('../server')` (see
 * `cron/boostCron.ts`) to avoid a circular import. Importing the module here
 * gives them the same `io` object they already expect, so not one of those
 * emit call sites has to change. `startServer()` is guarded by
 * `require.main === module`, so importing it does NOT open a second HTTP
 * listener — this process never binds a port.
 *
 * The emits reach real clients because `socketAdapterReady` attaches the Redis
 * adapter, which fans each emit out across processes. Without Redis configured
 * that fan-out cannot happen, so this worker refuses to start rather than run
 * jobs whose notifications would silently vanish.
 */
import dotenv from 'dotenv';
import { logger } from './config/logger';
import { connectDatabase } from './config/database';
import { startBackgroundJobs, socketAdapterReady } from './server';

dotenv.config();

const main = async (): Promise<void> => {
    logger.info(`[CronWorker] Starting background job process ${process.pid}...`);

    await connectDatabase();

    const adapterAttached = await socketAdapterReady;
    if (!adapterAttached) {
        // Refusing here is deliberate. Starting anyway would run every job
        // correctly while their realtime notifications — arrival prompts, plan
        // cancellations, boost expiry — disappeared with no error anywhere. A
        // loud crash-loop is far easier to notice than silently missing pushes,
        // and the parent's restart backoff keeps retrying in case Redis is just
        // slow to come up.
        logger.error(
            '[CronWorker] Socket adapter is not attached, so realtime events from this process would never reach clients. ' +
            'Refusing to start jobs. Configure REDIS_HOST, or set RUN_CRON=false and run jobs in the web process.'
        );
        process.exit(1);
    }

    startBackgroundJobs();
    logger.info(`[CronWorker] Ready (pid ${process.pid}).`);
};

// A job process that dies quietly takes reminders, payment timeouts and expiry
// with it. Exit loudly instead so the parent's restart logic takes over.
process.on('unhandledRejection', (reason) => {
    logger.error('[CronWorker] Unhandled rejection:', reason);
});
process.on('uncaughtException', (err) => {
    logger.error('[CronWorker] Uncaught exception, exiting for restart:', err);
    process.exit(1);
});
process.on('SIGTERM', () => {
    logger.info('[CronWorker] SIGTERM received, shutting down.');
    process.exit(0);
});

main().catch((err) => {
    logger.error('[CronWorker] Failed to start:', err);
    process.exit(1);
});
