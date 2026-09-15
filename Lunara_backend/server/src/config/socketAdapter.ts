import { Server as SocketIOServer } from 'socket.io';
import Redis, { Cluster, RedisOptions } from 'ioredis';
import { createAdapter } from '@socket.io/redis-adapter';
import { logger } from './logger';

/**
 * Makes `io.to(room).emit(...)` reach clients connected to a *different* process.
 *
 * Socket.IO keeps its room membership in the memory of the process that owns the
 * connection. The cron jobs emit in at least a dozen places — arrival prompts,
 * plan cancellations, boost expiry, large-party status — via a lazy
 * `require('../server')` to reach `io`. Once those jobs run in their own process
 * (see `cronWorker.ts`), that `io` has no clients attached and every one of those
 * emits would silently go nowhere.
 *
 * The Redis adapter makes each process publish its emits to Redis and deliver
 * anything it receives to its own clients. Every existing `io.to(...).emit(...)`
 * call site then works unchanged across processes, which is why this is wired
 * here rather than by rewriting those call sites.
 *
 * Connection settings mirror `config/redis.ts` so both use the same Azure
 * Managed Redis instance and the same TLS quirks.
 */
export async function attachRedisAdapter(io: SocketIOServer): Promise<boolean> {
    // Every integration test imports `../server`, which evaluates this at module
    // scope. Opening real Redis sockets there would leave handles behind and
    // hang Jest, so tests never attach the adapter regardless of configuration.
    if (process.env.NODE_ENV === 'test') return false;

    const host = process.env.REDIS_HOST;
    if (!host) {
        // Local development without Redis keeps today's behaviour exactly:
        // a single process owning both the sockets and the cron jobs.
        logger.info(
            '[SocketAdapter] REDIS_HOST not configured — sockets remain single-process. ' +
            'Cron jobs must run in-process (RUN_CRON unset/true) for their realtime events to be delivered.'
        );
        return false;
    }

    const port = parseInt(process.env.REDIS_PORT || '10000', 10);
    const useTls = process.env.REDIS_TLS !== 'false';
    const isClusterPolicy = process.env.REDIS_CLUSTER === 'true';

    const redisOptions: RedisOptions = {
        password: process.env.REDIS_PASSWORD || undefined,
        tls: useTls ? { servername: host, rejectUnauthorized: false } : undefined,
        connectTimeout: 10000,
        // The adapter's subscriber connection must not give up on a command mid
        // reconnect, or pub/sub silently stops delivering. `null` is what the
        // adapter documents for ioredis.
        maxRetriesPerRequest: null,
        enableReadyCheck: true,
        lazyConnect: true,
        retryStrategy(times) {
            if (times > 10) {
                logger.warn('[SocketAdapter] Max reconnection attempts reached.');
                return null;
            }
            return Math.min(times * 1000, 3000);
        },
    };

    // Built per branch rather than via `.duplicate()` on a `Redis | Cluster`
    // union, which TypeScript cannot resolve to a single call signature.
    const build = (): Redis | Cluster =>
        isClusterPolicy
            ? new Redis.Cluster([{ host, port }], {
                  redisOptions,
                  dnsLookup: (hostname, callback) => callback(null, hostname),
                  natMap: { [`${host}:${port}`]: { host, port } },
              })
            : new Redis(port, host, redisOptions);

    let pubClient: Redis | Cluster | undefined;
    let subClient: Redis | Cluster | undefined;

    try {
        pubClient = build();
        subClient = build();

        await Promise.all([pubClient.connect(), subClient.connect()]);

        io.adapter(createAdapter(pubClient as any, subClient as any));
        logger.info(
            `[SocketAdapter] Redis adapter attached (${host}:${port}) — socket emits now fan out across processes.`
        );
        return true;
    } catch (err: any) {
        // Never let a Redis problem stop the API from serving. Without the
        // adapter the process still delivers to its own clients; only
        // cross-process emits are lost, and that is logged loudly because it is
        // otherwise invisible.
        logger.error(
            `[SocketAdapter] FAILED to attach Redis adapter: ${err?.message}. ` +
            'Continuing single-process — realtime events emitted by the cron worker will NOT reach clients.'
        );
        try { pubClient?.disconnect(); } catch { /* already down */ }
        try { subClient?.disconnect(); } catch { /* already down */ }
        return false;
    }
}
