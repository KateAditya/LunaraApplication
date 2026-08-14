import PDFDocument from 'pdfkit';
import QRCode from 'qrcode';
import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
import { BlobServiceClient } from '@azure/storage-blob';
import { logger } from '../config/logger';
import Booking, { GoingMode } from '../models/Booking';
import User from '../models/User';
import UserPhoto from '../models/UserPhoto';
import Venue from '../models/Venue';
import VenueImage from '../models/VenueImage';
import StrangersMeetRequest from '../models/StrangersMeetRequest';
import GroupParty from '../models/GroupParty';
import Ticket, { TicketStatus, StorageCleanupStatus } from '../models/Ticket';

export interface TicketPDFOptions {
    bookingType: 'solo' | 'party_plan' | 'group_party_small' | 'group_party_large' | 'strangers_meet';
    ticketCode: string;
    hostName: string;
    hostUsername?: string | null;
    hostProfileUrl?: string | null;
    partnerName?: string | null;
    partnerUsername?: string | null;
    partnerProfileUrl?: string | null;
    venueName: string;
    venueAddress: string;
    venueImageUrl?: string | null;
    numberOfGuests: number;
    eventDate: Date | string;
    startTime: string;
    paymentAmount: number;
    paymentStatus: string;
}

/**
 * Downloads a remote image and returns it as a Buffer, or returns null if download fails.
 */
async function downloadImage(url: string): Promise<Buffer | null> {
    if (!url || url.includes('placeholder') || url.includes('picsum.photos')) {
        return null;
    }
    try {
        let fetchUrl = url;
        if (fetchUrl.startsWith('https//')) fetchUrl = fetchUrl.replace('https//', 'https://');
        if (fetchUrl.startsWith('http//')) fetchUrl = fetchUrl.replace('http//', 'http://');

        const response = await fetch(fetchUrl);
        if (!response.ok) return null;
        const arrayBuffer = await response.arrayBuffer();
        return Buffer.from(arrayBuffer);
    } catch (e: any) {
        logger.warn(`Failed to download image from ${url}: ${e.message}`);
        return null;
    }
}

/**
 * Resolves an image URL or local path to a Buffer.
 */
async function resolveImage(imgUrl: string | null | undefined): Promise<Buffer | null> {
    if (!imgUrl) return null;
    
    // Handle remote Azure or absolute URLs
    if (imgUrl.startsWith('http://') || imgUrl.startsWith('https://') || imgUrl.includes('.blob.core.windows.net') || imgUrl.includes('://')) {
        return downloadImage(imgUrl);
    }
    
    // Handle local uploads path
    try {
        const cleanPath = imgUrl.startsWith('/') ? imgUrl.substring(1) : imgUrl;
        const fullPath = path.join(process.cwd(), cleanPath);
        if (fs.existsSync(fullPath)) {
            return fs.readFileSync(fullPath);
        }
        
        // Try fallback under uploads dir
        const uploadsDir = process.env.UPLOAD_DIR || 'uploads';
        const fallbackPath = path.join(process.cwd(), uploadsDir, cleanPath);
        if (fs.existsSync(fallbackPath)) {
            return fs.readFileSync(fallbackPath);
        }
    } catch (e: any) {
        logger.warn(`Failed to read local image ${imgUrl}: ${e.message}`);
    }
    
    return null;
}

// Vector Icon Helpers for clean PDFKit rendering
function drawCheckmarkIcon(doc: any, cx: number, cy: number, r: number) {
    doc.save();
    doc.circle(cx, cy, r).fillColor('#22C55E').fill();
    doc.strokeColor('#FFFFFF').lineWidth(2).lineCap('round').lineJoin('round');
    doc.moveTo(cx - r * 0.4, cy).lineTo(cx - r * 0.1, cy + r * 0.35).lineTo(cx + r * 0.4, cy - r * 0.3).stroke();
    doc.restore();
}

function drawCalendarIcon(doc: any, cx: number, cy: number, size: number) {
    doc.save();
    doc.roundedRect(cx - size/2, cy - size/2, size, size, 3).fillColor('#F3E8FF').fill();
    doc.roundedRect(cx - size/2, cy - size/2, size, 4, 1.5).fillColor('#9333EA').fill();
    doc.fillColor('#9333EA').circle(cx - 3, cy - size/2 + 2, 0.8).fill();
    doc.fillColor('#9333EA').circle(cx + 3, cy - size/2 + 2, 0.8).fill();
    doc.restore();
}

function drawClockIcon(doc: any, cx: number, cy: number, r: number) {
    doc.save();
    doc.circle(cx, cy, r).fillColor('#F3E8FF').fill();
    doc.circle(cx, cy, r).strokeColor('#9333EA').lineWidth(1.2).stroke();
    doc.strokeColor('#9333EA').lineWidth(1.2).lineCap('round');
    doc.moveTo(cx, cy).lineTo(cx, cy - r * 0.5).stroke();
    doc.moveTo(cx, cy).lineTo(cx + r * 0.4, cy).stroke();
    doc.restore();
}

function drawUsersIcon(doc: any, cx: number, cy: number, r: number) {
    doc.save();
    doc.circle(cx, cy, r).fillColor('#F3E8FF').fill();
    doc.fillColor('#9333EA');
    doc.circle(cx - 2, cy - 2, 3).fill();
    doc.circle(cx + 4, cy - 1, 2.5).fill();
    doc.restore();
}

function drawHeartIcon(doc: any, cx: number, cy: number, r: number) {
    doc.save();
    doc.circle(cx, cy, r).fillColor('#F3E8FF').fill();
    doc.fillColor('#9333EA');
    const hx = cx;
    const hy = cy - 1;
    doc.moveTo(hx, hy + 4)
       .bezierCurveTo(hx - 5, hy, hx - 5, hy - 4, hx, hy - 2)
       .bezierCurveTo(hx + 5, hy - 4, hx + 5, hy, hx, hy + 4)
       .fill();
    doc.restore();
}

function drawLocationPinIcon(doc: any, cx: number, cy: number, r: number) {
    doc.save();
    doc.circle(cx, cy, r).fillColor('#F3E8FF').fill();
    doc.fillColor('#9333EA');
    doc.circle(cx, cy - 2, 4).fill();
    doc.moveTo(cx - 4, cy - 2).lineTo(cx + 4, cy - 2).lineTo(cx, cy + 5).fill();
    doc.fillColor('#FFFFFF').circle(cx, cy - 2, 1.8).fill();
    doc.restore();
}

function drawAvatarWithRing(doc: any, cx: number, cy: number, r: number, imgBuffer: Buffer | null, initials: string, ringColor: string) {
    doc.save();
    doc.circle(cx, cy, r + 2.5).strokeColor(ringColor).lineWidth(2.5).stroke();
    doc.circle(cx, cy, r).clip();
    if (imgBuffer) {
        try {
            doc.image(imgBuffer, cx - r, cy - r, { width: r * 2, height: r * 2, fit: [r * 2, r * 2] });
        } catch (_) {
            doc.rect(cx - r, cy - r, r * 2, r * 2).fillColor('#E2E8F0').fill();
            doc.fillColor('#475569').fontSize(14).font('Helvetica-Bold').text(initials, cx - r, cy - 6, { width: r * 2, align: 'center' });
        }
    } else {
        doc.rect(cx - r, cy - r, r * 2, r * 2).fillColor('#E2E8F0').fill();
        doc.fillColor('#475569').fontSize(14).font('Helvetica-Bold').text(initials, cx - r, cy - 6, { width: r * 2, align: 'center' });
    }
    doc.restore();
}

/**
 * Generates a clean light-theme digital ticket matching the custom format for each booking type.
 */
export async function generateTicketPDF(options: TicketPDFOptions): Promise<string> {
    try {
        logger.info(`Starting PDF ticket generation for code: ${options.ticketCode}, Type: ${options.bookingType}`);

        // 1. Generate QR Code Buffer
        const qrCodeBuffer = await QRCode.toBuffer(options.ticketCode, {
            errorCorrectionLevel: 'H',
            margin: 1,
            color: {
                dark: '#000000',
                light: '#FFFFFF'
            }
        });

        // 2. Fetch images in parallel
        const [hostImg, partnerImg] = await Promise.all([
            resolveImage(options.hostProfileUrl),
            resolveImage(options.partnerProfileUrl)
        ]);

        // 3. Setup PDFKit document with custom dimensions (380 x 740 pt)
        const doc = new PDFDocument({
            size: [380, 740],
            margins: { top: 0, bottom: 0, left: 0, right: 0 }
        });

        const chunks: Buffer[] = [];
        doc.on('data', (chunk) => chunks.push(chunk));
        
        const pdfPromise = new Promise<Buffer>((resolve, reject) => {
            doc.on('end', () => resolve(Buffer.concat(chunks)));
            doc.on('error', (err) => reject(err));
        });

        // Page background
        doc.rect(0, 0, 380, 740).fill('#F8FAFC');

        // Dynamic Header titles & badges per format type
        let headerTitle = 'PARTY PLAN TICKET';
        let badge1Text = 'LUNARA VIBE';
        let badge1Bg = '#F3E8FF';
        let badge1Color = '#9333EA';

        let badge2Text = 'PARTY TIME!';
        let badge2Bg = '#DCFCE7';
        let badge2Color = '#16A34A';

        let mainHeadingText = `Let's party at ${options.venueName.toUpperCase()} !`;
        let guestCountLabel = `${options.numberOfGuests} Going`;

        switch (options.bookingType) {
            case 'solo':
                headerTitle = 'SOLO BOOKING TICKET';
                badge1Text = 'SOLO PASS';
                badge1Bg = '#F3E8FF';
                badge1Color = '#9333EA';
                badge2Text = 'CONFIRMED';
                badge2Bg = '#DCFCE7';
                badge2Color = '#16A34A';
                mainHeadingText = `Party at ${options.venueName.toUpperCase()} !`;
                guestCountLabel = '1 Solo';
                break;

            case 'group_party_small':
                headerTitle = 'FRIENDS PARTY TICKET';
                badge1Text = 'LUNARA VIBE';
                badge1Bg = '#F3E8FF';
                badge1Color = '#9333EA';
                badge2Text = 'SQUAD PARTY';
                badge2Bg = '#DBEAFE';
                badge2Color = '#1D4ED8';
                mainHeadingText = `Squad Party at ${options.venueName.toUpperCase()} !`;
                guestCountLabel = `${options.numberOfGuests} Friends`;
                break;

            case 'party_plan':
                headerTitle = 'PARTY PLAN TICKET';
                badge1Text = 'LUNARA VIBE';
                badge1Bg = '#F3E8FF';
                badge1Color = '#9333EA';
                badge2Text = 'PARTY TIME!';
                badge2Bg = '#DCFCE7';
                badge2Color = '#16A34A';
                mainHeadingText = `Let's party at ${options.venueName.toUpperCase()} !`;
                guestCountLabel = `2 Going`;
                break;

            case 'group_party_large':
                headerTitle = 'GROUP PARTY VIP PASS';
                badge1Text = 'LUNARA VIBE';
                badge1Bg = '#F3E8FF';
                badge1Color = '#9333EA';
                badge2Text = 'GROUP VIP';
                badge2Bg = '#FEF3C7';
                badge2Color = '#D97706';
                mainHeadingText = `VIP Group Night at ${options.venueName.toUpperCase()} !`;
                guestCountLabel = `${options.numberOfGuests} Guests`;
                break;

            case 'strangers_meet':
                headerTitle = 'STRANGERS MEET TICKET';
                badge1Text = 'LUNARA VIBE';
                badge1Bg = '#F3E8FF';
                badge1Color = '#9333EA';
                badge2Text = 'MEETUP';
                badge2Bg = '#E0E7FF';
                badge2Color = '#4338CA';
                mainHeadingText = `Social Meetup at ${options.venueName.toUpperCase()} !`;
                guestCountLabel = `${options.numberOfGuests} Members`;
                break;
        }

        // ─── TOP HEADER BAR ───
        doc.fillColor('#0F172A')
           .fontSize(14)
           .font('Helvetica-Bold')
           .text(headerTitle, 0, 16, { align: 'center', width: 380, characterSpacing: 1 });

        // Outer White Card
        doc.roundedRect(15, 45, 350, 675, 20)
           .fillColor('#FFFFFF')
           .strokeColor('#E2E8F0')
           .lineWidth(1)
           .fillAndStroke();

        // ─── BADGES & TICKET ID ───
        // Badge 1 Pill
        doc.roundedRect(30, 60, 105, 22, 11).fillColor(badge1Bg).fill();
        doc.fillColor(badge1Color).fontSize(8.5).font('Helvetica-Bold').text(badge1Text, 30, 66, { width: 105, align: 'center' });

        // Ticket ID Text
        doc.fillColor('#64748B').fontSize(8.5).font('Helvetica').text('TICKET ID: ', 210, 66, { continued: true });
        doc.fillColor('#7E22CE').fontSize(8.5).font('Helvetica-Bold').text(options.ticketCode);

        // Badge 2 Pill
        doc.roundedRect(30, 88, 105, 22, 11).fillColor(badge2Bg).fill();
        doc.fillColor(badge2Color).fontSize(8.5).font('Helvetica-Bold').text(badge2Text, 30, 94, { width: 105, align: 'center' });

        // ─── MAIN HEADING ───
        doc.fillColor('#0F172A')
           .fontSize(17)
           .font('Helvetica-Bold')
           .text(mainHeadingText, 30, 122, { width: 320, ellipsis: true });

        doc.fillColor('#64748B')
           .fontSize(9.5)
           .font('Helvetica')
           .text('Get ready for a night full of vibes and memories.', 30, 145, { width: 320 });

        // ─── 3-COLUMN METRIC BOX ───
        const metricY = 168;
        doc.roundedRect(30, metricY, 320, 85, 16)
           .fillColor('#F8FAFC')
           .strokeColor('#E2E8F0')
           .lineWidth(1)
           .fillAndStroke();

        const evDate = options.eventDate instanceof Date ? options.eventDate : new Date(options.eventDate);
        const validEvDate = isNaN(evDate.getTime()) ? new Date() : evDate;
        const dateFormatted = validEvDate.toLocaleDateString('en-US', { month: 'short', day: '2-digit', year: 'numeric' });
        const dayFormatted = validEvDate.toLocaleDateString('en-US', { weekday: 'long' });

        // Col 1: DATE
        drawCalendarIcon(doc, 52, metricY + 22, 16);
        doc.fillColor('#94A3B8').fontSize(7.5).font('Helvetica-Bold').text('DATE', 40, metricY + 36, { width: 90, align: 'center' });
        doc.fillColor('#0F172A').fontSize(10.5).font('Helvetica-Bold').text(dateFormatted, 35, metricY + 48, { width: 100, align: 'center', ellipsis: true });
        doc.fillColor('#64748B').fontSize(8.5).font('Helvetica').text(dayFormatted, 35, metricY + 63, { width: 100, align: 'center' });

        // Divider 1
        doc.strokeColor('#E2E8F0').lineWidth(1).moveTo(136, metricY + 15).lineTo(136, metricY + 70).stroke();

        // Col 2: TIME
        drawClockIcon(doc, 190, metricY + 22, 9);
        doc.fillColor('#94A3B8').fontSize(7.5).font('Helvetica-Bold').text('TIME', 145, metricY + 36, { width: 90, align: 'center' });
        doc.fillColor('#0F172A').fontSize(10.5).font('Helvetica-Bold').text(options.startTime || '09:00 PM', 140, metricY + 48, { width: 100, align: 'center' });
        doc.fillColor('#64748B').fontSize(8.5).font('Helvetica').text('Onwards', 140, metricY + 63, { width: 100, align: 'center' });

        // Divider 2
        doc.strokeColor('#E2E8F0').lineWidth(1).moveTo(242, metricY + 15).lineTo(242, metricY + 70).stroke();

        // Col 3: GUESTS
        drawUsersIcon(doc, 296, metricY + 22, 9);
        doc.fillColor('#94A3B8').fontSize(7.5).font('Helvetica-Bold').text('GUESTS', 250, metricY + 36, { width: 90, align: 'center' });
        doc.fillColor('#0F172A').fontSize(10.5).font('Helvetica-Bold').text(guestCountLabel, 245, metricY + 48, { width: 100, align: 'center' });
        doc.fillColor('#64748B').fontSize(8.5).font('Helvetica').text('Confirmed', 245, metricY + 63, { width: 100, align: 'center' });

        // ─── DASHED CUTOUT DIVIDER ───
        const dividerY = 270;
        doc.circle(15, dividerY, 10).fillColor('#F1F5F9').fill();
        doc.circle(365, dividerY, 10).fillColor('#F1F5F9').fill();
        doc.strokeColor('#CBD5E1').lineWidth(1).dash(4, { space: 3 }).moveTo(30, dividerY).lineTo(350, dividerY).stroke().undash();

        // ─── HOST & PROFILE SECTION (Dynamic Per Format) ───
        const profileY = 290;
        const hostInitials = (options.hostName.charAt(0) || 'H').toUpperCase();
        const partnerName = options.partnerName || 'Invited Guest';
        const partnerInitials = (partnerName.charAt(0) || 'P').toUpperCase();
        const hostUsername = options.hostUsername || `@${options.hostName.toLowerCase().replace(/\s+/g, '')}`;
        const partnerUsername = options.partnerUsername || `@${partnerName.toLowerCase().replace(/\s+/g, '')}`;

        if (options.bookingType === 'party_plan') {
            // FORMAT 3: Party Plan Duo (Host & Joined Partner)
            
            // Host Column (Left)
            doc.roundedRect(55, profileY, 55, 18, 9).fillColor('#F3E8FF').fill();
            doc.fillColor('#7E22CE').fontSize(7.5).font('Helvetica-Bold').text('HOST', 55, profileY + 5, { width: 55, align: 'center' });

            drawAvatarWithRing(doc, 82, profileY + 52, 28, hostImg, hostInitials, '#9333EA');

            doc.fillColor('#0F172A').fontSize(11.5).font('Helvetica-Bold').text(options.hostName, 35, profileY + 90, { width: 95, align: 'center', ellipsis: true });
            doc.fillColor('#64748B').fontSize(8.5).font('Helvetica').text(hostUsername, 35, profileY + 104, { width: 95, align: 'center', ellipsis: true });

            // Heart Icon (Middle)
            drawHeartIcon(doc, 190, profileY + 52, 15);

            // Partner Column (Right)
            doc.roundedRect(245, profileY, 65, 18, 9).fillColor('#CCFBF1').fill();
            doc.fillColor('#0D9488').fontSize(7.5).font('Helvetica-Bold').text('PARTNER', 245, profileY + 5, { width: 65, align: 'center' });

            drawAvatarWithRing(doc, 278, profileY + 52, 28, partnerImg, partnerInitials, '#06B6D4');

            doc.fillColor('#0F172A').fontSize(11.5).font('Helvetica-Bold').text(partnerName, 225, profileY + 90, { width: 105, align: 'center', ellipsis: true });
            doc.fillColor('#64748B').fontSize(8.5).font('Helvetica').text(partnerUsername, 225, profileY + 104, { width: 105, align: 'center', ellipsis: true });

        } else if (options.bookingType === 'solo') {
            // FORMAT 1: Going Solo (Host details + Solo Pass badge)
            doc.roundedRect(152, profileY, 76, 18, 9).fillColor('#F3E8FF').fill();
            doc.fillColor('#7E22CE').fontSize(7.5).font('Helvetica-Bold').text('SOLO VISITOR', 152, profileY + 5, { width: 76, align: 'center' });

            drawAvatarWithRing(doc, 190, profileY + 52, 28, hostImg, hostInitials, '#9333EA');

            doc.fillColor('#0F172A').fontSize(12).font('Helvetica-Bold').text(options.hostName, 120, profileY + 90, { width: 140, align: 'center', ellipsis: true });
            doc.fillColor('#64748B').fontSize(8.5).font('Helvetica').text(hostUsername, 120, profileY + 104, { width: 140, align: 'center', ellipsis: true });

        } else {
            // FORMAT 2, 4, 5: Friends / Group Party / Strangers Meet (Host Details + Total Members Box)
            
            // Host Column (Left)
            const rolePillText = options.bookingType === 'group_party_large' ? 'ORGANIZER' : options.bookingType === 'strangers_meet' ? 'MEETUP HOST' : 'SQUAD HOST';
            doc.roundedRect(40, profileY, 85, 18, 9).fillColor('#F3E8FF').fill();
            doc.fillColor('#7E22CE').fontSize(7.5).font('Helvetica-Bold').text(rolePillText, 40, profileY + 5, { width: 85, align: 'center' });

            drawAvatarWithRing(doc, 82, profileY + 52, 28, hostImg, hostInitials, '#9333EA');

            doc.fillColor('#0F172A').fontSize(11.5).font('Helvetica-Bold').text(options.hostName, 30, profileY + 90, { width: 105, align: 'center', ellipsis: true });
            doc.fillColor('#64748B').fontSize(8.5).font('Helvetica').text(hostUsername, 30, profileY + 104, { width: 105, align: 'center', ellipsis: true });

            // Members Summary Box (Right)
            doc.roundedRect(155, profileY + 15, 190, 80, 14)
               .fillColor('#F8FAFC')
               .strokeColor('#E2E8F0')
               .lineWidth(1)
               .fillAndStroke();

            const summaryTitle = options.bookingType === 'group_party_large' ? 'GROUP CAPACITY' : options.bookingType === 'strangers_meet' ? 'MEETUP SEATS' : 'TOTAL SQUAD';
            const summarySub = options.bookingType === 'group_party_large' ? 'VIP Table Entry Pass' : options.bookingType === 'strangers_meet' ? 'Community Social Meetup' : 'Confirmed Squad Members';

            doc.fillColor('#94A3B8').fontSize(7.5).font('Helvetica-Bold').text(summaryTitle, 168, profileY + 28);
            doc.fillColor('#0F172A').fontSize(14).font('Helvetica-Bold').text(`${options.numberOfGuests} Persons`, 168, profileY + 41);
            doc.fillColor('#64748B').fontSize(8.5).font('Helvetica').text(summarySub, 168, profileY + 62);
        }

        // ─── DEPOSIT STATUS & PAYMENT CARD ───
        const payY = 418;
        doc.roundedRect(30, payY, 320, 54, 14)
           .fillColor('#F0FDF4')
           .strokeColor('#DCFCE7')
           .lineWidth(1)
           .fillAndStroke();

        drawCheckmarkIcon(doc, 52, payY + 27, 12);

        doc.fillColor('#64748B').fontSize(7.5).font('Helvetica-Bold').text('DEPOSIT STATUS', 74, payY + 13);
        doc.fillColor('#0F172A').fontSize(11).font('Helvetica-Bold').text('Lunara Secure Pay', 74, payY + 26);

        doc.fillColor('#64748B').fontSize(7.5).font('Helvetica-Bold').text('AMOUNT PAID', 200, payY + 13, { width: 90, align: 'right' });
        doc.fillColor('#16A34A').fontSize(12.5).font('Helvetica-Bold').text(`₹${Math.round(options.paymentAmount)}`, 190, payY + 26, { width: 95, align: 'right' });

        doc.roundedRect(290, payY + 26, 45, 18, 9).fillColor('#DCFCE7').fill();
        doc.fillColor('#15803D').fontSize(7.5).font('Helvetica-Bold').text('PAID', 290, payY + 31, { width: 45, align: 'center' });

        // ─── VENUE LOCATION BOX ───
        const venueY = 482;
        doc.roundedRect(30, venueY, 320, 95, 16)
           .fillColor('#F8FAFC')
           .strokeColor('#E2E8F0')
           .lineWidth(1)
           .fillAndStroke();

        drawLocationPinIcon(doc, 52, venueY + 26, 12);

        doc.fillColor('#0F172A').fontSize(12.5).font('Helvetica-Bold').text(options.venueName.toUpperCase(), 74, venueY + 12, { width: 260, ellipsis: true });
        doc.fillColor('#475569').fontSize(8.5).font('Helvetica').text(options.venueAddress, 74, venueY + 28, { width: 260, height: 24, ellipsis: true });

        // Map Button Box
        doc.roundedRect(45, venueY + 58, 290, 26, 8).fillColor('#F3E8FF').fill();
        doc.fillColor('#7E22CE').fontSize(8.5).font('Helvetica-Bold').text('VIEW MAP DIRECTIONS   >', 45, venueY + 66, { width: 290, align: 'center' });

        // ─── QR CODE CHECK-IN SECTION ───
        const qrY = 588;
        doc.image(qrCodeBuffer, 140, qrY, { width: 100, height: 100 });

        doc.fillColor('#64748B')
           .fontSize(7.5)
           .font('Helvetica-Bold')
           .text('PRESENT THIS DIGITAL PASS AT CLUB ENTRANCE', 30, qrY + 105, { width: 320, align: 'center', characterSpacing: 0.5 });

        // End PDF generation & get buffer
        doc.end();
        const pdfBuffer = await pdfPromise;

        // 4. Save/Upload PDF
        const filename = `${options.ticketCode}_ticket_${Date.now()}.pdf`;
        let ticketUrl = '';

        if (process.env.AZURE_STORAGE_CONNECTION_STRING) {
            try {
                logger.info(`Uploading generated ticket PDF to Azure Blob Storage: tickets/${filename}`);
                const blobServiceClient = BlobServiceClient.fromConnectionString(process.env.AZURE_STORAGE_CONNECTION_STRING);
                const containerName = process.env.AZURE_STORAGE_CONTAINER_NAME || 'uploads';
                const containerClient = blobServiceClient.getContainerClient(containerName);
                
                await containerClient.createIfNotExists({ access: 'blob' });
                
                const blobPath = `tickets/${filename}`;
                const blockBlobClient = containerClient.getBlockBlobClient(blobPath);
                
                await blockBlobClient.upload(pdfBuffer, pdfBuffer.length, {
                    blobHTTPHeaders: {
                        blobContentType: 'application/pdf',
                        blobCacheControl: 'public, max-age=31536000'
                    }
                });

                const accountName = process.env.AZURE_STORAGE_CONNECTION_STRING.match(/AccountName=([^;]+)/)?.[1] || 'lunarastorageprod';
                ticketUrl = `https://${accountName}.blob.core.windows.net/${containerName}/${blobPath}`;
                logger.info(`Ticket PDF uploaded successfully. Azure URL: ${ticketUrl}`);
            } catch (azureErr: any) {
                logger.error(`Azure Blob upload failed for ticket. Saving locally instead. Error: ${azureErr.message}`);
                ticketUrl = await saveLocally(pdfBuffer, filename);
            }
        } else {
            logger.info('Azure Connection String is not set. Saving ticket PDF locally.');
            ticketUrl = await saveLocally(pdfBuffer, filename);
        }

        return ticketUrl;
    } catch (err: any) {
        logger.error(`Failed to generate digital ticket: ${err.message}`, err);
        throw err;
    }
}

/**
 * Saves the buffer locally and returns the relative path URL.
 */
async function saveLocally(pdfBuffer: Buffer, filename: string): Promise<string> {
    const uploadsDir = process.env.UPLOAD_DIR || 'uploads';
    const ticketsDir = path.join(uploadsDir, 'tickets');
    if (!fs.existsSync(ticketsDir)) {
        fs.mkdirSync(ticketsDir, { recursive: true });
    }
    const filePath = path.join(ticketsDir, filename);
    fs.writeFileSync(filePath, pdfBuffer);
    return `/uploads/tickets/${filename}`;
}

export function generateHMACSignature(ticketCode: string, userId: string, eventDateStr: string): string {
    const secret = process.env.JWT_SECRET || 'lunara_ticket_secret_key_2026';
    return crypto.createHmac('sha256', secret)
        .update(`${ticketCode}:${userId}:${eventDateStr}`)
        .digest('hex');
}

export function generateUniqueTicketCode(typePrefix: string = 'BK'): string {
    const randomHex = crypto.randomBytes(4).toString('hex').toUpperCase();
    const year = new Date().getFullYear();
    return `LUN-${year}-${typePrefix}-${randomHex}`;
}

/**
 * Orchestrator helper to generate ticket for standard Booking model
 */
export async function generateTicketForBookingHelper(bookingId: string): Promise<string> {
    try {
        const booking = await Booking.findByPk(bookingId, {
            include: [{ model: Venue, as: 'venue' }]
        });
        if (!booking) {
            throw new Error(`Booking ${bookingId} not found`);
        }

        const host = await User.findByPk(booking.userId);
        if (!host) {
            throw new Error(`Host user ${booking.userId} not found`);
        }

        const hostPhoto = await UserPhoto.findOne({ where: { userId: booking.userId, isPrimary: true } });
        const venueImg = await VenueImage.findOne({ where: { venueId: booking.venueId, isPrimary: true } });

        let bookingType: 'solo' | 'party_plan' | 'group_party_small' | 'group_party_large' = 'solo';
        let partnerName: string | null = null;
        let partnerUsername: string | null = null;
        let partnerProfileUrl: string | null = null;

        if (booking.goingMode === 'party_request' && booking.specialRequests) {
            try {
                const meta = JSON.parse(booking.specialRequests);
                if (meta.joinerId) {
                    bookingType = 'party_plan';
                    const partner = await User.findByPk(meta.joinerId);
                    if (partner) {
                        partnerName = `${partner.firstName} ${partner.lastName}`.trim();
                        partnerUsername = `@${(partner.firstName || 'partner').toLowerCase()}_${(partner.lastName || '').toLowerCase()}`.replace(/_+$/, '');
                        const partnerPhoto = await UserPhoto.findOne({ where: { userId: meta.joinerId, isPrimary: true } });
                        partnerProfileUrl = partner.profileImageUrl || partnerPhoto?.filePath || null;
                    }
                } else {
                    bookingType = booking.numberOfGuests <= 20 ? 'group_party_small' : 'group_party_large';
                }
            } catch (_) {
                bookingType = booking.numberOfGuests <= 20 ? 'group_party_small' : 'group_party_large';
            }
        } else if (booking.goingMode === 'party_request') {
            bookingType = booking.numberOfGuests <= 20 ? 'group_party_small' : 'group_party_large';
        } else if ((booking.goingMode as string) === 'group_booking' || (booking as any).isGroupBooking) {
            bookingType = 'group_party_small';
        } else if ((booking as any).isLargePartyRequest) {
            bookingType = 'group_party_large';
        } else {
            bookingType = 'solo';
        }

        const ticketCode = booking.ticketCode || generateUniqueTicketCode('BK');
        const eventStartAt = new Date(booking.bookingDate);
        const eventEndAt = new Date(eventStartAt.getTime() + 12 * 60 * 60 * 1000);
        const expiresAt = eventEndAt;
        const storageDeletionAt = new Date(expiresAt.getTime() + 24 * 60 * 60 * 1000);
        const verificationToken = generateHMACSignature(ticketCode, booking.userId, booking.bookingDate.toString());

        const qrPayload = JSON.stringify({
            ticketId: ticketCode,
            bookingId: booking.id,
            userId: booking.userId,
            eventDate: booking.bookingDate,
            signature: verificationToken,
        });

        const hostName = `${host.firstName} ${host.lastName}`.trim();
        const hostUsername = `@${(host.firstName || 'host').toLowerCase()}_${(host.lastName || '').toLowerCase()}`.replace(/_+$/, '');
        const hostProfileUrl = host.profileImageUrl || hostPhoto?.filePath || null;

        const ticketUrl = await generateTicketPDF({
            bookingType,
            ticketCode,
            hostName,
            hostUsername,
            hostProfileUrl,
            partnerName,
            partnerUsername,
            partnerProfileUrl,
            venueName: (booking as any).venue?.name || 'SAHARA',
            venueAddress: (booking as any).venue?.addressLine1 || 'Hinjawadi - Aundh Rd, Pune',
            venueImageUrl: venueImg?.filePath || null,
            numberOfGuests: booking.numberOfGuests,
            eventDate: booking.bookingDate,
            startTime: booking.startTime,
            paymentAmount: Number(booking.totalAmount),
            paymentStatus: booking.paymentStatus,
        });

        await Ticket.upsert({
            ticketId: ticketCode,
            bookingId: booking.id,
            bookingType: (bookingType === 'party_plan' ? 'party_plan' : bookingType.startsWith('group_party') ? 'group_party' : 'solo') as any,
            userId: booking.userId,
            venueId: booking.venueId,
            ticketStatus: TicketStatus.ACTIVE,
            eventStartAt,
            eventEndAt,
            issuedAt: new Date(),
            expiresAt,
            storageDeletionAt,
            storageProvider: 'local',
            storageKey: ticketUrl,
            pdfUrl: ticketUrl,
            pdfVersion: 1,
            qrToken: qrPayload,
            verificationToken,
            storageCleanupStatus: StorageCleanupStatus.PENDING,
        });

        await booking.update({ ticketCode, ticketUrl });
        logger.info(`Successfully generated & saved ticket PDF for Booking ID: ${bookingId}, Code: ${ticketCode}, URL: ${ticketUrl}`);
        return ticketUrl;
    } catch (err: any) {
        logger.error(`Error generating ticket for Booking ID ${bookingId}: ${err.message}`, err);
        throw err;
    }
}

/**
 * Orchestrator helper to generate ticket for GroupParty model (<20 friends)
 */
export async function generateTicketForGroupPartyHelper(groupPartyId: string): Promise<string> {
    try {
        const groupParty = await GroupParty.findByPk(groupPartyId, {
            include: [{ model: Venue, as: 'venue' }]
        });
        if (!groupParty) {
            throw new Error(`GroupParty ${groupPartyId} not found`);
        }

        const host = await User.findByPk(groupParty.userId);
        if (!host) {
            throw new Error(`Host user ${groupParty.userId} not found`);
        }

        const hostPhoto = await UserPhoto.findOne({ where: { userId: groupParty.userId, isPrimary: true } });
        const venueImg = await VenueImage.findOne({ where: { venueId: groupParty.venueId, isPrimary: true } });

        const ticketCode = groupParty.ticketCode || generateUniqueTicketCode('GP');
        const eventStartAt = new Date(groupParty.partyDate);
        const eventEndAt = new Date(eventStartAt.getTime() + 12 * 60 * 60 * 1000);
        const expiresAt = eventEndAt;
        const storageDeletionAt = new Date(expiresAt.getTime() + 24 * 60 * 60 * 1000);
        const verificationToken = generateHMACSignature(ticketCode, groupParty.userId, groupParty.partyDate.toString());

        const qrPayload = JSON.stringify({
            ticketId: ticketCode,
            bookingId: groupParty.id,
            userId: groupParty.userId,
            eventDate: groupParty.partyDate,
            signature: verificationToken,
        });

        const hostName = `${host.firstName} ${host.lastName}`.trim();
        const hostUsername = `@${(host.firstName || 'host').toLowerCase()}_${(host.lastName || '').toLowerCase()}`.replace(/_+$/, '');
        const hostProfileUrl = host.profileImageUrl || hostPhoto?.filePath || null;

        const ticketUrl = await generateTicketPDF({
            bookingType: 'group_party_small',
            ticketCode,
            hostName,
            hostUsername,
            hostProfileUrl,
            venueName: (groupParty as any).venue?.name || 'SAHARA',
            venueAddress: (groupParty as any).venue?.addressLine1 || 'Hinjawadi - Aundh Rd, Pune',
            venueImageUrl: venueImg?.filePath || null,
            numberOfGuests: groupParty.numberOfFriends,
            eventDate: groupParty.partyDate,
            startTime: '08:00 PM',
            paymentAmount: Number(groupParty.totalAmount),
            paymentStatus: groupParty.paymentStatus,
        });

        await Ticket.upsert({
            ticketId: ticketCode,
            bookingId: groupParty.id,
            bookingType: 'group_party',
            userId: groupParty.userId,
            venueId: groupParty.venueId,
            ticketStatus: TicketStatus.ACTIVE,
            eventStartAt,
            eventEndAt,
            issuedAt: new Date(),
            expiresAt,
            storageDeletionAt,
            storageProvider: 'local',
            storageKey: ticketUrl,
            pdfUrl: ticketUrl,
            pdfVersion: 1,
            qrToken: qrPayload,
            verificationToken,
            storageCleanupStatus: StorageCleanupStatus.PENDING,
        });

        await groupParty.update({ ticketUrl, ticketCode });
        logger.info(`Successfully generated & saved ticket PDF for GroupParty ID: ${groupPartyId}, Code: ${ticketCode}, URL: ${ticketUrl}`);
        return ticketUrl;
    } catch (err: any) {
        logger.error(`Error generating ticket for GroupParty ID ${groupPartyId}: ${err.message}`, err);
        throw err;
    }
}

/**
 * Orchestrator helper to generate ticket for StrangersMeetRequest model
 */
export async function generateTicketForStrangersMeetHelper(requestId: string): Promise<string> {
    try {
        const request = await StrangersMeetRequest.findByPk(requestId, {
            include: [{ model: Venue, as: 'venue' }]
        });
        if (!request) {
            throw new Error(`StrangersMeetRequest ${requestId} not found`);
        }

        const host = await User.findByPk(request.userId);
        if (!host) {
            throw new Error(`Host user ${request.userId} not found`);
        }

        const hostPhoto = await UserPhoto.findOne({ where: { userId: request.userId, isPrimary: true } });
        const venueImg = await VenueImage.findOne({ where: { venueId: request.venueId, isPrimary: true } });

        const ticketCode = request.ticketId || generateUniqueTicketCode('SM');
        const eventStartAt = new Date(request.eventDateTime);
        const eventEndAt = new Date(eventStartAt.getTime() + 12 * 60 * 60 * 1000);
        const expiresAt = eventEndAt;
        const storageDeletionAt = new Date(expiresAt.getTime() + 24 * 60 * 60 * 1000);
        const verificationToken = generateHMACSignature(ticketCode, request.userId, request.eventDateTime.toString());

        const qrPayload = JSON.stringify({
            ticketId: ticketCode,
            bookingId: request.id,
            userId: request.userId,
            eventDate: request.eventDateTime,
            signature: verificationToken,
        });

        const hostName = `${host.firstName} ${host.lastName}`.trim();
        const hostUsername = `@${(host.firstName || 'host').toLowerCase()}_${(host.lastName || '').toLowerCase()}`.replace(/_+$/, '');
        const hostProfileUrl = host.profileImageUrl || hostPhoto?.filePath || null;

        const ticketUrl = await generateTicketPDF({
            bookingType: 'strangers_meet',
            ticketCode,
            hostName,
            hostUsername,
            hostProfileUrl,
            venueName: (request as any).venue?.name || 'SAHARA',
            venueAddress: (request as any).venue?.addressLine1 || 'Hinjawadi - Aundh Rd, Pune',
            venueImageUrl: venueImg?.filePath || null,
            numberOfGuests: request.numberOfPersons,
            eventDate: request.eventDateTime,
            startTime: request.eventDateTime ? new Date(request.eventDateTime).toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' }) : '08:00 PM',
            paymentAmount: Number(request.paymentAmount || 0),
            paymentStatus: request.paymentStatus,
        });

        await Ticket.upsert({
            ticketId: ticketCode,
            bookingId: request.id,
            bookingType: 'strangers_meet',
            userId: request.userId,
            venueId: request.venueId,
            ticketStatus: TicketStatus.ACTIVE,
            eventStartAt,
            eventEndAt,
            issuedAt: new Date(),
            expiresAt,
            storageDeletionAt,
            storageProvider: 'local',
            storageKey: ticketUrl,
            pdfUrl: ticketUrl,
            pdfVersion: 1,
            qrToken: qrPayload,
            verificationToken,
            storageCleanupStatus: StorageCleanupStatus.PENDING,
        });

        await request.update({ ticketUrl, ticketId: ticketCode });
        logger.info(`Successfully generated & saved ticket PDF for StrangersMeetRequest ID: ${requestId}, Code: ${ticketCode}, URL: ${ticketUrl}`);
        return ticketUrl;
    } catch (err: any) {
        logger.error(`Error generating ticket for StrangersMeetRequest ID ${requestId}: ${err.message}`, err);
        throw err;
    }
}

/**
 * Orchestrator helper to generate ticket for Party Plan request
 */
export async function generateTicketForPartyPlanHelper(requestId: string): Promise<string> {
    try {
        const PartyPlanRequestModel = (await import('../models/PartyPlanRequest')).default;
        const PartyPlanModel = (await import('../models/PartyPlan')).default;

        const reqRecord = await PartyPlanRequestModel.findByPk(requestId, {
            include: [
                {
                    model: PartyPlanModel,
                    as: 'plan',
                    include: [{ model: Venue, as: 'venue' }]
                },
                { model: User, as: 'requester' }
            ]
        });
        if (!reqRecord) {
            throw new Error(`PartyPlanRequest ${requestId} not found`);
        }

        const plan = (reqRecord as any).plan;
        const host = plan ? await User.findByPk(plan.userId) : null;
        const joiner = (reqRecord as any).requester;

        const hostPhoto = host ? await UserPhoto.findOne({ where: { userId: host.id, isPrimary: true } }) : null;
        const joinerPhoto = joiner ? await UserPhoto.findOne({ where: { userId: joiner.id, isPrimary: true } }) : null;
        const venueImg = plan?.venueId ? await VenueImage.findOne({ where: { venueId: plan.venueId, isPrimary: true } }) : null;

        const booking = await Booking.findOne({
            where: { goingMode: GoingMode.PARTY_REQUEST, userId: plan?.userId, venueId: plan?.venueId },
            order: [['createdAt', 'DESC']],
        });

        const ticketCode = booking?.ticketCode || `PP-${reqRecord.id.substring(0, 6).toUpperCase()}`;

        const hostName = host ? `${host.firstName} ${host.lastName}`.trim() : 'Aditya Kate';
        const hostUsername = `@${(host?.firstName || 'aditya').toLowerCase()}_${(host?.lastName || 'kate').toLowerCase()}`.replace(/_+$/, '');
        const hostProfileUrl = host?.profileImageUrl || hostPhoto?.filePath || null;

        const partnerName = joiner ? `${joiner.firstName} ${joiner.lastName}`.trim() : 'Partner';
        const partnerUsername = `@${(joiner?.firstName || 'partner').toLowerCase()}_${(joiner?.lastName || '').toLowerCase()}`.replace(/_+$/, '');
        const partnerProfileUrl = joiner?.profileImageUrl || joinerPhoto?.filePath || null;

        const ticketUrl = await generateTicketPDF({
            bookingType: 'party_plan',
            ticketCode,
            hostName,
            hostUsername,
            hostProfileUrl,
            partnerName,
            partnerUsername,
            partnerProfileUrl,
            venueName: plan?.venue?.name || 'SAHARA',
            venueAddress: plan?.venue?.addressLine1 || 'Hinjawadi - Aundh Rd, near Yug Honda Showroom, Shedge Vasti, Wakad, Pune, Pimpri-Chinchwad, Maharashtra 411057',
            venueImageUrl: venueImg?.filePath || null,
            numberOfGuests: 2,
            eventDate: plan?.planDateTime || new Date(),
            startTime: plan?.planDateTime ? new Date(plan.planDateTime).toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' }) : '09:00 PM',
            paymentAmount: Number(plan?.depositAmount || 99),
            paymentStatus: 'PAID',
        });

        if (booking) {
            await booking.update({ ticketUrl });
        }
        logger.info(`Successfully generated & saved ticket PDF for PartyPlanRequest ID: ${requestId}, URL: ${ticketUrl}`);
        return ticketUrl;
    } catch (err: any) {
        logger.error(`Error generating ticket for PartyPlanRequest ID ${requestId}: ${err.message}`, err);
        throw err;
    }
}
