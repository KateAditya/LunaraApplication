import nodemailer from 'nodemailer';
import { logger } from '../config/logger';
import { LOGO_V4_BASE64, FAVICON_BASE64 } from './emailAssets';

// Resolve credentials — support both EMAIL_USER/SMTP_USER naming conventions
const smtpUser = process.env.EMAIL_USER || process.env.SMTP_USER || '';
const smtpPass = process.env.EMAIL_PASSWORD || process.env.SMTP_PASSWORD || '';
const smtpHost = process.env.EMAIL_HOST || process.env.SMTP_HOST || 'smtp.gmail.com';
const smtpPort = parseInt(process.env.EMAIL_PORT || process.env.SMTP_PORT || '587');
const smtpFrom = process.env.EMAIL_FROM || `Lunara <${smtpUser}>`;
// port 465 = implicit TLS (secure:true); port 587 = STARTTLS (secure:false)
const smtpSecure = smtpPort === 465;

const transporter = nodemailer.createTransport({
  host: smtpHost,
  port: smtpPort,
  secure: smtpSecure,
  auth: {
    user: smtpUser,
    pass: smtpPass,
  },
  tls: {
    rejectUnauthorized: false,
  },
});

export { smtpFrom };

transporter.verify((error: Error | null) => {
  if (error) {
    logger.warn(`[EmailService] SMTP verification notice: ${error.message}. (Transactional emails disabled until valid credentials provided)`);
  } else {
    logger.info(`Email service ready — sending as: ${smtpFrom} via ${smtpHost}:${smtpPort}`);
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Shared brand constants
// ─────────────────────────────────────────────────────────────────────────────
const BRAND_PURPLE = '#7c3aed';
const BRAND_PURPLE2 = '#a855f7';
const BRAND_GOLD = '#f59e0b';
const BRAND_DARK = '#0f0a1e';
const YEAR = new Date().getFullYear();

const commonAttachments = [
  {
    filename: 'logo.png',
    path: LOGO_V4_BASE64,
    cid: 'logo'
  },
  {
    filename: 'favicon.png',
    path: FAVICON_BASE64,
    cid: 'favicon'
  }
];

/**
 * Shared header for all Lunara emails.
 * Renders a dark gradient banner with the Lunara logo + tagline.
 */
function emailHeader(tagline: string): string {
  // Use embedded base64 logo — works in all email clients, no external URL needed
  return `
    <tr>
      <td style="background:linear-gradient(135deg,${BRAND_DARK} 0%,#1e0a3c 60%,#2d1060 100%);padding:40px 40px 32px;text-align:center;">
        <!-- Lunara Logo V4 (base64 embedded) -->
        <div style="margin-bottom:14px;">
          <img
            src="cid:logo"
            alt="Lunara"
            width="180"
            style="max-width:180px;height:auto;display:inline-block;"
          />
        </div>
        <!-- Tagline -->
        <p style="margin:0;font-size:11px;letter-spacing:0.2em;color:rgba(255,255,255,0.45);text-transform:uppercase;font-family:'Segoe UI',Arial,sans-serif;">
          ${tagline}
        </p>
      </td>
    </tr>`;
}

/**
 * Shared footer for all Lunara emails.
 */
function emailFooter(): string {
  // Use embedded base64 favicon — works without a public server URL
  return `
    <tr>
      <td style="background:#0f0a1e;padding:28px 40px;text-align:center;border-top:1px solid rgba(124,58,237,0.25);">
        <!-- Favicon icon (base64 embedded) -->
        <div style="margin-bottom:10px;">
          <img src="cid:favicon" alt="Lunara" width="32" style="width:32px;height:auto;display:inline-block;opacity:0.85;" />
        </div>
        <p style="margin:0 0 6px;font-size:12px;color:rgba(255,255,255,0.4);font-family:'Segoe UI',Arial,sans-serif;">
          © ${YEAR} Lunara · India's Premier Nightlife Platform
        </p>
        <p style="margin:0 0 6px;font-size:11px;color:rgba(255,255,255,0.25);font-family:'Segoe UI',Arial,sans-serif;">
          Questions? <a href="mailto:support@lunara.com" style="color:${BRAND_PURPLE2};text-decoration:none;">support@lunara.com</a>
        </p>
        <p style="margin:0;font-size:10px;color:rgba(255,255,255,0.18);font-family:'Segoe UI',Arial,sans-serif;">
          This is an automated email. Please do not reply directly.
        </p>
      </td>
    </tr>`;
}

/**
 * Wrapper that centres the 600px email card on a neutral background.
 */
function emailWrapper(innerRows: string): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1.0"/>
</head>
<body style="margin:0;padding:0;background-color:#f0ebff;font-family:'Segoe UI',Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background:#f0ebff;padding:40px 16px;">
    <tr><td align="center">
      <table width="600" cellpadding="0" cellspacing="0"
             style="max-width:600px;width:100%;background:#ffffff;border-radius:20px;overflow:hidden;box-shadow:0 8px 40px rgba(124,58,237,0.18);">
        ${innerRows}
      </table>
    </td></tr>
  </table>
</body>
</html>`;
}

// ─────────────────────────────────────────────────────────────────────────────
// CTA button helper
// ─────────────────────────────────────────────────────────────────────────────
function ctaButton(url: string, label: string): string {
  return `
    <table width="100%" cellpadding="0" cellspacing="0">
      <tr>
        <td align="center" style="padding:28px 0 8px;">
          <a href="${url}"
             style="display:inline-block;background:linear-gradient(135deg,${BRAND_PURPLE},${BRAND_PURPLE2});color:#ffffff;
                    text-decoration:none;padding:16px 48px;border-radius:50px;font-size:15px;font-weight:700;
                    letter-spacing:0.4px;box-shadow:0 8px 28px rgba(124,58,237,0.4);font-family:'Segoe UI',Arial,sans-serif;">
            ${label}
          </a>
        </td>
      </tr>
    </table>`;
}

// ─────────────────────────────────────────────────────────────────────────────
// Info box helper
// ─────────────────────────────────────────────────────────────────────────────
function infoBox(content: string, color = BRAND_PURPLE): string {
  return `
    <table width="100%" cellpadding="0" cellspacing="0" style="margin:20px 0;">
      <tr>
        <td style="background:#faf5ff;border-left:4px solid ${color};border-radius:0 10px 10px 0;padding:16px 20px;">
          ${content}
        </td>
      </tr>
    </table>`;
}

// ─────────────────────────────────────────────────────────────────────────────
// Body row helper
// ─────────────────────────────────────────────────────────────────────────────
function bodyRow(html: string): string {
  return `<tr><td style="padding:40px;">${html}</td></tr>`;
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. Email Verification
// ─────────────────────────────────────────────────────────────────────────────
export async function sendVerificationEmail(email: string, token: string, userName: string): Promise<void> {
  const verificationUrl = `${process.env.FRONTEND_URL || 'http://localhost:3000'}/verify-email?token=${token}`;

  const body = bodyRow(`
    <p style="margin:0 0 6px;font-size:22px;font-weight:700;color:#0f0a1e;">Welcome to Lunara, ${userName}! 🎉</p>
    <p style="margin:0 0 20px;font-size:14px;color:#555;line-height:1.7;">
      You're one step away from unlocking India's most exciting nightlife experiences. Please verify your email address to activate your account.
    </p>
    ${infoBox(`<p style="margin:0;font-size:13px;color:#374151;line-height:1.7;">Tap the button below to confirm your email. This link expires in <strong>24 hours</strong>.</p>`)}
    ${ctaButton(verificationUrl, '✉ Verify My Email')}
    <p style="margin:20px 0 0;font-size:12px;color:#9ca3af;word-break:break-all;">
      Or paste this link into your browser:<br/>
      <a href="${verificationUrl}" style="color:${BRAND_PURPLE};text-decoration:none;">${verificationUrl}</a>
    </p>
    <p style="margin:16px 0 0;font-size:12px;color:#9ca3af;">
      Didn't create an account? You can safely ignore this email.
    </p>
  `);

  try {
    await transporter.sendMail({
      from: smtpFrom,
      to: email,
      subject: '✦ Verify Your Lunara Account',
      html: emailWrapper(emailHeader('Your Gateway to Premium Nightlife') + body + emailFooter()),
      attachments: commonAttachments,
    });
    logger.info(`Verification email sent to ${email}`);
  } catch (error) {
    logger.error('Error sending verification email:', error);
    throw new Error('Failed to send verification email');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. Password Reset
// ─────────────────────────────────────────────────────────────────────────────
export async function sendPasswordResetEmail(email: string, token: string, userName: string): Promise<void> {
  const resetUrl = `${process.env.FRONTEND_URL || 'http://localhost:3000'}/reset-password?token=${token}`;

  const body = bodyRow(`
    <p style="margin:0 0 6px;font-size:22px;font-weight:700;color:#0f0a1e;">Password Reset Request</p>
    <p style="margin:0 0 20px;font-size:14px;color:#555;line-height:1.7;">
      Hi <strong>${userName}</strong>, we received a request to reset your Lunara account password.
      If this wasn't you, please ignore this email — your account remains secure.
    </p>
    ${ctaButton(resetUrl, '🔑 Reset My Password')}
    ${infoBox(`
      <p style="margin:0 0 8px;font-size:13px;font-weight:700;color:#b45309;">⚠ Security Notice</p>
      <ul style="margin:0;padding-left:18px;">
        <li style="font-size:12px;color:#374151;line-height:1.8;">This link expires in <strong>15 minutes</strong></li>
        <li style="font-size:12px;color:#374151;line-height:1.8;">It can only be used once</li>
        <li style="font-size:12px;color:#374151;line-height:1.8;">Never share this link with anyone</li>
      </ul>
    `, BRAND_GOLD)}
    <p style="margin:20px 0 0;font-size:12px;color:#9ca3af;word-break:break-all;">
      Or paste this link: <a href="${resetUrl}" style="color:${BRAND_PURPLE};text-decoration:none;">${resetUrl}</a>
    </p>
  `);

  try {
    await transporter.sendMail({
      from: smtpFrom,
      to: email,
      subject: '✦ Reset Your Lunara Password',
      html: emailWrapper(emailHeader('Account Security') + body + emailFooter()),
      attachments: commonAttachments,
    });
    logger.info(`Password reset email sent to ${email}`);
  } catch (error) {
    logger.error('Error sending password reset email:', error);
    throw new Error('Failed to send password reset email');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. Welcome Email
// ─────────────────────────────────────────────────────────────────────────────
export async function sendWelcomeEmail(email: string, userName: string): Promise<void> {
  const exploreUrl = `${process.env.FRONTEND_URL || 'http://localhost:3000'}/explore`;

  const features = [
    { icon: '🏢', title: 'Discover Venues', desc: 'Explore top-rated pubs, clubs, lounges, hotels & rooftops.' },
    { icon: '📅', title: 'Instant Bookings', desc: 'Reserve your spot at exclusive venues with just a few taps.' },
    { icon: '💘', title: 'Match the Vibes', desc: 'Connect with like-minded people based on your nightlife preferences.' },
    { icon: '👥', title: 'Group Nights', desc: 'Plan nights out with friends and split payments easily.' },
  ];

  const featureRows = features.map(f => `
    <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:12px;">
      <tr>
        <td style="background:#faf5ff;border-radius:12px;padding:14px 18px;">
          <p style="margin:0;font-size:14px;font-weight:700;color:#0f0a1e;">${f.icon} ${f.title}</p>
          <p style="margin:4px 0 0;font-size:12px;color:#6b7280;line-height:1.6;">${f.desc}</p>
        </td>
      </tr>
    </table>
  `).join('');

  const body = bodyRow(`
    <p style="margin:0 0 6px;font-size:22px;font-weight:700;color:#0f0a1e;">You're All Set, ${userName}! 🎊</p>
    <p style="margin:0 0 24px;font-size:14px;color:#555;line-height:1.7;">
      Your Lunara account is now <strong style="color:${BRAND_PURPLE};">verified and active</strong>.
      Get ready to discover the best nightlife in your city.
    </p>
    ${featureRows}
    ${ctaButton(exploreUrl, '🚀 Start Exploring')}
    <p style="margin:20px 0 0;font-size:12px;color:#9ca3af;text-align:center;">
      <strong>Pro Tip:</strong> Complete your profile to get personalised venue recommendations!
    </p>
  `);

  try {
    await transporter.sendMail({
      from: smtpFrom,
      to: email,
      subject: '✦ Welcome to Lunara — Let\'s Get the Night Started!',
      html: emailWrapper(emailHeader('India\'s Premier Nightlife Platform') + body + emailFooter()),
      attachments: commonAttachments,
    });
    logger.info(`Welcome email sent to ${email}`);
  } catch (error) {
    logger.error('Error sending welcome email:', error);
    // Non-critical — don't throw
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. Venue Confirmation Email  (T&C + Go-Live CTA)
// ─────────────────────────────────────────────────────────────────────────────
export async function sendVenueConfirmationEmail(
  cpEmail: string,
  cpName: string,
  venueName: string,
  confirmUrl: string
): Promise<void> {
  const body = bodyRow(`
    <!-- Action badge -->
    <div style="display:inline-block;background:#fef3c7;border:1px solid ${BRAND_GOLD};color:#b45309;border-radius:6px;
                padding:4px 14px;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:0.06em;margin-bottom:20px;">
      ⚡ Action Required
    </div>

    <p style="margin:0 0 8px;font-size:22px;font-weight:700;color:#0f0a1e;">Your Venue Is Almost Live! 🎉</p>
    <p style="margin:0 0 20px;font-size:14px;color:#555;line-height:1.7;">
      Hi <strong>${cpName || 'there'}</strong>, your venue has been submitted to
      <strong style="color:${BRAND_PURPLE};">Lunara</strong> — India's premier nightlife discovery platform.
      One last step: please review and formally confirm your listing.
    </p>

    <!-- Venue card -->
    <table width="100%" cellpadding="0" cellspacing="0"
           style="background:linear-gradient(135deg,#1e0a3c,#2d1060);border-radius:14px;margin:0 0 28px;">
      <tr>
        <td style="padding:22px 28px;">
          <p style="margin:0 0 4px;font-size:20px;font-weight:800;color:#ffffff;">🏢 ${venueName}</p>
          <p style="margin:0;font-size:13px;color:rgba(255,255,255,0.6);">Submitted for Lunara listing — pending confirmation</p>
        </td>
      </tr>
    </table>

    ${ctaButton(confirmUrl, '✅ Confirm &amp; Accept — Go Live')}

    <p style="margin:12px 0 0;font-size:12px;color:#9ca3af;text-align:center;">
      ⏰ This link expires in <strong>72 hours</strong>.
      After clicking, your venue will be reviewed and go live shortly.
    </p>
    <p style="margin:6px 0 24px;font-size:11px;color:#c4b5fd;text-align:center;word-break:break-all;">
      ${confirmUrl}
    </p>

    <hr style="border:none;border-top:1px solid #e5e7eb;margin:28px 0;"/>

    <!-- T&C -->
    <table width="100%" cellpadding="0" cellspacing="0" style="background:#faf5ff;border:1px solid #ddd6fe;border-radius:12px;">
      <tr>
        <td style="padding:24px;">
          <h3 style="margin:0 0 12px;font-size:13px;font-weight:700;color:${BRAND_PURPLE};text-transform:uppercase;letter-spacing:0.06em;">
            📄 Lunara Venue Partner — Terms &amp; Conditions
          </h3>
          <p style="margin:0 0 14px;font-size:13px;color:#374151;line-height:1.7;">
            Please read the following carefully before confirming your venue listing.
          </p>

          <h4 style="margin:12px 0 4px;font-size:12px;color:#0f0a1e;">1. Acceptance of Terms</h4>
          <p style="margin:0 0 10px;font-size:12px;color:#374151;line-height:1.7;">
            By confirming, you agree to be bound by these Terms and our Privacy Policy. If you do not agree, please do not proceed.
          </p>

          <h4 style="margin:12px 0 4px;font-size:12px;color:#0f0a1e;">2. Use of Services</h4>
          <p style="margin:0 0 10px;font-size:12px;color:#374151;line-height:1.7;">
            You may use Lunara only as permitted by law. We may suspend services if you violate our terms or policies.
          </p>

          <h4 style="margin:12px 0 4px;font-size:12px;color:#0f0a1e;">3. Venue Information</h4>
          <p style="margin:0 0 10px;font-size:12px;color:#374151;line-height:1.7;">
            You are responsible for maintaining accurate, up-to-date venue information. Misleading content may lead to suspension.
          </p>

          <h4 style="margin:12px 0 4px;font-size:12px;color:#0f0a1e;">4. Booking and Payments</h4>
          <p style="margin:0 0 10px;font-size:12px;color:#374151;line-height:1.7;">
            All bookings are subject to availability. Prices are subject to change without notice.
          </p>

          <h4 style="margin:12px 0 4px;font-size:12px;color:#0f0a1e;">5. Limitation of Liability</h4>
          <p style="margin:0 0 10px;font-size:12px;color:#374151;line-height:1.7;">
            Lunara will not be liable for any indirect, incidental, or consequential damages arising from venue operations.
          </p>

          <h4 style="margin:12px 0 4px;font-size:12px;color:#0f0a1e;">6. Changes to Terms</h4>
          <p style="margin:0 0 16px;font-size:12px;color:#374151;line-height:1.7;">
            We may modify these terms at any time. Continued use of the platform constitutes acceptance of updated terms.
          </p>

          <p style="margin:0;font-size:11px;color:#6b7280;line-height:1.7;border-top:1px solid #e5e7eb;padding-top:14px;">
            By clicking <strong style="color:${BRAND_PURPLE};">"Confirm &amp; Accept"</strong>, you acknowledge that you have read, understood,
            and agree to be legally bound by these Terms &amp; Conditions.
            Your IP address and confirmation timestamp will be recorded for compliance purposes.
          </p>
        </td>
      </tr>
    </table>
  `);

  try {
    await transporter.sendMail({
      from: smtpFrom,
      to: cpEmail,
      subject: `✦ Action Required: Confirm "${venueName}" on Lunara`,
      html: emailWrapper(emailHeader('Venue Partner Onboarding') + body + emailFooter()),
      attachments: commonAttachments,
    });
    logger.info(`Venue confirmation email sent to ${cpEmail} for venue "${venueName}"`);
  } catch (error) {
    logger.error(`Error sending venue confirmation email to ${cpEmail}:`, error);
    throw new Error('Failed to send venue confirmation email');
  }
}

export default {
  sendVerificationEmail,
  sendPasswordResetEmail,
  sendWelcomeEmail,
  sendVenueConfirmationEmail,
};
