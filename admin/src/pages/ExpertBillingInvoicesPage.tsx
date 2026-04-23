import { useCallback, useMemo, useState } from 'react';
import { GlassCard } from '../components/ui/GlassCard';
import { Button } from '../components/ui/Button';
import { useApi } from '../hooks/useApi';
import { getExpertPayoutInvoices, requestExpertPayout } from '../api/expert';
import { downloadInvoicePdf } from '../utils/invoice-pdf';

const PAYOUT_PROVIDER_OPTIONS = [
  { value: 'paypal', label: 'PayPal payout' },
  { value: 'bank_transfer', label: 'Bank transfer' },
] as const;

export function ExpertBillingInvoicesPage() {
  const [submitting, setSubmitting] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [messageTone, setMessageTone] = useState<'success' | 'error' | 'neutral'>('neutral');
  const [payoutProvider, setPayoutProvider] = useState<'paypal' | 'bank_transfer'>('bank_transfer');
  const [accountHolderName, setAccountHolderName] = useState('');
  const [bankName, setBankName] = useState('');
  const [bankAccountOrIban, setBankAccountOrIban] = useState('');
  const [swiftBic, setSwiftBic] = useState('');
  const [transactionReference, setTransactionReference] = useState('');

  const invoicesFetcher = useCallback(() => getExpertPayoutInvoices(), []);

  const { data: invoices, loading: invoicesLoading, error: invoicesError, refetch: refetchInvoices } = useApi(invoicesFetcher, []);

  async function handleRequestPayout() {
    if (accountHolderName.trim().length < 3) {
      setMessage('Please provide the account holder name.');
      setMessageTone('error');
      return;
    }
    if (bankName.trim().length < 2) {
      setMessage('Please provide the bank name.');
      setMessageTone('error');
      return;
    }
    if (bankAccountOrIban.trim().length < 4) {
      setMessage('Please provide bank account number or IBAN.');
      setMessageTone('error');
      return;
    }

    setSubmitting(true);
    setMessage(null);
    setMessageTone('neutral');
    try {
      const result = await requestExpertPayout({
        payoutProvider,
        accountHolderName: accountHolderName.trim(),
        bankName: bankName.trim(),
        bankAccountOrIban: bankAccountOrIban.trim(),
        swiftBic: swiftBic.trim() || undefined,
        transactionReference: transactionReference.trim() || undefined,
      });
      setMessage(result.message);
      setMessageTone('success');
      setAccountHolderName('');
      setBankName('');
      setBankAccountOrIban('');
      setSwiftBic('');
      setTransactionReference('');
      refetchInvoices();
    } catch (e: unknown) {
      const msg =
        (e as any)?.response?.data?.message ||
        (e as any)?.message ||
        'Unable to request payout';
      setMessage(msg);
      setMessageTone('error');
    } finally {
      setSubmitting(false);
    }
  }

  const messageStyle = useMemo<React.CSSProperties>(() => {
    if (messageTone === 'success') {
      return {
        marginTop: 12,
        fontSize: 13,
        color: 'var(--color-accent)',
        border: '1px solid rgba(183,244,8,0.45)',
        background: 'rgba(183,244,8,0.1)',
        borderRadius: 12,
        padding: '10px 12px',
      };
    }
    if (messageTone === 'error') {
      return {
        marginTop: 12,
        fontSize: 13,
        color: 'var(--color-danger)',
        border: '1px solid rgba(255,77,79,0.45)',
        background: 'rgba(255,77,79,0.1)',
        borderRadius: 12,
        padding: '10px 12px',
      };
    }
    return {
      marginTop: 12,
      fontSize: 13,
      color: 'var(--color-text-muted)',
    };
  }, [messageTone]);

  return (
    <div style={pageStyle}>
      <GlassCard className="ui-reveal" style={heroCardStyle}>
        <div style={heroTitleStyle}>Billing and Invoices</div>
        <div style={heroSubtitleStyle}>
          Manage payout details and invoice history in one place.
        </div>
        <div style={heroHintStyle}>
          Every payout request sends one email to admin and one confirmation email to your expert account.
        </div>
      </GlassCard>

      <GlassCard className="ui-reveal ui-delay-1" style={sectionCardStyle}>
        <div style={sectionTitleStyle}>Send Billing Details</div>
        <div style={sectionSubtitleStyle}>
          Fill your bank billing information and submit. This request is sent by email to admin and a copy is sent to your email.
        </div>

        <div style={formGridStyle}>
          <label style={fieldLabelStyle}>Payout Method</label>
          <select
            value={payoutProvider}
            onChange={(e) => setPayoutProvider(e.target.value as 'paypal' | 'bank_transfer')}
            className="ui-select"
          >
            {PAYOUT_PROVIDER_OPTIONS.map((option) => (
              <option key={option.value} value={option.value}>{option.label}</option>
            ))}
          </select>

          <label style={fieldLabelStyle}>Account Holder Name</label>
          <input
            value={accountHolderName}
            onChange={(e) => setAccountHolderName(e.target.value)}
            placeholder="Account holder name"
            className="ui-input"
          />

          <label style={fieldLabelStyle}>Bank Name</label>
          <input
            value={bankName}
            onChange={(e) => setBankName(e.target.value)}
            placeholder="Bank name"
            className="ui-input"
          />

          <label style={fieldLabelStyle}>Bank Account Number or IBAN</label>
          <input
            value={bankAccountOrIban}
            onChange={(e) => setBankAccountOrIban(e.target.value)}
            placeholder="Bank account number or IBAN"
            className="ui-input"
          />

          <label style={fieldLabelStyle}>SWIFT or BIC (optional)</label>
          <input
            value={swiftBic}
            onChange={(e) => setSwiftBic(e.target.value)}
            placeholder="SWIFT / BIC (optional)"
            className="ui-input"
          />

          <label style={fieldLabelStyle}>Provider Transaction Reference (optional)</label>
          <input
            value={transactionReference}
            onChange={(e) => setTransactionReference(e.target.value)}
            placeholder="Optional provider transaction reference"
            className="ui-input"
          />
        </div>

        <div style={actionRowStyle}>
          <Button variant="primary" onClick={() => void handleRequestPayout()} disabled={submitting} style={ctaButtonStyle}>
            {submitting ? 'Submitting...' : 'Submit Billing Details'}
          </Button>
          <div style={actionHintStyle}>
            Admin receives your billing details by email, and you receive a confirmation email.
          </div>
        </div>

        {message && <div style={messageStyle}>{message}</div>}
      </GlassCard>

      <GlassCard className="ui-reveal ui-delay-2" style={sectionCardStyle}>
        <div style={sectionTitleStyle}>All Payment Invoices</div>
        {invoicesLoading && <div style={metaTextStyle}>Loading invoices...</div>}
        {invoicesError && <div style={{ ...metaTextStyle, color: 'var(--color-danger)' }}>{invoicesError}</div>}
        {!invoicesLoading && !invoicesError && (!invoices || invoices.length === 0) && (
          <div style={metaTextStyle}>No invoices yet.</div>
        )}
        {!invoicesLoading && !invoicesError && invoices && invoices.length > 0 && (
          <div style={tableWrapStyle}>
            <table style={tableStyle}>
              <thead>
                <tr style={tableHeadRowStyle}>
                  <th style={tableHeadCellStyle}>Invoice</th>
                  <th style={tableHeadCellStyle}>Amount</th>
                  <th style={tableHeadCellStyle}>Provider</th>
                  <th style={tableHeadCellStyle}>Destination</th>
                  <th style={tableHeadCellStyle}>Reference</th>
                  <th style={tableHeadCellStyle}>Requested</th>
                  <th style={tableHeadCellStyle}>Expected</th>
                  <th style={tableHeadCellStyle}>Status</th>
                  <th style={tableHeadCellStyle}></th>
                </tr>
              </thead>
              <tbody>
                {invoices.map((invoice) => (
                  <tr key={invoice.invoiceId} className="billing-row">
                    <td style={tableCellStyle}>{invoice.invoiceId}</td>
                    <td style={{ ...tableCellStyle, color: 'var(--color-accent)' }}>EUR {invoice.amountEur}</td>
                    <td style={{ ...tableCellStyle, textTransform: 'capitalize' }}>{invoice.payoutProvider.replace('_', ' ')}</td>
                    <td style={tableCellStyle}>{invoice.payoutDestinationMasked}</td>
                    <td style={tableCellStyle}>{invoice.transactionReference}</td>
                    <td style={tableCellStyle}>{new Date(invoice.requestedAt).toLocaleDateString()}</td>
                    <td style={tableCellStyle}>{new Date(invoice.expectedPaymentAt).toLocaleDateString()}</td>
                    <td style={tableCellStyle}>
                      <span style={statusPillStyle(invoice.status)}>{invoice.status}</span>
                    </td>
                    <td style={{ ...tableCellStyle, whiteSpace: 'nowrap' }}>
                      <Button
                        id={`download-pdf-${invoice.invoiceId}`}
                        size="sm"
                        variant="ghost"
                        onClick={() => void downloadInvoicePdf(invoice)}
                        style={{
                          fontSize: 11,
                          border: '1px solid rgba(29,99,255,0.4)',
                          color: 'var(--color-primary)',
                          background: 'rgba(29,99,255,0.08)',
                          gap: 4,
                        }}
                      >
                        📥 Download PDF
                      </Button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </GlassCard>
    </div>
  );
}

function statusPillStyle(status: string): React.CSSProperties {
  const s = String(status || '').toLowerCase();
  if (s === 'paid') {
    return {
      display: 'inline-flex',
      borderRadius: 999,
      padding: '4px 10px',
      fontSize: 11,
      fontWeight: 800,
      color: 'var(--color-success)',
      border: '1px solid rgba(50,213,131,0.4)',
      background: 'rgba(50,213,131,0.1)',
      textTransform: 'capitalize',
    };
  }
  if (s === 'rejected') {
    return {
      display: 'inline-flex',
      borderRadius: 999,
      padding: '4px 10px',
      fontSize: 11,
      fontWeight: 800,
      color: 'var(--color-danger)',
      border: '1px solid rgba(255,77,79,0.4)',
      background: 'rgba(255,77,79,0.1)',
      textTransform: 'capitalize',
    };
  }
  return {
    display: 'inline-flex',
    borderRadius: 999,
    padding: '4px 10px',
    fontSize: 11,
    fontWeight: 800,
    color: 'var(--color-warning)',
    border: '1px solid rgba(253,176,34,0.4)',
    background: 'rgba(253,176,34,0.12)',
    textTransform: 'capitalize',
  };
}

const pageStyle: React.CSSProperties = {
  display: 'grid',
  gap: 16,
};

const heroCardStyle: React.CSSProperties = {
  background: 'radial-gradient(120% 170% at 100% 0%, rgba(29,99,255,0.2) 0%, rgba(18,27,43,0.95) 45%, rgba(12,20,34,0.98) 100%)',
  border: '1px solid rgba(29,99,255,0.28)',
};

const heroTitleStyle: React.CSSProperties = {
  fontSize: 30,
  fontWeight: 900,
  lineHeight: 1.1,
  letterSpacing: '-0.03em',
  marginBottom: 8,
};

const heroSubtitleStyle: React.CSSProperties = {
  color: '#c7d3ea',
  fontSize: 15,
  fontWeight: 600,
  marginBottom: 6,
};

const heroHintStyle: React.CSSProperties = {
  color: 'var(--color-text-muted)',
  fontSize: 12,
};

const sectionCardStyle: React.CSSProperties = {
  background: 'linear-gradient(180deg, rgba(18,27,43,0.95), rgba(11,18,32,0.98))',
  border: '1px solid rgba(39,49,74,0.9)',
};

const sectionTitleStyle: React.CSSProperties = {
  fontSize: 31,
  fontWeight: 900,
  letterSpacing: '-0.02em',
  marginBottom: 4,
};

const sectionSubtitleStyle: React.CSSProperties = {
  color: 'var(--color-text-muted)',
  fontSize: 13,
  marginBottom: 14,
};

const fieldLabelStyle: React.CSSProperties = {
  color: '#a8bad8',
  fontSize: 11,
  fontWeight: 800,
  letterSpacing: '1.1px',
  textTransform: 'uppercase',
  marginTop: 2,
};

const formGridStyle: React.CSSProperties = {
  display: 'grid',
  gap: 9,
};

const actionRowStyle: React.CSSProperties = {
  marginTop: 14,
  display: 'flex',
  gap: 10,
  alignItems: 'center',
  flexWrap: 'wrap',
};

const ctaButtonStyle: React.CSSProperties = {
  minWidth: 210,
};

const actionHintStyle: React.CSSProperties = {
  fontSize: 13,
  color: 'var(--color-text-muted)',
  fontWeight: 600,
};

const metaTextStyle: React.CSSProperties = {
  fontSize: 13,
  color: 'var(--color-text-muted)',
};

const tableWrapStyle: React.CSSProperties = {
  overflowX: 'auto',
  border: '1px solid rgba(39,49,74,0.9)',
  borderRadius: 14,
  background: 'rgba(11,18,32,0.75)',
};

const tableStyle: React.CSSProperties = {
  width: '100%',
  borderCollapse: 'collapse',
  fontSize: 13,
};

const tableHeadRowStyle: React.CSSProperties = {
  color: '#9fb0cb',
  textAlign: 'left',
};

const tableHeadCellStyle: React.CSSProperties = {
  padding: '10px 10px',
  borderBottom: '1px solid var(--color-border)',
  textTransform: 'uppercase',
  letterSpacing: '0.8px',
  fontSize: 11,
  fontWeight: 800,
};

const tableCellStyle: React.CSSProperties = {
  padding: '10px 10px',
  borderBottom: '1px solid rgba(39,49,74,0.7)',
  fontWeight: 600,
};
