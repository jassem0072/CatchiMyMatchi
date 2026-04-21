import { useRef, useEffect, type ChangeEvent } from 'react';

interface SearchInputProps {
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
  debounceMs?: number;
}

export function SearchInput({
  value,
  onChange,
  placeholder = 'Search…',
  debounceMs = 400,
}: SearchInputProps) {
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  function handleChange(e: ChangeEvent<HTMLInputElement>) {
    const v = e.target.value;
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(() => onChange(v), debounceMs);
  }

  useEffect(() => () => { if (timer.current) clearTimeout(timer.current); }, []);

  return (
    <input
      defaultValue={value}
      onChange={handleChange}
      placeholder={placeholder}
      style={{
        background: 'var(--color-surface2)',
        border: '1px solid rgba(39,49,74,0.9)',
        borderRadius: 'var(--radius-input)',
        color: 'var(--color-text)',
        padding: '10px 16px',
        fontSize: 14,
        width: '100%',
        maxWidth: 320,
      }}
    />
  );
}
