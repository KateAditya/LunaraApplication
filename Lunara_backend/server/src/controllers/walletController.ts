import { Request, Response } from 'express';
import { Op } from 'sequelize';
import { logger } from '../config/logger';
import PartyPlan from '../models/PartyPlan';
import PartyPlanRequest from '../models/PartyPlanRequest';
import Payment from '../models/Payment';
import Booking, { GoingMode } from '../models/Booking';
import Venue from '../models/Venue';
import VenueImage from '../models/VenueImage';
import User from '../models/User';
import UserPhoto from '../models/UserPhoto';
import UserProfile from '../models/UserProfile';
import { PartyPlanPaymentStatus } from '../models/PartyPlan';
import { PartyPlanRequestStatus, PartyPlanJoinerPaymentStatus } from '../models/PartyPlanRequest';
import StrangersMeetRequest, { StrangersMeetStatus, StrangersMeetPaymentStatus } from '../models/StrangersMeetRequest';
import StrangersMeetJoiner, { StrangersMeetJoinerPaymentStatus } from '../models/StrangersMeetJoiner';
import SubscriptionTransaction from '../models/SubscriptionTransaction';
import SubscriptionPackage, { PackageTier } from '../models/SubscriptionPackage';
import WalletTransaction from '../models/WalletTransaction';

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/wallet?userId=<uuid>
// Returns:
//   incompleteEvents: party plans the user paid for (as host OR joiner) that
//                     are not yet fully matched / confirmed
//   transactions:     all Payment records linked to this user, enriched with
//                     booking / party-plan context
// ─────────────────────────────────────────────────────────────────────────────
export const getWalletData = async (req: Request, res: Response): Promise<void> => {
    try {
        const userId = req.user!.id;

        // ── 1. Incomplete Events ─────────────────────────────────────────────
        //
        // Case A – User is the HOST and has already paid the deposit,
        //          but the event hasn't been fully confirmed (no accepted joiner
        //          with joiner payment PAID, or plan is still ACTIVE/INACTIVE).
        const hostPlans = await PartyPlan.findAll({
            where: {
                userId,
                hostPaymentStatus: PartyPlanPaymentStatus.PAID,
                status: { [Op.in]: ['active', 'inactive'] },
            },
            include: [
                {
                    model: Venue,
                    as: 'venue',
                    attributes: ['id', 'name', 'addressLine1', 'area', 'city'],
                    include: [
                        {
                            model: VenueImage,
                            as: 'images',
                            attributes: ['filePath', 'imageType', 'isPrimary'],
                            where: { imageType: 'cover', isPrimary: true },
                            required: false,
                        },
                    ],
                },
                {
                    model: PartyPlanRequest,
                    as: 'requests',
                    where: {
                        status: {
                            [Op.in]: [
                                PartyPlanRequestStatus.PENDING,
                                PartyPlanRequestStatus.PAYMENT_PENDING,
                                PartyPlanRequestStatus.ACCEPTED,
                            ],
                        },
                    },
                    required: false,
                    include: [
                        {
                            model: User,
                            as: 'requester',
                            attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'],
                            include: [
                                {
                                    model: UserPhoto,
                                    as: 'photos',
                                    where: { isPrimary: true },
                                    required: false,
                                    attributes: ['filePath'],
                                },
                            ],
                        },
                    ],
                },
            ],
        });

        // Case B – User is a JOINER who has paid the deposit,
        //          but the plan hasn't been fully confirmed yet.
        const joinerRequests = await PartyPlanRequest.findAll({
            where: {
                requesterId: userId,
                joinerPaymentStatus: PartyPlanJoinerPaymentStatus.PAID,
                status: {
                    [Op.in]: [
                        PartyPlanRequestStatus.PAYMENT_PENDING,
                        PartyPlanRequestStatus.ACCEPTED,
                    ],
                },
            },
            include: [
                {
                    model: PartyPlan,
                    as: 'plan',
                    where: { status: { [Op.in]: ['active', 'inactive'] } },
                    required: true,
                    include: [
                        {
                            model: Venue,
                            as: 'venue',
                            attributes: ['id', 'name', 'addressLine1', 'area', 'city'],
                            include: [
                                {
                                    model: VenueImage,
                                    as: 'images',
                                    attributes: ['filePath', 'imageType', 'isPrimary'],
                                    where: { imageType: 'cover', isPrimary: true },
                                    required: false,
                                },
                            ],
                        },
                        {
                            model: User,
                            as: 'creator',
                            attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'],
                            include: [
                                {
                                    model: UserProfile,
                                    as: 'profile',
                                    attributes: ['occupation'],
                                    required: false,
                                },
                                {
                                    model: UserPhoto,
                                    as: 'photos',
                                    where: { isPrimary: true },
                                    required: false,
                                    attributes: ['filePath'],
                                },
                            ],
                        },
                    ],
                },
            ],
        });

        // Case C – User is Strangers Meet Host, safety deposit PAID, but meet is not completed
        const hostStrangersMeets = await StrangersMeetRequest.findAll({
            where: {
                userId,
                paymentStatus: StrangersMeetPaymentStatus.PAID,
                status: { [Op.in]: [StrangersMeetStatus.PENDING, StrangersMeetStatus.APPROVED] },
            },
            include: [
                {
                    model: Venue,
                    as: 'venue',
                    attributes: ['id', 'name', 'addressLine1', 'area', 'city'],
                    include: [
                        {
                            model: VenueImage,
                            as: 'images',
                            attributes: ['filePath', 'imageType', 'isPrimary'],
                            where: { imageType: 'cover', isPrimary: true },
                            required: false,
                        },
                    ],
                },
                {
                    model: StrangersMeetJoiner,
                    as: 'joiners',
                    required: false,
                    include: [
                        {
                            model: User,
                            as: 'user',
                            attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'],
                            include: [
                                {
                                    model: UserPhoto,
                                    as: 'photos',
                                    where: { isPrimary: true },
                                    required: false,
                                    attributes: ['filePath'],
                                },
                            ],
                        },
                    ],
                },
            ],
        });

        // Case D – User is Strangers Meet Joiner, join fee PAID, but meet is not completed
        const joinerStrangersMeets = await StrangersMeetJoiner.findAll({
            where: {
                userId,
                paymentStatus: StrangersMeetJoinerPaymentStatus.PAID,
            },
            include: [
                {
                    model: StrangersMeetRequest,
                    as: 'strangersMeetRequest',
                    where: {
                        status: { [Op.in]: [StrangersMeetStatus.PENDING, StrangersMeetStatus.APPROVED] }
                    },
                    required: true,
                    include: [
                        {
                            model: Venue,
                            as: 'venue',
                            attributes: ['id', 'name', 'addressLine1', 'area', 'city'],
                            include: [
                                {
                                    model: VenueImage,
                                    as: 'images',
                                    attributes: ['filePath', 'imageType', 'isPrimary'],
                                    where: { imageType: 'cover', isPrimary: true },
                                    required: false,
                                },
                            ],
                        },
                        {
                            model: User,
                            as: 'user',
                            attributes: ['id', 'firstName', 'lastName', 'profileImageUrl'],
                            include: [
                                {
                                    model: UserPhoto,
                                    as: 'photos',
                                    where: { isPrimary: true },
                                    required: false,
                                    attributes: ['filePath'],
                                },
                            ],
                        },
                    ],
                },
            ],
        });

        // Build a unified incomplete-events list
        const buildVenueCover = (venue: any): string | null => {
            const img = venue?.images?.[0];
            if (!img) return null;
            if (img.filePath.startsWith('http')) return img.filePath;
            return `${process.env.AZURE_STORAGE_BASE_URL || ''}/${img.filePath.replace(/\\/g, '/')}`;
        };

        const incompleteEvents: any[] = [];

        // Host-paid plans
        for (const plan of hostPlans) {
            const venue = (plan as any).venue;
            const requests = (plan as any).requests ?? [];
            const activeRequest = requests.find((r: any) =>
                [PartyPlanRequestStatus.PAYMENT_PENDING, PartyPlanRequestStatus.ACCEPTED].includes(r.status)
            ) || requests[0] || null;

            const requester = activeRequest ? activeRequest.requester : null;
            const requesterProfileUrl = requester?.profileImageUrl ??
                (requester?.photos?.[0]?.filePath
                    ? `/${requester.photos[0].filePath.replace(/\\/g, '/')}`
                    : null);

            incompleteEvents.push({
                eventId: plan.id,
                role: 'host',
                type: 'party_plan',
                planDateTime: plan.planDateTime,
                depositAmount: Number(plan.depositAmount),
                paymentStatus: plan.paymentStatus,
                planStatus: plan.status,
                hostPaymentStatus: plan.hostPaymentStatus,
                waitingFor: activeRequest
                    ? (activeRequest.joinerPaymentStatus === PartyPlanJoinerPaymentStatus.PAID
                        ? 'Confirmation'
                        : 'Joiner Payment')
                    : 'Joiner to Apply',
                requestId: activeRequest?.id ?? null,
                joinerPaymentStatus: activeRequest?.joinerPaymentStatus ?? null,
                paymentTimeoutAt: activeRequest?.paymentTimeoutAt ?? null,
                pendingRequestCount: requests.length,
                venue: venue
                    ? {
                          id: venue.id,
                          name: venue.name,
                          addressLine1: venue.addressLine1,
                          area: venue.area,
                          city: venue.city,
                          coverImage: buildVenueCover(venue),
                      }
                    : null,
                joiner: requester
                    ? {
                          id: requester.id,
                          name: `${requester.firstName} ${requester.lastName?.charAt(0) ?? ''}.`,
                          profileImageUrl: requesterProfileUrl,
                      }
                    : null,
                createdAt: plan.createdAt,
            });
        }

        // Joiner-paid requests
        for (const req of joinerRequests) {
            const plan = (req as any).plan;
            if (!plan) continue;
            const venue = (plan as any).venue;
            const creator = (plan as any).creator;
            const creatorProfileUrl = creator?.profileImageUrl ??
                (creator?.photos?.[0]?.filePath
                    ? `/${creator.photos[0].filePath.replace(/\\/g, '/')}`
                    : null);

            incompleteEvents.push({
                eventId: plan.id,
                requestId: req.id,
                role: 'joiner',
                type: 'party_plan',
                planDateTime: plan.planDateTime,
                depositAmount: Number(plan.depositAmount),
                paymentStatus: plan.paymentStatus,
                planStatus: plan.status,
                joinerPaymentStatus: req.joinerPaymentStatus,
                paymentTimeoutAt: req.paymentTimeoutAt,
                waitingFor: plan.hostPaymentStatus === PartyPlanPaymentStatus.PAID
                    ? 'Confirmation'
                    : 'Host Payment',
                venue: venue
                    ? {
                          id: venue.id,
                          name: venue.name,
                          addressLine1: venue.addressLine1,
                          area: venue.area,
                          city: venue.city,
                          coverImage: buildVenueCover(venue),
                      }
                    : null,
                host: creator
                    ? {
                          id: creator.id,
                          name: `${creator.firstName} ${creator.lastName?.charAt(0) ?? ''}.`,
                          profileImageUrl: creatorProfileUrl,
                          occupation: creator.profile?.occupation,
                      }
                    : null,
                createdAt: req.createdAt,
            });
        }

        // Host Strangers Meet plans
        for (const meet of hostStrangersMeets) {
            const venue = (meet as any).venue;
            const joiners = (meet as any).joiners ?? [];
            const paidJoiners = joiners.filter((j: any) => j.paymentStatus === StrangersMeetJoinerPaymentStatus.PAID);
            
            incompleteEvents.push({
                eventId: meet.id,
                role: 'host',
                type: 'strangers_meet',
                planDateTime: meet.eventDateTime,
                depositAmount: Number(meet.paymentAmount || 0),
                paymentStatus: meet.paymentStatus,
                planStatus: meet.status,
                hostPaymentStatus: meet.paymentStatus,
                waitingFor: paidJoiners.length >= meet.numberOfPersons
                    ? 'Confirmation'
                    : 'Participants to Join',
                venue: venue
                    ? {
                          id: venue.id,
                          name: venue.name,
                          addressLine1: venue.addressLine1,
                          area: venue.area,
                          city: venue.city,
                          coverImage: buildVenueCover(venue),
                      }
                    : null,
                createdAt: meet.createdAt,
            });
        }

        // Joiner Strangers Meet requests
        for (const jm of joinerStrangersMeets) {
            const meet = (jm as any).strangersMeetRequest;
            if (!meet) continue;
            const venue = (meet as any).venue;
            const creator = (meet as any).user;
            const creatorProfileUrl = creator?.profileImageUrl ??
                (creator?.photos?.[0]?.filePath
                    ? `/${creator.photos[0].filePath.replace(/\\/g, '/')}`
                    : null);

            incompleteEvents.push({
                eventId: meet.id,
                requestId: jm.id,
                role: 'joiner',
                type: 'strangers_meet',
                planDateTime: meet.eventDateTime,
                depositAmount: Number(jm.paymentAmount || 0),
                paymentStatus: jm.paymentStatus,
                planStatus: meet.status,
                joinerPaymentStatus: jm.paymentStatus,
                waitingFor: 'Meet Completion',
                venue: venue
                    ? {
                          id: venue.id,
                          name: venue.name,
                          addressLine1: venue.addressLine1,
                          area: venue.area,
                          city: venue.city,
                          coverImage: buildVenueCover(venue),
                      }
                    : null,
                host: creator
                    ? {
                          id: creator.id,
                          name: `${creator.firstName} ${creator.lastName?.charAt(0) ?? ''}.`,
                          profileImageUrl: creatorProfileUrl,
                      }
                    : null,
                createdAt: jm.createdAt,
            });
        }

        // Sort incomplete events by planDateTime (ascending — soonest first)
        incompleteEvents.sort((a, b) => new Date(a.planDateTime).getTime() - new Date(b.planDateTime).getTime());

        // ── 2. Transaction History ────────────────────────────────────────────
        const payments = await Payment.findAll({
            where: { userId },
            order: [['createdAt', 'DESC']],
            include: [
                {
                    model: Booking,
                    as: 'booking',
                    attributes: [
                        'id', 'bookingNumber', 'bookingDate', 'startTime',
                        'tablePackage', 'goingMode', 'status', 'totalAmount',
                        'venueId',
                    ],
                    required: false,
                    include: [
                        {
                            model: Venue,
                            as: 'venue',
                            attributes: ['id', 'name', 'addressLine1', 'city'],
                            required: false,
                        },
                    ],
                },
            ],
        });

        // Also pull party-plan payments (stored in gatewayResponse.partyPlanId)
        // plus any host/joiner payment IDs from PartyPlan/PartyPlanRequest
        const hostPartyPayments = await PartyPlan.findAll({
            where: {
                userId,
                hostPaymentStatus: PartyPlanPaymentStatus.PAID,
                hostRazorpayPaymentId: { [Op.ne]: null as any },
            },
            attributes: [
                'id', 'planDateTime', 'depositAmount', 'hostRazorpayOrderId',
                'hostRazorpayPaymentId', 'createdAt',
            ],
            include: [
                {
                    model: Venue,
                    as: 'venue',
                    attributes: ['id', 'name', 'city'],
                },
            ],
        });

        const joinerPartyPayments = await PartyPlanRequest.findAll({
            where: {
                requesterId: userId,
                joinerPaymentStatus: PartyPlanJoinerPaymentStatus.PAID,
                joinerRazorpayPaymentId: { [Op.ne]: null as any },
            },
            attributes: [
                'id', 'planId', 'joinerRazorpayOrderId', 'joinerRazorpayPaymentId',
                'createdAt',
            ],
            include: [
                {
                    model: PartyPlan,
                    as: 'plan',
                    attributes: ['id', 'planDateTime', 'depositAmount'],
                    include: [
                        {
                            model: Venue,
                            as: 'venue',
                            attributes: ['id', 'name', 'city'],
                        },
                    ],
                },
            ],
        });

        // Pull Strangers Meet host payments
        const hostStrangersMeetPayments = await StrangersMeetRequest.findAll({
            where: {
                userId,
                paymentStatus: StrangersMeetPaymentStatus.PAID,
                razorpayPaymentId: { [Op.ne]: null as any },
            },
            attributes: [
                'id', 'eventDateTime', 'paymentAmount', 'razorpayOrderId',
                'razorpayPaymentId', 'createdAt', 'subject',
            ],
            include: [
                {
                    model: Venue,
                    as: 'venue',
                    attributes: ['id', 'name', 'city'],
                },
            ],
        });

        // Pull Strangers Meet joiner payments
        const joinerStrangersMeetPayments = await StrangersMeetJoiner.findAll({
            where: {
                userId,
                paymentStatus: StrangersMeetJoinerPaymentStatus.PAID,
                razorpayPaymentId: { [Op.ne]: null as any },
            },
            attributes: [
                'id', 'strangersMeetRequestId', 'razorpayOrderId', 'razorpayPaymentId',
                'paymentAmount', 'createdAt',
            ],
            include: [
                {
                    model: StrangersMeetRequest,
                    as: 'strangersMeetRequest',
                    attributes: ['id', 'eventDateTime', 'subject'],
                    include: [
                        {
                            model: Venue,
                            as: 'venue',
                            attributes: ['id', 'name', 'city'],
                        },
                    ],
                },
            ],
        });

        // Unified transactions list with strict multi-source deduplication
        const transactions: any[] = [];
        const seenTxnIds = new Set<string>();
        const seenPartyPlanKeys = new Set<string>();
        const seenStrangersMeetKeys = new Set<string>();

        // Standard booking payments
        for (const p of payments) {
            const booking = (p as any).booking;
            const venue = booking?.venue;

            let partyPlanId: string | null = null;
            let strangersMeetId: string | null = null;
            if (booking?.specialRequests) {
                try {
                    const parsedReqs = typeof booking.specialRequests === 'string' ? JSON.parse(booking.specialRequests) : booking.specialRequests;
                    partyPlanId = parsedReqs?.planId || null;
                    strangersMeetId = parsedReqs?.strangersMeetId || parsedReqs?.meetId || null;
                } catch (_) {}
            }

            if (p.transactionId) seenTxnIds.add(p.transactionId);
            if (partyPlanId) seenPartyPlanKeys.add(partyPlanId);
            if (strangersMeetId) seenStrangersMeetKeys.add(strangersMeetId);

            const isPartyDeposit = booking?.goingMode === GoingMode.PARTY_REQUEST || !!partyPlanId;

            transactions.push({
                txnId: p.transactionId,
                paymentId: p.id,
                type: isPartyDeposit ? 'party_plan_deposit' : 'booking',
                amount: Number(p.amount),
                currency: p.currency || 'INR',
                status: p.status,
                paymentMethod: p.paymentMethod,
                paymentGateway: p.paymentGateway,
                refundAmount: Number(p.refundAmount ?? 0),
                refundedAt: p.refundedAt,
                createdAt: p.createdAt,
                context: booking
                    ? {
                          bookingId: booking.id,
                          bookingNumber: booking.bookingNumber,
                          bookingDate: booking.bookingDate,
                          startTime: booking.startTime,
                          tablePackage: booking.tablePackage,
                          goingMode: booking.goingMode,
                          bookingStatus: booking.status,
                          venueName: venue?.name ?? 'Unknown Venue',
                          venueCity: venue?.city ?? '',
                          venueAddress: venue?.addressLine1 ?? '',
                          partyPlanId: partyPlanId || undefined,
                          strangersMeetId: strangersMeetId || undefined,
                          label: isPartyDeposit ? 'Party Plan Deposit' : 'Table Booking',
                      }
                    : null,
            });
        }

        // Host party plan payments (safety deposit)
        for (const plan of hostPartyPayments) {
            if (plan.hostRazorpayPaymentId && seenTxnIds.has(plan.hostRazorpayPaymentId)) continue;
            if (seenPartyPlanKeys.has(plan.id)) continue;
            if (plan.hostRazorpayPaymentId) seenTxnIds.add(plan.hostRazorpayPaymentId);
            seenPartyPlanKeys.add(plan.id);

            const venue = (plan as any).venue;
            transactions.push({
                txnId: plan.hostRazorpayPaymentId,
                paymentId: plan.id,
                type: 'party_plan_deposit',
                role: 'host',
                amount: Number(plan.depositAmount || 99),
                currency: 'INR',
                status: 'successful',
                paymentMethod: 'razorpay',
                paymentGateway: 'razorpay',
                refundAmount: 0,
                refundedAt: null,
                createdAt: plan.createdAt,
                context: {
                    partyPlanId: plan.id,
                    planDateTime: plan.planDateTime,
                    venueName: venue?.name ?? 'Party Venue',
                    venueCity: venue?.city ?? '',
                    label: 'Host Safety Deposit',
                },
            });
        }

        // Joiner party plan payments (safety deposit)
        for (const req of joinerPartyPayments) {
            if (req.joinerRazorpayPaymentId && seenTxnIds.has(req.joinerRazorpayPaymentId)) continue;
            if (seenPartyPlanKeys.has(req.planId) || seenPartyPlanKeys.has(req.id)) continue;
            if (req.joinerRazorpayPaymentId) seenTxnIds.add(req.joinerRazorpayPaymentId);
            seenPartyPlanKeys.add(req.planId);
            seenPartyPlanKeys.add(req.id);

            const plan = (req as any).plan;
            const venue = plan ? (plan as any).venue : null;
            transactions.push({
                txnId: req.joinerRazorpayPaymentId,
                paymentId: req.id,
                type: 'party_plan_deposit',
                role: 'joiner',
                amount: Number(plan?.depositAmount ?? 99),
                currency: 'INR',
                status: 'successful',
                paymentMethod: 'razorpay',
                paymentGateway: 'razorpay',
                refundAmount: 0,
                refundedAt: null,
                createdAt: req.createdAt,
                context: {
                    partyPlanId: req.planId,
                    planDateTime: plan?.planDateTime,
                    venueName: venue?.name ?? 'Party Venue',
                    venueCity: venue?.city ?? '',
                    label: 'Joiner Safety Deposit',
                },
            });
        }

        // Host Strangers Meet payments
        for (const meet of hostStrangersMeetPayments) {
            if (meet.razorpayPaymentId && seenTxnIds.has(meet.razorpayPaymentId)) continue;
            if (seenStrangersMeetKeys.has(meet.id)) continue;
            if (meet.razorpayPaymentId) seenTxnIds.add(meet.razorpayPaymentId);
            seenStrangersMeetKeys.add(meet.id);

            const venue = (meet as any).venue;
            transactions.push({
                txnId: meet.razorpayPaymentId,
                paymentId: meet.id,
                type: 'strangers_meet_deposit',
                role: 'host',
                amount: Number(meet.paymentAmount || 0),
                currency: 'INR',
                status: 'successful',
                paymentMethod: 'razorpay',
                paymentGateway: 'razorpay',
                refundAmount: 0,
                refundedAt: null,
                createdAt: meet.createdAt,
                context: {
                    strangersMeetId: meet.id,
                    planDateTime: meet.eventDateTime,
                    venueName: venue?.name ?? 'Venue',
                    venueCity: venue?.city ?? '',
                    label: 'Host Platform Deposit',
                    subject: meet.subject,
                },
            });
        }

        // Joiner Strangers Meet payments
        for (const jm of joinerStrangersMeetPayments) {
            if (jm.razorpayPaymentId && seenTxnIds.has(jm.razorpayPaymentId)) continue;
            if (seenStrangersMeetKeys.has(jm.id) || seenStrangersMeetKeys.has(jm.strangersMeetRequestId)) continue;
            if (jm.razorpayPaymentId) seenTxnIds.add(jm.razorpayPaymentId);
            seenStrangersMeetKeys.add(jm.id);

            const meet = (jm as any).strangersMeetRequest;
            const venue = meet ? (meet as any).venue : null;
            transactions.push({
                txnId: jm.razorpayPaymentId,
                paymentId: jm.id,
                type: 'strangers_meet_join',
                role: 'joiner',
                amount: Number(jm.paymentAmount || 0),
                currency: 'INR',
                status: 'successful',
                paymentMethod: 'razorpay',
                paymentGateway: 'razorpay',
                refundAmount: 0,
                refundedAt: null,
                createdAt: jm.createdAt,
                context: {
                    strangersMeetId: jm.strangersMeetRequestId,
                    planDateTime: meet?.eventDateTime,
                    venueName: venue?.name ?? 'Venue',
                    venueCity: venue?.city ?? '',
                    label: 'Joiner Fee',
                    subject: meet?.subject ?? 'Strangers Meet',
                },
            });
        }

        // Sort by createdAt descending
        transactions.sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());

        // ── 2b. Subscription Transactions ──────────────────────────────────────
        const subTransactions = await SubscriptionTransaction.findAll({
            where: { userId },
            include: [{ model: SubscriptionPackage, as: 'package', attributes: ['id', 'name', 'tier'] }],
            order: [['created_at', 'DESC']],
        });

        // Tier → icon mapping (sent to client for rendering)
        const tierIconMap: Record<string, string> = {
            FREE: 'free_badge',
            CORE: 'core_badge',
            PLUS: 'plus_badge',
            PRO: 'pro_badge',
            ELITE: 'elite_badge',
        };

        const subscriptionTxns: any[] = subTransactions.map(st => {
            const pkg = (st as any).package;
            const txnTypeDisplay: Record<string, string> = {
                purchase: 'New Subscription',
                upgrade: 'Plan Upgrade',
                downgrade: 'Plan Downgrade',
                renew: 'Subscription Renewal',
                cancel: 'Cancellation',
                expire: 'Plan Expired',
                boost: 'Profile Boost',
                refund: 'Refund',
                trial: 'Trial Activation',
            };

            return {
                txnId: st.id,
                paymentId: st.id,
                invoiceNumber: st.invoiceNumber,
                type: 'subscription',
                subType: st.type,
                amount: Number(st.amount),
                currency: st.currency || 'INR',
                status: st.status,
                paymentMethod: st.paymentMethod || 'razorpay',
                paymentGateway: st.paymentGateway || 'razorpay',
                refundAmount: Number(st.refundAmount ?? 0),
                refundedAt: st.refundedAt,
                createdAt: st.createdAt,
                context: {
                    label: txnTypeDisplay[st.type] ?? 'Subscription',
                    planName: pkg?.name ?? 'Lunara VIP',
                    planTier: pkg?.tier ?? 'FREE',
                    planColor: pkg?.themeColor ?? '#7F00FF',
                    tierIcon: tierIconMap[pkg?.tier ?? 'FREE'] ?? 'core_badge',
                    gatewayOrderId: st.gatewayOrderId,
                    gatewayPaymentId: st.gatewayPaymentId,
                    metadata: st.metadata,
                },
            };
        });

        // ── 3. Summary stats ─────────────────────────────────────────────────
        // Merge all transactions (plan payments + subscription) into a unified list
        const allTransactions = [...transactions, ...subscriptionTxns].sort(
            (a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime()
        );

        const totalSpent = allTransactions
            .filter(t => t.status === 'successful' || t.status === 'success')
            .reduce((sum, t) => sum + t.amount, 0);
        const totalRefunded = allTransactions.reduce((sum, t) => sum + (t.refundAmount ?? 0), 0);
        const totalSubscriptionSpent = subscriptionTxns
            .filter(t => t.status === 'success')
            .reduce((sum, t) => sum + t.amount, 0);

        // ── Auto-heal any missed Party Plan refund for Host or Joiner ──
        try {
            const { PartyPlan, PartyPlanRequest } = await import('../models');
            const { PartyPlanStatus } = await import('../models/PartyPlan');
            const { PartyPlanRequestStatus } = await import('../models/PartyPlanRequest');
            const Op = (await import('sequelize')).Op;

            // Check host cancelled plans
            const hostCancelledPlans = await PartyPlan.findAll({
                where: {
                    userId,
                    [Op.or]: [
                        { status: PartyPlanStatus.CANCELLED },
                        { lifecycleStatus: 'cancelled' },
                        { paymentStatus: { [Op.iLike]: '%refund%' } },
                        { hostPaymentStatus: { [Op.iLike]: '%refund%' } },
                    ],
                },
                attributes: ['id', 'depositAmount', 'paymentStatus', 'hostPaymentStatus', 'hostRazorpayPaymentId'],
                limit: 10,
            });

            for (const plan of hostCancelledPlans) {
                const hostRefundRef = `REFUND_HOST_CANCEL_${plan.id}`;
                const hostCreditRef = `PARTY_PLAN_CANCEL_CREDIT_HOST_${plan.id}`;
                const existingRefund = await WalletTransaction.findOne({
                    where: {
                        userId,
                        partyPlanId: plan.id,
                        [Op.or]: [
                            { reference: hostRefundRef },
                            { reference: hostCreditRef },
                            { transactionType: 'refund' },
                            { transactionType: 'deposit_unlock' },
                        ],
                    },
                });
                if (!existingRefund) {
                    const depositAmt = Number(plan.depositAmount) || 99.00;
                    await WalletService.creditRefund({
                        userId,
                        amount: depositAmt,
                        referenceId: hostRefundRef,
                        reason: 'Party Plan Cancelled Deposit Refund (Auto-Healed)',
                        partyPlanId: plan.id,
                    });
                }
            }

            // Check joiner cancelled requests
            const joinerCancelledRequests = await PartyPlanRequest.findAll({
                where: {
                    requesterId: userId,
                    [Op.or]: [
                        { status: PartyPlanRequestStatus.CANCELLED },
                        { joinerPaymentStatus: { [Op.iLike]: '%refund%' } },
                    ],
                },
                attributes: ['id', 'planId', 'joinerPaymentStatus', 'joinerRazorpayPaymentId'],
                limit: 10,
            });

            for (const reqItem of joinerCancelledRequests) {
                const joinerRefundRef = `REFUND_JOINER_CANCEL_${reqItem.id}`;
                const joinerRepostRef = `REFUND_JOINER_REPOST_${reqItem.id}`;
                const joinerCreditRef = `PARTY_PLAN_CANCEL_CREDIT_JOINER_${reqItem.planId}_${userId}`;
                const existingRefund = await WalletTransaction.findOne({
                    where: {
                        userId,
                        [Op.or]: [
                            { reference: joinerRefundRef },
                            { reference: joinerRepostRef },
                            { reference: joinerCreditRef },
                        ],
                    },
                });
                if (!existingRefund) {
                    await WalletService.creditRefund({
                        userId,
                        amount: 99.00,
                        referenceId: joinerRefundRef,
                        reason: 'Party Plan Request Cancelled Deposit Refund (Auto-Healed)',
                        partyPlanId: reqItem.planId,
                    });
                }
            }
        } catch (autoHealErr: any) {
            logger.warn('[getWalletData] Auto-heal refund error:', autoHealErr.message);
        }

        const smartWallet = await WalletService.getOrCreateWallet(userId);
        await smartWallet.reload();
        const config = await WalletService.getGlobalConfig();
        const rawSmartTransactions = await WalletTransaction.findAll({
            where: { userId },
            order: [['createdAt', 'DESC']],
            limit: 50,
        });

        const { WalletTransactionType, WalletTransactionStatus } = await import('../models/WalletTransaction');

        // Exclude smart transactions that duplicate gateway ledger entries, but keep all refunds & deposit unlocks
        const smartTransactions = rawSmartTransactions.filter(st => {
            if (st.transactionType === WalletTransactionType.REFUND || st.transactionType === WalletTransactionType.DEPOSIT_UNLOCK) {
                return true;
            }
            if (st.reference && seenTxnIds.has(st.reference)) return false;
            if (st.partyPlanId && seenPartyPlanKeys.has(st.partyPlanId) && (st as any).source === 'razorpay') return false;
            return true;
        });

        const totalRechargedFromTxns = rawSmartTransactions
            .filter(t => t.transactionType === WalletTransactionType.RECHARGE && t.status === WalletTransactionStatus.SUCCESS)
            .reduce((sum, t) => sum + Number(t.amount || 0), 0);

        const calculatedLifetimeRecharged = Math.max(Number(smartWallet.lifetimeRecharged || 0), totalRechargedFromTxns);
        const calculatedLifetimeSpent = Math.max(Number(smartWallet.lifetimeSpent || 0), totalSpent);
        const calculatedLifetimeRefunds = Math.max(Number(smartWallet.lifetimeRefunds || 0), totalRefunded);

        res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate');
        res.json({
            success: true,
            data: {
                wallet: {
                    id: smartWallet.id,
                    userId: smartWallet.userId,
                    availableBalance: Number(smartWallet.totalAvailableBalance || smartWallet.balance || 0),
                    balance: Number(smartWallet.balance || 0),
                    lockedBalance: Number(smartWallet.lockedBalance || 0),
                    pendingBalance: Number(smartWallet.pendingBalance || 0),
                    promotionalBalance: Number(smartWallet.promotionalBalance || 0),
                    cashbackBalance: Number(smartWallet.cashbackBalance || 0),
                    rewardBalance: Number(smartWallet.rewardBalance || 0),
                    lifetimeRecharged: Math.round(calculatedLifetimeRecharged * 100) / 100,
                    lifetimeSpent: Math.round(calculatedLifetimeSpent * 100) / 100,
                    lifetimePromotional: Number(smartWallet.lifetimePromotional || 0),
                    lifetimeCashback: Number(smartWallet.lifetimeCashback || 0),
                    lifetimeRewards: Number(smartWallet.lifetimeRewards || 0),
                    lifetimeRefunds: Math.round(calculatedLifetimeRefunds * 100) / 100,
                    isFrozen: smartWallet.isFrozen,
                    frozenReason: smartWallet.frozenReason,
                },
                config: {
                    minRecharge: config.minRechargeAmount,
                    maxRecharge: config.maxRechargeAmount,
                    suggestedAmounts: config.suggestedAmounts,
                    isWalletActive: config.isWalletActive,
                },
                incompleteEvents,
                transactions: allTransactions,
                smartTransactions,
                summary: {
                    totalIncompleteEvents: incompleteEvents.length,
                    totalTransactions: allTransactions.length + smartTransactions.length,
                    totalRecharged: Math.round(calculatedLifetimeRecharged * 100) / 100,
                    totalSpent: Math.round(calculatedLifetimeSpent * 100) / 100,
                    totalRefunded: Math.round(calculatedLifetimeRefunds * 100) / 100,
                    totalSubscriptionSpent: Math.round(totalSubscriptionSpent * 100) / 100,
                },
            },
        });
    } catch (err: any) {
        logger.error('getWalletData error:', err);
        res.status(500).json({ success: false, message: 'Failed to fetch wallet data', error: err.message });
    }
};

import WalletService from '../services/walletService';

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/wallet/pay-with-wallet
// Processes booking / party deposit spending using Smart Credit Wallet
// ─────────────────────────────────────────────────────────────────────────────
export const payWithWallet = async (req: Request, res: Response): Promise<void> => {
    try {
        const { amount, planId, bookingId, paymentType = 'booking_payment' } = req.body;
        const userId = req.user!.id;

        if (!amount) {
            res.status(400).json({ success: false, message: 'amount is required' });
            return;
        }

        const requiredAmount = Number(amount);
        if (isNaN(requiredAmount) || requiredAmount <= 0) {
            res.status(400).json({ success: false, message: 'Invalid payment amount' });
            return;
        }

        const sanitizeId = (raw: any): string | undefined => {
            if (!raw) return undefined;
            const clean = String(raw)
                .replace(/^group_party_timeline_/, '')
                .replace(/^large_party_timeline_/, '')
                .replace(/^solo_booking_/, '')
                .replace(/^party_plan_timeline_/, '')
                .replace(/^group_party_/, '')
                .replace(/^large_party_/, '')
                .replace(/^party_plan_/, '')
                .replace(/^booking_/, '')
                .replace(/^group_/, '')
                .replace(/^party_/, '')
                .replace(/^req_/, '')
                .trim();
            const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(clean);
            return isUuid ? clean : undefined;
        };

        const cleanBookingId = sanitizeId(bookingId);
        const cleanPlanId = sanitizeId(planId);

        if (paymentType === 'commitment_deposit' || paymentType === 'host_deposit') {
            const lockResult = await WalletService.lockDeposit({
                userId,
                amount: requiredAmount,
                partyPlanId: cleanPlanId,
                bookingId: cleanBookingId,
            });
            const txnId = lockResult.txn?.id || `lock_${Date.now()}`;
            res.json({
                success: true,
                message: 'Commitment deposit locked in wallet successfully!',
                data: {
                    transactionId: txnId,
                    txnId,
                    wallet: lockResult.wallet,
                    availableBalance: Number(lockResult.wallet.totalAvailableBalance.toFixed(2)),
                    txn: lockResult.txn,
                },
            });
            return;
        }

        const WalletTransactionType = (await import('../models/WalletTransaction')).WalletTransactionType;
        const purchaseResult = await WalletService.purchaseFeatureWithCredit({
            userId,
            price: requiredAmount,
            transactionType: WalletTransactionType.BOOKING_PAYMENT,
            reference: `BOOK_${cleanPlanId || cleanBookingId || Date.now()}`,
            bookingId: cleanBookingId,
            partyPlanId: cleanPlanId,
            metadata: { paymentType, rawBookingId: bookingId, rawPlanId: planId },
        });

        const txnId = purchaseResult.txn?.id || purchaseResult.data?.transactionId || `pay_${Date.now()}`;
        const walletObj = purchaseResult.wallet || purchaseResult.data?.wallet;
        const availableBal = walletObj
            ? Number(walletObj.totalAvailableBalance.toFixed(2))
            : (purchaseResult.data?.availableBalance || 0);

        res.json({
            success: true,
            message: 'Wallet booking payment successful!',
            data: {
                transactionId: txnId,
                txnId,
                wallet: walletObj,
                availableBalance: availableBal,
                txn: purchaseResult.txn || purchaseResult.data?.txn,
            },
        });
    } catch (err: any) {
        if (err.statusCode === 402) {
            res.status(402).json({
                success: false,
                insufficientBalance: true,
                message: 'Insufficient wallet balance. Recharge missing amount to auto-complete booking.',
                data: err.shortfallData,
            });
            return;
        }
        logger.error('payWithWallet error:', err);
        res.status(500).json({ success: false, message: err.message || 'Wallet payment failed' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/wallet/recharge-order
// Creates Razorpay Order for Smart Wallet Recharge
// ─────────────────────────────────────────────────────────────────────────────
export const createRechargeOrder = async (req: Request, res: Response): Promise<void> => {
    try {
        const { amount, autoContinueSession } = req.body;
        const userId = req.user!.id;
        if (!amount) {
            res.status(400).json({ success: false, message: 'amount is required' });
            return;
        }

        const rechargeAmount = Number(amount);
        const config = await WalletService.getGlobalConfig();
        if (rechargeAmount < Number(config.minRechargeAmount) || rechargeAmount > Number(config.maxRechargeAmount)) {
            res.status(400).json({
                success: false,
                message: `Recharge amount must be between ₹${config.minRechargeAmount} and ₹${config.maxRechargeAmount}`,
            });
            return;
        }

        let razorpayOrder = null;
        if (process.env.RAZORPAY_KEY_ID && process.env.RAZORPAY_KEY_SECRET) {
            const Razorpay = require('razorpay');
            const razorpay = new Razorpay({
                key_id: process.env.RAZORPAY_KEY_ID,
                key_secret: process.env.RAZORPAY_KEY_SECRET,
            });
            razorpayOrder = await razorpay.orders.create({
                amount: Math.round(rechargeAmount * 100),
                currency: 'INR',
                receipt: `WAL_${userId.substring(0, 8)}_${Date.now()}`,
                notes: { userId, type: 'WALLET_RECHARGE' },
            });
        } else {
            razorpayOrder = {
                id: `order_sim_${Date.now()}`,
                amount: Math.round(rechargeAmount * 100),
                currency: 'INR',
            };
        }

        res.json({
            success: true,
            message: 'Razorpay recharge order created successfully',
            data: {
                orderId: razorpayOrder.id,
                amount: rechargeAmount,
                currency: 'INR',
                keyId: process.env.RAZORPAY_KEY_ID || 'rzp_test_fallback',
                autoContinueSession: autoContinueSession || null,
            },
        });
    } catch (err: any) {
        logger.error('createRechargeOrder error:', err);
        res.status(500).json({ success: false, message: 'Failed to create Razorpay recharge order', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/wallet/verify-recharge
// Recharges user wallet after Razorpay signature verification
// ─────────────────────────────────────────────────────────────────────────────
export const verifyRechargePayment = async (req: Request, res: Response): Promise<void> => {
    try {
        const { amount, razorpayOrderId, razorpayPaymentId, razorpaySignature, autoContinueSession } = req.body;
        const userId = req.user!.id;
        const result = await WalletService.rechargeWalletWithRazorpay({
            userId,
            amount: Number(amount),
            razorpayOrderId,
            razorpayPaymentId,
            razorpaySignature,
            autoContinueSession,
        });
        res.json(result);
    } catch (err: any) {
        logger.error('verifyRechargePayment error:', err);
        res.status(500).json({ success: false, message: err.message || 'Failed to verify wallet recharge payment' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/wallet/recharge (Direct Fallback)
// ─────────────────────────────────────────────────────────────────────────────
export const rechargeWallet = async (req: Request, res: Response): Promise<void> => {
    try {
        const { amount, paymentId = `PAY_${Date.now()}` } = req.body;
        const userId = req.user!.id;
        const result = await WalletService.rechargeWalletWithRazorpay({
            userId,
            amount: Number(amount),
            razorpayPaymentId: paymentId,
        });
        res.json(result);
    } catch (err: any) {
        logger.error('rechargeWallet error:', err);
        res.status(500).json({ success: false, message: err.message || 'Wallet recharge failed' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/wallet/pay-vip
// Purchases/Renews/Upgrades VIP membership using Smart Credit Wallet
// ─────────────────────────────────────────────────────────────────────────────
export const payVipWithWallet = async (req: Request, res: Response): Promise<void> => {
    try {
        const { packageId } = req.body;
        const userId = req.user!.id;

        // Price is never trusted from the client — always sourced from the
        // package record itself, which is the only authoritative price.
        const pkg = await SubscriptionPackage.findOne({ where: { id: packageId, isActive: true } });
        if (!pkg) {
            res.status(400).json({ success: false, message: 'Invalid or inactive subscription package' });
            return;
        }

        const requiredPrice = Number(pkg.price);
        const tier = pkg.tier;

        // Execute Feature Purchase via WalletService Engine
        const WalletTransactionType = (await import('../models/WalletTransaction')).WalletTransactionType;
        const purchaseResult = await WalletService.purchaseFeatureWithCredit({
            userId,
            price: requiredPrice,
            transactionType: WalletTransactionType.VIP_PURCHASE,
            reference: `VIP_${tier}_${Date.now()}`,
            metadata: { packageId, tier },
        });

        // Activate User Subscription
        const UserSubscriptionModel = (await import('../models/UserSubscription')).default;
        const SubscriptionStatusEnum = (await import('../models/UserSubscription')).SubscriptionStatus;

        const durationDays = pkg.durationDays;
        const superlikesRemaining = pkg.superlikesPerCycle;
        const boostsRemaining = pkg.boostsPerCycle;

        // Deactivate/Expire any FREE stub or stranded 2099 subscription when upgrading to a paid package
        if (pkg.tier !== PackageTier.FREE) {
            await UserSubscriptionModel.update(
                { status: SubscriptionStatusEnum.EXPIRED },
                {
                    where: {
                        userId,
                        status: { [Op.in]: [SubscriptionStatusEnum.ACTIVE, SubscriptionStatusEnum.UPCOMING] },
                        [Op.or]: [
                            { endDate: { [Op.gte]: new Date(2050, 0, 1) } },
                            { startDate: { [Op.gte]: new Date(2050, 0, 1) } },
                        ]
                    }
                }
            );
        }

        // Find the latest legitimate upcoming or active subscription to determine start date
        const lastUpcoming = await UserSubscriptionModel.findOne({
            where: {
                userId,
                status: SubscriptionStatusEnum.UPCOMING,
                endDate: { [Op.lt]: new Date(2050, 0, 1) }
            },
            include: [{ model: SubscriptionPackage, as: 'package', where: { tier: { [Op.ne]: PackageTier.FREE } }, required: true }],
            order: [['endDate', 'DESC']]
        });
        
        const activeSubForDate = await UserSubscriptionModel.findOne({
            where: {
                userId,
                status: SubscriptionStatusEnum.ACTIVE,
                endDate: { [Op.gt]: new Date(), [Op.lt]: new Date(2050, 0, 1) }
            },
            include: [{ model: SubscriptionPackage, as: 'package', where: { tier: { [Op.ne]: PackageTier.FREE } }, required: true }],
        });

        const startDate = new Date();
        if (lastUpcoming && lastUpcoming.endDate > startDate) {
            startDate.setTime(lastUpcoming.endDate.getTime());
        } else if (activeSubForDate && activeSubForDate.endDate > startDate) {
            startDate.setTime(activeSubForDate.endDate.getTime());
        }

        const validUntil = new Date(startDate);
        validUntil.setDate(validUntil.getDate() + durationDays);

        const newStatus = startDate > new Date() ? SubscriptionStatusEnum.UPCOMING : SubscriptionStatusEnum.ACTIVE;

        const sub = await UserSubscriptionModel.create({
            userId,
            packageId: pkg.id,
            status: newStatus,
            startDate,
            endDate: validUntil,
            superlikesRemaining,
            boostsRemaining,
            autoRenew: false,
        });

        const { SubscriptionService } = await import('../services/subscriptionService');
        SubscriptionService.invalidateCache(userId);

        res.json({
            success: true,
            message: `🎉 VIP Membership (${tier}) is now active!`,
            data: {
                userId,
                tier,
                pricePaid: requiredPrice,
                remainingBalance: purchaseResult.data.remainingBalance,
                subscriptionId: sub.id,
                validUntil: validUntil.toISOString(),
            },
        });
    } catch (err: any) {
        if (err.statusCode === 402) {
            res.status(402).json({
                success: false,
                insufficientBalance: true,
                message: 'Insufficient Smart Credit Wallet balance.',
                data: err.shortfallData,
            });
            return;
        }
        logger.error('payVipWithWallet error:', err);
        res.status(500).json({ success: false, message: err.message || 'VIP wallet purchase failed' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/wallet/pay-super-likes
// ─────────────────────────────────────────────────────────────────────────────
// Server-authoritative pricing for à la carte credit purchases — matches the
// Boost Profile pricing already used by mobileSubscriptionController.ts's
// Razorpay boost flow (₹49/₹90/₹140/₹160 for 1/2/3/5). Client-supplied price
// is never trusted.
const CREDIT_PRICE_TABLE: Record<number, number> = { 1: 49, 2: 90, 3: 140, 5: 160 };

async function findOrCreateSubscriptionForCredit(userId: string) {
    const UserSubscriptionModel = (await import('../models/UserSubscription')).default;
    const SubscriptionStatusEnum = (await import('../models/UserSubscription')).SubscriptionStatus;
    const { PackageTier } = await import('../models/SubscriptionPackage');

    let sub = await UserSubscriptionModel.findOne({
        where: { userId, status: SubscriptionStatusEnum.ACTIVE, endDate: { [Op.gt]: new Date() } },
        order: [['createdAt', 'DESC']],
    });

    if (!sub) {
        let freePackage = await SubscriptionPackage.findOne({ where: { tier: PackageTier.FREE } });
        if (!freePackage) {
            freePackage = await SubscriptionPackage.findOne({ order: [['price', 'ASC']] });
        }
        if (!freePackage) {
            const err: any = new Error('No subscription package found to link credit purchase');
            err.statusCode = 400;
            throw err;
        }
        sub = await UserSubscriptionModel.create({
            userId,
            packageId: freePackage.id,
            status: SubscriptionStatusEnum.ACTIVE,
            startDate: new Date(),
            endDate: new Date(2099, 0, 1),
            superlikesRemaining: 0,
            boostsRemaining: 0,
        });
    }
    return sub;
}

export const paySuperLikesWithWallet = async (req: Request, res: Response): Promise<void> => {
    try {
        const { count } = req.body;
        const userId = req.user!.id;
        const purchaseCount = Number(count);

        const price = CREDIT_PRICE_TABLE[purchaseCount];
        if (!price) {
            res.status(400).json({ success: false, message: 'Invalid Super Like count' });
            return;
        }

        const sub = await findOrCreateSubscriptionForCredit(userId);

        const WalletTransactionType = (await import('../models/WalletTransaction')).WalletTransactionType;
        const purchaseResult = await WalletService.purchaseFeatureWithCredit({
            userId,
            price,
            transactionType: WalletTransactionType.SUPER_LIKE_PURCHASE,
            reference: `SUPER_LIKES_${purchaseCount}_${Date.now()}`,
            metadata: { count: purchaseCount },
        });

        await sub.update({ superlikesRemaining: sub.superlikesRemaining + purchaseCount });
        const { SubscriptionService } = await import('../services/subscriptionService');
        SubscriptionService.invalidateCache(userId);

        res.json({
            success: true,
            message: `Successfully purchased ${purchaseCount} Super Likes!`,
            data: { ...purchaseResult.data, superlikesRemaining: sub.superlikesRemaining },
        });
    } catch (err: any) {
        if (err.statusCode === 402) {
            res.status(402).json({ success: false, insufficientBalance: true, data: err.shortfallData });
            return;
        }
        if (err.statusCode === 400) {
            res.status(400).json({ success: false, message: err.message });
            return;
        }
        res.status(500).json({ success: false, message: err.message || 'Super Likes purchase failed' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/wallet/pay-boost
// ─────────────────────────────────────────────────────────────────────────────
export const payBoostWithWallet = async (req: Request, res: Response): Promise<void> => {
    try {
        const { count } = req.body;
        const userId = req.user!.id;
        const purchaseCount = Number(count);

        const price = CREDIT_PRICE_TABLE[purchaseCount];
        if (!price) {
            res.status(400).json({ success: false, message: 'Invalid boost count' });
            return;
        }

        const sub = await findOrCreateSubscriptionForCredit(userId);

        const WalletTransactionType = (await import('../models/WalletTransaction')).WalletTransactionType;
        const purchaseResult = await WalletService.purchaseFeatureWithCredit({
            userId,
            price,
            transactionType: WalletTransactionType.BOOST_PURCHASE,
            reference: `BOOST_${purchaseCount}_${Date.now()}`,
            metadata: { count: purchaseCount },
        });

        await sub.update({ boostsRemaining: sub.boostsRemaining + purchaseCount });
        const { SubscriptionService } = await import('../services/subscriptionService');
        SubscriptionService.invalidateCache(userId);

        res.json({
            success: true,
            message: `Successfully purchased Profile Boost!`,
            data: { ...purchaseResult.data, boostsRemaining: sub.boostsRemaining },
        });
    } catch (err: any) {
        if (err.statusCode === 402) {
            res.status(402).json({ success: false, insufficientBalance: true, data: err.shortfallData });
            return;
        }
        if (err.statusCode === 400) {
            res.status(400).json({ success: false, message: err.message });
            return;
        }
        res.status(500).json({ success: false, message: err.message || 'Profile Boost purchase failed' });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/wallet/transactions
// ─────────────────────────────────────────────────────────────────────────────
export const getWalletTransactions = async (req: Request, res: Response): Promise<void> => {
    try {
        const userId = req.user!.id;

        const WalletTransaction = (await import('../models/WalletTransaction')).default;
        const transactions = await WalletTransaction.findAll({
            where: { userId },
            order: [['createdAt', 'DESC']],
            limit: 100,
        });

        res.json({
            success: true,
            data: transactions,
        });
    } catch (err: any) {
        logger.error('getWalletTransactions error:', err);
        res.status(500).json({ success: false, message: 'Failed to fetch wallet transactions', error: err.message });
    }
};
