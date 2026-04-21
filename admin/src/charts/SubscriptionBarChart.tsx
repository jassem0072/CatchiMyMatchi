import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Cell } from 'recharts';

interface SubscriptionBarChartProps {
  subscriptions: { basic: number; premium: number; elite: number };
}

export function SubscriptionBarChart({ subscriptions }: SubscriptionBarChartProps) {
  const data = [
    { name: 'Basic',   value: subscriptions.basic,   color: '#32D583' },
    { name: 'Premium', value: subscriptions.premium,  color: '#B7F408' },
    { name: 'Elite',   value: subscriptions.elite,    color: '#FDB022' },
  ];

  return (
    <ResponsiveContainer width="100%" height={220}>
      <BarChart data={data} margin={{ top: 10, right: 16, left: 0, bottom: 0 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="rgba(39,49,74,0.6)" />
        <XAxis
          dataKey="name"
          tick={{ fill: '#9AA6BD', fontSize: 11, fontWeight: 600 }}
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
          formatter={(v: number) => [v, 'Scouters']}
        />
        <Bar dataKey="value" radius={[6, 6, 0, 0]}>
          {data.map((entry, index) => (
            <Cell key={`cell-${index}`} fill={entry.color} />
          ))}
        </Bar>
      </BarChart>
    </ResponsiveContainer>
  );
}
