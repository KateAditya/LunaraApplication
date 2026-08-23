import { Router, Request, Response } from 'express';
import { authenticate } from '../middleware/auth';
import { PaymentService } from '../services/PaymentService';
import { PaymentIntentEntityType, PaymentIntentMethod } from '../models/PaymentIntent';

const router = Router();

/**
 * POST /api/mobile/payments/intent
 * Initiates or retrieves a central payment intent for any paid feature.
 */
router.post('/intent', authenticate, async (req: Request, res: Response) => {
    try {
        const userId = (req as any).user.id;
        const { entityType, entityId, amount, paymentMethod, metadata } = req.body;

        if (!entityType || !entityId) {
            return res.status(400).json({ success: false, message: 'entityType and entityId are required' });
        }

        const validMethods = [PaymentIntentMethod.WALLET, PaymentIntentMethod.RAZORPAY, PaymentIntentMethod.HYBRID, PaymentIntentMethod.FREE];
        const method = validMethods.includes(paymentMethod) ? paymentMethod : PaymentIntentMethod.RAZORPAY;

        const result = await PaymentService.createPaymentIntent({
            userId,
            entityType: entityType as PaymentIntentEntityType,
            entityId,
            amount: Number(amount) || 0,
            paymentMethod: method,
            metadata,
        });

        if (!result.success && result.shortfallData) {
            return res.status(200).json({
                success: false,
                code: 'INSUFFICIENT_WALLET_BALANCE',
                message: result.message,
                data: result.shortfallData,
                paymentIntent: result.paymentIntent,
            });
        }

        return res.status(200).json({
            success: true,
            data: {
                paymentIntent: result.paymentIntent,
                razorpayOrder: result.razorpayOrder,
                message: result.message,
            },
        });
    } catch (error: any) {
        console.error('Error creating payment intent:', error);
        return res.status(500).json({ success: false, message: error?.message || 'Failed to initiate payment intent' });
    }
});

/**
 * POST /api/mobile/payments/wallet-pay
 * Executes direct Lunara Smart Wallet payment for an intent.
 */
router.post('/wallet-pay', authenticate, async (req: Request, res: Response) => {
    try {
        const userId = (req as any).user.id;
        const { paymentIntentId } = req.body;

        if (!paymentIntentId) {
            return res.status(400).json({ success: false, message: 'paymentIntentId is required' });
        }

        const result = await PaymentService.processWalletPayment(paymentIntentId, userId);
        return res.json({
            success: true,
            message: result.message || 'Payment completed successfully using Smart Credit Wallet',
            data: { paymentIntent: result.paymentIntent },
        });
    } catch (error: any) {
        console.error('Error processing wallet payment:', error);
        return res.status(400).json({ success: false, message: error?.message || 'Wallet payment could not be completed' });
    }
});

/**
 * POST /api/mobile/payments/verify
 * Verifies Razorpay payment signature and finalizes payment.
 */
router.post('/verify', authenticate, async (req: Request, res: Response) => {
    try {
        const userId = (req as any).user.id;
        const { paymentIntentId, paymentReference, razorpay_order_id, razorpay_payment_id, razorpay_signature } = req.body;

        const orderId = razorpay_order_id || req.body.razorpayOrderId;
        const paymentId = razorpay_payment_id || req.body.razorpayPaymentId;
        const signature = razorpay_signature || req.body.razorpaySignature;

        if (!orderId && !paymentIntentId && !paymentReference) {
            return res.status(400).json({ success: false, message: 'razorpay_order_id or paymentIntentId is required' });
        }

        const result = await PaymentService.verifyRazorpayPayment({
            paymentIntentId,
            paymentReference,
            razorpayOrderId: orderId,
            razorpayPaymentId: paymentId || `pay_mock_${Date.now()}`,
            razorpaySignature: signature,
            userId,
        });

        if (!result.success) {
            return res.status(400).json({ success: false, message: result.message });
        }

        return res.json({
            success: true,
            message: 'Payment verified and booking confirmed!',
            data: { paymentIntent: result.paymentIntent },
        });
    } catch (error: any) {
        console.error('Error verifying payment:', error);
        return res.status(500).json({ success: false, message: error?.message || 'Payment verification failed' });
    }
});

/**
 * POST /api/mobile/payments/webhook
 * Public Razorpay Webhook listener for asynchronous payment capture events.
 */
router.post('/webhook', async (req: Request, res: Response) => {
    try {
        const signature = (req.headers['x-razorpay-signature'] as string) || '';
        const result = await PaymentService.handleRazorpayWebhook(req.body, signature);
        return res.status(200).json({ success: true, message: result.message });
    } catch (error: any) {
        console.error('Error processing Razorpay webhook:', error);
        return res.status(200).json({ success: false, message: 'Webhook error logged safely' });
    }
});

/**
 * GET /api/mobile/payments/:intentId/status
 * Queries the latest backend payment status for reconciliation.
 */
router.get('/:intentId/status', authenticate, async (req: Request, res: Response) => {
    try {
        const { intentId } = req.params;
        const intent = await PaymentService.verifyRazorpayPayment({
            paymentIntentId: intentId,
            razorpayOrderId: '',
            razorpayPaymentId: '',
            userId: (req as any).user.id,
        }).catch(() => null);

        return res.json({
            success: true,
            data: { status: intent?.paymentIntent?.status || 'unknown' },
        });
    } catch (error: any) {
        return res.status(500).json({ success: false, message: 'Failed to fetch status' });
    }
});

export default router;
