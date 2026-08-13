import 'dart:typed_data';
import 'package:flutter/material.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'api_service.dart';

class TicketPdfService {
  static Future<Uint8List?> generateTicketBytes({
    required String venueName,
    required String venueAddress,
    required String dateStr,
    required String timeStr,
    required String table,
    required String guests,
    required String ticketId,
    required String status,
    required String hostName,
    required String imageUrl,
  }) async {
    try {
      final pdf = pw.Document();

      debugPrint('========== LUNARA TICKET PDF IMAGE DEBUG ==========');
      debugPrint('Ticket ID: $ticketId');
      debugPrint('Venue Name: $venueName');
      debugPrint('Venue Image Value: $imageUrl');
      debugPrint('Venue Image URL: $imageUrl');
      debugPrint('Venue Image URL Length: ${imageUrl.length}');
      debugPrint('====================================================');

      pw.MemoryImage? venueImage;
      
      if (imageUrl.isNotEmpty) {
        debugPrint('Image URL: $imageUrl');
        try {
          final headers = <String, String>{};
          if (ApiService.authToken != null) {
            headers['Authorization'] = 'Bearer ${ApiService.authToken}';
          }
          final response = await http.get(Uri.parse(imageUrl), headers: headers).timeout(const Duration(seconds: 15));
          debugPrint('HTTP Status Code: ${response.statusCode}');
          debugPrint('Content-Type: ${response.headers['content-type'] ?? 'unknown'}');
          debugPrint('Content-Length: ${response.headers['content-length'] ?? 'unknown'}');
          debugPrint('Downloaded Bytes: ${response.bodyBytes.length}');
          
          if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
            venueImage = pw.MemoryImage(response.bodyBytes);
          } else if (response.statusCode != 200) {
            debugPrint('VENUE IMAGE NOT AVAILABLE FROM API (HTTP ${response.statusCode})');
          }
        } catch (e) {
          debugPrint('HTTP Status Code: ERROR ($e)');
          debugPrint('Downloaded Bytes: 0');
          debugPrint('VENUE IMAGE NOT AVAILABLE FROM API');
        }
      } else {
        debugPrint('VENUE IMAGE NOT AVAILABLE FROM API');
      }
      
      debugPrint('PDF Image Object: ${venueImage != null ? "successfully created" : "null"}');
      debugPrint('PDF Header Image: ${venueImage != null ? "visible" : "missing"}');

      // Lunara Theme Colors
      final primaryColor = PdfColor.fromHex('#7B1FA2'); // Purple accent
      final lightBg = PdfColor.fromHex('#F8F9FA'); // Light background for ticket body
      final white = PdfColor.fromHex('#FFFFFF');
      final darkText = PdfColor.fromHex('#15151D'); // Midnight black
      final greyText = PdfColor.fromHex('#6E6E73');
      final dividerColor = PdfColor.fromHex('#E5E5EA');
      
      final isExpired = status.toUpperCase() == 'EXPIRED';
      final statusColor = isExpired ? PdfColor.fromHex('#E53935') : primaryColor;

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(vertical: 40, horizontal: 30),
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Container(
                width: 500, // Widened to fill more space
                decoration: pw.BoxDecoration(
                  color: white,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(24)),
                  boxShadow: [
                    pw.BoxShadow(
                      color: PdfColor.fromHex('#0000001A'),
                      blurRadius: 20,
                      spreadRadius: 2,
                      offset: const PdfPoint(0, 10),
                    )
                  ],
                ),
                child: pw.Column(
                  mainAxisSize: pw.MainAxisSize.min,
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    // --- 1. Venue Header ---
                    pw.Container(
                      height: 220,
                      decoration: pw.BoxDecoration(
                        color: lightBg,
                        borderRadius: const pw.BorderRadius.vertical(top: pw.Radius.circular(24)),
                      ),
                      child: pw.ClipRRect(
                        horizontalRadius: 24,
                        verticalRadius: 24,
                        child: pw.Stack(
                          children: [
                            if (venueImage != null)
                              pw.Positioned.fill(
                                child: pw.Image(venueImage, fit: pw.BoxFit.cover),
                              )
                            else
                              pw.Positioned.fill(
                                child: pw.Container(
                                  color: PdfColor.fromHex('#4A148C'), // Solid purple fallback
                                ),
                              ),
                            
                            // Dark semi-transparent overlay for text readability
                            pw.Positioned.fill(
                              child: pw.Container(
                                color: const PdfColor(0, 0, 0, 0.4), // 40% black overlay
                              ),
                            ),

                            // Header Text Content
                            pw.Positioned(
                              bottom: 24,
                              left: 24,
                              right: 24,
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text(
                                    venueName.toUpperCase(),
                                    style: pw.TextStyle(
                                      color: white,
                                      fontSize: 28,
                                      fontWeight: pw.FontWeight.bold,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                  pw.SizedBox(height: 8),
                                  pw.Row(
                                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                                    children: [
                                      pw.Text(
                                        dateStr.toUpperCase(),
                                        style: pw.TextStyle(color: primaryColor, fontSize: 13, fontWeight: pw.FontWeight.bold),
                                      ),
                                      pw.SizedBox(width: 6),
                                      pw.Container(
                                        width: 4,
                                        height: 4,
                                        decoration: pw.BoxDecoration(
                                          color: primaryColor,
                                          shape: pw.BoxShape.circle,
                                        ),
                                      ),
                                      pw.SizedBox(width: 6),
                                      pw.Text(
                                        timeStr.toUpperCase(),
                                        style: pw.TextStyle(color: primaryColor, fontSize: 13, fontWeight: pw.FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // --- 2. Ticket Status & Branding ---
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: pw.CrossAxisAlignment.center,
                            children: [
                              pw.Text(
                                'LUNARA DIGITAL TICKET',
                                style: pw.TextStyle(
                                  color: primaryColor,
                                  fontSize: 16,
                                  fontWeight: pw.FontWeight.bold,
                                  letterSpacing: 2,
                                ),
                              ),
                              pw.Container(
                                padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                decoration: pw.BoxDecoration(
                                  color: statusColor,
                                  borderRadius: pw.BorderRadius.circular(12),
                                ),
                                child: pw.Text(
                                  status.toUpperCase(),
                                  style: pw.TextStyle(
                                    color: white,
                                    fontSize: 12,
                                    fontWeight: pw.FontWeight.bold,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          pw.SizedBox(height: 20),
                          pw.Divider(color: dividerColor, thickness: 1),
                          pw.SizedBox(height: 20),

                          // --- 3. Ticket Information ---
                          _buildInfoBlock('TICKET HOLDER', hostName, greyText, darkText),
                          pw.SizedBox(height: 16),
                          
                          _buildInfoBlock('VENUE', venueName, greyText, darkText),
                          pw.SizedBox(height: 16),
                          
                          if (venueAddress.isNotEmpty) ...[
                            _buildInfoBlock('VENUE ADDRESS', venueAddress, greyText, darkText),
                            pw.SizedBox(height: 16),
                          ],

                          pw.Row(
                            children: [
                              pw.Expanded(child: _buildInfoBlock('TICKET TYPE', table, greyText, darkText)),
                              pw.Expanded(child: _buildInfoBlock('GUESTS', guests, greyText, darkText)),
                            ],
                          ),
                          pw.SizedBox(height: 16),

                          _buildInfoBlock('TICKET ID', ticketId, greyText, darkText),
                          pw.SizedBox(height: 16),

                          pw.Row(
                            children: [
                              pw.Expanded(child: _buildInfoBlock('DATE', dateStr, greyText, darkText)),
                              pw.Expanded(child: _buildInfoBlock('TIME', timeStr, greyText, darkText)),
                            ],
                          ),
                          
                          pw.SizedBox(height: 24),
                          pw.Divider(color: dividerColor, thickness: 1),
                          pw.SizedBox(height: 20),
                          
                          // Footer note
                          pw.Center(
                            child: pw.Text(
                              'Please present this digital ticket at the venue entrance.',
                              style: pw.TextStyle(
                                color: greyText,
                                fontSize: 10,
                                fontStyle: pw.FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );

      return await pdf.save();
    } catch (e) {
      debugPrint('Failed to generate PDF: $e');
      return null;
    }
  }

  static pw.Widget _buildInfoBlock(String label, String value, PdfColor labelColor, PdfColor valueColor) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label.toUpperCase(),
          style: pw.TextStyle(
            color: labelColor,
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          value.isNotEmpty ? value : 'N/A',
          style: pw.TextStyle(
            color: valueColor,
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
