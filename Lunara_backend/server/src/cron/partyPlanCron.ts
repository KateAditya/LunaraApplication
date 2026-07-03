import cron from 'node-cron';
import { Op } from 'sequelize';
import PartyPlanRequest, { PartyPlanRequestStatus } from '../models/PartyPlanRequest';
import PartyPlan, { PartyPlanStatus } from '../models/PartyPlan';
import User from '../models/User';
import { logger } from '../config/logger';

// Run every 5 minutes
export const startPartyPlanCron = () => {
    cron.schedule('*/5 * * * *', async () => {
        try {
            logger.info('Running Party Plan Cron Jobs...');
            
            const now = new Date();

            // 1. Check for expired payment timeouts
            // Requests that are PAYMENT_PENDING but the timeout has passed
            const expiredRequests = await PartyPlanRequest.findAll({
                where: {
                    status: PartyPlanRequestStatus.PAYMENT_PENDING,
                    paymentTimeoutAt: {
                        [Op.lt]: now
                    }
                },
                include: [{ model: PartyPlan, as: 'plan' }]
            });

            for (const request of expiredRequests) {
                const plan = (request as any).plan as PartyPlan;
                if (!plan) {
                    await request.update({ status: PartyPlanRequestStatus.PAYMENT_FAILED });
                    continue;
                }

                const hostPaid = plan.hostPaymentStatus === 'paid';
                const joinerPaid = request.joinerPaymentStatus === 'paid';

                if (!joinerPaid) {
                    // Case 1 — Interested Person does NOT pay:
                    // Refund interested person if pre-authorized (marked payment failed)
                    await request.update({ status: PartyPlanRequestStatus.PAYMENT_FAILED });
                    // Re-list the post publicly, no penalty to host (keep their deposit status)
                    await plan.update({ isLive: true });
                    logger.info(`Plan ${plan.id} is live again because joiner (req ${request.id}) did not pay within 30m.`);
                } else if (joinerPaid && !hostPaid) {
                    // Case 2 — Host does NOT pay:
                    // Refund the interested person
                    await request.update({ 
                        status: PartyPlanRequestStatus.PAYMENT_FAILED,
                        joinerPaymentStatus: 'refunded' as any
                    });
                    // Flag/cancel the post per business rule
                    await plan.update({ status: PartyPlanStatus.CANCELLED, isLive: false });
                    logger.warn(`Plan ${plan.id} cancelled/flagged because host failed to pay within 30m.`);
                } else {
                    // Fallback for Case 3 (both paid but somehow cron run first)
                    await request.update({ 
                        status: PartyPlanRequestStatus.ACCEPTED,
                        joinerPaymentStatus: 'refunded' as any
                    });
                    await plan.update({ 
                        hostPaymentStatus: 'refunded' as any,
                        status: PartyPlanStatus.INACTIVE,
                        isLive: false
                    });
                    logger.info(`Match Success (cron fallback) for plan ${plan.id}. Refunded both.`);
                }
            }

            // 2. Process Completed Plans (3 hours after planDateTime)
            // Refund successful matches and penalize no-shows
            const threeHoursAgo = new Date(now.getTime() - 3 * 60 * 60 * 1000);
            
            const completedPlans = await PartyPlan.findAll({
                where: {
                    status: PartyPlanStatus.ACTIVE,
                    planDateTime: {
                        [Op.lt]: threeHoursAgo
                    }
                }
            });

            for (const plan of completedPlans) {
                // Find paid join requests
                const paidRequests = await PartyPlanRequest.findAll({
                    where: {
                        planId: plan.id,
                        joinerPaymentStatus: 'paid'
                    }
                });

                if (paidRequests.length > 0) {
                    // We only have 1 accepted joiner for 1-on-1 party plan
                    const joinerReq = paidRequests[0];
                    const hostCheckedIn = plan.hostLatLangCheckIn;
                    const joinerCheckedIn = joinerReq.latLangCheckIn;

                    if (hostCheckedIn && joinerCheckedIn) {
                        // MATCH SUCCESS -> Refund both
                        logger.info(`Match Success! Refunding deposit for plan ${plan.id}`);
                        
                        // In reality, call Razorpay refund API here. For now mock:
                        await plan.update({ hostPaymentStatus: 'refunded' as any });
                        await joinerReq.update({ joinerPaymentStatus: 'refunded' as any });
                    } else {
                        // NO SHOW LOGIC
                        if (!hostCheckedIn) {
                            logger.info(`Host NO SHOW for plan ${plan.id}`);
                            const hostUser = await User.findByPk(plan.userId);
                            if (hostUser) {
                                const newCount = (hostUser.noShowCount || 0) + 1;
                                await hostUser.update({ noShowCount: newCount });
                                if (newCount >= 2) {
                                    logger.warn(`Restricting User profile for Host ${hostUser.id} due to 2 No-Shows`);
                                    await hostUser.update({ isActive: false });
                                }
                            }
                        }

                        if (!joinerCheckedIn) {
                            logger.info(`Joiner NO SHOW for request ${joinerReq.id}`);
                            const joinerUser = await User.findByPk(joinerReq.requesterId);
                            if (joinerUser) {
                                const newCount = (joinerUser.noShowCount || 0) + 1;
                                await joinerUser.update({ noShowCount: newCount });
                                if (newCount >= 2) {
                                    logger.warn(`Restricting User profile for Joiner ${joinerUser.id} due to 2 No-Shows`);
                                    await joinerUser.update({ isActive: false });
                                }
                            }
                        }
                    }
                }

                // Mark plan as completed/inactive so we don't process it again
                await plan.update({ status: PartyPlanStatus.INACTIVE });
            }
            
        } catch (error) {
            logger.error('Error running party plan cron jobs:', error);
        }
    });
};
