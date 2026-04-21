import type { ButtonHTMLAttributes, ReactNode } from 'react';

type Variant = 'primary' | 'ghost' | 'danger' | 'warning';

const styles: Record<Variant, React.CSSProperties> = {
  primary: {
    background: 'var(--color-primary)',
    color: '#fff',
    border: 'none',
  },
  ghost: {
    background: 'transparent',
    color: 'var(--color-text)',
    border: '1px solid var(--color-border)',
  },
  danger: {
    background: 'rgba(255,77,79,0.12)',
    color: 'var(--color-danger)',
    border: '1px solid rgba(255,77,79,0.35)',
  },
  warning: {
    background: 'rgba(253,176,34,0.12)',
    color: 'var(--color-warning)',
    border: '1px solid rgba(253,176,34,0.35)',
  },
};

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant;
  children: ReactNode;
  size?: 'sm' | 'md';
}

export function Button({ variant = 'primary', children, size = 'md', style, ...rest }: ButtonProps) {
  const sizeStyle: React.CSSProperties =
    size === 'sm'
      ? { padding: '6px 14px', fontSize: 12, fontWeight: 700 }
      : { padding: '10px 20px', fontSize: 14, fontWeight: 700 };

  return (
    <button
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        justifyContent: 'center',
        gap: 8,
        borderRadius: 'var(--radius-btn)',
        cursor: 'pointer',
        letterSpacing: '0.3px',
        transition: 'opacity 0.15s',
        ...styles[variant],
        ...sizeStyle,
        ...style,
      }}
      onMouseEnter={(e) => { (e.currentTarget.style.opacity = '0.82'); }}
      onMouseLeave={(e) => { (e.currentTarget.style.opacity = '1'); }}
      {...rest}
    >
      {children}
    </button>
  );
}
