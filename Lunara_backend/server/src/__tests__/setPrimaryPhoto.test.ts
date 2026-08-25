import request from 'supertest';
import app from '../server';
import User, { UserRole } from '../models/User';
import UserPhoto from '../models/UserPhoto';
import { generateAccessToken } from '../utils/jwt';

jest.mock('../services/fcmService', () => ({
    sendPushNotification: jest.fn().mockResolvedValue(true),
    sendMulticastPushNotification: jest.fn().mockResolvedValue(true),
}));

describe('Set Profile Picture / Primary Photo Suite', () => {
    let testUser: User;
    let token: string;
    let photo1: UserPhoto;
    let photo2: UserPhoto;

    beforeAll(async () => {
        const ts = Date.now();
        const numSuffix = String(ts % 100000).padStart(5, '0');
        testUser = await User.create({
            firstName: 'Neha',
            lastName: 'PhotoTest',
            email: `neha_photo_${ts}@test.com`,
            phone: `98777${numSuffix}`,
            passwordHash: 'hashed',
            dateOfBirth: new Date('1997-03-25'),
            role: UserRole.CUSTOMER,
            isVerified: true,
        });

        token = generateAccessToken({ userId: testUser.id, email: testUser.email, role: testUser.role });

        photo1 = await UserPhoto.create({
            userId: testUser.id,
            filePath: `uploads/users/${testUser.id}/gallery/photo1_${ts}.jpg`,
            fileSize: 102400,
            mimeType: 'image/jpeg',
            isPrimary: true,
            displayOrder: 0,
        });

        photo2 = await UserPhoto.create({
            userId: testUser.id,
            filePath: `uploads/users/${testUser.id}/gallery/photo2_${ts}.jpg`,
            fileSize: 102400,
            mimeType: 'image/jpeg',
            isPrimary: false,
            displayOrder: 1,
        });
    });

    it('Successfully sets photo2 as primary profile picture via /api/profile/photos/:id/primary', async () => {
        const res = await request(app)
            .put(`/api/profile/photos/${photo2.id}/primary`)
            .set('Authorization', `Bearer ${token}`)
            .send();

        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        expect(res.body.message).toContain('Primary photo updated successfully');

        // Verify photo2 is now primary and photo1 is not
        const updatedPhoto1 = await UserPhoto.findByPk(photo1.id);
        const updatedPhoto2 = await UserPhoto.findByPk(photo2.id);
        expect(updatedPhoto1!.isPrimary).toBe(false);
        expect(updatedPhoto2!.isPrimary).toBe(true);

        // Verify User profileImageUrl is updated with photo2
        const updatedUser = await User.findByPk(testUser.id);
        expect(updatedUser!.profileImageUrl).toBe('/' + photo2.filePath.replace(/\\/g, '/'));
    });

    it('Successfully sets photo1 back as primary profile picture via /api/mobile/user/photos/:id/primary', async () => {
        const res = await request(app)
            .put(`/api/mobile/user/photos/${photo1.id}/primary`)
            .set('Authorization', `Bearer ${token}`)
            .send();

        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);

        const updatedPhoto1 = await UserPhoto.findByPk(photo1.id);
        expect(updatedPhoto1!.isPrimary).toBe(true);

        const updatedUser = await User.findByPk(testUser.id);
        expect(updatedUser!.profileImageUrl).toBe('/' + photo1.filePath.replace(/\\/g, '/'));
    });

    it('Returns 404 if photo does not exist or belong to user', async () => {
        const fakeId = '00000000-0000-0000-0000-000000000000';
        const res = await request(app)
            .put(`/api/profile/photos/${fakeId}/primary`)
            .set('Authorization', `Bearer ${token}`)
            .send();

        expect(res.status).toBe(404);
        expect(res.body.success).toBe(false);
    });
});
