import request from 'supertest';
import app from '../server';
import User, { UserRole } from '../models/User';
import Message, { MessageType, MessageStatus } from '../models/Message';
import SocialConnection, { ConnectionStatus } from '../models/SocialConnection';
import { generateAccessToken } from '../utils/jwt';

jest.mock('../services/fcmService', () => ({
    sendPushNotification: jest.fn().mockResolvedValue(true),
    sendMulticastPushNotification: jest.fn().mockResolvedValue(true),
}));

describe('Chat Blocking & Multi-Select Batch Delete Test Suite', () => {
    let userA: User;
    let userB: User;
    let tokenA: string;
    let tokenB: string;
    let conversationId: string;

    beforeAll(async () => {
        const ts = Date.now();
        const numSuffix = String(ts % 100000).padStart(5, '0');
        userA = await User.create({
            firstName: 'Alice',
            lastName: 'Blocker',
            email: `alice_${ts}@test.com`,
            phone: `98765${numSuffix}`,
            passwordHash: 'hashed',
            dateOfBirth: new Date('1995-05-15'),
            role: UserRole.CUSTOMER,
            isVerified: true,
        });

        userB = await User.create({
            firstName: 'Bob',
            lastName: 'Sender',
            email: `bob_${ts}@test.com`,
            phone: `98766${numSuffix}`,
            passwordHash: 'hashed',
            dateOfBirth: new Date('1996-06-20'),
            role: UserRole.CUSTOMER,
            isVerified: true,
        });

        tokenA = generateAccessToken({ userId: userA.id, email: userA.email, role: userA.role });
        tokenB = generateAccessToken({ userId: userB.id, email: userB.email, role: userB.role });

        // Create or get conversation between User A and User B
        const convRes = await request(app)
            .post('/api/mobile/chat/conversations')
            .set('Authorization', `Bearer ${tokenA}`)
            .send({
                userId: userA.id,
                otherUserId: userB.id,
            });

        expect([200, 201]).toContain(convRes.status);
        conversationId = convRes.body.data.id;
    });

    describe('1. Chat Blocking & Delivery Isolation', () => {
        it('User A blocks User B', async () => {
            const blockRes = await request(app)
                .post('/api/mobile/user/block')
                .set('Authorization', `Bearer ${tokenA}`)
                .send({
                    userId: userA.id,
                    targetUserId: userB.id,
                });

            expect([200, 201]).toContain(blockRes.status);

            const connection = await SocialConnection.findOne({
                where: {
                    requesterId: userA.id,
                    receiverId: userB.id,
                    status: ConnectionStatus.BLOCKED,
                },
            });
            expect(connection).not.toBeNull();
        });

        it('User A (blocker) cannot send messages to User B while blocking', async () => {
            const res = await request(app)
                .post(`/api/mobile/chat/conversations/${conversationId}/messages`)
                .set('Authorization', `Bearer ${tokenA}`)
                .send({
                    senderId: userA.id,
                    type: MessageType.TEXT,
                    content: 'Hello Bob from Alice',
                });

            expect(res.status).toBe(403);
            expect(res.body.message).toContain('You have blocked this user');
        });

        it('User B (blocked user) sends a message to User A: created for B, isolated and hidden from A', async () => {
            const res = await request(app)
                .post(`/api/mobile/chat/conversations/${conversationId}/messages`)
                .set('Authorization', `Bearer ${tokenB}`)
                .send({
                    senderId: userB.id,
                    type: MessageType.TEXT,
                    content: 'Secret message from Bob while blocked',
                });

            expect(res.status).toBe(201);
            expect(res.body.success).toBe(true);
            const createdMsgId = res.body.data.id;

            // Verify in DB that deletedForUsers includes User A
            const dbMsg = await Message.findByPk(createdMsgId);
            expect(dbMsg).not.toBeNull();
            expect(dbMsg!.status).toBe(MessageStatus.SENT);
            expect((dbMsg as any).deletedForUsers).toEqual([userA.id]);

            // Bob can see his message in getMessages
            const bobMessagesRes = await request(app)
                .get(`/api/mobile/chat/conversations/${conversationId}/messages`)
                .set('Authorization', `Bearer ${tokenB}`)
                .query({ userId: userB.id });

            expect(bobMessagesRes.status).toBe(200);
            const bobMsgIds = bobMessagesRes.body.data.map((m: any) => m.id);
            expect(bobMsgIds).toContain(createdMsgId);

            // Alice CANNOT see Bob's blocked message in getMessages
            const aliceMessagesRes = await request(app)
                .get(`/api/mobile/chat/conversations/${conversationId}/messages`)
                .set('Authorization', `Bearer ${tokenA}`)
                .query({ userId: userA.id });

            expect(aliceMessagesRes.status).toBe(200);
            const aliceMsgIds = aliceMessagesRes.body.data.map((m: any) => m.id);
            expect(aliceMsgIds).not.toContain(createdMsgId);
        });

        it('User A unblocks User B: future messages are visible, past blocked messages stay hidden from A', async () => {
            // Alice unblocks Bob
            const unblockRes = await request(app)
                .post('/api/mobile/user/unblock')
                .set('Authorization', `Bearer ${tokenA}`)
                .send({
                    userId: userA.id,
                    targetUserId: userB.id,
                });

            expect([200, 204]).toContain(unblockRes.status);

            // Bob sends a new message after unblock
            const postUnblockRes = await request(app)
                .post(`/api/mobile/chat/conversations/${conversationId}/messages`)
                .set('Authorization', `Bearer ${tokenB}`)
                .send({
                    senderId: userB.id,
                    type: MessageType.TEXT,
                    content: 'Hello Alice after unblocking!',
                });

            expect(postUnblockRes.status).toBe(201);
            const newMsgId = postUnblockRes.body.data.id;

            // Alice checks messages: sees newMsgId, but NOT the blocked message
            const aliceMessages = await request(app)
                .get(`/api/mobile/chat/conversations/${conversationId}/messages`)
                .set('Authorization', `Bearer ${tokenA}`)
                .query({ userId: userA.id });

            const aliceMsgIds = aliceMessages.body.data.map((m: any) => m.id);
            const aliceMsgContents = aliceMessages.body.data.map((m: any) => m.content);
            expect(aliceMsgIds).toContain(newMsgId);
            expect(aliceMsgContents).toContain('Hello Alice after unblocking!');
            expect(aliceMsgContents).not.toContain('Secret message from Bob while blocked');
        });
    });

    describe('2. Multi-Select Batch Message Deletion', () => {
        let msg1Id: string;
        let msg2Id: string;
        let msg3Id: string;

        beforeAll(async () => {
            // Bob sends 3 test messages
            const r1 = await request(app)
                .post(`/api/mobile/chat/conversations/${conversationId}/messages`)
                .set('Authorization', `Bearer ${tokenB}`)
                .send({ senderId: userB.id, type: MessageType.TEXT, content: 'Batch Msg 1' });
            msg1Id = r1.body.data.id;

            const r2 = await request(app)
                .post(`/api/mobile/chat/conversations/${conversationId}/messages`)
                .set('Authorization', `Bearer ${tokenB}`)
                .send({ senderId: userB.id, type: MessageType.TEXT, content: 'Batch Msg 2' });
            msg2Id = r2.body.data.id;

            const r3 = await request(app)
                .post(`/api/mobile/chat/conversations/${conversationId}/messages`)
                .set('Authorization', `Bearer ${tokenB}`)
                .send({ senderId: userB.id, type: MessageType.TEXT, content: 'Batch Msg 3' });
            msg3Id = r3.body.data.id;
        });

        it('Rejects batch delete for everyone if user did not send all messages', async () => {
            const res = await request(app)
                .post(`/api/mobile/chat/conversations/${conversationId}/messages/batch-delete`)
                .set('Authorization', `Bearer ${tokenA}`)
                .send({
                    userId: userA.id,
                    messageIds: [msg1Id, msg2Id],
                    deleteForEveryone: true,
                });

            expect(res.status).toBe(403);
            expect(res.body.message).toContain('You can only delete your own messages for everyone');
        });

        it('Batch deletes messages for everyone by sender (Bob)', async () => {
            const res = await request(app)
                .post(`/api/mobile/chat/conversations/${conversationId}/messages/batch-delete`)
                .set('Authorization', `Bearer ${tokenB}`)
                .send({
                    userId: userB.id,
                    messageIds: [msg1Id, msg2Id],
                    deleteForEveryone: true,
                });

            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.data.messageIds).toEqual(expect.arrayContaining([msg1Id, msg2Id]));

            // Verify both messages have deletedAt set
            const m1 = await Message.findByPk(msg1Id);
            const m2 = await Message.findByPk(msg2Id);
            expect(m1!.deletedAt).not.toBeNull();
            expect(m2!.deletedAt).not.toBeNull();
        });

        it('Batch deletes messages for me (Alice deletes Msg 3 for herself)', async () => {
            const res = await request(app)
                .post(`/api/mobile/chat/conversations/${conversationId}/messages/batch-delete`)
                .set('Authorization', `Bearer ${tokenA}`)
                .send({
                    userId: userA.id,
                    messageIds: [msg3Id],
                    deleteForEveryone: false,
                });

            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);

            // Alice should not see msg3
            const aliceRes = await request(app)
                .get(`/api/mobile/chat/conversations/${conversationId}/messages`)
                .set('Authorization', `Bearer ${tokenA}`)
                .query({ userId: userA.id });

            const aliceIds = aliceRes.body.data.map((m: any) => m.id);
            expect(aliceIds).not.toContain(msg3Id);

            // Bob should STILL see msg3
            const bobRes = await request(app)
                .get(`/api/mobile/chat/conversations/${conversationId}/messages`)
                .set('Authorization', `Bearer ${tokenB}`)
                .query({ userId: userB.id });

            const bobIds = bobRes.body.data.map((m: any) => m.id);
            expect(bobIds).toContain(msg3Id);
        });
    });
});
