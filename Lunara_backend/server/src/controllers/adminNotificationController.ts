import { Request, Response } from 'express';
import Booking from '../models/Booking';
import PartyPlanRequest from '../models/PartyPlanRequest';
import GroupParty from '../models/GroupParty';
import StrangersMeetRequest from '../models/StrangersMeetRequest';
import User from '../models/User';
import Venue from '../models/Venue';

/**
 * Get pending/NEW notification summary counts for admin sidebar and header
 */
export const getAdminNotificationSummary = async (req: Request, res: Response): Promise<Response> => {
    try {
        const {
            lastSeenBookings,
            lastSeenPartyRequests,
            lastSeenGroupParties,
            lastSeenStrangersMeet,
        } = req.query;

        const parseDate = (val?: any): Date | null => {
            if (!val) return null;
            const d = new Date(val as string);
            return isNaN(d.getTime()) ? null : d;
        };

        const dateBookings = parseDate(lastSeenBookings);
        const datePartyRequests = parseDate(lastSeenPartyRequests);
        const dateGroupParties = parseDate(lastSeenGroupParties);
        const dateStrangersMeet = parseDate(lastSeenStrangersMeet);

        const { Op } = require('sequelize');

        // Helper to build where clause:
        // If lastSeen timestamp is provided, count items created strictly AFTER that timestamp.
        // If no timestamp is provided, count items created within the last 24 hours as NEW.
        const makeWhere = (lastSeenDate: Date | null) => {
            if (!lastSeenDate) {
                return {
                    createdAt: { [Op.gt]: new Date(Date.now() - 24 * 60 * 60 * 1000) }
                };
            }
            return {
                createdAt: { [Op.gt]: lastSeenDate }
            };
        };

        const [bookingsCount, partyRequestsCount, groupPartiesCount, strangersMeetCount] = await Promise.all([
            Booking.count({ where: makeWhere(dateBookings) }).catch(() => 0),
            PartyPlanRequest.count({ where: makeWhere(datePartyRequests) }).catch(() => 0),
            GroupParty.count({ where: makeWhere(dateGroupParties) }).catch(() => 0),
            StrangersMeetRequest.count({ where: makeWhere(dateStrangersMeet) }).catch(() => 0),
        ]);

        const totalPending = bookingsCount + partyRequestsCount + groupPartiesCount + strangersMeetCount;

        return res.status(200).json({
            success: true,
            data: {
                bookings: bookingsCount,
                partyRequests: partyRequestsCount,
                groupParties: groupPartiesCount,
                strangersMeet: strangersMeetCount,
                totalPending,
            },
        });
    } catch (error: any) {
        console.error('Error fetching admin notification summary:', error);
        return res.status(500).json({
            success: false,
            message: 'Failed to fetch notification summary',
            error: error.message,
        });
    }
};

/**
 * Get recent activity feed for admin top header notification dropdown
 */
export const getAdminNotificationActivity = async (_req: Request, res: Response): Promise<Response> => {
    try {
        const [recentBookings, recentPartyReqs, recentGroupParties, recentStrangersMeet] = await Promise.all([
            Booking.findAll({
                limit: 5,
                order: [['createdAt', 'DESC']],
                include: [
                    { model: User, as: 'user', attributes: ['id', 'firstName', 'lastName', 'email'] },
                    { model: Venue, as: 'venue', attributes: ['id', 'name', 'city'] },
                ],
            }).catch(() => []),
            PartyPlanRequest.findAll({
                limit: 5,
                order: [['createdAt', 'DESC']],
                include: [
                    { model: User, as: 'user', attributes: ['id', 'firstName', 'lastName', 'email'] },
                ],
            }).catch(() => []),
            GroupParty.findAll({
                limit: 5,
                order: [['createdAt', 'DESC']],
                include: [
                    { model: User, as: 'creator', attributes: ['id', 'firstName', 'lastName', 'email'] },
                    { model: Venue, as: 'venue', attributes: ['id', 'name', 'city'] },
                ],
            }).catch(() => []),
            StrangersMeetRequest.findAll({
                limit: 5,
                order: [['createdAt', 'DESC']],
                include: [
                    { model: User, as: 'user', attributes: ['id', 'firstName', 'lastName', 'email'] },
                    { model: Venue, as: 'venue', attributes: ['id', 'name', 'city'] },
                ],
            }).catch(() => []),
        ]);

        const activities: Array<{
            id: string;
            type: 'booking' | 'party_request' | 'group_party' | 'strangers_meet';
            title: string;
            subtitle: string;
            path: string;
            status: string;
            isPending: boolean;
            createdAt: Date;
        }> = [];

        // Map Bookings
        recentBookings.forEach((b: any) => {
            const userName = b.user ? `${b.user.firstName || ''} ${b.user.lastName || ''}`.trim() : 'User';
            const venueName = b.venue?.name || 'Venue';
            activities.push({
                id: `booking_${b.id}`,
                type: 'booking',
                title: `🎫 Solo/Venue Booking: ${userName}`,
                subtitle: `Booked ${venueName} (${b.status})`,
                path: '/bookings',
                status: b.status,
                isPending: b.status === 'pending',
                createdAt: b.createdAt,
            });
        });

        // Map Party Requests
        recentPartyReqs.forEach((pr: any) => {
            const userName = pr.user ? `${pr.user.firstName || ''} ${pr.user.lastName || ''}`.trim() : 'User';
            activities.push({
                id: `pr_${pr.id}`,
                type: 'party_request',
                title: `🎉 Party Request: ${userName}`,
                subtitle: `Submitted a party request (${pr.status})`,
                path: '/party-requests',
                status: pr.status,
                isPending: pr.status === 'pending',
                createdAt: pr.createdAt,
            });
        });

        // Map Group Parties
        recentGroupParties.forEach((gp: any) => {
            const userName = gp.creator ? `${gp.creator.firstName || ''} ${gp.creator.lastName || ''}`.trim() : 'User';
            const venueName = gp.venue?.name || 'Venue';
            activities.push({
                id: `gp_${gp.id}`,
                type: 'group_party',
                title: `👥 Group Party: ${userName}`,
                subtitle: `Posted a group party for ${gp.numberOfFriends + 1} guests @ ${venueName} (${gp.status})`,
                path: '/group-parties',
                status: gp.status,
                isPending: gp.status === 'pending',
                createdAt: gp.createdAt,
            });
        });

        // Map Strangers Meet
        recentStrangersMeet.forEach((sm: any) => {
            const userName = sm.user ? `${sm.user.firstName || ''} ${sm.user.lastName || ''}`.trim() : 'User';
            const venueName = sm.venue?.name || 'Venue';
            activities.push({
                id: `sm_${sm.id}`,
                type: 'strangers_meet',
                title: `🤝 Strangers Meet: ${userName}`,
                subtitle: `Created "${sm.subject || 'Strangers Meet'}" @ ${venueName} (${sm.status})`,
                path: '/strangers-meet',
                status: sm.status,
                isPending: sm.status === 'pending',
                createdAt: sm.createdAt,
            });
        });

        // Sort all by createdAt DESC
        activities.sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());

        return res.status(200).json({
            success: true,
            data: activities.slice(0, 15),
        });
    } catch (error: any) {
        console.error('Error fetching admin notification activity:', error);
        return res.status(500).json({
            success: false,
            message: 'Failed to fetch notification activity',
            error: error.message,
        });
    }
};
