import { logger } from '../config/logger';

export interface SMSSendResult {
    success: boolean;
    message: string;
    gatewayResponse?: any;
}

export class SMSService {
    private static defaultUsername = process.env.SMS_USERNAME || 'sskworld!';
    private static defaultPassword = process.env.SMS_PASSWORD || '';
    private static defaultSenderId = process.env.SMS_SENDER_ID || 'SSKWRD';
    private static defaultPeid = process.env.SMS_PEID || '';
    private static defaultTemplateId = process.env.SMS_TEMPLATE_ID || '';

    /**
     * Normalizes a phone number into a clean 10-digit Indian mobile number string.
     * E.g., '+91 98765 43210' -> '9876543210'
     */
    public static normalizePhone(phone: string): string {
        if (!phone) return '';
        let cleaned = phone.replace(/\D/g, ''); // strip all non-digits
        if (cleaned.startsWith('91') && cleaned.length === 12) {
            cleaned = cleaned.substring(2);
        } else if (cleaned.startsWith('0') && cleaned.length === 11) {
            cleaned = cleaned.substring(1);
        }
        return cleaned;
    }

    /**
     * Validates an Indian 10-digit mobile number (must start with 6, 7, 8, or 9).
     */
    public static isValidIndianMobile(phone: string): boolean {
        const cleaned = this.normalizePhone(phone);
        return /^[6-9]\d{9}$/.test(cleaned);
    }

    /**
     * Sends OTP SMS using True Bulk SMS HTTP GET API
     */
    public static async sendOTP(phone: string, otpCode: string): Promise<SMSSendResult> {
        const cleanedPhone = this.normalizePhone(phone);
        if (!this.isValidIndianMobile(cleanedPhone)) {
            return { success: false, message: 'Invalid 10-digit Indian mobile number' };
        }

        const formattedTo = `91${cleanedPhone}`;
        const messageText = `Your LUNARA verification code is ${otpCode}. Enter this OTP to create your account. This code is valid for 5 minutes. Do not share it with anyone.`;

        const username = process.env.SMS_USERNAME || this.defaultUsername;
        const password = process.env.SMS_PASSWORD || this.defaultPassword;
        const sender = process.env.SMS_SENDER_ID || this.defaultSenderId;
        const peid = process.env.SMS_PEID || this.defaultPeid;
        const templateid = process.env.SMS_TEMPLATE_ID || this.defaultTemplateId;

        // If SMS credentials are missing and SMS API is not explicitly enabled, simulate send in development
        if (!password && !process.env.SMS_ENABLED) {
            logger.info(`[SMSService] SMS simulated for +${formattedTo}. Generated OTP Code: ${otpCode}`);
            return {
                success: true,
                message: 'OTP sent (Development mode simulated)',
            };
        }

        try {
            const queryParams = new URLSearchParams({
                username,
                password,
                sender,
                sendto: formattedTo,
                message: messageText,
                PEID: peid,
                templateid: templateid,
            });

            const apiUrl = `http://truebulksms.biz/api.php?${queryParams.toString()}`;

            logger.info(`[SMSService] Sending OTP via True Bulk SMS to +${formattedTo}...`);

            const response = await fetch(apiUrl, {
                method: 'GET',
                signal: AbortSignal.timeout(10000), // 10-second timeout
            });

            const responseText = await response.text();
            logger.info(`[SMSService] True Bulk SMS Response: ${responseText}`);

            if (response.ok) {
                return {
                    success: true,
                    message: 'OTP SMS sent successfully',
                    gatewayResponse: responseText,
                };
            } else {
                return {
                    success: false,
                    message: `SMS gateway returned error code ${response.status}`,
                    gatewayResponse: responseText,
                };
            }
        } catch (error: any) {
            logger.error(`[SMSService] Error dispatching SMS to +${formattedTo}:`, error?.message || error);
            return {
                success: false,
                message: `SMS dispatch failed: ${error?.message || 'Network error'}`,
            };
        }
    }
}
