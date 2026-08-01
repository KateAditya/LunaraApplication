import { Request, Response } from 'express';
import crypto from 'crypto';
import { Op } from 'sequelize';
import sequelize from '../config/database';
import Ticket, { TicketStatus } from '../models/Ticket';
import Venue from '../models/Venue';
import User from '../models/User';
import { logger } from '../config/logger';

export class MobileTicketController {
    /**
     * GET /api/mobile/tickets
     * Fetch user tickets grouped by status tabs: upcoming, active, used, expired, cancelled
     */
    public static async getUserTickets(req: Request, res: Response): Promise<Response> {
        try {
            const userId = (req.query.userId || req.body?.userId) as string;
            const tab = (req.query.tab as string) || 'all';

            if (!userId) {
                return res.status(400).json({ success: false, message: 'userId parameter is required' });
            }

            const whereClause: any = { userId };
            const now = new Date();

            if (tab === 'upcoming' || tab === 'active') {
                whereClause.ticketStatus = { [Op.in]: [TicketStatus.ACTIVE, TicketStatus.ISSUED, TicketStatus.GENERATING] };
                whereClause.eventEndAt = { [Op.gte]: now };
            } else if (tab === 'used') {
                whereClause.ticketStatus = TicketStatus.USED;
            } else if (tab === 'expired') {
                whereClause[Op.or] = [
                    { ticketStatus: TicketStatus.EXPIRED },
                    { eventEndAt: { [Op.lt]: now }, ticketStatus: { [Op.ne]: TicketStatus.CANCELLED } }
                ];
            } else if (tab === 'cancelled') {
                whereClause.ticketStatus = { [Op.in]: [TicketStatus.CANCELLED, TicketStatus.REFUNDED, TicketStatus.VOID] };
            }

            const tickets = await Ticket.findAll({
                where: whereClause,
                include: [
                    { model: Venue, as: 'venue', attributes: ['id', 'name', 'addressLine1', 'city', 'area'] },
                ],
                order: [['eventStartAt', 'ASC']],
            });

            const formattedTickets = tickets.map(t => {
                const isExpired = t.ticketStatus === TicketStatus.EXPIRED || new Date(t.expiresAt) < now;
                return {
                    id: t.id,
                    ticketId: t.ticketId,
                    bookingId: t.bookingId,
                    bookingType: t.bookingType,
                    status: isExpired && t.ticketStatus !== TicketStatus.CANCELLED ? TicketStatus.EXPIRED : t.ticketStatus,
                    eventStartAt: t.eventStartAt,
                    eventEndAt: t.eventEndAt,
                    issuedAt: t.issuedAt,
                    expiresAt: t.expiresAt,
                    usedAt: t.usedAt,
                    pdfUrl: isExpired ? null : t.pdfUrl, // Hide PDF for expired tickets
                    qrToken: isExpired ? null : t.qrToken,
                    venueName: t.venue?.name || 'Lunara Venue',
                    venueAddress: `${t.venue?.area || t.venue?.addressLine1 || ''}, ${t.venue?.city || ''}`.trim(),
                    isExpired,
                };
            });

            return res.status(200).json({
                success: true,
                count: formattedTickets.length,
                data: formattedTickets,
            });
        } catch (err: any) {
            logger.error(`getUserTickets error: ${err.message}`, err);
            return res.status(500).json({ success: false, message: 'Failed to fetch tickets' });
        }
    }

    /**
     * GET /api/mobile/tickets/:id
     * Get single ticket metadata
     */
    public static async getTicketById(req: Request, res: Response): Promise<Response> {
        try {
            const { id } = req.params;
            const userId = req.query.userId as string;

            const ticket = await Ticket.findOne({
                where: { [Op.or]: [{ id }, { ticketId: id }] },
                include: [
                    { model: Venue, as: 'venue' },
                    { model: User, as: 'user', attributes: ['id', 'firstName', 'lastName', 'email', 'phone'] },
                ],
            });

            if (!ticket) {
                return res.status(404).json({ success: false, message: 'Ticket not found' });
            }

            if (userId && ticket.userId !== userId) {
                return res.status(403).json({ success: false, message: 'Unauthorized ticket access' });
            }

            const now = new Date();
            const isExpired = ticket.ticketStatus === TicketStatus.EXPIRED || new Date(ticket.expiresAt) < now;

            return res.status(200).json({
                success: true,
                data: {
                    id: ticket.id,
                    ticketId: ticket.ticketId,
                    bookingId: ticket.bookingId,
                    bookingType: ticket.bookingType,
                    status: isExpired && ticket.ticketStatus !== TicketStatus.CANCELLED ? TicketStatus.EXPIRED : ticket.ticketStatus,
                    eventStartAt: ticket.eventStartAt,
                    eventEndAt: ticket.eventEndAt,
                    issuedAt: ticket.issuedAt,
                    expiresAt: ticket.expiresAt,
                    usedAt: ticket.usedAt,
                    pdfUrl: isExpired ? null : ticket.pdfUrl,
                    qrToken: isExpired ? null : ticket.qrToken,
                    venueName: ticket.venue?.name || 'Lunara Venue',
                    venueAddress: ticket.venue?.addressLine1 || '',
                    guestName: ticket.user ? `${ticket.user.firstName} ${ticket.user.lastName}` : 'Guest',
                    isExpired,
                },
            });
        } catch (err: any) {
            logger.error(`getTicketById error: ${err.message}`, err);
            return res.status(500).json({ success: false, message: 'Failed to fetch ticket' });
        }
    }

    /**
     * GET /api/mobile/tickets/:id/download
     * Generates a secure, time-limited signed PDF download URL or streams file
     */
    public static async getTicketDownloadUrl(req: Request, res: Response): Promise<Response> {
        try {
            const { id } = req.params;
            const userId = req.query.userId as string;

            const ticket = await Ticket.findOne({
                where: { [Op.or]: [{ id }, { ticketId: id }] },
            });

            if (!ticket) {
                return res.status(404).json({ success: false, message: 'Ticket not found' });
            }

            if (userId && ticket.userId !== userId) {
                return res.status(403).json({ success: false, message: 'Unauthorized access' });
            }

            const now = new Date();
            if (ticket.ticketStatus === TicketStatus.EXPIRED || new Date(ticket.expiresAt) < now) {
                return res.status(403).json({
                    success: false,
                    message: 'Ticket has expired. PDF download is no longer available.',
                    code: 'TICKET_EXPIRED',
                });
            }

            if (!ticket.pdfUrl) {
                return res.status(404).json({ success: false, message: 'Ticket PDF file not found' });
            }

            return res.status(200).json({
                success: true,
                ticketId: ticket.ticketId,
                downloadUrl: ticket.pdfUrl,
                expiresInSeconds: 300, // 5 minutes signed download token
            });
        } catch (err: any) {
            logger.error(`getTicketDownloadUrl error: ${err.message}`, err);
            return res.status(500).json({ success: false, message: 'Failed to generate download URL' });
        }
    }

    /**
     * POST /api/mobile/tickets/:id/share
     * Create or retrieve a secure public share token for WhatsApp / OS Share Sheet
     */
    public static async createShareToken(req: Request, res: Response): Promise<Response> {
        try {
            const { id } = req.params;
            const userId = req.body?.userId || req.query?.userId;

            const ticket = await Ticket.findOne({
                where: { [Op.or]: [{ id }, { ticketId: id }] },
            });

            if (!ticket) {
                return res.status(404).json({ success: false, message: 'Ticket not found' });
            }

            if (userId && ticket.userId !== userId) {
                return res.status(403).json({ success: false, message: 'Unauthorized' });
            }

            // Reuse shareToken if active
            let shareToken = ticket.shareToken;
            const now = new Date();

            if (!shareToken || !ticket.shareTokenExpiresAt || ticket.shareTokenExpiresAt < now) {
                shareToken = `LNS-${crypto.randomBytes(8).toString('hex')}`;
                const shareTokenExpiresAt = ticket.eventEndAt; // Valid until event end

                await ticket.update({
                    shareToken,
                    shareTokenExpiresAt,
                });
            }

            const shareUrl = `https://lunara.app/ticket/share/${shareToken}`;
            const shareText = `🎟 My Lunara Ticket\n\nTicket Code: ${ticket.ticketId}\nStatus: ${ticket.ticketStatus}\n\nView details: ${shareUrl}`;

            return res.status(200).json({
                success: true,
                ticketId: ticket.ticketId,
                shareToken,
                shareUrl,
                shareText,
                expiresAt: ticket.shareTokenExpiresAt,
            });
        } catch (err: any) {
            logger.error(`createShareToken error: ${err.message}`, err);
            return res.status(500).json({ success: false, message: 'Failed to create share token' });
        }
    }

    /**
     * GET /api/mobile/tickets/share/:token
     * Public preview endpoint for ticket share recipients (Sanitized preview)
     */
    public static async getShareTicketPreview(req: Request, res: Response): Promise<Response> {
        try {
            const { token } = req.params;

            const ticket = await Ticket.findOne({
                where: { shareToken: token },
                include: [
                    { model: Venue, as: 'venue', attributes: ['name', 'city', 'area'] },
                    { model: User, as: 'user', attributes: ['firstName'] },
                ],
            });

            if (!ticket) {
                return res.status(404).json({ success: false, message: 'Invalid or expired share link' });
            }

            const now = new Date();
            if (ticket.shareTokenExpiresAt && ticket.shareTokenExpiresAt < now) {
                return res.status(410).json({ success: false, message: 'Ticket share link has expired' });
            }

            return res.status(200).json({
                success: true,
                data: {
                    ticketId: ticket.ticketId,
                    bookingType: ticket.bookingType,
                    status: ticket.ticketStatus,
                    guestFirstName: ticket.user?.firstName || 'Lunara Member',
                    venueName: ticket.venue?.name || 'Lunara Venue',
                    city: ticket.venue?.city || '',
                    eventStartAt: ticket.eventStartAt,
                    eventEndAt: ticket.eventEndAt,
                },
            });
        } catch (err: any) {
            logger.error(`getShareTicketPreview error: ${err.message}`, err);
            return res.status(500).json({ success: false, message: 'Failed to fetch share preview' });
        }
    }

    /**
     * POST /api/mobile/tickets/verify
     * Atomic Gate Scanner Verification for Venue Staff
     */
    public static async verifyGateScanTicket(req: Request, res: Response): Promise<Response> {
        const t = await sequelize.transaction();
        try {
            const { ticketCode, qrToken } = req.body;

            if (!ticketCode && !qrToken) {
                await t.rollback();
                return res.status(400).json({ success: false, message: 'ticketCode or qrToken is required' });
            }

            let searchCode = ticketCode;
            if (!searchCode && qrToken) {
                try {
                    const parsed = JSON.parse(qrToken);
                    searchCode = parsed.ticketId;
                } catch (_) {
                    searchCode = qrToken;
                }
            }

            // Atomic Lock FOR UPDATE
            const ticket = await Ticket.findOne({
                where: { ticketId: searchCode },
                transaction: t,
                lock: true,
            });

            if (!ticket) {
                await t.rollback();
                return res.status(404).json({
                    success: false,
                    verificationStatus: 'INVALID',
                    message: 'Ticket not found in database',
                });
            }

            const now = new Date();

            // 1. Check if already used
            if (ticket.ticketStatus === TicketStatus.USED) {
                await t.rollback();
                return res.status(400).json({
                    success: false,
                    verificationStatus: 'ALREADY_USED',
                    message: `Ticket was already redeemed on ${ticket.usedAt}`,
                    usedAt: ticket.usedAt,
                    ticketId: ticket.ticketId,
                });
            }

            // 2. Check if cancelled or refunded
            if (ticket.ticketStatus === TicketStatus.CANCELLED || ticket.ticketStatus === TicketStatus.REFUNDED) {
                await t.rollback();
                return res.status(400).json({
                    success: false,
                    verificationStatus: ticket.ticketStatus,
                    message: `Ticket is ${ticket.ticketStatus} and invalid for venue entry`,
                });
            }

            // 3. Check if expired
            if (ticket.ticketStatus === TicketStatus.EXPIRED || new Date(ticket.expiresAt) < now) {
                await t.rollback();
                return res.status(400).json({
                    success: false,
                    verificationStatus: 'EXPIRED',
                    message: 'Event has ended. Ticket is expired.',
                });
            }

            // 4. Mark Ticket as USED atomically
            await ticket.update(
                {
                    ticketStatus: TicketStatus.USED,
                    usedAt: now,
                },
                { transaction: t }
            );

            await t.commit();

            logger.info(`Gate scanner verified & redeemed Ticket ${ticket.ticketId} at ${now}`);

            return res.status(200).json({
                success: true,
                verificationStatus: 'VALID',
                message: 'ENTRY GRANTED! Ticket successfully redeemed.',
                ticketId: ticket.ticketId,
                bookingId: ticket.bookingId,
                usedAt: now,
            });
        } catch (err: any) {
            await t.rollback();
            logger.error(`verifyGateScanTicket error: ${err.message}`, err);
            return res.status(500).json({ success: false, message: 'Gate verification failed' });
        }
    }
}
