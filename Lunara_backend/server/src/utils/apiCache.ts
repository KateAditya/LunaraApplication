interface CacheEntry<T> {
    data: T;
    expiresAt: number;
}

export class ApiCache {
    private cache = new Map<string, CacheEntry<any>>();
    private cleanupInterval: NodeJS.Timeout | null = null;

    constructor() {
        // Run sweep every 60 seconds to evict expired items
        this.cleanupInterval = setInterval(() => {
            const now = Date.now();
            for (const [key, entry] of this.cache.entries()) {
                if (entry.expiresAt <= now) {
                    this.cache.delete(key);
                }
            }
        }, 60000);

        if (this.cleanupInterval.unref) {
            this.cleanupInterval.unref();
        }
    }

    public get<T>(key: string): T | null {
        const entry = this.cache.get(key);
        if (!entry) return null;
        if (entry.expiresAt <= Date.now()) {
            this.cache.delete(key);
            return null;
        }
        return entry.data as T;
    }

    public set<T>(key: string, data: T, ttlSeconds: number = 60): void {
        this.cache.set(key, {
            data,
            expiresAt: Date.now() + ttlSeconds * 1000,
        });
    }

    public delete(key: string): void {
        this.cache.delete(key);
    }

    public invalidatePrefix(prefix: string): void {
        const normalizedPrefix = prefix.toLowerCase();
        for (const key of this.cache.keys()) {
            if (key.toLowerCase().startsWith(normalizedPrefix) || key.toLowerCase().includes(normalizedPrefix)) {
                this.cache.delete(key);
            }
        }
    }

    public invalidatePattern(pattern: string): void {
        this.invalidatePrefix(pattern);
    }

    public clear(): void {
        this.cache.clear();
    }

    public size(): number {
        return this.cache.size;
    }
}

export const apiCache = new ApiCache();
export default apiCache;
