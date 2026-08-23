export enum NotificationEventType {
    // Partner Matching & Interest
    INTEREST_MARKED = 'INTEREST_MARKED',
    INTEREST_REMOVED = 'INTEREST_REMOVED',
    NEW_INTERESTED_PARTNER = 'NEW_INTERESTED_PARTNER',
    PARTNER_REQUEST_SENT = 'PARTNER_REQUEST_SENT',
    PARTNER_REQUEST_RECEIVED = 'PARTNER_REQUEST_RECEIVED',
    PARTNER_REQUEST_ACCEPTED = 'PARTNER_REQUEST_ACCEPTED',
    PARTNER_REQUEST_DECLINED = 'PARTNER_REQUEST_DECLINED',
    PARTNER_REQUEST_CANCELLED = 'PARTNER_REQUEST_CANCELLED',
    PARTNER_REQUEST_EXPIRED = 'PARTNER_REQUEST_EXPIRED',
    MATCH_CREATED = 'MATCH_CREATED',
    MATCH_EXPIRED = 'MATCH_EXPIRED',

    // Upcoming Nights
    UPCOMING_NIGHT_CREATED = 'UPCOMING_NIGHT_CREATED',
    UPCOMING_NIGHT_UPDATED = 'UPCOMING_NIGHT_UPDATED',
    UPCOMING_NIGHT_CANCELLED = 'UPCOMING_NIGHT_CANCELLED',
    UPCOMING_NIGHT_STARTING_SOON = 'UPCOMING_NIGHT_STARTING_SOON',

    // Booking
    BOOKING_CREATED = 'BOOKING_CREATED',
    BOOKING_PENDING = 'BOOKING_PENDING',
    BOOKING_CONFIRMED = 'BOOKING_CONFIRMED',
    BOOKING_CANCELLED = 'BOOKING_CANCELLED',
    BOOKING_REJECTED = 'BOOKING_REJECTED',
    BOOKING_EXPIRED = 'BOOKING_EXPIRED',

    // Payment
    PAYMENT_REQUIRED = 'PAYMENT_REQUIRED',
    PAYMENT_SUCCESS = 'PAYMENT_SUCCESS',
    PAYMENT_FAILED = 'PAYMENT_FAILED',
    PAYMENT_EXPIRED = 'PAYMENT_EXPIRED',
    REFUND_INITIATED = 'REFUND_INITIATED',
    REFUND_COMPLETED = 'REFUND_COMPLETED',

    // Chat
    NEW_MESSAGE = 'NEW_MESSAGE',
    MESSAGE_REPLY = 'MESSAGE_REPLY',
    CHAT_UNLOCKED = 'CHAT_UNLOCKED',

    // Group Party
    GROUP_INVITE_SENT = 'GROUP_INVITE_SENT',
    GROUP_INVITE_ACCEPTED = 'GROUP_INVITE_ACCEPTED',
    GROUP_MEMBER_JOINED = 'GROUP_MEMBER_JOINED',
    GROUP_FULL = 'GROUP_FULL',

    // Stranger Meet
    STRANGER_MEET_REQUEST = 'STRANGER_MEET_REQUEST',
    STRANGER_MEET_ACCEPTED = 'STRANGER_MEET_ACCEPTED',
    STRANGER_MEET_DECLINED = 'STRANGER_MEET_DECLINED',
    STRANGER_MEET_MATCHED = 'STRANGER_MEET_MATCHED',

    // Admin & System
    ADMIN_APPROVED = 'ADMIN_APPROVED',
    ADMIN_REJECTED = 'ADMIN_REJECTED',
    ACCOUNT_WARNING = 'ACCOUNT_WARNING',
    SYSTEM_ANNOUNCEMENT = 'SYSTEM_ANNOUNCEMENT',

    // Schedule / Time-Lock
    SCHEDULE_UNLOCKED = 'SCHEDULE_UNLOCKED',
}

export type NotificationCategory =
    | 'requests'
    | 'matches'
    | 'bookings'
    | 'messages'
    | 'payments'
    | 'events'
    | 'system'
    | 'alert'
    | 'activity'
    | 'super_like'
    | 'likes';

export type NotificationPriority = 'CRITICAL' | 'HIGH' | 'NORMAL' | 'LOW';

export interface NotificationPayload {
    recipientUserId: string;
    actorUserId?: string;
    eventType: NotificationEventType | string;
    category: NotificationCategory;
    entityType?: string;
    entityId?: string;
    title: string;
    body: string;
    imageUrl?: string;
    actionType?: string;
    deepLink?: string;
    priority?: NotificationPriority;
    idempotencyKey?: string;
    metadata?: Record<string, any>;
    expiresAt?: Date;
}
