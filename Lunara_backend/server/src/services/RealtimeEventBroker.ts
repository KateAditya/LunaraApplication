import { logger } from '../config/logger';
import { v4 as uuidv4 } from 'uuid';

export interface RealtimeEventEnvelope<T = any> {
    eventId: string;
    type: string;
    entity: 'party_plan' | 'stranger_meet' | 'group_party' | 'large_party' | 'venue' | 'user' | 'chat' | 'notification' | 'payment' | 'wallet' | 'ticket' | 'vip' | 'system';
    entityId: string;
    version: number;
    updatedAt: string;
    data?: T;
}

export class RealtimeEventBroker {
    private static getSocketIO(): any {
        try {
            const { io } = require('../server');
            return io;
        } catch (err) {
            logger.warn('[RealtimeEventBroker] Socket.IO server not available yet:', err);
            return null;
        }
    }

    /**
     * Build standard event envelope with unique eventId and ISO timestamp
     */
    public static createEnvelope<T>(
        type: string,
        entity: RealtimeEventEnvelope['entity'],
        entityId: string,
        data?: T,
        version: number = Date.now()
    ): RealtimeEventEnvelope<T> {
        return {
            eventId: `evt_${uuidv4().replace(/-/g, '')}`,
            type,
            entity,
            entityId: String(entityId),
            version,
            updatedAt: new Date().toISOString(),
            data,
        };
    }

    /**
     * Dispatch an event to a single user's private room
     */
    public static emitToUser<T>(
        userId: string,
        type: string,
        entity: RealtimeEventEnvelope['entity'],
        entityId: string,
        data?: T,
        version?: number
    ): RealtimeEventEnvelope<T> | null {
        if (!userId) return null;
        const envelope = this.createEnvelope(type, entity, entityId, data, version);
        const io = this.getSocketIO();
        if (io) {
            io.to(`user_${userId}`).emit(type, envelope);
            io.to(`user_${userId}`).emit('realtime_event', envelope);
        }
        return envelope;
    }

    /**
     * Dispatch an event to multiple specific users (e.g. host & invitee, match partners)
     */
    public static emitToUsers<T>(
        userIds: string[],
        type: string,
        entity: RealtimeEventEnvelope['entity'],
        entityId: string,
        data?: T,
        version?: number
    ): RealtimeEventEnvelope<T> | null {
        const cleanIds = Array.from(new Set(userIds.filter(Boolean)));
        if (cleanIds.length === 0) return null;
        const envelope = this.createEnvelope(type, entity, entityId, data, version);
        const io = this.getSocketIO();
        if (io) {
            for (const uid of cleanIds) {
                io.to(`user_${uid}`).emit(type, envelope);
                io.to(`user_${uid}`).emit('realtime_event', envelope);
            }
        }
        return envelope;
    }

    /**
     * Dispatch a public event to the Live Feed room (only for public plans / stranger meets)
     */
    public static emitToLiveFeed<T>(
        type: string,
        entity: RealtimeEventEnvelope['entity'],
        entityId: string,
        data?: T,
        version?: number
    ): RealtimeEventEnvelope<T> | null {
        const envelope = this.createEnvelope(type, entity, entityId, data, version);
        const io = this.getSocketIO();
        if (io) {
            io.to('live_feed').emit(type, envelope);
            io.to('live_feed').emit('realtime_event', envelope);
        }
        return envelope;
    }

    /**
     * Dispatch to a city/area room (e.g. for venues, local events)
     */
    public static emitToCity<T>(
        city: string,
        type: string,
        entity: RealtimeEventEnvelope['entity'],
        entityId: string,
        data?: T,
        version?: number
    ): RealtimeEventEnvelope<T> | null {
        if (!city) return null;
        const envelope = this.createEnvelope(type, entity, entityId, data, version);
        const io = this.getSocketIO();
        if (io) {
            const cleanCity = city.trim().toLowerCase().replace(/\s+/g, '_');
            io.to(`city_${cleanCity}`).emit(type, envelope);
            io.to(`city_${cleanCity}`).emit('realtime_event', envelope);
        }
        return envelope;
    }

    /**
     * Broadcast globally (used sparingly for critical app-wide updates like ads)
     */
    public static broadcast<T>(
        type: string,
        entity: RealtimeEventEnvelope['entity'],
        entityId: string,
        data?: T,
        version?: number
    ): RealtimeEventEnvelope<T> | null {
        const envelope = this.createEnvelope(type, entity, entityId, data, version);
        const io = this.getSocketIO();
        if (io) {
            io.emit(type, envelope);
            io.emit('realtime_event', envelope);
        }
        return envelope;
    }
}
