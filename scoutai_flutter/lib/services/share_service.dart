import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import '../widgets/fifa_card_stats.dart';

class ShareService {
  /// Builds a rich 2-page PDF from player metrics and captured widget images,
  /// then triggers the OS share sheet.
  static Future<void> sharePdf({
    required BuildContext context,
    required String playerName,
    required String position,
    required FifaCardStats cardStats,
    required double distanceKm,
    required double maxSpeedKmh,
    required double avgSpeedKmh,
    required int sprints,
    required int accelPeaks,
    required int positionCount,
    Uint8List? portraitBytes,
    // ── Extended data for page 2 ──
    Uint8List? heatmapImage,
    Uint8List? speedChartImage,
    double? workRate,
    double? movingRatio,
    double? directionChanges,
    Map<String, dynamic>? movementZones,
    bool isCalibrated = false,
    // ── Player profile details ──
    String? profileEmail,
    String? profileNation,
    int? profileAge,
    int? profileHeightCm,
    String? profileTier,
    bool? profileBadgeVerified,
    // ── Home dashboard summary ──
    int? totalVideos,
    int? matchesAnalyzed,
    double? totalDistanceKm,
    double? avgDistanceKm,
    double? avgSpeedKmhOverall,
    int? totalSprintsOverall,
    int? totalAccelPeaksOverall,
    double? bestDistanceKm,
    double? bestAvgSpeedKmh,
    int? bestSprints,
    int? calibratedCount,
    int? uncalibratedCount,
    // ── Home dashboard movement/intensity (aggregated) ──
    Map<String, dynamic>? dashboardMovementZones,
    double? dashboardWorkRate,
    double? dashboardMovingRatio,
    double? dashboardDirectionChanges,
  }) async {
    final pdf = pw.Document();

    // ── PAGE 1 — Player card + basic metrics ─────────────────────────────────
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // ── Header ──
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'ScoutAI - Player Report',
                      style: pw.TextStyle(
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromHex('#1D63FF'),
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Generated on ${_formatDate(DateTime.now())}',
                      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Divider(color: PdfColor.fromHex('#1D63FF'), thickness: 1.5),
            pw.SizedBox(height: 20),

            // ── Player card + name ──
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _pdfLegendaryCard(
                  playerName: playerName,
                  position: position,
                  stats: cardStats,
                  portraitBytes: portraitBytes,
                ),
                pw.SizedBox(width: 28),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        playerName.toUpperCase(),
                        style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Position: $position   OVR: ${cardStats.ovr}',
                        style: const pw.TextStyle(fontSize: 13, color: PdfColors.grey700),
                      ),
                      pw.SizedBox(height: 18),
                      pw.Text(
                        'FIFA ATTRIBUTES',
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromHex('#1D63FF'),
                          letterSpacing: 1.5,
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      _pdfStatGrid(cardStats),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 24),
            pw.Divider(color: PdfColors.grey300),
            pw.SizedBox(height: 16),

            // ── Performance metrics ──
            pw.Text(
              'PERFORMANCE METRICS',
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromHex('#1D63FF'),
                letterSpacing: 1.5,
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Row(
              children: [
                _pdfMetricBox('Distance', '${distanceKm.toStringAsFixed(2)} km'),
                pw.SizedBox(width: 12),
                _pdfMetricBox('Top Speed', '${maxSpeedKmh.toStringAsFixed(1)} km/h'),
                pw.SizedBox(width: 12),
                _pdfMetricBox('Avg Speed', '${avgSpeedKmh.toStringAsFixed(1)} km/h'),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Row(
              children: [
                _pdfMetricBox('Sprints', '$sprints'),
                pw.SizedBox(width: 12),
                _pdfMetricBox('Accel Peaks', '$accelPeaks'),
                pw.SizedBox(width: 12),
                _pdfMetricBox('Tracking Pts', '$positionCount'),
              ],
            ),

            // ── Extended metrics row (if available) ──
            if (workRate != null || movingRatio != null || directionChanges != null) ...[
              pw.SizedBox(height: 10),
              pw.Row(
                children: [
                  if (workRate != null) ...[
                    _pdfMetricBox('Work Rate', '${workRate.toStringAsFixed(0)} m/min'),
                    pw.SizedBox(width: 12),
                  ],
                  if (movingRatio != null) ...[
                    _pdfMetricBox('Activity', '${(movingRatio * 100).toStringAsFixed(0)}%'),
                    pw.SizedBox(width: 12),
                  ],
                  if (directionChanges != null)
                    _pdfMetricBox('Dir. Changes', '${directionChanges.toStringAsFixed(1)}/min'),
                ],
              ),
            ],

            pw.SizedBox(height: 24),
            pw.Divider(color: PdfColors.grey300),
            pw.SizedBox(height: 12),

            // ── Footer ──
            pw.Text(
              'Report generated by ScoutAI — Page 1 of 2',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
            ),
          ],
        ),
      ),
    );

    // ── PAGE 2 — Movement zones + heatmap + speed chart ──────────────────────
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) {
          final zonesForReport = dashboardMovementZones ?? movementZones;
          final workRateForReport = dashboardWorkRate ?? workRate;
          final movingRatioForReport = dashboardMovingRatio ?? movingRatio;
          final dirChangesForReport = dashboardDirectionChanges ?? directionChanges;

          final children = <pw.Widget>[
            // ── Header ──
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'ScoutAI - Player Report',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('#1D63FF'),
                  ),
                ),
                pw.Text(
                  playerName.toUpperCase(),
                  style: const pw.TextStyle(fontSize: 14, color: PdfColors.grey700),
                ),
              ],
            ),
            pw.Divider(color: PdfColor.fromHex('#1D63FF'), thickness: 1.5),
            pw.SizedBox(height: 16),
          ];

          // ── Calibration warning ──
          if (!isCalibrated) {
            children.addAll([
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#FFF8E1'),
                  border: pw.Border.all(color: PdfColor.fromHex('#FFB300')),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Row(
                  children: [
                    pw.Text(
                      'UNCALIBRATED — ',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromHex('#E65100'),
                      ),
                    ),
                    pw.Text(
                      'Speed, distance and heatmap are pixel-estimated. Use pitch calibration for accurate metrics.',
                      style: pw.TextStyle(fontSize: 9, color: PdfColor.fromHex('#E65100')),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 14),
            ]);
          }

          // ── Movement Zones ──
          if (zonesForReport != null) {
            children.addAll([
              pw.Text(
                'MOVEMENT ZONES',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromHex('#1D63FF'),
                  letterSpacing: 1.5,
                ),
              ),
              pw.SizedBox(height: 8),
              _pdfMovementZonesBar(zonesForReport),
              pw.SizedBox(height: 16),
              pw.Divider(color: PdfColors.grey300),
              pw.SizedBox(height: 16),
            ]);
          }

          if (workRateForReport != null || movingRatioForReport != null || dirChangesForReport != null) {
            children.addAll([
              pw.Text(
                'WORK RATE & INTENSITY',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromHex('#1D63FF'),
                  letterSpacing: 1.5,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Row(
                children: [
                  if (workRateForReport != null) ...[
                    _pdfMetricBox('Work Rate', '${workRateForReport.toStringAsFixed(0)} m/min'),
                    pw.SizedBox(width: 8),
                  ],
                  if (movingRatioForReport != null) ...[
                    _pdfMetricBox('Activity', '${(movingRatioForReport * 100).toStringAsFixed(0)}%'),
                    pw.SizedBox(width: 8),
                  ],
                  if (dirChangesForReport != null)
                    _pdfMetricBox('Dir. Changes', '${dirChangesForReport.toStringAsFixed(1)}/min'),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Divider(color: PdfColors.grey300),
              pw.SizedBox(height: 16),
            ]);
          }

          // ── Player profile block ──
          children.addAll([
            pw.Text(
              'PLAYER PROFILE',
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromHex('#1D63FF'),
                letterSpacing: 1.5,
              ),
            ),
            pw.SizedBox(height: 8),
            _pdfProfileGrid(
              email: profileEmail,
              nation: profileNation,
              age: profileAge,
              heightCm: profileHeightCm,
              tier: profileTier,
              badgeVerified: profileBadgeVerified,
            ),
            pw.SizedBox(height: 14),
            pw.Divider(color: PdfColors.grey300),
            pw.SizedBox(height: 14),
          ]);

          // ── Home KPI summary block ──
          children.addAll([
            pw.Text(
              'HOME DASHBOARD SUMMARY',
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromHex('#1D63FF'),
                letterSpacing: 1.5,
              ),
            ),
            pw.SizedBox(height: 8),
            _pdfSummaryGrid([
              ('Videos', '${totalVideos ?? 0}'),
              ('Analyzed', '${matchesAnalyzed ?? 0}'),
              ('Total Dist', '${(totalDistanceKm ?? 0).toStringAsFixed(2)} km'),
              ('Avg Dist', '${(avgDistanceKm ?? 0).toStringAsFixed(2)} km'),
              ('Avg Speed', '${(avgSpeedKmhOverall ?? 0).toStringAsFixed(1)} km/h'),
              ('Total Sprints', '${totalSprintsOverall ?? 0}'),
              ('Accel Peaks', '${totalAccelPeaksOverall ?? 0}'),
              ('Best Dist', '${(bestDistanceKm ?? 0).toStringAsFixed(2)} km'),
              ('Best Avg Speed', '${(bestAvgSpeedKmh ?? 0).toStringAsFixed(1)} km/h'),
              ('Best Sprints', '${bestSprints ?? 0}'),
            ]),
            pw.SizedBox(height: 14),
          ]);

          // ── Data quality block ──
          final cal = calibratedCount ?? (isCalibrated ? 1 : 0);
          final uncal = uncalibratedCount ?? (isCalibrated ? 0 : 1);
          final totalQuality = cal + uncal;
          final qualityLabel = totalQuality > 0
              ? 'Calibrated analyses: $cal / $totalQuality'
              : (isCalibrated ? 'Calibrated analysis' : 'Uncalibrated analysis');
          children.addAll([
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: uncal > 0 ? PdfColor.fromHex('#FFF8E1') : PdfColor.fromHex('#ECFDF3'),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(
                  color: uncal > 0 ? PdfColor.fromHex('#FFB300') : PdfColor.fromHex('#23A26D'),
                ),
              ),
              child: pw.Text(
                qualityLabel,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: uncal > 0 ? PdfColor.fromHex('#A15C00') : PdfColor.fromHex('#166D4B'),
                ),
              ),
            ),
            pw.SizedBox(height: 14),
            pw.Divider(color: PdfColors.grey300),
            pw.SizedBox(height: 14),
          ]);

          // ── Heatmap image ──
          if (heatmapImage != null) {
            children.addAll([
              pw.Text(
                'FIELD HEATMAP',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromHex('#1D63FF'),
                  letterSpacing: 1.5,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Center(
                child: pw.Container(
                  width: 400,
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  ),
                  child: pw.ClipRRect(
                    horizontalRadius: 6,
                    verticalRadius: 6,
                    child: pw.Image(pw.MemoryImage(heatmapImage), fit: pw.BoxFit.contain),
                  ),
                ),
              ),
              pw.SizedBox(height: 16),
              pw.Divider(color: PdfColors.grey300),
              pw.SizedBox(height: 16),
            ]);
          }

          // ── Speed timeline chart image ──
          if (speedChartImage != null) {
            children.addAll([
              pw.Text(
                'SPEED TIMELINE',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromHex('#1D63FF'),
                  letterSpacing: 1.5,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Container(
                width: double.infinity,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.ClipRRect(
                  horizontalRadius: 6,
                  verticalRadius: 6,
                  child: pw.Image(pw.MemoryImage(speedChartImage), fit: pw.BoxFit.contain),
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Peak: ${maxSpeedKmh.toStringAsFixed(1)} km/h',
                      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                  pw.Text('Average: ${avgSpeedKmh.toStringAsFixed(1)} km/h',
                      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                ],
              ),
              pw.SizedBox(height: 16),
            ]);
          }

          children.addAll([
            pw.Spacer(),
            pw.Divider(color: PdfColors.grey300),
            pw.SizedBox(height: 8),
            pw.Text(
              'Report generated by ScoutAI — Page 2 of 2',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
            ),
          ]);

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: children,
          );
        },
      ),
    );

    // ── Saving & Sharing ──────────────────────────────────────────────────────
    final pdfBytes = await pdf.save();
    final safeName = playerName.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');

    List<XFile> filesToShare;

    if (kIsWeb) {
      filesToShare = [
        XFile.fromData(
          pdfBytes,
          name: 'scoutai_${safeName}_report.pdf',
          mimeType: 'application/pdf',
        )
      ];
    } else {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/scoutai_${safeName}_report.pdf');
      await file.writeAsBytes(pdfBytes);
      filesToShare = [XFile(file.path, mimeType: 'application/pdf')];
    }

    await Share.shareXFiles(
      filesToShare,
      subject: 'ScoutAI Player Report - $playerName',
      text: 'Check out this ScoutAI player report for $playerName!\n'
          'Position: $position | OVR: ${cardStats.ovr} | Top Speed: ${maxSpeedKmh.toStringAsFixed(1)} km/h',
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  static pw.Widget _pdfStatGrid(FifaCardStats s) {
    final stats = [
      ('PAC', s.pac),
      ('SHO', s.sho),
      ('PAS', s.pas),
      ('DRI', s.dri),
      ('DEF', s.def),
      ('PHY', s.phy),
    ];
    return pw.Wrap(
      spacing: 8,
      runSpacing: 4,
      children: stats.map((e) => pw.SizedBox(width: 50, child: _pdfStatCell(e.$1, e.$2))).toList(),
    );
  }

  static pw.Widget _pdfStatCell(String label, int value) {
    final color = value >= 80
        ? PdfColor.fromHex('#00E676')
        : value >= 65
            ? PdfColor.fromHex('#76FF03')
            : value >= 50
                ? PdfColor.fromHex('#FFD600')
                : value >= 35
                    ? PdfColor.fromHex('#FF6D00')
                    : PdfColor.fromHex('#FF1744');
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey600)),
          pw.SizedBox(width: 6),
          pw.Text(
            '$value',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  static pw.Widget _pdfMetricBox(String label, String value) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromHex('#F0F4FF'),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
          border: pw.Border.all(color: PdfColor.fromHex('#D0DBFF')),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              label.toUpperCase(),
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromHex('#1D63FF'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _pdfProfileGrid({
    String? email,
    String? nation,
    int? age,
    int? heightCm,
    String? tier,
    bool? badgeVerified,
  }) {
    final rows = [
      ('Email', _fallbackText(email)),
      ('Nation', _fallbackText(nation)),
      ('Age', age != null && age > 0 ? '$age' : 'N/A'),
      ('Height', heightCm != null && heightCm > 0 ? '$heightCm cm' : 'N/A'),
      ('Plan', _fallbackText(tier)),
      ('Badge', badgeVerified == true ? 'Verified' : 'Not verified'),
    ];

    return pw.Wrap(
      spacing: 8,
      runSpacing: 8,
      children: rows
          .map(
            (e) => pw.Container(
              width: 160,
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F7F9FF'),
                border: pw.Border.all(color: PdfColor.fromHex('#DCE4FF')),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(e.$1.toUpperCase(), style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
                  pw.SizedBox(height: 2),
                  pw.Text(e.$2, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  static pw.Widget _pdfSummaryGrid(List<(String, String)> items) {
    return pw.Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items
          .map(
            (e) => pw.Container(
              width: 120,
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F0F4FF'),
                border: pw.Border.all(color: PdfColor.fromHex('#D0DBFF')),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(e.$1.toUpperCase(), style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
                  pw.SizedBox(height: 2),
                  pw.Text(e.$2, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  static String _fallbackText(String? v) {
    if (v == null || v.trim().isEmpty) return 'N/A';
    return v.trim();
  }

  /// Draws movement zones as a stacked horizontal bar with legend.
  static pw.Widget _pdfMovementZonesBar(Map<String, dynamic> zones) {
    const keys = ['walking', 'jogging', 'running', 'highSpeed', 'sprinting'];
    const labels = ['Walking', 'Jogging', 'Running', 'High Speed', 'Sprinting'];
    final pdfColors = [
      PdfColor.fromHex('#4CAF50'),
      PdfColor.fromHex('#8BC34A'),
      PdfColor.fromHex('#FFB300'),
      PdfColor.fromHex('#FF7043'),
      PdfColor.fromHex('#E53935'),
    ];

    final values = keys.map((k) {
      final v = zones[k];
      return v is num ? v.toDouble() : 0.0;
    }).toList();
    final total = values.fold(0.0, (a, b) => a + b);

    // Build a stacked bar using pw.Row with flex-like proportions
    final barSegments = <pw.Widget>[];
    for (int i = 0; i < keys.length; i++) {
      final frac = total > 0 ? values[i] / total : 0.0;
      if (frac < 0.005) continue;
      barSegments.add(
        pw.Expanded(
          flex: (frac * 1000).round(),
          child: pw.Container(
            height: 16,
            color: pdfColors[i],
          ),
        ),
      );
    }

    final legendItems = <pw.Widget>[];
    for (int i = 0; i < keys.length; i++) {
      final pct = total > 0 ? (values[i] / total * 100) : 0.0;
      legendItems.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(right: 16, bottom: 4),
          child: pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Container(width: 10, height: 10, color: pdfColors[i]),
              pw.SizedBox(width: 4),
              pw.Text(
                '${labels[i]} ${pct.toStringAsFixed(0)}%',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
              ),
            ],
          ),
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.ClipRRect(
          horizontalRadius: 4,
          verticalRadius: 4,
          child: pw.Row(children: barSegments),
        ),
        pw.SizedBox(height: 8),
        pw.Wrap(children: legendItems),
      ],
    );
  }

  // ── Native PDF Legendary Card ───────────────────────────────────────────────

  static pw.Widget _pdfLegendaryCard({
    required String playerName,
    required String position,
    required FifaCardStats stats,
    Uint8List? portraitBytes,
  }) {
    final isLegend = stats.ovr >= 80;
    final isSilver = stats.ovr >= 70 && stats.ovr < 80;
    final baseColor = isLegend
        ? PdfColor.fromHex('#D4A843')
        : isSilver
            ? PdfColor.fromHex('#A8A8A8')
            : PdfColor.fromHex('#CD7F32');

    final darkColor = isLegend
        ? PdfColor.fromHex('#6B4F10')
        : isSilver
            ? PdfColor.fromHex('#707070')
            : PdfColor.fromHex('#8B5A2B');

    return pw.Container(
      width: 170,
      height: 240,
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#0F1628'),
        border: pw.Border.all(color: baseColor, width: 3),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
      ),
      padding: const pw.EdgeInsets.all(10),
      child: pw.Column(
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text(
                    '${stats.ovr}',
                    style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: baseColor),
                  ),
                  pw.Text(
                    position,
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: baseColor),
                  ),
                ],
              ),
              pw.Spacer(),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: pw.BoxDecoration(
                  color: darkColor,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
                ),
                child: pw.Text(
                  isLegend ? 'LEGEND' : isSilver ? 'SILVER' : 'BRONZE',
                  style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                ),
              )
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Container(
            width: 70,
            height: 70,
            decoration: pw.BoxDecoration(
              shape: pw.BoxShape.circle,
              border: pw.Border.all(color: baseColor, width: 2),
              color: PdfColor.fromHex('#162036'),
            ),
            child: (portraitBytes != null && _isValidImage(portraitBytes))
                ? pw.ClipOval(child: pw.Image(pw.MemoryImage(portraitBytes), fit: pw.BoxFit.cover))
                : pw.Center(child: pw.Text('?', style: pw.TextStyle(color: PdfColors.white, fontSize: 24))),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            playerName.toUpperCase(),
            maxLines: 1,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: baseColor),
          ),
          pw.SizedBox(height: 4),
          pw.Divider(color: darkColor),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _miniStat('PAC', stats.pac),
                  _miniStat('SHO', stats.sho),
                  _miniStat('PAS', stats.pas),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _miniStat('DRI', stats.dri),
                  _miniStat('DEF', stats.def),
                  _miniStat('PHY', stats.phy),
                ],
              ),
            ],
          )
        ],
      ),
    );
  }

  static pw.Widget _miniStat(String label, int val) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Container(width: 22, child: pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: PdfColors.white))),
          pw.Text('$val', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
        ],
      ),
    );
  }

  static bool _isValidImage(Uint8List bytes) {
    if (bytes.length < 4) return false;
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) return true;
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return true;
    return false;
  }

  static String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
