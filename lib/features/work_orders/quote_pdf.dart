import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../data/models/work_order.dart';

/// Builds the customer-facing quote PDF for a work order and hands it to the
/// OS share sheet (Messages / Mail / AirDrop). Branding matches the app bar:
/// Easy HVAC mark + Tempstar Elite Dealer lockup.
Future<void> shareQuotePdf(WorkOrder order) async {
  final quote = order.quote;
  if (quote == null) return;

  final money = NumberFormat.currency(symbol: r'$');
  final dateFmt = DateFormat('MMMM d, y');

  final easyHvacLogo = pw.MemoryImage(
    (await rootBundle.load('assets/images/easy_hvac_logo.png'))
        .buffer
        .asUint8List(),
  );
  final tempstarLockup = pw.MemoryImage(
    (await rootBundle.load('assets/images/tempstar_elite_dealer.png'))
        .buffer
        .asUint8List(),
  );

  const navy = PdfColor.fromInt(0xFF0A2A5E);
  const slate = PdfColor.fromInt(0xFF64748B);
  const hairline = PdfColor.fromInt(0xFFCBD5E1);
  const counterRed = PdfColor.fromInt(0xFFC62828);

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.fromLTRB(48, 40, 48, 48),
      // Pinned to the bottom of every page: validity note left, quote number
      // right (the red counter, like the paper invoice pad).
      footer: (ctx) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text(
            'This quote is valid for 30 days. Thank you for choosing Easy HVAC.',
            style: const pw.TextStyle(fontSize: 9, color: slate),
          ),
          pw.Text(
            'No. ${(quote.number ?? 1).toString().padLeft(4, '0')}',
            style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: counterRed),
          ),
        ],
      ),
      build: (ctx) => [
        // ── Letterhead ──
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Image(easyHvacLogo, height: 76),
            pw.SizedBox(width: 16),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Install and Service of HVAC Equipment',
                      style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: navy)),
                  pw.Text(
                      'Furnaces, Tankless Water Heaters, AC, Heat Pumps & more',
                      style: const pw.TextStyle(fontSize: 8, color: slate)),
                ],
              ),
            ),
            pw.Image(tempstarLockup, height: 40),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Divider(color: navy, thickness: 2),
        pw.SizedBox(height: 4),
        // Contact strip — mirrors the paper invoice letterhead.
        pw.Center(
          child: pw.Text(
            '2265 Petawawa Blvd. Pembroke, Ontario   |   24-hour 613.585.8615   |   Emergency Service 613.631.1399',
            style: const pw.TextStyle(fontSize: 8.5, color: slate),
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Center(
          child: pw.Text(
            'easyhvacservices@hotmail.com   |   H.S.T.# 721074524RT0001',
            style: const pw.TextStyle(fontSize: 8.5, color: slate),
          ),
        ),
        pw.SizedBox(height: 10),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('QUOTE',
                    style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: navy)),
                pw.SizedBox(height: 4),
                pw.Text('Date: ${dateFmt.format(quote.updatedAt)}',
                    style: const pw.TextStyle(fontSize: 10, color: slate)),
                pw.Text('Work order created: ${dateFmt.format(order.createdAt)}',
                    style: const pw.TextStyle(fontSize: 10, color: slate)),
                if (order.installDate != null)
                  pw.Text(
                      'Proposed install: ${dateFmt.format(order.installDate!)}',
                      style: const pw.TextStyle(fontSize: 10, color: slate)),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Easy HVAC',
                    style: pw.TextStyle(
                        fontSize: 13, fontWeight: pw.FontWeight.bold)),
                pw.Text('${order.installerName} - Licence # ${order.installerLicense}',
                    style: const pw.TextStyle(fontSize: 10, color: slate)),
                pw.Text('Tempstar Elite Dealer',
                    style: const pw.TextStyle(fontSize: 10, color: slate)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 16),

        // ── Prepared for ──
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: hairline),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('PREPARED FOR',
                  style: pw.TextStyle(
                      fontSize: 8,
                      color: slate,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 1)),
              pw.SizedBox(height: 3),
              if (order.customerName?.isNotEmpty == true)
                pw.Text(order.customerName!,
                    style: pw.TextStyle(
                        fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.Text(order.address, style: const pw.TextStyle(fontSize: 11)),
              pw.SizedBox(height: 2),
              pw.Text('Job type: ${order.reason.label}',
                  style: const pw.TextStyle(fontSize: 10, color: slate)),
            ],
          ),
        ),
        pw.SizedBox(height: 16),

        // ── Line items ──
        pw.TableHelper.fromTextArray(
          headers: ['Description', 'Qty', 'Unit price', 'Amount'],
          data: [
            for (final l in quote.lines)
              [
                l.description,
                '${l.quantity}',
                money.format(l.unitPrice),
                money.format(l.lineTotal),
              ],
          ],
          headerStyle: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: navy),
          cellStyle: const pw.TextStyle(fontSize: 10),
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.center,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
          },
          columnWidths: {
            0: const pw.FlexColumnWidth(5),
            1: const pw.FlexColumnWidth(1),
            2: const pw.FlexColumnWidth(1.6),
            3: const pw.FlexColumnWidth(1.6),
          },
          border: const pw.TableBorder(
            horizontalInside: pw.BorderSide(color: hairline, width: .5),
          ),
        ),
        pw.SizedBox(height: 10),

        // ── Totals ──
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.SizedBox(
              width: 220,
              child: pw.Column(
                children: [
                  _totalRow('Subtotal', money.format(quote.subtotal)),
                  _totalRow(
                      'HST (${(quote.taxRate * 100).toStringAsFixed(0)}%)',
                      money.format(quote.tax)),
                  pw.Divider(color: hairline, height: 8),
                  _totalRow('Total', money.format(quote.total),
                      bold: true, color: navy),
                ],
              ),
            ),
          ],
        ),

        // ── Notes ──
        if (quote.notes?.isNotEmpty == true) ...[
          pw.SizedBox(height: 18),
          pw.Text('Notes',
              style:
                  pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(quote.notes!,
              style: const pw.TextStyle(fontSize: 10, color: slate)),
        ],

      ],
    ),
  );

  final safeAddress = order.address
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  await Printing.sharePdf(
    bytes: await doc.save(),
    filename: 'EasyHVAC-Quote-$safeAddress.pdf',
  );
}

pw.Widget _totalRow(String label, String value,
    {bool bold = false, PdfColor? color}) {
  final style = pw.TextStyle(
    fontSize: bold ? 12 : 10,
    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    color: color,
  );
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [pw.Text(label, style: style), pw.Text(value, style: style)],
    ),
  );
}
