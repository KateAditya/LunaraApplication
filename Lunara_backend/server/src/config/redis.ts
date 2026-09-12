import Redis, { Cluster, RedisOptions } from 'ioredis';
import { logger } from './logger';
import dotenv from 'dotenv';

dotenv.config();

// In-memory fallback map if Redis is not configured or temporarily unreachable
const inMemoryFallback = new Map<string, { data: any; expiresAt: number }>();

class RedisService {
    private client: Redis | Cluster | null = null;
    private isConnected: boolean = false;

    constructor() {
        this.initClient();
    }

    private initClient(): void {
        const host = process.env.REDIS_HOST;
        const port = parseInt(process.env.REDIS_PORT || '10000', 10);
        const password = process.env.REDIS_PASSWORD;
        const useTls = process.env.REDIS_TLS !== 'false';
        const isClusterPolicy = process.env.REDIS_CLUSTER === 'true';

        if (!host) {
            logger.info('[Redis] REDIS_HOST not configured. Operating in high-speed In-Memory Cache mode.');
            return;
        }

        try {
            const redisOptions: RedisOptions = {
                password: password || undefined,
                tls: useTls ? { servername: host, rejectUnauthorized: false } : undefined,
                connectTimeout: 10000,
                maxRetriesPerRequest: 2,
                enableReadyCheck: true,
                lazyConnect: true,
                retryStrategy(times) {
                    if (times > 10) {
                        logger.warn('[Redis] Max reconnection attempts reached. Using memory fallback.');
                        return null; // Stop retrying
                    }
                    return Math.min(times * 1000, 3000);
                },
            };

            // Azure Managed Redis with OSSCluster policy
            if (isClusterPolicy) {
                this.client = new Redis.Cluster(
                    [{ host, port }],
                    {
                        redisOptions,
                        scaleReads: 'all',
                        dnsLookup: (hostname, callback) => callback(null, hostname),
                        natMap: {
                            [`${host}:${port}`]: { host, port },
                        },
                    }
                );
            } else {
                this.client = new Redis(port, host, redisOptions);
            }

            this.client.on('connect', () => {
                this.isConnected = true;
                logger.info(`[Redis] 🚀 Successfully connected to Azure Managed Redis (${host}:${port})`);
            });

            this.client.on('ready', () => {
                this.isConnected = true;
                logger.info('[Redis] Azure Redis is ready for commands.');
            });

            this.client.on('error', (err: any) => {
                this.isConnected = false;
                logger.warn(`[Redis] Connection warning: ${err.message}. Falling back to memory cache.`);
            });

            this.client.on('close', () => {
                this.isConnected = false;
            });

            // Asynchronously connect without blocking Node.js event loop
            this.client.connect().catch((err: any) => {
                logger.warn(`[Redis] Non-blocking connect notice: ${err.message}`);
            });
        } catch (err: any) {
            logger.error(`[Redis] Initialization failed: ${err.message}. Using memory fallback.`);
            this.client = null;
            this.isConnected = false;
        }
    }

    public async get<T = any>(key: string): Promise<T | null> {
        if (this.isConnected && this.client) {
            try {
                const data = await this.client.get(key);
                return data ? JSON.parse(data) : null;
            } catch (err: any) {
                logger.warn(`[Redis] GET error for key ${key}: ${err.message}`);
            }
        }

        // Fallback to in-memory
        const item = inMemoryFallback.get(key);
        if (item) {
            if (Date.now() > item.expiresAt) {
                inMemoryFallback.delete(key);
                return null;
            }
            return item.data as T;
        }
        return null;
    }

    public async set(key: string, value: any, ttlSeconds: number = 60): Promise<void> {
        const serialized = JSON.stringify(value);

        if (this.isConnected && this.client) {
            try {
                if (ttlSeconds > 0) {
                    await this.client.set(key, serialized, 'EX', ttlSeconds);
                } else {
                    await this.client.set(key, serialized);
                }
                return;
            } catch (err: any) {
                logger.warn(`[Redis] SET error for key ${key}: ${err.message}`);
            }
        }

        // Fallback to in-memory
        inMemoryFallback.set(key, {
            data: value,
            expiresAt: Date.now() + ttlSeconds * 1000,
        });
    }

    public async del(key: string): Promise<void> {
        if (this.isConnected && this.client) {
            try {
                await this.client.del(key);
            } catch (err: any) {
                logger.warn(`[Redis] DEL error for key ${key}: ${err.message}`);
            }
        }
        inMemoryFallback.delete(key);
    }

    public async invalidatePattern(pattern: string): Promise<void> {
        if (this.isConnected && this.client) {
            try {
                const keys = await (this.client as any).keys(pattern);
                if (keys && keys.length > 0) {
                    await (this.client as any).del(...keys);
                }
            } catch (err: any) {
                logger.warn(`[Redis] Pattern invalidation error for ${pattern}: ${err.message}`);
            }
        }

        // In-memory pattern cleanup
        const regex = new RegExp(`^${pattern.replace(/\*/g, '.*')}$`);
        for (const k of inMemoryFallback.keys()) {
            if (regex.test(k)) {
                inMemoryFallback.delete(k);
            }
        }
    }

    public getRawClient(): Redis | Cluster | null {
        return this.client;
    }

    public isReady(): boolean {
        return this.isConnected;
    }
}

export const redisService = new RedisService();
