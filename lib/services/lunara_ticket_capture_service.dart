import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class LunaraTicketCaptureService {
  /// Captures a RenderRepaintBoundary widget as high-resolution PNG bytes.
  static Future<Uint8List?> captureTicketPng(
    GlobalKey ticketKey, {
    double pixelRatio = 3.0,
  }) async {
    try {
      final boundary = ticketKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        debugPrint('[LunaraTicketCaptureService] RenderRepaintBoundary not found.');
        return null;
      }

      // If already painting or needs layout, wait a brief frame
      if (boundary.debugNeedsPaint) {
        await Future.delayed(const Duration(milliseconds: 60));
      }

      final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) {
        debugPrint('[LunaraTicketCaptureService] Failed to encode image to PNG byte data.');
        return null;
      }

      return byteData.buffer.asUint8List();
    } catch (e) {
      debugPrint('[LunaraTicketCaptureService] captureTicketPng error: $e');
      return null;
    }
  }

  /// Downloads the ticket image as a crisp, HD file matching the exact in-app UI.
  static Future<bool> downloadTicket({
    required BuildContext context,
    required GlobalKey ticketKey,
    required String ticketCode,
    required String eventType,
    required String venueName,
    required String eventDateTime,
  }) async {
    try {
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 12),
              Text('Generating high-definition ticket pass...'),
            ],
          ),
          duration: Duration(milliseconds: 1400),
          backgroundColor: Color(0xFF7C3AED),
        ),
      );

      final pngBytes = await captureTicketPng(ticketKey, pixelRatio: 3.0);
      if (pngBytes == null || pngBytes.isEmpty) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Failed to render ticket image. Please try again.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return false;
      }

      final cleanType = eventType.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final cleanCode = ticketCode.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
      final fileName = 'Lunara_${cleanType}_Ticket_$cleanCode.png';

      if (kIsWeb) {
        // Web Download via Data URI link
        final uri = Uri.dataFromBytes(pngBytes, mimeType: 'image/png');
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        }
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('🎉 Ticket ($cleanCode) downloaded successfully!'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
        return true;
      } else {
        // Mobile (Android / iOS)
        final tempDir = await getTemporaryDirectory();
        final filePath = '${tempDir.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(pngBytes, flush: true);

        final box = context.mounted ? context.findRenderObject() as RenderBox? : null;
        final positionOrigin = box != null
            ? box.localToGlobal(Offset.zero) & box.size
            : null;

        // ignore: deprecated_member_use
        await Share.shareXFiles(
          [XFile(filePath, name: fileName, mimeType: 'image/png')],
          text: '🎟️ Lunara Official Entry Pass ($ticketCode)\n📍 $venueName • $eventDateTime',
          sharePositionOrigin: positionOrigin,
        );

        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('✅ Ticket ($cleanCode) saved & ready to share!'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
        return true;
      }
    } catch (e) {
      debugPrint('[LunaraTicketCaptureService] downloadTicket error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return false;
    }
  }

  /// Shares the ticket card as a visual HD image along with formatted text details.
  static Future<void> shareTicket({
    required BuildContext context,
    required GlobalKey ticketKey,
    required String ticketCode,
    required String venueName,
    required String eventDateTime,
    required String eventType,
    String? hostName,
    String? guestCount,
    String? extraDetails,
  }) async {
    try {
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 10),
              Text('Preparing visual ticket pass...'),
            ],
          ),
          duration: Duration(milliseconds: 1000),
          backgroundColor: Color(0xFF7C3AED),
        ),
      );

      final pngBytes = await captureTicketPng(ticketKey, pixelRatio: 3.0);
      final box = context.mounted ? context.findRenderObject() as RenderBox? : null;
      final positionOrigin = box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : null;

      final formattedText = StringBuffer();
      formattedText.writeln('🎟️ LUNARA OFFICIAL ENTRY PASS');
      formattedText.writeln('━━━━━━━━━━━━━━━━━━━━━━━━');
      formattedText.writeln('⚡ Event: $eventType');
      formattedText.writeln('📍 Venue: $venueName');
      formattedText.writeln('📅 Date & Time: $eventDateTime');
      formattedText.writeln('🔑 Pass Code: $ticketCode');
      if (hostName != null && hostName.isNotEmpty) {
        formattedText.writeln('👤 Host: $hostName');
      }
      if (guestCount != null && guestCount.isNotEmpty) {
        formattedText.writeln('👥 Guests: $guestCount');
      }
      if (extraDetails != null && extraDetails.isNotEmpty) {
        formattedText.writeln('✨ Details: $extraDetails');
      }
      formattedText.writeln('━━━━━━━━━━━━━━━━━━━━━━━━');
      formattedText.writeln('Verified & Authenticated by Lunara Experience Hub');

      if (pngBytes != null && pngBytes.isNotEmpty) {
        final cleanType = eventType.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
        final cleanCode = ticketCode.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
        final fileName = 'Lunara_${cleanType}_Ticket_$cleanCode.png';

        if (!kIsWeb) {
          final tempDir = await getTemporaryDirectory();
          final filePath = '${tempDir.path}/$fileName';
          final file = File(filePath);
          await file.writeAsBytes(pngBytes, flush: true);

          // ignore: deprecated_member_use
          await Share.shareXFiles(
            [XFile(filePath, name: fileName, mimeType: 'image/png')],
            text: formattedText.toString(),
            subject: 'Lunara Ticket Pass ($ticketCode)',
            sharePositionOrigin: positionOrigin,
          );
          return;
        }
      }

      // Fallback if image capture is not supported on web share API
      // ignore: deprecated_member_use
      await Share.share(
        formattedText.toString(),
        subject: 'Lunara Ticket Pass ($ticketCode)',
        sharePositionOrigin: positionOrigin,
      );
    } catch (e) {
      debugPrint('[LunaraTicketCaptureService] shareTicket error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Share error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }
}
