import { Request, Response } from 'express';
import { Op } from 'sequelize';
import { logger } from '../config/logger';
import PartyPlan from '../models/PartyPlan';
import PartyPlanRequest from '../models/PartyPlanRequest';
import Payment from '../models/Payment';
import Booking from '../models/Booking';
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
import SubscriptionPackage from '../models/SubscriptionPackage';

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
        const userId = (req.query.userId || req.body.userId) as string;

        if (!userId) {
            res.status(400).json({ success: false, message: 'userId is required' });
            return;
        }

        const userRecord = await User.findByPk(userId);

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

        // Unified transactions list
        const transactions: any[] = [];

        // Standard booking payments
        for (const p of payments) {
            const booking = (p as any).booking;
            const venue = booking?.venue;
            transactions.push({
                txnId: p.transactionId,
                paymentId: p.id,
                type: 'booking',
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
                      }
                    : null,
            });
        }

        // Host party plan payments (safety deposit)
        for (const plan of hostPartyPayments) {
            const venue = (plan as any).venue;
            // Avoid duplicate if already captured in payments table
            const alreadyAdded = transactions.find(
                t => t.context?.partyPlanId === plan.id && t.role === 'host'
            );
            if (alreadyAdded) continue;

            transactions.push({
                txnId: plan.hostRazorpayPaymentId,
                paymentId: plan.id,
                type: 'party_plan_deposit',
                role: 'host',
                amount: Number(plan.depositAmount),
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
            const plan = (req as any).plan;
            const venue = plan ? (plan as any).venue : null;
            const alreadyAdded = transactions.find(
                t => t.context?.partyPlanId === req.planId && t.role === 'joiner'
            );
            if (alreadyAdded) continue;

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

        res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate');
        res.json({
            success: true,
            data: {
                walletBalance: userRecord?.walletBalance ? Number(userRecord.walletBalance) : 0.00,
                incompleteEvents,
                transactions: allTransactions,
                subscriptionTransactions: subscriptionTxns,
                summary: {
                    totalIncompleteEvents: incompleteEvents.length,
                    totalTransactions: allTransactions.length,
                    totalSpent: Math.round(totalSpent * 100) / 100,
                    totalRefunded: Math.round(totalRefunded * 100) / 100,
                    totalSubscriptionSpent: Math.round(totalSubscriptionSpent * 100) / 100,
                    totalPlanPayments: transactions.length,
                    totalSubscriptionPayments: subscriptionTxns.length,
                },
            },
        });
    } catch (err: any) {
        logger.error('getWalletData error:', err);
        res.status(500).json({ success: false, message: 'Failed to fetch wallet data', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/wallet/pay-with-wallet
// Pays commitment deposit or booking fees using user wallet balance
// ─────────────────────────────────────────────────────────────────────────────
export const payWithWallet = async (req: Request, res: Response): Promise<void> => {
    try {
        const { userId, amount, planId, requestId, paymentType = 'host_deposit' } = req.body;

        if (!userId || !amount) {
            res.status(400).json({ success: false, message: 'userId and amount are required' });
            return;
        }

        const requiredAmount = Number(amount);
        if (isNaN(requiredAmount) || requiredAmount <= 0) {
            res.status(400).json({ success: false, message: 'Invalid payment amount' });
            return;
        }

        const user = await User.findByPk(userId);
        if (!user) {
            res.status(404).json({ success: false, message: 'User not found' });
            return;
        }

        const currentBalance = Number(user.walletBalance || 0);

        if (currentBalance < requiredAmount) {
            const requiredRecharge = Math.ceil(requiredAmount - currentBalance);
            res.status(402).json({
                success: false,
                insufficientBalance: true,
                requiredRecharge,
                currentBalance,
                requiredAmount,
                message: `Recharge ₹${requiredRecharge} to complete this payment.`,
            });
            return;
        }

        // Deduct from wallet atomically
        const newBalance = Math.max(0, currentBalance - requiredAmount);
        await user.update({ walletBalance: newBalance });

        // Record WalletTransaction Ledger
        const WalletTransaction = (await import('../models/WalletTransaction')).default;
        const WalletTransactionType = (await import('../models/WalletTransaction')).WalletTransactionType;
        await WalletTransaction.logTransaction({
            userId,
            partyPlanId: planId,
            amount: requiredAmount,
            openingBalance: currentBalance,
            closingBalance: newBalance,
            transactionType: WalletTransactionType.COMMITMENT_DEPOSIT,
            reference: `PLAN_${planId || 'DIRECT'}`,
            metadata: { paymentType, requestId }
        });

        // Record Audit Log
        const AuditLog = (await import('../models/AuditLog')).default;
        await AuditLog.logAction({
            userId,
            partyPlanId: planId,
            action: 'Wallet Payment Completed',
            metadata: { amount: requiredAmount, paymentType, requestId, remainingBalance: newBalance }
        });

        res.json({
            success: true,
            message: 'Wallet payment successful',
            data: {
                userId,
                amountPaid: requiredAmount,
                remainingBalance: newBalance,
                transactionId: `WAL_TXN_${Date.now()}_${Math.floor(Math.random() * 1000)}`,
            }
        });
    } catch (err: any) {
        logger.error('payWithWallet error:', err);
        res.status(500).json({ success: false, message: 'Wallet payment failed', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/wallet/recharge
// Recharges user wallet balance
// ─────────────────────────────────────────────────────────────────────────────
export const rechargeWallet = async (req: Request, res: Response): Promise<void> => {
    try {
        const { userId, amount, paymentId, paymentGateway = 'razorpay' } = req.body;

        if (!userId || !amount) {
            res.status(400).json({ success: false, message: 'userId and amount are required' });
            return;
        }

        const rechargeAmount = Number(amount);
        if (isNaN(rechargeAmount) || rechargeAmount <= 0) {
            res.status(400).json({ success: false, message: 'Invalid recharge amount' });
            return;
        }

        const user = await User.findByPk(userId);
        if (!user) {
            res.status(404).json({ success: false, message: 'User not found' });
            return;
        }

        const currentBalance = Number(user.walletBalance || 0);
        const newBalance = currentBalance + rechargeAmount;
        await user.update({ walletBalance: newBalance });

        const WalletTransaction = (await import('../models/WalletTransaction')).default;
        const WalletTransactionType = (await import('../models/WalletTransaction')).WalletTransactionType;
        const txn = await WalletTransaction.logTransaction({
            userId,
            amount: rechargeAmount,
            openingBalance: currentBalance,
            closingBalance: newBalance,
            transactionType: WalletTransactionType.RECHARGE,
            reference: paymentId || `RECHARGE_${Date.now()}`,
            metadata: { paymentGateway, paymentId }
        });

        const AuditLog = (await import('../models/AuditLog')).default;
        await AuditLog.logAction({
            userId,
            action: 'Wallet Recharged',
            metadata: { amount: rechargeAmount, newBalance, paymentId }
        });

        res.json({
            success: true,
            message: `Successfully recharged ₹${rechargeAmount} to your wallet!`,
            data: {
                userId,
                rechargedAmount: rechargeAmount,
                walletBalance: newBalance,
                transactionId: txn.id,
            }
        });
    } catch (err: any) {
        logger.error('rechargeWallet error:', err);
        res.status(500).json({ success: false, message: 'Wallet recharge failed', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/mobile/wallet/pay-vip
// Purchases VIP membership using wallet balance
// ─────────────────────────────────────────────────────────────────────────────
export const payVipWithWallet = async (req: Request, res: Response): Promise<void> => {
    try {
        const { userId, packageId, tier = 'GOLD', price = 199 } = req.body;

        if (!userId) {
            res.status(400).json({ success: false, message: 'userId is required' });
            return;
        }

        const user = await User.findByPk(userId);
        if (!user) {
            res.status(404).json({ success: false, message: 'User not found' });
            return;
        }

        const requiredPrice = Number(price);
        const currentBalance = Number(user.walletBalance || 0);

        if (currentBalance < requiredPrice) {
            const requiredRecharge = Math.ceil(requiredPrice - currentBalance);
            res.status(402).json({
                success: false,
                insufficientBalance: true,
                requiredRecharge,
                currentBalance,
                requiredPrice,
                message: `Recharge ₹${requiredRecharge} to complete VIP Purchase.`,
            });
            return;
        }

        const newBalance = Math.max(0, currentBalance - requiredPrice);
        await user.update({ walletBalance: newBalance });

        // Activate UserSubscription
        const UserSubscriptionModel = (await import('../models/UserSubscription')).default;
        const SubscriptionStatusEnum = (await import('../models/UserSubscription')).SubscriptionStatus;
        
        const validUntil = new Date();
        validUntil.setMonth(validUntil.getMonth() + 1);

        let sub = await UserSubscriptionModel.findOne({ where: { userId } });
        if (sub) {
            await sub.update({
                packageId: packageId || sub.packageId,
                status: SubscriptionStatusEnum.ACTIVE,
                startDate: new Date(),
                endDate: validUntil,
                autoRenew: false,
            });
        } else {
            sub = await UserSubscriptionModel.create({
                userId,
                packageId: packageId || 'DEFAULT_GOLD_PKG',
                status: SubscriptionStatusEnum.ACTIVE,
                startDate: new Date(),
                endDate: validUntil,
                autoRenew: false,
            });
        }

        // Ledger & Audit
        const WalletTransaction = (await import('../models/WalletTransaction')).default;
        const WalletTransactionType = (await import('../models/WalletTransaction')).WalletTransactionType;
        await WalletTransaction.logTransaction({
            userId,
            amount: requiredPrice,
            openingBalance: currentBalance,
            closingBalance: newBalance,
            transactionType: WalletTransactionType.VIP_PURCHASE,
            reference: `VIP_${tier}`,
            metadata: { tier, packageId, validUntil: validUntil.toISOString() }
        });

        const AuditLog = (await import('../models/AuditLog')).default;
        await AuditLog.logAction({
            userId,
            action: 'VIP Membership Purchased via Wallet',
            metadata: { tier, price: requiredPrice, validUntil: validUntil.toISOString() }
        });

        res.json({
            success: true,
            message: `🎉 Congratulations! VIP Membership (${tier}) is now active.`,
            data: {
                userId,
                tier,
                pricePaid: requiredPrice,
                walletBalance: newBalance,
                subscriptionId: sub.id,
                validUntil: validUntil.toISOString(),
            }
        });
    } catch (err: any) {
        logger.error('payVipWithWallet error:', err);
        res.status(500).json({ success: false, message: 'VIP wallet purchase failed', error: err.message });
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/mobile/wallet/transactions
// Fetches full audit history of wallet transactions
// ─────────────────────────────────────────────────────────────────────────────
export const getWalletTransactions = async (req: Request, res: Response): Promise<void> => {
    try {
        const userId = (req.query.userId || req.body.userId) as string;
        if (!userId) {
            res.status(400).json({ success: false, message: 'userId is required' });
            return;
        }

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
