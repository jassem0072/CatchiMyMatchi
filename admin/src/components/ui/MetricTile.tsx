import type { CSSProperties, ReactNode } from 'react';

interface MetricTileProps {
  label: string;
  value: string | number;
  valueColor?: string;
  icon?: ReactNode;
  style?: CSSProperties;
}

export function MetricTile({ label, value, valueColor, icon, style }: MetricTileProps) {
  return (
    <div
      style={{
        background: 'var(--color-surface2)',
        border: '1px solid rgba(39,49,74,0.9)',
        borderRadius: 'var(--radius-card)',
        padding: '20px 24px',
        display: 'flex',
        flexDirection: 'column',
        gap: 8,
        ...style,
      }}
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
        {icon && <span style={{ opacity: 0.7 }}>{icon}</span>}
        <span
          style={{
            fontSize: 11,
            fontWeight: 800,
            color: 'var(--color-text-muted)',
            textTransform: 'uppercase',
            letterSpacing: '1.4px',
          }}
        >
          {label}
        </span>
      </div>
      <span
        style={{
          fontSize: 36,
          fontWeight: 900,
          lineHeight: 1,
          color: valueColor || 'var(--color-text)',
        }}
      >
        {value}
      </span>
    </div>
  );
}
