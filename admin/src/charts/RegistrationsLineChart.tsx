import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  Area,
  AreaChart,
} from 'recharts';

interface RegistrationsLineChartProps {
  data: Array<{ label: string; count: number }>;
}

export function RegistrationsLineChart({ data }: RegistrationsLineChartProps) {
  return (
    <ResponsiveContainer width="100%" height={220}>
      <AreaChart data={data} margin={{ top: 10, right: 16, left: 0, bottom: 0 }}>
        <defs>
          <linearGradient id="regGrad" x1="0" y1="0" x2="0" y2="1">
            <stop offset="5%" stopColor="#1D63FF" stopOpacity={0.3} />
            <stop offset="95%" stopColor="#1D63FF" stopOpacity={0} />
          </linearGradient>
        </defs>
        <CartesianGrid strokeDasharray="3 3" stroke="rgba(39,49,74,0.6)" />
        <XAxis
          dataKey="label"
          tick={{ fill: '#9AA6BD', fontSize: 10 }}
          axisLine={{ stroke: '#27314A' }}
          tickLine={false}
        />
        <YAxis
          tick={{ fill: '#9AA6BD', fontSize: 10 }}
          axisLine={false}
          tickLine={false}
          allowDecimals={false}
        />
        <Tooltip
          contentStyle={{
            background: '#121B2B',
            border: '1px solid #27314A',
            borderRadius: 10,
            fontSize: 12,
            color: '#E9EEF8',
          }}
          formatter={(v: number) => [v, 'Registrations']}
        />
        <Area
          type="monotone"
          dataKey="count"
          stroke="#1D63FF"
          strokeWidth={2}
          fill="url(#regGrad)"
          dot={{ fill: '#1D63FF', strokeWidth: 0, r: 3 }}
          activeDot={{ r: 5, fill: '#1D63FF' }}
        />
      </AreaChart>
    </ResponsiveContainer>
  );
}
