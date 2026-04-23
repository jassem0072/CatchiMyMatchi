import client from './client';

export interface ExpertEarningsSummary {
  verifiedPlayers: number;
  paidPlayers: number;
  pendingPlayers: number;
  totalUsd: number;
  paidUsd: number;
  pendingUsd: number;
}

export interface ExpertClaimResult {
  claimedPlayers: number;
  claimedUsd: number;
  message: string;
}

export interface ExpertPayoutInvoice {
  invoiceId: string;
  amountEur: number;
  claimedPlayers: number;
  requestedAt: string;
  expectedPaymentAt: string;
  payoutProvider: 'paypal' | 'bank_transfer' | 'legacy_card';
  payoutDestinationMasked: string;
  transactionReference: string;
  status: 'requested' | 'processing' | 'paid';
}

export async function getExpertEarnings(): Promise<ExpertEarningsSummary> {
  const res = await client.get<ExpertEarningsSummary>('/admin/expert/earnings');
  return res.data;
}

export async function requestExpertPayout(payload: {
  payoutProvider: 'paypal' | 'bank_transfer';
  accountHolderName: string;
  bankName: string;
  bankAccountOrIban: string;
  swiftBic?: string;
  transactionReference?: string;
}): Promise<ExpertClaimResult> {
  const res = await client.post<ExpertClaimResult>('/admin/expert/claim-earnings', payload);
  return res.data;
}

export async function getExpertPayoutInvoices(): Promise<ExpertPayoutInvoice[]> {
  const res = await client.get<ExpertPayoutInvoice[]>('/admin/expert/invoices');
  return res.data;
}

export async function notifyExpertInvoiceReady(expertId: string): Promise<{ sent: boolean; invoiceId: string; amountEur: number }> {
  const res = await client.post<{ sent: boolean; invoiceId: string; amountEur: number }>(
    `/admin/experts/${expertId}/notify-invoice-ready`,
  );
  return res.data;
}
