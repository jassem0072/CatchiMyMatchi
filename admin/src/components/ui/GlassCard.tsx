import type { CSSProperties, ReactNode } from 'react';

interface GlassCardProps {
  children: ReactNode;
  style?: CSSProperties;
  className?: string;
}

export function GlassCard({ children, style, className }: GlassCardProps) {
  return (
    <div
      className={className}
      style={{
        background: 'rgba(18, 27, 43, 0.92)',
        border: '1px solid rgba(39, 49, 74, 0.9)',
        borderRadius: 'var(--radius-card)',
        padding: '20px',
        ...style,
      }}
    >
      {children}
    </div>
  );
}
