import { PieChart, Pie, Cell, Tooltip, ResponsiveContainer, Legend } from 'recharts';

interface RoleDonutChartProps {
  players: number;
  scouterss: number;
}

const COLORS = ['#1D63FF', '#B7F408'];

export function RoleDonutChart({ players, scouterss }: RoleDonutChartProps) {
  const data = [
    { name: 'Players', value: players },
    { name: 'Scouters', value: scouterss },
  ];

  return (
    <ResponsiveContainer width="100%" height={220}>
      <PieChart>
        <Pie
          data={data}
          cx="50%"
          cy="50%"
          innerRadius={60}
          outerRadius={85}
          paddingAngle={3}
          dataKey="value"
        >
          {data.map((_, index) => (
            <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
          ))}
        </Pie>
        <Tooltip
          contentStyle={{
            background: '#121B2B',
            border: '1px solid #27314A',
            borderRadius: 10,
            fontSize: 12,
            color: '#E9EEF8',
          }}
        />
        <Legend
          iconType="circle"
          iconSize={8}
          formatter={(v) => (
            <span style={{ color: '#9AA6BD', fontSize: 11, fontWeight: 600 }}>{v}</span>
          )}
        />
      </PieChart>
    </ResponsiveContainer>
  );
}
