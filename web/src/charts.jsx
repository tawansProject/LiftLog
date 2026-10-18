// Small SVG charts, sized by viewBox so they scale to the phone width.

export function LineChart({ points, height = 160, format = (v) => Math.round(v), color = '#ffffff', xLabel = (x) => x }) {
  const W = 340, H = height, L = 36, R = 8, T = 10, B = 22;
  if (!points.length) return <div class="empty small">No data in this range yet.</div>;
  const xs = points.map((p) => p.x), ys = points.map((p) => p.y);
  const x0 = Math.min(...xs), x1 = Math.max(...xs);
  let y0 = Math.min(...ys), y1 = Math.max(...ys);
  if (y0 === y1) { y0 = Math.max(0, y0 - 1); y1 = y1 + 1; }
  const pad = (y1 - y0) * 0.1; y0 = Math.max(0, y0 - pad); y1 += pad;
  const sx = (x) => (x1 === x0 ? (L + W - R) / 2 : L + ((x - x0) / (x1 - x0)) * (W - L - R));
  const sy = (y) => T + (1 - (y - y0) / (y1 - y0)) * (H - T - B);
  const d = points.map((p, i) => `${i ? 'L' : 'M'}${sx(p.x).toFixed(1)},${sy(p.y).toFixed(1)}`).join(' ');
  const area = `${d} L${sx(points[points.length - 1].x).toFixed(1)},${H - B} L${sx(points[0].x).toFixed(1)},${H - B} Z`;
  const ticks = [y0, (y0 + y1) / 2, y1];
  const id = `g${Math.random().toString(36).slice(2, 8)}`;
  return (
    <svg class="chart" viewBox={`0 0 ${W} ${H}`} role="img">
      <defs><linearGradient id={id} x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color={color} stop-opacity="0.28" /><stop offset="1" stop-color={color} stop-opacity="0" /></linearGradient></defs>
      {ticks.map((t) => <g key={t}><line x1={L} x2={W - R} y1={sy(t)} y2={sy(t)} stroke="rgba(255,255,255,0.08)" /><text x={L - 4} y={sy(t) + 3} text-anchor="end">{format(t)}</text></g>)}
      <path d={area} fill={`url(#${id})`} />
      <path d={d} fill="none" stroke={color} stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round" />
      {points.map((p) => <circle key={p.x} cx={sx(p.x)} cy={sy(p.y)} r={points.length > 30 ? 1.5 : 3} fill={color} />)}
      <text x={L} y={H - 6}>{xLabel(x0)}</text>
      {x1 !== x0 && <text x={W - R} y={H - 6} text-anchor="end">{xLabel(x1)}</text>}
    </svg>
  );
}

export function BarChart({ bars, height = 120, color = '#ffffff' }) {
  const W = 340, H = height, B = 18, T = 6;
  const max = Math.max(1, ...bars.map((b) => b.value));
  const bw = W / bars.length;
  return (
    <svg class="chart" viewBox={`0 0 ${W} ${H}`} role="img">
      {bars.map((b, i) => {
        const h = (b.value / max) * (H - B - T);
        return (
          <g key={i}>
            <rect x={i * bw + bw * 0.18} y={H - B - Math.max(h, b.value ? 2 : 0)} width={bw * 0.64} height={Math.max(h, b.value ? 2 : 0)} rx="3" fill={b.value ? color : 'rgba(255,255,255,0.1)'} />
            {b.label && <text x={i * bw + bw / 2} y={H - 5} text-anchor="middle">{b.label}</text>}
          </g>
        );
      })}
      {bars.every((b) => !b.value) && <line x1="0" x2={W} y1={H - B} y2={H - B} stroke="rgba(255,255,255,0.1)" />}
    </svg>
  );
}
