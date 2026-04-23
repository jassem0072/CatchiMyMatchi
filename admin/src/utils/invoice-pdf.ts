/**
 * invoice-pdf.ts
 *
 * Client-side PDF generation for expert payout invoices using pdf-lib.
 * Produces a professional branded invoice with ScoutAI header.
 */
import { PDFDocument, rgb, StandardFonts } from 'pdf-lib';
import type { ExpertPayoutInvoice } from '../api/expert';

// ScoutAI brand colours
const BRAND_DARK = rgb(0.071, 0.106, 0.169);   // #121B2B
const BRAND_BLUE = rgb(0.114, 0.388, 1.0);      // #1D63FF
const BRAND_ACCENT = rgb(0.718, 0.957, 0.031);  // #B7F408
const WHITE = rgb(1, 1, 1);
const GREY = rgb(0.6, 0.67, 0.76);
const LIGHT_BG = rgb(0.937, 0.953, 0.973);      // #EFF3F8
const TEXT_DARK = rgb(0.094, 0.122, 0.18);      // #181F2E

function formatDate(iso: string): string {
  try {
    return new Date(iso).toLocaleDateString('en-GB', {
      day: '2-digit', month: 'short', year: 'numeric',
    });
  } catch {
    return iso;
  }
}

function capitalize(str: string): string {
  return str.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
}

/**
 * Generates a branded ScoutAI PDF invoice and triggers a browser download.
 */
export async function downloadInvoicePdf(invoice: ExpertPayoutInvoice, expertEmail?: string): Promise<void> {
  const doc = await PDFDocument.create();
  const page = doc.addPage([595, 842]); // A4 portrait

  const boldFont = await doc.embedFont(StandardFonts.HelveticaBold);
  const regularFont = await doc.embedFont(StandardFonts.Helvetica);

  const { height } = page.getSize();
  const margin = 48;
  let y = height - margin;

  // ── Header band ──────────────────────────────────────────────────────────
  page.drawRectangle({
    x: 0, y: height - 100,
    width: 595, height: 100,
    color: BRAND_DARK,
  });

  // ScoutAI logo text (SVG logo not embedded — use styled text)
  page.drawText('SCOUT', {
    x: margin, y: height - 52,
    size: 28, font: boldFont, color: WHITE,
  });
  page.drawText('AI', {
    x: margin + 92, y: height - 52,
    size: 28, font: boldFont, color: BRAND_ACCENT,
  });
  page.drawText('Expert Payout Invoice', {
    x: margin, y: height - 74,
    size: 11, font: regularFont, color: GREY,
  });

  // Invoice ID top-right
  page.drawText(invoice.invoiceId, {
    x: 595 - margin - boldFont.widthOfTextAtSize(invoice.invoiceId, 11),
    y: height - 52,
    size: 11, font: boldFont, color: WHITE,
  });
  page.drawText('Invoice ID', {
    x: 595 - margin - boldFont.widthOfTextAtSize('Invoice ID', 9),
    y: height - 66,
    size: 9, font: regularFont, color: GREY,
  });

  y = height - 130;

  // ── Status pill ───────────────────────────────────────────────────────────
  const statusText = capitalize(invoice.status);
  const statusColor = invoice.status === 'paid' ? rgb(0.196, 0.835, 0.514)
    : invoice.status === 'processing' ? rgb(0.992, 0.69, 0.133)
    : BRAND_BLUE;
  const pillW = boldFont.widthOfTextAtSize(statusText, 10) + 20;
  page.drawRectangle({ x: margin, y: y - 4, width: pillW, height: 18, color: statusColor });
  page.drawText(statusText, { x: margin + 10, y: y - 1, size: 10, font: boldFont, color: WHITE });

  y -= 36;

  // ── Amount hero ───────────────────────────────────────────────────────────
  page.drawText(`EUR ${invoice.amountEur.toFixed(2)}`, {
    x: margin, y,
    size: 36, font: boldFont, color: TEXT_DARK,
  });
  y -= 16;
  page.drawText(`For ${invoice.claimedPlayers} verified player${invoice.claimedPlayers !== 1 ? 's' : ''} @ EUR 30 each`, {
    x: margin, y,
    size: 11, font: regularFont, color: GREY,
  });

  y -= 32;
  // horizontal rule
  page.drawLine({ start: { x: margin, y }, end: { x: 595 - margin, y }, thickness: 1, color: LIGHT_BG });
  y -= 24;

  // ── Details table ─────────────────────────────────────────────────────────
  const rows: [string, string][] = [
    ['Requested',       formatDate(invoice.requestedAt)],
    ['Expected Payment',formatDate(invoice.expectedPaymentAt)],
    ['Payout Method',   capitalize(invoice.payoutProvider)],
    ['Destination',     invoice.payoutDestinationMasked],
    ['Reference',       invoice.transactionReference],
    ...(expertEmail ? [['Expert Email', expertEmail] as [string, string]] : []),
  ];

  const colLabel = margin;
  const colValue = margin + 190;
  const rowH = 28;

  rows.forEach(([label, value], i) => {
    const rowY = y - i * rowH;
    // Alternating background
    if (i % 2 === 0) {
      page.drawRectangle({ x: margin - 8, y: rowY - 6, width: 595 - margin * 2 + 16, height: rowH, color: LIGHT_BG });
    }
    page.drawText(label, { x: colLabel, y: rowY + 4, size: 10, font: boldFont, color: GREY });
    page.drawText(value, { x: colValue, y: rowY + 4, size: 10, font: regularFont, color: TEXT_DARK });
  });

  y -= rows.length * rowH + 24;

  // horizontal rule
  page.drawLine({ start: { x: margin, y }, end: { x: 595 - margin, y }, thickness: 1, color: LIGHT_BG });
  y -= 20;

  // ── Footer note ───────────────────────────────────────────────────────────
  page.drawText('This document confirms your payout request has been submitted to ScoutAI.', {
    x: margin, y,
    size: 9, font: regularFont, color: GREY,
  });
  y -= 13;
  page.drawText('Payment will be processed within 3 business days to the destination above.', {
    x: margin, y,
    size: 9, font: regularFont, color: GREY,
  });

  // ── Bottom accent bar ────────────────────────────────────────────────────
  page.drawRectangle({ x: 0, y: 0, width: 595, height: 6, color: BRAND_BLUE });
  page.drawRectangle({ x: 0, y: 6, width: 200, height: 3, color: BRAND_ACCENT });

  // ── Page number ───────────────────────────────────────────────────────────
  page.drawText('Page 1 of 1  ·  ScoutAI Platform', {
    x: margin, y: 18,
    size: 8, font: regularFont, color: GREY,
  });

  // ── Save + download ───────────────────────────────────────────────────────
  const bytes = await doc.save();
  const blob = new Blob([bytes.buffer as ArrayBuffer], { type: 'application/pdf' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `ScoutAI_Invoice_${invoice.invoiceId}.pdf`;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 5000);
}
