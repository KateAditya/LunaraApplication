import request from 'supertest';
import app from '../server';
import User from '../models/User';


jest.mock('../services/emailService', () => ({
    sendVerificationEmail: jest.fn().mockResolvedValue(true),
    sendPasswordResetEmail: jest.fn().mockResolvedValue(true),
    sendWelcomeEmail: jest.fn().mockResolvedValue(true),
}));

describe('Auth Endpoints', () => {
    const testUser = {
        firstName: 'Test',
        lastName: 'User',
        email: 'testuser@example.com',
        phone: '9876543210',
        password: 'Password123!',
        dateOfBirth: '1995-01-01',
    };

    let userToken = '';
    let userId = '';

    it('should register a new user successfully', async () => {
        const res = await request(app)
            .post('/api/auth/register')
            .send(testUser);

        expect(res.status).toBe(201);
        expect(res.body.success).toBe(true);
        expect(res.body.message).toContain('Registration successful');
        expect(res.body.data).toHaveProperty('accessToken');

        userToken = res.body.data.accessToken;
        userId = res.body.data.user.id;
    });

    it('should verify email successfully', async () => {
        // Create token directly in DB for testing
        const crypto = require('crypto');
        const rawToken = crypto.randomBytes(32).toString('hex');
        const hashedToken = crypto.createHash('sha256').update(rawToken).digest('hex');
        const EmailVerification = require('../models/EmailVerification').default;

        // Remove old tokens
        await EmailVerification.destroy({ where: { userId } });

        await EmailVerification.create({
            userId,
            token: hashedToken,
            expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000)
        });

        const res = await request(app)
            .post('/api/auth/verify-email')
            .send({ token: rawToken });

        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);

        const user = await User.findByPk(userId);
        expect(user?.isVerified).toBe(true);
    });

    it('should fail login with incorrect password', async () => {
        const res = await request(app)
            .post('/api/auth/login')
            .send({
                email: testUser.email,
                password: 'WrongPassword!',
            });

        expect(res.status).toBe(401);
        expect(res.body.success).toBe(false);
    });

    it('should login successfully', async () => {
        const res = await request(app)
            .post('/api/auth/login')
            .send({
                email: testUser.email,
                password: testUser.password,
            });

        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        expect(res.body.data).toHaveProperty('accessToken');
    });

    it('should get current user profile', async () => {
        const res = await request(app)
            .get('/api/auth/me')
            .set('Authorization', `Bearer ${userToken}`);

        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        expect(res.body.data.email).toBe(testUser.email);
        expect(res.body.data.profile).toBeDefined();
    });

    it('should update user profile correctly', async () => {
        const res = await request(app)
            .put('/api/auth/me')
            .set('Authorization', `Bearer ${userToken}`)
            .send({
                firstName: 'Updated',
                bio: 'This is my test bio',
                city: 'Test City',
            });

        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        expect(res.body.data.firstName).toBe('Updated');
        expect(res.body.data.profile.bio).toBe('This is my test bio');
        expect(res.body.data.profile.city).toBe('Test City');
    });

    it('should setup 2FA successfully', async () => {
        const res = await request(app)
            .post('/api/auth/setup-2fa')
            .set('Authorization', `Bearer ${userToken}`);

        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        expect(res.body.data).toHaveProperty('secret');
        expect(res.body.data).toHaveProperty('qrCodeUrl');
    });

    it('should request forgot password', async () => {
        const sendPasswordResetEmailMock = require('../services/emailService').sendPasswordResetEmail;

        const res = await request(app)
            .post('/api/auth/forgot-password')
            .send({ email: testUser.email });

        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        expect(sendPasswordResetEmailMock).toHaveBeenCalled();
    });

    it('should change password successfully', async () => {
        const res = await request(app)
            .post('/api/auth/change-password')
            .set('Authorization', `Bearer ${userToken}`)
            .send({
                currentPassword: testUser.password,
                newPassword: 'NewPassword123!',
            });

        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
    });

    it('should setup the unified profile successfully', async () => {
        const res = await request(app)
            .put('/api/auth/profile-setup')
            .set('Authorization', `Bearer ${userToken}`)
            .send({
                bio: 'Looking for a fun night out.',
                gender: 'MALE',
                smokingPreference: 'NON-SMOKER',
                musicPreference: ['TECHNO', 'JAZZ'],
                preferredGenders: ['WOMEN', 'ALL'],
                minAgePreference: 21,
                maxAgePreference: 35,
                budgetRange: 'premium',
                showMeInMatching: true
            });

        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        expect(res.body.data.profile.gender).toBe('MALE');
        expect(res.body.data.preferences.smokingPreference).toBe('NON-SMOKER');
        expect(res.body.data.preferences.musicPreference).toContain('TECHNO');
        expect(res.body.data.preferences.preferredGenders).toContain('WOMEN');
        expect(res.body.data.preferences.minAgePreference).toBe(21);
    });
});
