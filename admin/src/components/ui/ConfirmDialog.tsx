import { Modal } from './Modal';
import { Button } from './Button';

interface ConfirmDialogProps {
  open: boolean;
  title?: string;
  message: string;
  confirmLabel?: string;
  cancelLabel?: string;
  onConfirm: () => void;
  onCancel: () => void;
  loading?: boolean;
}

export function ConfirmDialog({
  open,
  title = 'Confirm',
  message,
  confirmLabel = 'Confirm',
  cancelLabel = 'Cancel',
  onConfirm,
  onCancel,
  loading,
}: ConfirmDialogProps) {
  return (
    <Modal open={open} onClose={onCancel} title={title} width={400}>
      <p style={{ color: 'var(--color-text-muted)', marginBottom: 24, lineHeight: 1.6 }}>{message}</p>
      <div style={{ display: 'flex', gap: 12, justifyContent: 'flex-end' }}>
        <Button variant="ghost" onClick={onCancel} disabled={loading}>
          {cancelLabel}
        </Button>
        <Button variant="danger" onClick={onConfirm} disabled={loading}>
          {loading ? 'Loading…' : confirmLabel}
        </Button>
      </div>
    </Modal>
  );
}
