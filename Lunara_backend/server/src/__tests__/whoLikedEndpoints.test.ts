import { getWhoLikedSummary, getPeopleWhoLikedMe, getMyLikesAndMatches } from '../controllers/mobileUserController';
import { User, UserLike, UserMatch, UserProfile, UserSubscription, SubscriptionPackage } from '../models';
import { MatchStatus } from '../models/UserMatch';
import { SubscriptionStatus } from '../models/UserSubscription';
import { PackageTier } from '../models/SubscriptionPackage';
import { SubscriptionService } from '../services/subscriptionService';

describe('Who Liked Endpoints & Permission System', () => {
    let likerUser: any;
    let targetUser: any;
    let vipPackage: any;

    beforeAll(async () => {
        // Create test liker and target users
        const randPhone1 = `98${Math.floor(10000000 + Math.random() * 90000000)}`;
        const randPhone2 = `97${Math.floor(10000000 + Math.random() * 90000000)}`;

        likerUser = await User.create({
            email: `liker_${Date.now()}@lunara.test`,
            passwordHash: 'hashed_pw_test',
            firstName: 'Liker',
            lastName: 'User',
            phone: randPhone1,
            dateOfBirth: new Date('2000-01-01'),
            role: 'customer' as any,
        });

        targetUser = await User.create({
            email: `target_${Date.now()}@lunara.test`,
            passwordHash: 'hashed_pw_test',
            firstName: 'Target',
            lastName: 'User',
            phone: randPhone2,
            dateOfBirth: new Date('2000-01-01'),
            role: 'customer' as any,
        });

        await UserProfile.create({
            userId: likerUser.id,
            city: 'Pune',
            occupation: 'Software Engineer',
            interests: ['Music', 'Nightlife'],
        });

        await UserProfile.create({
            userId: targetUser.id,
            city: 'Pune',
            occupation: 'Designer',
            interests: ['Art', 'Dining'],
        });

        // Seed or find VIP package
        vipPackage = await SubscriptionPackage.findOne({ where: { tier: PackageTier.PRO } });
        if (!vipPackage) {
            vipPackage = await SubscriptionPackage.create({
                tier: PackageTier.PRO,
                name: 'Lunara Pro VIP',
                price: 499,
                dailyLikes: -1,
                superlikesPerCycle: 10,
                boostsPerCycle: 5,
                canSeeWhoLiked: true,
                hasPriorityVisibility: true,
            });
        }
    });

    afterAll(async () => {
        try {
            if (likerUser) {
                await UserLike.destroy({ where: { userId: likerUser.id } });
                await UserMatch.destroy({ where: { user1Id: likerUser.id } });
                await UserProfile.destroy({ where: { userId: likerUser.id } });
                await User.destroy({ where: { id: likerUser.id } });
            }
            if (targetUser) {
                await UserLike.destroy({ where: { targetUserId: targetUser.id } });
                await UserMatch.destroy({ where: { user2Id: targetUser.id } });
                await UserSubscription.destroy({ where: { userId: targetUser.id } });
                await UserProfile.destroy({ where: { userId: targetUser.id } });
                await User.destroy({ where: { id: targetUser.id } });
            }
        } catch (_) {}
    });

    const createMockRes = () => {
        const res: any = {};
        res.statusCode = 200;
        res.status = (code: number) => {
            res.statusCode = code;
            return res;
        };
        res.json = (body: any) => {
            res.body = body;
            return res;
        };
        return res;
    };

    it('1. should return total count in who-liked-summary without 500 error', async () => {
        // Liker likes target
        await UserLike.create({
            userId: likerUser.id,
            targetUserId: targetUser.id,
            actionType: 'like',
        });

        const req: any = {
            user: { id: targetUser.id },
            query: { userId: targetUser.id },
        };
        const res = createMockRes();

        await getWhoLikedSummary(req, res);

        expect(res.statusCode).toBe(200);
        expect(res.body.success).toBe(true);
        expect(res.body.data.totalCount).toBeGreaterThanOrEqual(1);
    });

    it('2. should return locked=true for free users in who-liked-me', async () => {
        SubscriptionService.invalidateCache(targetUser.id);

        const req: any = {
            user: { id: targetUser.id },
            query: { userId: targetUser.id },
        };
        const res = createMockRes();

        await getPeopleWhoLikedMe(req, res);

        expect(res.statusCode).toBe(200);
        expect(res.body.success).toBe(true);
        expect(res.body.locked).toBe(true);
        expect(res.body.canSeeWhoLiked).toBe(false);
    });

    it('3. should return unmasked profiles for VIP subscribers in who-liked-me', async () => {
        // Upgrade target to VIP
        await UserSubscription.create({
            userId: targetUser.id,
            packageId: vipPackage.id,
            status: SubscriptionStatus.ACTIVE,
            startDate: new Date(),
            endDate: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
            amount: 499,
        });

        SubscriptionService.invalidateCache(targetUser.id);

        const req: any = {
            user: { id: targetUser.id },
            query: { userId: targetUser.id },
        };
        const res = createMockRes();

        await getPeopleWhoLikedMe(req, res);

        expect(res.statusCode).toBe(200);
        expect(res.body.success).toBe(true);
        expect(res.body.locked).toBe(false);
        expect(res.body.canSeeWhoLiked).toBe(true);
        expect(Array.isArray(res.body.data)).toBe(true);
        expect(res.body.data.length).toBeGreaterThanOrEqual(1);
        expect(res.body.data[0].id).toBe(likerUser.id);
    });

    it('4. should handle getMyLikesAndMatches with valid status without enum errors', async () => {
        await UserMatch.create({
            user1Id: likerUser.id,
            user2Id: targetUser.id,
            compatibilityScore: 88,
            status: MatchStatus.PENDING,
            expiresAt: new Date(Date.now() + 86400000),
        });

        const req: any = {
            user: { id: targetUser.id },
            query: { userId: targetUser.id },
        };
        const res = createMockRes();

        await getMyLikesAndMatches(req, res);

        expect(res.statusCode).toBe(200);
        expect(res.body.success).toBe(true);
        expect(Array.isArray(res.body.data)).toBe(true);
    });
});
