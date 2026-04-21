import type { CSSProperties, ReactNode } from 'react';

type Variant = 'primary' | 'success' | 'warning' | 'danger' | 'muted' | 'accent';

const variantColors: Record<Variant, { bg: string; border: string; text: string }> = {
  primary: { bg: 'rgba(29,99,255,0.2)',   border: 'rgba(29,99,255,0.45)',   text: '#1D63FF' },
  success: { bg: 'rgba(50,213,131,0.2)',  border: 'rgba(50,213,131,0.45)',  text: '#32D583' },
  warning: { bg: 'rgba(253,176,34,0.2)',  border: 'rgba(253,176,34,0.45)',  text: '#FDB022' },
  danger:  { bg: 'rgba(255,77,79,0.2)',   border: 'rgba(255,77,79,0.45)',   text: '#FF4D4F' },
  muted:   { bg: 'rgba(39,49,74,0.5)',    border: 'rgba(39,49,74,0.9)',     text: '#9AA6BD' },
  accent:  { bg: 'rgba(183,244,8,0.15)',  border: 'rgba(183,244,8,0.4)',    text: '#B7F408' },
};

interface PillBadgeProps {
  children: ReactNode;
  variant?: Variant;
  style?: CSSProperties;
}

export function PillBadge({ children, variant = 'muted', style }: PillBadgeProps) {
  const c = variantColors[variant];
  return (
    <span
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        gap: 4,
        background: c.bg,
        border: `1px solid ${c.border}`,
        borderRadius: 'var(--radius-pill)',
        color: c.text,
        fontSize: 11,
        fontWeight: 700,
        letterSpacing: '0.8px',
        textTransform: 'uppercase',
        padding: '3px 10px',
        ...style,
      }}
    >
      {children}
    </span>
  );
}
