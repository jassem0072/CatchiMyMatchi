import type { ReactNode } from 'react';

export interface Column<T> {
  key: string;
  header: string;
  render?: (row: T) => ReactNode;
  width?: string | number;
}

interface DataTableProps<T> {
  columns: Column<T>[];
  rows: T[];
  loading?: boolean;
  keyExtractor?: (row: T) => string;
  emptyMessage?: string;
}

export function DataTable<T extends object>({
  columns,
  rows,
  loading,
  keyExtractor,
  emptyMessage = 'No data',
}: DataTableProps<T>) {
  return (
    <div
      style={{
        overflowX: 'auto',
        border: '1px solid var(--color-border)',
        borderRadius: 'var(--radius-card)',
      }}
    >
      <table style={{ width: '100%', borderCollapse: 'collapse' }}>
        <thead>
          <tr style={{ background: 'var(--color-surface2)', borderBottom: '1px solid var(--color-border)' }}>
            {columns.map((col) => (
              <th
                key={col.key}
                style={{
                  padding: '12px 16px',
                  textAlign: 'left',
                  fontSize: 11,
                  fontWeight: 800,
                  color: 'var(--color-text-muted)',
                  textTransform: 'uppercase',
                  letterSpacing: '1.2px',
                  whiteSpace: 'nowrap',
                  width: col.width,
                }}
              >
                {col.header}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {loading ? (
            <tr>
              <td
                colSpan={columns.length}
                style={{ padding: 32, textAlign: 'center', color: 'var(--color-text-muted)' }}
              >
                Loading…
              </td>
            </tr>
          ) : rows.length === 0 ? (
            <tr>
              <td
                colSpan={columns.length}
                style={{ padding: 32, textAlign: 'center', color: 'var(--color-text-muted)' }}
              >
                {emptyMessage}
              </td>
            </tr>
          ) : (
            rows.map((row, i) => (
              <tr
                key={keyExtractor ? keyExtractor(row) : String(i)}
                style={{
                  borderBottom: '1px solid rgba(39,49,74,0.5)',
                  background: i % 2 === 0 ? 'var(--color-surface)' : 'var(--color-bg)',
                }}
              >
                {columns.map((col) => (
                  <td
                    key={col.key}
                    style={{ padding: '12px 16px', fontSize: 13, verticalAlign: 'middle' }}
                  >
                    {col.render
                      ? col.render(row)
                      : String((row as Record<string, unknown>)[col.key] ?? '—')}
                  </td>
                ))}
              </tr>
            ))
          )}
        </tbody>
      </table>
    </div>
  );
}
