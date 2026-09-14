import '../models';
import sequelize from '../config/database';
import User, { UserRole } from '../models/User';
import UserProfile from '../models/UserProfile';
import UserPreference from '../models/UserPreference';
import SubscriptionPackage from '../models/SubscriptionPackage';
import UserSubscription, { SubscriptionStatus } from '../models/UserSubscription';
import { SubscriptionService } from '../services/subscriptionService';
import { NightPartnerService } from '../services/NightPartnerService';
import { updateProfile } from '../controllers/profileController';
import mobileUserController from '../controllers/mobileUserController';

describe('Hide Profile Feature & VIP Entitlement Test Suite', () => {
    let freeUser: User;
    let vipUser: User;
    let observerUser: User;
    let vipPackage: SubscriptionPackage;

    beforeAll(async () => {
        await sequelize.authenticate();

        // 1. Create Free User
        const freeEmail = `free_hide_${Date.now()}@lunara.test`;
        freeUser = await User.create({
            email: freeEmail,
            phone: `91${Math.floor(10000000 + Math.random() * 90000000)}`,
            passwordHash: '$2a$10$abcdefghijklmnopqrstuvwxyz123456',
            firstName: 'Free',
            lastName: 'User',
            dateOfBirth: new Date(1996, 4, 10),
            role: UserRole.CUSTOMER,
        });

        await UserProfile.create({
            userId: freeUser.id,
            displayName: 'Free User',
            gender: 'MALE',
            city: 'Mumbai',
        });

        await UserPreference.create({
            userId: freeUser.id,
            matchDistanceKm: 25,
            showMeInMatching: true,
            bookingAlertsEnabled: true,
        });

        // 2. Create VIP User (with PLUS/PRO/ELITE tier package)
        const vipEmail = `vip_hide_${Date.now()}@lunara.test`;
        vipUser = await User.create({
            email: vipEmail,
            phone: `91${Math.floor(10000000 + Math.random() * 90000000)}`,
            passwordHash: '$2a$10$abcdefghijklmnopqrstuvwxyz123456',
            firstName: 'Vip',
            lastName: 'User',
            dateOfBirth: new Date(1994, 7, 20),
            role: UserRole.CUSTOMER,
        });

        await UserProfile.create({
            userId: vipUser.id,
            displayName: 'Vip User',
            gender: 'FEMALE',
            city: 'Mumbai',
        });

        await UserPreference.create({
            userId: vipUser.id,
            matchDistanceKm: 25,
            showMeInMatching: true,
            bookingAlertsEnabled: true,
        });

        // 3. Create Observer User (to browse discovery)
        const obsEmail = `obs_hide_${Date.now()}@lunara.test`;
        observerUser = await User.create({
            email: obsEmail,
            phone: `91${Math.floor(10000000 + Math.random() * 90000000)}`,
            passwordHash: '$2a$10$abcdefghijklmnopqrstuvwxyz123456',
            firstName: 'Observer',
            lastName: 'User',
            dateOfBirth: new Date(1995, 1, 1),
            role: UserRole.CUSTOMER,
        });

        // Ensure VIP Subscription package exists
        const [pkg] = await SubscriptionPackage.findOrCreate({
            where: { tier: 'PLUS' },
            defaults: {
                name: 'Lunara Plus',
                tier: 'PLUS',
                price: 499,
                durationDays: 30,
                hasHideProfile: true,
                hasPriorityVisibility: true,
                hasTrustBadge: true,
                canSeeWhoLiked: true,
                dailyLikes: 50,
                superlikesPerCycle: 5,
                boostsPerCycle: 1,
                isActive: true,
            },
        });
        vipPackage = pkg;

        // Assign active VIP subscription to vipUser
        await UserSubscription.create({
            userId: vipUser.id,
            packageId: vipPackage.id,
            status: SubscriptionStatus.ACTIVE,
            startDate: new Date(),
            endDate: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
            autoRenew: true,
        });
    });

    afterAll(async () => {
        try {
            if (freeUser) {
                await UserSubscription.destroy({ where: { userId: freeUser.id } });
                await UserPreference.destroy({ where: { userId: freeUser.id } });
                await UserProfile.destroy({ where: { userId: freeUser.id } });
                await User.destroy({ where: { id: freeUser.id } });
            }
            if (vipUser) {
                await UserSubscription.destroy({ where: { userId: vipUser.id } });
                await UserPreference.destroy({ where: { userId: vipUser.id } });
                await UserProfile.destroy({ where: { userId: vipUser.id } });
                await User.destroy({ where: { id: vipUser.id } });
            }
            if (observerUser) {
                await User.destroy({ where: { id: observerUser.id } });
            }
        } catch (e) {
            // cleanup best effort
        }
    });

    describe('1. Entitlement Checks via SubscriptionService', () => {
        it('should NOT allow freeUser to hide profile', async () => {
            const hasAccess = await SubscriptionService.hasAccess(freeUser.id, 'hide_profile');
            expect(hasAccess).toBe(false);
        });

        it('should allow vipUser to hide profile', async () => {
            const hasAccess = await SubscriptionService.hasAccess(vipUser.id, 'hide_profile');
            expect(hasAccess).toBe(true);
        });
    });

    describe('2. Backend Controller Entitlement & Security Validation', () => {
        it('should reject Free user attempting to hide profile via updateProfile (invisibleMode: true)', async () => {
            let statusCode = 200;
            let responseData: any = null;

            const req: any = {
                user: { id: freeUser.id },
                body: { invisibleMode: true },
            };
            const res: any = {
                status: (code: number) => {
                    statusCode = code;
                    return res;
                },
                json: (data: any) => {
                    responseData = data;
                    return res;
                },
            };

            await updateProfile(req, res);

            expect(statusCode).toBe(403);
            expect(responseData.success).toBe(false);
            expect(responseData.code).toBe('UPGRADE_REQUIRED');
        });

        it('should reject Free user attempting to hide profile via completeProfileSetup (showMeInMatching: false)', async () => {
            let statusCode = 200;
            let responseData: any = null;

            const req: any = {
                user: { id: freeUser.id },
                body: { showMeInMatching: false },
            };
            const res: any = {
                status: (code: number) => {
                    statusCode = code;
                    return res;
                },
                json: (data: any) => {
                    responseData = data;
                    return res;
                },
            };

            await mobileUserController.completeProfileSetup(req, res);

            expect(statusCode).toBe(403);
            expect(responseData.success).toBe(false);
            expect(responseData.code).toBe('UPGRADE_REQUIRED');
        });

        it('should allow VIP user to hide profile via updateProfile', async () => {
            let statusCode = 200;
            let responseData: any = null;

            const req: any = {
                user: { id: vipUser.id },
                body: { invisibleMode: true },
            };
            const res: any = {
                status: (code: number) => {
                    statusCode = code;
                    return res;
                },
                json: (data: any) => {
                    responseData = data;
                    return res;
                },
            };

            await updateProfile(req, res);

            expect(statusCode).toBe(200);
            expect(responseData.success).toBe(true);

            // Verify in DB that showMeInMatching is false
            const prefs = await UserPreference.findOne({ where: { userId: vipUser.id } });
            expect(prefs?.showMeInMatching).toBe(false);
        });
    });

    describe('3. Matching & Discovery Feed Exclusion', () => {
        it('should exclude hidden VIP user from customer discovery list', async () => {
            let responseData: any = null;

            const req: any = {
                user: { id: observerUser.id },
                query: { page: '1', limit: '50' },
            };
            const res: any = {
                status: () => res,
                json: (data: any) => {
                    responseData = data;
                    return res;
                },
            };

            await mobileUserController.getAllCustomers(req, res);

            expect(responseData.success).toBe(true);
            const userIds = (responseData.data || responseData.users || []).map((u: any) => u.id);
            // Hidden VIP user should NOT be in the general discovery list
            expect(userIds).not.toContain(vipUser.id);
        });

        it('should exclude hidden VIP user from NightPartner matching candidates', async () => {
            const VenueModel = (await import('../models/Venue')).default;
            const venue = await VenueModel.findOne();
            const venueId = venue ? venue.id : '00000000-0000-0000-0000-000000000001';

            const candidates = await NightPartnerService.getAvailableInvitees(
                observerUser.id,
                venueId,
                '2026-10-01'
            );

            const candidateIds = candidates.map((c: any) => c.id);
            expect(candidateIds).not.toContain(vipUser.id);
        });
    });

    describe('4. Unhide Profile Flow', () => {
        it('should allow VIP user to unhide profile (invisibleMode: false)', async () => {
            let statusCode = 200;
            let responseData: any = null;

            const req: any = {
                user: { id: vipUser.id },
                body: { invisibleMode: false },
            };
            const res: any = {
                status: (code: number) => {
                    statusCode = code;
                    return res;
                },
                json: (data: any) => {
                    responseData = data;
                    return res;
                },
            };

            await updateProfile(req, res);

            expect(statusCode).toBe(200);
            expect(responseData.success).toBe(true);

            // Verify in DB
            const prefs = await UserPreference.findOne({ where: { userId: vipUser.id } });
            expect(prefs?.showMeInMatching).toBe(true);
        });

        it('should include unhidden VIP user back into discovery list', async () => {
            let responseData: any = null;

            const req: any = {
                user: { id: observerUser.id },
                query: { page: '1', limit: '50' },
            };
            const res: any = {
                status: () => res,
                json: (data: any) => {
                    responseData = data;
                    return res;
                },
            };

            await mobileUserController.getAllCustomers(req, res);

            expect(responseData.success).toBe(true);
            const userIds = (responseData.data || responseData.users || []).map((u: any) => u.id);
            expect(userIds).toContain(vipUser.id);
        });
    });
});
