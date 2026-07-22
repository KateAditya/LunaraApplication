import PDFDocument from 'pdfkit';
import QRCode from 'qrcode';
import fs from 'fs';
import path from 'path';
import { BlobServiceClient } from '@azure/storage-blob';
import { logger } from '../config/logger';
import Booking, { GoingMode } from '../models/Booking';
import User from '../models/User';
import UserPhoto from '../models/UserPhoto';
import Venue from '../models/Venue';
import VenueImage from '../models/VenueImage';
import StrangersMeetRequest from '../models/StrangersMeetRequest';
import GroupParty from '../models/GroupParty';

export interface TicketPDFOptions {
    bookingType: 'solo' | 'party_plan' | 'group_party_small' | 'group_party_large' | 'strangers_meet';
    ticketCode: string;
    hostName: string;
    hostProfileUrl?: string | null;
    partnerName?: string | null;
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
        const response = await fetch(url);
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
    if (imgUrl.startsWith('http://') || imgUrl.startsWith('https://')) {
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

/**
 * Generates a beautiful digital ticket in PDF format, stores it on Azure or locally, and returns the URL.
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
        const [hostImg, partnerImg, venueImg] = await Promise.all([
            resolveImage(options.hostProfileUrl),
            resolveImage(options.partnerProfileUrl),
            resolveImage(options.venueImageUrl)
        ]);

        // 3. Setup PDFKit document with custom dimensions for mobile compatibility (380 x 780 pt)
        const doc = new PDFDocument({
            size: [380, 780],
            margins: { top: 0, bottom: 0, left: 0, right: 0 }
        });

        const chunks: Buffer[] = [];
        doc.on('data', (chunk) => chunks.push(chunk));
        
        const pdfPromise = new Promise<Buffer>((resolve, reject) => {
            doc.on('end', () => resolve(Buffer.concat(chunks)));
            doc.on('error', (err) => reject(err));
        });

        // Draw Ticket Background (Dark Midnight theme)
        doc.rect(0, 0, 380, 780).fill('#0F0C1B');
        
        // Add subtle radial glow background representation
        doc.circle(190, 390, 200).fillOpacity(0.04).fill('#8B5CF6');
        doc.fillOpacity(1.0); // Reset opacity

        // ─── HEADER SECTION ───
        // Neon color scheme variables
        let bookingLabel = 'DIGITAL TICKET';
        let accentColor = '#8B5CF6'; // Violet
        
        switch (options.bookingType) {
            case 'solo':
                bookingLabel = 'SOLO BOOKING';
                accentColor = '#8B5CF6';
                break;
            case 'party_plan':
                bookingLabel = 'PARTY PLAN BOOKING';
                accentColor = '#EC4899'; // Pink
                break;
            case 'group_party_small':
                bookingLabel = 'GROUP PARTY';
                accentColor = '#06B6D4'; // Cyan
                break;
            case 'group_party_large':
                bookingLabel = 'LARGE GROUP PARTY';
                accentColor = '#3B82F6'; // Blue
                break;
            case 'strangers_meet':
                bookingLabel = 'STRANGERS MEET';
                accentColor = '#10B981'; // Green
                break;
        }

        // Draw top accent banner border
        doc.rect(0, 0, 380, 8).fill(accentColor);

        // Ticket Header text
        doc.fillColor('#FFFFFF')
           .fontSize(10)
           .font('Helvetica-Bold')
           .text('LUNARA VIP PASS', 20, 25, { characterSpacing: 2, align: 'center', width: 340 });

        doc.fillColor(accentColor)
           .fontSize(18)
           .font('Helvetica-Bold')
           .text(bookingLabel, 20, 42, { characterSpacing: 1.5, align: 'center', width: 340 });

        // ─── VENUE IMAGE / DETAIL BANNER ───
        const venueBannerY = 75;
        const venueBannerHeight = 150;
        
        if (venueImg) {
            try {
                doc.save();
                // Draw rounded venue banner card
                doc.roundedRect(20, venueBannerY, 340, venueBannerHeight, 16).clip();
                doc.image(venueImg, 20, venueBannerY, { width: 340, height: venueBannerHeight, fit: [340, venueBannerHeight] });
                
                // Dark overlay gradient over image
                doc.rect(20, venueBannerY, 340, venueBannerHeight).fillColor('#000000').fillOpacity(0.55).fill();
                doc.restore();
            } catch (imgErr: any) {
                logger.warn(`Failed to render venue image in PDF: ${imgErr.message}`);
                // Fallback background for venue
                doc.roundedRect(20, venueBannerY, 340, venueBannerHeight, 16).fillColor('#1E1B2D').fill();
            }
        } else {
            // Draw placeholder card
            doc.roundedRect(20, venueBannerY, 340, venueBannerHeight, 16).fillColor('#1E1B2D').fill();
            // Draw stylized DJ/dance icon placeholder using shapes
            doc.circle(190, venueBannerY + 50, 25).fillColor('#2D2B3F').fill();
            doc.circle(190, venueBannerY + 50, 15).fillColor(accentColor).fill();
        }

        // Venue Overlay Text
        doc.fillColor('#FFFFFF')
           .fontSize(18)
           .font('Helvetica-Bold')
           .text(options.venueName.toUpperCase(), 35, venueBannerY + 80, { width: 310, align: 'left', ellipsis: true });
        
        doc.fillColor('#A7F3D0') // Soft green-cyan for contrast
            .fontSize(10)
            .font('Helvetica')
            .text(options.venueAddress, 35, venueBannerY + 105, { width: 310, height: 25, ellipsis: true });

        // ─── TICKET CUTOUT DIVIDER ───
        const dividerY = 245;
        // Draw Left Cutout
        doc.circle(0, dividerY, 12).fillColor('#0F0C1B').fill();
        // Draw Right Cutout
        doc.circle(380, dividerY, 12).fillColor('#0F0C1B').fill();
        // Draw Dashed Divider Line
        doc.strokeColor('#FFFFFF')
           .lineWidth(1)
           .opacity(0.2)
           .dash(6, { space: 4 })
           .moveTo(15, dividerY)
           .lineTo(365, dividerY)
           .stroke();
        doc.opacity(1.0).undash(); // Reset settings

        // ─── DATE / TIME & METADATA SECTION ───
        const dateStr = typeof options.eventDate === 'string' 
            ? options.eventDate 
            : options.eventDate.toLocaleDateString('en-IN', { weekday: 'short', day: '2-digit', month: 'short', year: 'numeric' });

        doc.fillColor('#06B6D4') // Cyan
           .fontSize(11)
           .font('Helvetica-Bold')
           .text(`${dateStr.toUpperCase()}  •  ${options.startTime}`, 20, 265, { align: 'center', width: 340 });

        // ─── PROFILE / PEOPLE SECTION ───
        const peopleY = 300;
        doc.roundedRect(20, peopleY, 340, 110, 16).fillColor('#1E1B2D').fill();

        if (options.bookingType === 'party_plan') {
            // Dual Column Layout (Host & Partner)
            
            // Host Column
            const hostColX = 30;
            if (hostImg) {
                try {
                    doc.save();
                    doc.circle(hostColX + 35, peopleY + 45, 28).clip();
                    doc.image(hostImg, hostColX + 7, peopleY + 17, { width: 56, height: 56, fit: [56, 56] });
                    doc.restore();
                    // Draw gold/violet avatar border
                    doc.circle(hostColX + 35, peopleY + 45, 28).strokeColor('#F59E0B').lineWidth(2).stroke();
                } catch (_) {
                    doc.circle(hostColX + 35, peopleY + 45, 28).fillColor('#2D2B3F').fill();
                }
            } else {
                doc.circle(hostColX + 35, peopleY + 45, 28).fillColor('#2D2B3F').fill();
                doc.fillColor('#FFFFFF').fontSize(14).font('Helvetica-Bold').text(options.hostName.charAt(0), hostColX + 27, peopleY + 37);
            }
            doc.fillColor('#FFFFFF').fontSize(11).font('Helvetica-Bold').text(options.hostName, hostColX, peopleY + 80, { width: 70, align: 'center', ellipsis: true });
            doc.fillColor('#F59E0B').fontSize(7).font('Helvetica-Bold').text('HOST', hostColX, peopleY + 93, { width: 70, align: 'center' });

            // Link Icon in between columns
            doc.fillColor(accentColor).fontSize(16).text('⇄', 170, peopleY + 38, { width: 40, align: 'center' });

            // Partner/Joiner Column
            const partnerColX = 280;
            const partnerName = options.partnerName || 'Invited Guest';
            if (partnerImg) {
                try {
                    doc.save();
                    doc.circle(partnerColX + 35, peopleY + 45, 28).clip();
                    doc.image(partnerImg, partnerColX + 7, peopleY + 17, { width: 56, height: 56, fit: [56, 56] });
                    doc.restore();
                    doc.circle(partnerColX + 35, peopleY + 45, 28).strokeColor(accentColor).lineWidth(2).stroke();
                } catch (_) {
                    doc.circle(partnerColX + 35, peopleY + 45, 28).fillColor('#2D2B3F').fill();
                }
            } else {
                doc.circle(partnerColX + 35, peopleY + 45, 28).fillColor('#2D2B3F').fill();
                doc.fillColor('#FFFFFF').fontSize(14).font('Helvetica-Bold').text(partnerName.charAt(0), partnerColX + 27, peopleY + 37);
            }
            doc.fillColor('#FFFFFF').fontSize(11).font('Helvetica-Bold').text(partnerName, partnerColX, peopleY + 80, { width: 70, align: 'center', ellipsis: true });
            doc.fillColor(accentColor).fontSize(7).font('Helvetica-Bold').text('PARTNER', partnerColX, peopleY + 93, { width: 70, align: 'center' });

        } else {
            // Single Column Host Layout + Metadata breakdown
            const hostColX = 40;
            if (hostImg) {
                try {
                    doc.save();
                    doc.circle(hostColX + 35, peopleY + 45, 28).clip();
                    doc.image(hostImg, hostColX + 7, peopleY + 17, { width: 56, height: 56, fit: [56, 56] });
                    doc.restore();
                    doc.circle(hostColX + 35, peopleY + 45, 28).strokeColor('#F59E0B').lineWidth(2).stroke();
                } catch (_) {
                    doc.circle(hostColX + 35, peopleY + 45, 28).fillColor('#2D2B3F').fill();
                }
            } else {
                doc.circle(hostColX + 35, peopleY + 45, 28).fillColor('#2D2B3F').fill();
                doc.fillColor('#FFFFFF').fontSize(14).font('Helvetica-Bold').text(options.hostName.charAt(0), hostColX + 27, peopleY + 37);
            }
            doc.fillColor('#FFFFFF').fontSize(12).font('Helvetica-Bold').text(options.hostName, hostColX, peopleY + 80, { width: 70, align: 'center', ellipsis: true });
            doc.fillColor('#F59E0B').fontSize(7).font('Helvetica-Bold').text('HOST / CREATOR', hostColX, peopleY + 93, { width: 70, align: 'center' });

            // Vertical separator line
            doc.strokeColor('#FFFFFF')
               .lineWidth(1)
               .opacity(0.1)
               .moveTo(145, peopleY + 15)
               .lineTo(145, peopleY + 95)
               .stroke();
            doc.opacity(1.0); // Reset

            // Metadata Detail block
            const detailX = 160;
            doc.fillColor('#9CA3AF').fontSize(8).font('Helvetica-Bold').text('GUEST COUNT', detailX, peopleY + 20);
            
            const totalMembers = options.numberOfGuests;
            doc.fillColor('#FFFFFF').fontSize(12).font('Helvetica-Bold').text(`${totalMembers} Persons (Admit)`, detailX, peopleY + 32);

            doc.fillColor('#9CA3AF').fontSize(8).font('Helvetica-Bold').text('STATUS', detailX, peopleY + 60);
            
            const displayStatus = options.paymentStatus === 'paid' || options.paymentStatus === 'PAID' ? 'CONFIRMED' : 'VERIFIED';
            doc.fillColor('#10B981').fontSize(12).font('Helvetica-Bold').text(displayStatus, detailX, peopleY + 72);
        }

        // ─── BILL / PAYMENT BREAKDOWN ───
        const paymentY = 425;
        doc.roundedRect(20, paymentY, 340, 50, 12)
           .fillColor('#24213B')
           .strokeColor(accentColor)
           .lineWidth(0.5)
           .fillAndStroke();

        doc.fillColor('#9CA3AF').fontSize(7).font('Helvetica-Bold').text('PAYMENT METHOD', 35, paymentY + 12);
        doc.fillColor('#FFFFFF').fontSize(10).font('Helvetica-Bold').text('Razorpay Gateway', 35, paymentY + 24);

        doc.fillColor('#9CA3AF').fontSize(7).font('Helvetica-Bold').text('AMOUNT PAID', 260, paymentY + 12, { align: 'right', width: 85 });
        doc.fillColor('#10B981').fontSize(11).font('Helvetica-Bold').text(`₹${options.paymentAmount.toFixed(2)}`, 260, paymentY + 24, { align: 'right', width: 85 });

        // ─── SCANNER / QR CODE SECTION ───
        const qrY = 490;
        doc.roundedRect(80, qrY, 220, 220, 20).fillColor('#FFFFFF').fill();
        
        // Draw the QR Code image inside the card
        doc.image(qrCodeBuffer, 90, qrY + 10, { width: 200, height: 200 });

        doc.fillColor('#4B5563')
           .fontSize(8)
           .font('Helvetica-Bold')
           .text(`TICKET CODE: ${options.ticketCode}`, 90, qrY + 198, { width: 200, align: 'center', characterSpacing: 0.5 });

        // Instruction Text below QR
        doc.fillColor('#9CA3AF')
           .fontSize(8)
           .font('Helvetica')
           .text('PRESENT THIS QR CODE AT THE CLUB ENTRANCE', 20, 725, { width: 340, align: 'center', characterSpacing: 0.5 });

        // ─── FOOTER ───
        doc.fillColor('#FFFFFF')
           .opacity(0.3)
           .fontSize(7)
           .font('Helvetica-Bold')
           .text('POWERED BY LUNARA VIP SYSTEM', 20, 755, { align: 'center', width: 340, characterSpacing: 1 });
        doc.opacity(1.0); // Reset

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
        let partnerProfileUrl: string | null = null;

        if (booking.goingMode === 'party_request' && booking.specialRequests) {
            try {
                const meta = JSON.parse(booking.specialRequests);
                if (meta.joinerId) {
                    bookingType = 'party_plan';
                    const partner = await User.findByPk(meta.joinerId);
                    if (partner) {
                        partnerName = `${partner.firstName} ${partner.lastName}`;
                        const partnerPhoto = await UserPhoto.findOne({ where: { userId: meta.joinerId, isPrimary: true } });
                        partnerProfileUrl = partnerPhoto?.filePath || null;
                    }
                } else {
                    bookingType = booking.numberOfGuests <= 20 ? 'group_party_small' : 'group_party_large';
                }
            } catch (_) {
                bookingType = booking.numberOfGuests <= 20 ? 'group_party_small' : 'group_party_large';
            }
        } else if (booking.goingMode === 'party_request') {
            bookingType = booking.numberOfGuests <= 20 ? 'group_party_small' : 'group_party_large';
        }

        const ticketUrl = await generateTicketPDF({
            bookingType,
            ticketCode: booking.ticketCode || `BK-${booking.id.substring(0, 8).toUpperCase()}`,
            hostName: `${host.firstName} ${host.lastName}`,
            hostProfileUrl: hostPhoto?.filePath || null,
            partnerName,
            partnerProfileUrl,
            venueName: (booking as any).venue?.name || 'LUNARA VENUE',
            venueAddress: (booking as any).venue?.addressLine1 || 'LUNARA ADDRESS',
            venueImageUrl: venueImg?.filePath || null,
            numberOfGuests: booking.numberOfGuests,
            eventDate: booking.bookingDate,
            startTime: booking.startTime,
            paymentAmount: Number(booking.totalAmount),
            paymentStatus: booking.paymentStatus,
        });

        await booking.update({ ticketUrl });
        logger.info(`Successfully generated & saved ticket PDF for Booking ID: ${bookingId}, URL: ${ticketUrl}`);
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

        const ticketCode = groupParty.ticketCode || groupParty.paymentId || `GP-${groupParty.id.substring(0, 8).toUpperCase()}`;

        const ticketUrl = await generateTicketPDF({
            bookingType: 'group_party_small',
            ticketCode,
            hostName: `${host.firstName} ${host.lastName}`,
            hostProfileUrl: hostPhoto?.filePath || null,
            venueName: (groupParty as any).venue?.name || 'LUNARA VENUE',
            venueAddress: (groupParty as any).venue?.addressLine1 || 'LUNARA ADDRESS',
            venueImageUrl: venueImg?.filePath || null,
            numberOfGuests: groupParty.numberOfFriends + 1, // Including the host!
            eventDate: groupParty.partyDate,
            startTime: '08:00 PM',
            paymentAmount: Number(groupParty.totalAmount),
            paymentStatus: groupParty.paymentStatus,
        });

        await groupParty.update({ ticketUrl, ticketCode });
        logger.info(`Successfully generated & saved ticket PDF for GroupParty ID: ${groupPartyId}, URL: ${ticketUrl}`);
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

        const ticketCode = request.ticketId || `SM-${request.id.substring(0, 8).toUpperCase()}`;

        const ticketUrl = await generateTicketPDF({
            bookingType: 'strangers_meet',
            ticketCode,
            hostName: `${host.firstName} ${host.lastName}`,
            hostProfileUrl: hostPhoto?.filePath || null,
            venueName: (request as any).venue?.name || 'LUNARA VENUE',
            venueAddress: (request as any).venue?.addressLine1 || 'LUNARA ADDRESS',
            venueImageUrl: venueImg?.filePath || null,
            numberOfGuests: request.numberOfPersons,
            eventDate: request.eventDateTime,
            startTime: request.eventDateTime.toTimeString().split(' ')[0] || '08:00 PM',
            paymentAmount: Number(request.paymentAmount || 0),
            paymentStatus: request.paymentStatus,
        });

        await request.update({ ticketUrl, ticketId: ticketCode });
        logger.info(`Successfully generated & saved ticket PDF for StrangersMeetRequest ID: ${requestId}, URL: ${ticketUrl}`);
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

        const ticketCode = booking?.ticketCode || `PP-${reqRecord.id.substring(0, 8).toUpperCase()}`;

        const ticketUrl = await generateTicketPDF({
            bookingType: 'party_plan',
            ticketCode,
            hostName: host ? `${host.firstName} ${host.lastName}` : 'Host',
            hostProfileUrl: hostPhoto?.filePath || null,
            partnerName: joiner ? `${joiner.firstName} ${joiner.lastName}` : 'Partner',
            partnerProfileUrl: joinerPhoto?.filePath || null,
            venueName: plan?.venue?.name || 'LUNARA VENUE',
            venueAddress: plan?.venue?.addressLine1 || 'LUNARA ADDRESS',
            venueImageUrl: venueImg?.filePath || null,
            numberOfGuests: 2,
            eventDate: plan?.planDateTime || new Date(),
            startTime: plan?.planDateTime ? new Date(plan.planDateTime).toTimeString().split(' ')[0] : '08:00 PM',
            paymentAmount: Number(plan?.depositAmount || 198),
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
