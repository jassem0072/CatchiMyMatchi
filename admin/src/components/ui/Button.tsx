import type { ButtonHTMLAttributes, ReactNode } from 'react';

type Variant = 'primary' | 'ghost' | 'danger' | 'warning';

const styles: Record<Variant, React.CSSProperties> = {
  primary: {
    background: 'linear-gradient(135deg, #1D63FF 0%, #2E79FF 55%, #4A90FF 100%)',
    color: '#fff',
    border: 'none',
    boxShadow: '0 8px 20px rgba(29,99,255,0.35)',
  },
  ghost: {
    background: 'rgba(15,23,38,0.75)',
    color: 'var(--color-text)',
    border: '1px solid rgba(39,49,74,0.95)',
  },
  danger: {
    background: 'linear-gradient(135deg, rgba(255,77,79,0.15), rgba(255,77,79,0.09))',
    color: 'var(--color-danger)',
    border: '1px solid rgba(255,77,79,0.35)',
  },
  warning: {
    background: 'linear-gradient(135deg, rgba(253,176,34,0.16), rgba(253,176,34,0.1))',
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
      : { padding: '10px 20px', fontSize: 14, fontWeight: 800 };

  const disabled = Boolean(rest.disabled);

  return (
    <button
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        justifyContent: 'center',
        gap: 8,
        borderRadius: 'var(--radius-btn)',
        cursor: disabled ? 'not-allowed' : 'pointer',
        letterSpacing: '0.2px',
        transform: 'translateY(0)',
        transition: 'transform 0.18s ease, box-shadow 0.18s ease, opacity 0.18s ease, filter 0.18s ease',
        opacity: disabled ? 0.56 : 1,
        ...styles[variant],
        ...sizeStyle,
        ...style,
      }}
      onMouseEnter={(e) => {
        if (disabled) return;
        e.currentTarget.style.transform = 'translateY(-1px)';
        e.currentTarget.style.filter = 'brightness(1.03)';
        if (variant === 'primary') {
          e.currentTarget.style.boxShadow = '0 12px 24px rgba(29,99,255,0.42)';
        }
      }}
      onMouseLeave={(e) => {
        e.currentTarget.style.transform = 'translateY(0)';
        e.currentTarget.style.filter = 'brightness(1)';
        e.currentTarget.style.boxShadow = styles[variant].boxShadow ? String(styles[variant].boxShadow) : 'none';
      }}
      {...rest}
    >
      {children}
    </button>
  );
}
