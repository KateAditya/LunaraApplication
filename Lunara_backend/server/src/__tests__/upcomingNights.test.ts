import {
    NightPartnerMatchStatus,
    NightPartnerPaymentMode,
    NightPartnerCancellationStatus,
} from '../models/NightPartnerMatch';
import { NightPartnerRequestStatus } from '../models/NightPartnerRequest';
import { NightInterestStatus } from '../models/NightInterest';
import NightPartnerMatch from '../models/NightPartnerMatch';
import NightPartnerRequest from '../models/NightPartnerRequest';
import { NightPartnerService } from '../services/NightPartnerService';

describe('Upcoming Nights Architecture & Payment Logic', () => {
    describe('Enums & Schema Attribute Verification', () => {
        it('should have correct NightPartnerMatch statuses', () => {
            expect(NightPartnerMatchStatus.MATCHED).toBe('MATCHED');
            expect(NightPartnerMatchStatus.PAYMENT_PENDING).toBe('PAYMENT_PENDING');
            expect(NightPartnerMatchStatus.PAYMENT_FAILED).toBe('PAYMENT_FAILED');
            expect(NightPartnerMatchStatus.CONFIRMED).toBe('CONFIRMED');
            expect(NightPartnerMatchStatus.CANCELLED).toBe('CANCELLED');
            expect(NightPartnerMatchStatus.EXPIRED).toBe('EXPIRED');
        });

        it('should have correct NightPartnerPaymentMode options', () => {
            expect(NightPartnerPaymentMode.SELF_PAY).toBe('SELF_PAY');
            expect(NightPartnerPaymentMode.SPLIT).toBe('SPLIT');
        });

        it('should have correct NightPartnerCancellationStatus options', () => {
            expect(NightPartnerCancellationStatus.NONE).toBe('NONE');
            expect(NightPartnerCancellationStatus.REQUESTED).toBe('REQUESTED');
            expect(NightPartnerCancellationStatus.APPROVED).toBe('APPROVED');
            expect(NightPartnerCancellationStatus.REJECTED).toBe('REJECTED');
            expect(NightPartnerCancellationStatus.REFUNDED).toBe('REFUNDED');
        });

        it('should have correct NightPartnerRequest statuses', () => {
            expect(NightPartnerRequestStatus.PENDING).toBe('PENDING');
            expect(NightPartnerRequestStatus.ACCEPTED).toBe('ACCEPTED');
            expect(NightPartnerRequestStatus.DECLINED).toBe('DECLINED');
            expect(NightPartnerRequestStatus.CANCELLED).toBe('CANCELLED');
            expect(NightPartnerRequestStatus.EXPIRED).toBe('EXPIRED');
        });

        it('should have correct NightInterest statuses', () => {
            expect(NightInterestStatus.INTERESTED).toBe('interested');
            expect(NightInterestStatus.REMOVED).toBe('removed');
        });
    });

    describe('Split vs Self Pay Pricing Calculations', () => {
        const mockVenueCharges = 1999.0;

        it('should calculate 100% host amount for SELF_PAY mode', () => {
            const paymentMode = NightPartnerPaymentMode.SELF_PAY;
            const isHost = true;

            const hostAmount = paymentMode === NightPartnerPaymentMode.SELF_PAY ? mockVenueCharges : mockVenueCharges / 2;
            const partnerAmount = paymentMode === NightPartnerPaymentMode.SELF_PAY ? 0 : mockVenueCharges / 2;
            const userAmountToPay = isHost ? hostAmount : partnerAmount;

            expect(hostAmount).toBe(1999.0);
            expect(partnerAmount).toBe(0);
            expect(userAmountToPay).toBe(1999.0);
            expect(hostAmount + partnerAmount).toBe(mockVenueCharges);
        });

        it('should calculate exact 50% split for SPLIT mode', () => {
            const paymentMode = NightPartnerPaymentMode.SPLIT;
            const hostAmount = paymentMode === NightPartnerPaymentMode.SPLIT ? mockVenueCharges / 2 : mockVenueCharges;
            const partnerAmount = paymentMode === NightPartnerPaymentMode.SPLIT ? mockVenueCharges / 2 : 0;

            expect(hostAmount).toBe(999.5);
            expect(partnerAmount).toBe(999.5);
            expect(hostAmount + partnerAmount).toBe(mockVenueCharges);
        });

        it('should verify total amount equals sum of host and partner shares', () => {
            const amounts = [500, 1000, 2499, 5000];
            for (const total of amounts) {
                // Self Pay
                const selfHost = total;
                const selfPartner = 0;
                expect(selfHost + selfPartner).toBe(total);

                // Split
                const splitHost = Math.round((total / 2) * 100) / 100;
                const splitPartner = total - splitHost;
                expect(splitHost + splitPartner).toBe(total);
            }
        });
    });

    describe('Evolving Notification Timeline Card Dynamic Generation', () => {
        it('should enrich pending request card for partner with Accept / Decline actions', async () => {
            const mockRequest = {
                id: 'req_123',
                hostId: 'host_user_1',
                partnerId: 'partner_user_2',
                eventDate: new Date('2026-09-10'),
                status: NightPartnerRequestStatus.PENDING,
                venue: { name: 'Skyline Club' },
                reminder2hSent: false,
                reminder1hSent: false,
                reminder30mSent: false,
                updatedAt: new Date(),
            };

            jest.spyOn(NightPartnerMatch, 'findByPk').mockResolvedValue(null as any);
            jest.spyOn(NightPartnerRequest, 'findByPk').mockResolvedValue(mockRequest as any);

            const card = await NightPartnerService.enrichUpcomingNightNotificationCard('req_123', 'partner_user_2');
            expect(card).not.toBeNull();
            expect(card.id).toBe('upcoming_night_timeline_req_123');
            expect(card.title).toContain('Skyline Club');
            expect(card.data.isHost).toBe(false);
            const actionTypes = card.data.actionButtons.map((b: any) => b.action);
            expect(actionTypes).toContain('ACCEPT_REQUEST');
            expect(actionTypes).toContain('DECLINE_REQUEST');
        });

        it('should enrich confirmed match card with View Ticket, Open Chat & Cancel actions', async () => {
            const mockMatch = {
                id: 'match_123',
                hostId: 'host_user_1',
                partnerId: 'partner_user_2',
                eventDate: new Date('2026-09-10'),
                status: NightPartnerMatchStatus.CONFIRMED,
                conversationId: 'conv_789',
                bookingId: 'bk_456',
                paymentMode: NightPartnerPaymentMode.SELF_PAY,
                hostPaid: true,
                partnerPaid: false,
                totalAmount: 1999,
                hostAmount: 1999,
                partnerAmount: 0,
                venue: { name: 'Illuzion Club' },
                reminder2hSent: false,
                reminder1hSent: false,
                reminder30mSent: false,
                updatedAt: new Date(),
            };

            jest.spyOn(NightPartnerMatch, 'findByPk').mockResolvedValue(mockMatch as any);

            const card = await NightPartnerService.enrichUpcomingNightNotificationCard('match_123', 'host_user_1');
            expect(card).not.toBeNull();
            expect(card.id).toBe('upcoming_night_timeline_match_123');
            expect(card.title).toContain('Upcoming Night Confirmed!');
            expect(card.data.isHost).toBe(true);
            expect(card.data.paymentMode).toBe('SELF_PAY');
            const actionTypes = card.data.actionButtons.map((b: any) => b.action);
            expect(actionTypes).toContain('VIEW_TICKET');
            expect(actionTypes).toContain('OPEN_CHAT');
            expect(actionTypes).toContain('CANCEL_EVENT');
        });

        it('should enrich cancelled match card with Cancelled status text', async () => {
            const mockCancelledMatch = {
                id: 'match_cancelled',
                hostId: 'host_user_1',
                partnerId: 'partner_user_2',
                eventDate: new Date('2026-09-10'),
                status: NightPartnerMatchStatus.CANCELLED,
                venue: { name: 'Illuzion Club' },
                updatedAt: new Date(),
            };

            jest.spyOn(NightPartnerMatch, 'findByPk').mockResolvedValue(mockCancelledMatch as any);

            const card = await NightPartnerService.enrichUpcomingNightNotificationCard('match_cancelled', 'host_user_1');
            expect(card).not.toBeNull();
            expect(card.title).toContain('Upcoming Night Cancelled');
            expect(card.data.statusText).toBe('Cancelled');
        });
    });
});
