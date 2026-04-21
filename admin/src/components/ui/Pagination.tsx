interface PaginationProps {
  page: number;
  total: number;
  limit: number;
  onChange: (page: number) => void;
}

export function Pagination({ page, total, limit, onChange }: PaginationProps) {
  const totalPages = Math.ceil(total / limit);
  if (totalPages <= 1) return null;

  const pages = Array.from({ length: Math.min(7, totalPages) }, (_, i) => {
    if (totalPages <= 7) return i + 1;
    if (page <= 4) return i + 1;
    if (page >= totalPages - 3) return totalPages - 6 + i;
    return page - 3 + i;
  });

  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '16px 0' }}>
      <button
        onClick={() => onChange(page - 1)}
        disabled={page <= 1}
        style={btnStyle(page <= 1)}
      >
        ‹
      </button>
      {pages.map((p) => (
        <button
          key={p}
          onClick={() => onChange(p)}
          style={btnStyle(false, p === page)}
        >
          {p}
        </button>
      ))}
      <button
        onClick={() => onChange(page + 1)}
        disabled={page >= totalPages}
        style={btnStyle(page >= totalPages)}
      >
        ›
      </button>
      <span style={{ fontSize: 12, color: 'var(--color-text-muted)', marginLeft: 8 }}>
        {total} total
      </span>
    </div>
  );
}

function btnStyle(disabled: boolean, active = false): React.CSSProperties {
  return {
    width: 32,
    height: 32,
    border: active
      ? '1px solid var(--color-primary)'
      : '1px solid var(--color-border)',
    borderRadius: 8,
    background: active ? 'var(--color-primary)' : 'transparent',
    color: active ? '#fff' : disabled ? 'var(--color-text-muted)' : 'var(--color-text)',
    cursor: disabled ? 'not-allowed' : 'pointer',
    fontSize: 13,
    fontWeight: 600,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    opacity: disabled ? 0.4 : 1,
    transition: 'all 0.15s',
  };
}
