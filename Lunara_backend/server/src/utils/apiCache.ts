import { redisService } from '../config/redis';

interface CacheEntry<T> {
    data: T;
    expiresAt: number;
}

export class ApiCache {
    private localCache = new Map<string, CacheEntry<any>>();
    private cleanupInterval: NodeJS.Timeout | null = null;

    constructor() {
        // Run sweep every 60 seconds to evict expired local cache items
        this.cleanupInterval = setInterval(() => {
            const now = Date.now();
            for (const [key, entry] of this.localCache.entries()) {
                if (entry.expiresAt <= now) {
                    this.localCache.delete(key);
                }
            }
        }, 60000);

        if (this.cleanupInterval.unref) {
            this.cleanupInterval.unref();
        }
    }

    public get<T>(key: string): T | null {
        // Fast local memory cache check
        const entry = this.localCache.get(key);
        if (entry) {
            if (entry.expiresAt <= Date.now()) {
                this.localCache.delete(key);
            } else {
                return entry.data as T;
            }
        }
        return null;
    }

    public async getAsync<T>(key: string): Promise<T | null> {
        // 1. Try local memory
        const local = this.get<T>(key);
        if (local !== null) return local;

        // 2. Try Redis
        const remote = await redisService.get<T>(key);
        if (remote !== null) {
            // Populate local short-lived L1 cache
            this.setLocal(key, remote, 10);
            return remote;
        }

        return null;
    }

    public set<T>(key: string, data: T, ttlSeconds: number = 60): void {
        this.setLocal(key, data, ttlSeconds);
        // Persist to Azure Redis in background
        redisService.set(key, data, ttlSeconds).catch(() => {});
    }

    private setLocal<T>(key: string, data: T, ttlSeconds: number = 60): void {
        this.localCache.set(key, {
            data,
            expiresAt: Date.now() + ttlSeconds * 1000,
        });
    }

    public delete(key: string): void {
        this.localCache.delete(key);
        redisService.del(key).catch(() => {});
    }

    public invalidatePrefix(prefix: string): void {
        const normalizedPrefix = prefix.toLowerCase();
        for (const key of this.localCache.keys()) {
            if (key.toLowerCase().startsWith(normalizedPrefix) || key.toLowerCase().includes(normalizedPrefix)) {
                this.localCache.delete(key);
            }
        }
        redisService.invalidatePattern(`*${prefix}*`).catch(() => {});
    }

    public invalidatePattern(pattern: string): void {
        this.invalidatePrefix(pattern);
    }

    public clear(): void {
        this.localCache.clear();
    }
}

export const apiCache = new ApiCache();
export default apiCache;
