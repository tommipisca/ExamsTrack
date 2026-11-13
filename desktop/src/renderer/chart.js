// Grafico dell'andamento della media: una linea monotona con un punto per esame.
// Passando sopra con il mouse si vede il dettaglio dell'esame più vicino.

import { averageText } from '../core/logic.js';
import { italianMonthYear, italianShort } from '../core/calendar.js';
import { C, esc } from './components.js';

const PAD = { left: 34, right: 14, top: 16, bottom: 26 };

/** Tangenti di Fritsch–Carlson: la curva non supera mai i punti (come .monotone di Swift Charts). */
function monotonePath(points) {
  if (points.length < 2) return '';
  const n = points.length;
  const dx = [];
  const slope = [];
  for (let i = 0; i < n - 1; i++) {
    dx.push(points[i + 1].x - points[i].x);
    // Pendenza nulla per i tratti verticali, così non deformano le curve vicine.
    slope.push(dx[i] < 2 ? 0 : (points[i + 1].y - points[i].y) / dx[i]);
  }
  const tangent = [slope[0]];
  for (let i = 1; i < n - 1; i++) {
    tangent.push(slope[i - 1] * slope[i] <= 0 ? 0 : (slope[i - 1] + slope[i]) / 2);
  }
  tangent.push(slope[n - 2]);
  for (let i = 0; i < n - 1; i++) {
    if (slope[i] === 0) {
      tangent[i] = 0;
      tangent[i + 1] = 0;
      continue;
    }
    const a = tangent[i] / slope[i];
    const b = tangent[i + 1] / slope[i];
    const h = a * a + b * b;
    if (h > 9) {
      const t = 3 / Math.sqrt(h);
      tangent[i] = t * a * slope[i];
      tangent[i + 1] = t * b * slope[i];
    }
  }
  let d = `M${points[0].x},${points[0].y}`;
  for (let i = 0; i < n - 1; i++) {
    // Esami nello stesso giorno (o quasi): un tratto dritto, senza anse.
    if (dx[i] < 2) {
      d += ` L${points[i + 1].x},${points[i + 1].y}`;
      continue;
    }
    const third = dx[i] / 3;
    d += ` C${points[i].x + third},${points[i].y + tangent[i] * third} ${points[i + 1].x - third},${points[i + 1].y - tangent[i + 1] * third} ${points[i + 1].x},${points[i + 1].y}`;
  }
  return d;
}

export function trendChart(trend, height = 220) {
  const width = 640;
  const values = trend.map((point) => point.average);
  const low = Math.max(18, Math.floor(Math.min(...values) - 1));
  const high = Math.max(Math.min(30, Math.ceil(Math.max(...values) + 1)), low + 1);
  const times = trend.map((point) => new Date(point.date).getTime());
  const first = Math.min(...times);
  const span = Math.max(Math.max(...times) - first, 1);
  const plotW = width - PAD.left - PAD.right;
  const plotH = height - PAD.top - PAD.bottom;
  const x = (time) => PAD.left + ((time - first) / span) * plotW;
  const y = (value) => PAD.top + (1 - (value - low) / (high - low)) * plotH;
  const points = trend.map((point, index) => ({ x: x(times[index]), y: y(point.average), point }));

  const step = Math.max(1, Math.ceil((high - low) / 4));
  const grid = [];
  for (let value = low; value <= high; value += step) {
    grid.push(`<line x1="${PAD.left}" x2="${width - PAD.right}" y1="${y(value)}" y2="${y(value)}" stroke="${C.stroke}" stroke-width="0.6"/>
      <text x="${PAD.left - 8}" y="${y(value) + 4}" text-anchor="end" class="axis">${value}</text>`);
  }
  const labelCount = Math.min(4, trend.length);
  const labels = [];
  for (let i = 0; i < labelCount; i++) {
    const time = first + (span * i) / Math.max(labelCount - 1, 1);
    const anchor = i === 0 ? 'start' : i === labelCount - 1 ? 'end' : 'middle';
    labels.push(`<text x="${x(time)}" y="${height - 6}" text-anchor="${anchor}" class="axis">${italianMonthYear(new Date(time))}</text>`);
  }

  const dots = points.map(({ x: px, y: py }) => `<circle cx="${px}" cy="${py}" r="4" fill="${C.chartLine}" stroke="${C.surface}" stroke-width="2"/>`).join('');
  const data = esc(JSON.stringify(points.map(({ x: px, y: py, point }) => ({
    x: px, y: py, name: point.examName, line: `Voto ${point.grade} · media ${averageText(point.average)} · ${italianShort(point.date)}`,
  }))));

  return `<div class="chart" data-chart="${data}">
    <svg viewBox="0 0 ${width} ${height}">
      ${grid.join('')}${labels.join('')}
      <path d="${monotonePath(points)}" fill="none" stroke="${C.chartLine}" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" vector-effect="non-scaling-stroke"/>
      <line class="chart-rule" x1="0" x2="0" y1="${PAD.top}" y2="${height - PAD.bottom}" stroke="${C.textSecondary}" stroke-width="1" vector-effect="non-scaling-stroke" visibility="hidden"/>
      ${dots}
    </svg>
    <div class="chart-tip" hidden></div>
  </div>`;
}

/** Mini linea della media, senza assi, per il riepilogo della carriera. */
export function sparkline(trend, width = 84, height = 40) {
  const values = trend.map((point) => point.average);
  const low = Math.min(...values) - 0.5;
  const high = Math.max(...values) + 0.5;
  const d = values.map((value, index) => {
    const px = (width * index) / Math.max(values.length - 1, 1);
    const py = height * (1 - (value - low) / Math.max(high - low, 0.001));
    return `${index === 0 ? 'M' : 'L'}${px.toFixed(1)},${py.toFixed(1)}`;
  }).join(' ');
  return `<svg class="sparkline" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}"><path d="${d}" fill="none" stroke="${C.chartLine}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
}

/** Il dettaglio del punto più vicino al mouse. */
export function attachChartHover(root) {
  for (const chart of root.querySelectorAll('.chart')) {
    const points = JSON.parse(chart.dataset.chart);
    const svg = chart.querySelector('svg');
    const rule = chart.querySelector('.chart-rule');
    const tip = chart.querySelector('.chart-tip');
    const viewWidth = svg.viewBox.baseVal.width;
    svg.addEventListener('mousemove', (event) => {
      const box = svg.getBoundingClientRect();
      const vx = ((event.clientX - box.left) / box.width) * viewWidth;
      const nearest = points.reduce((best, point) => (Math.abs(point.x - vx) < Math.abs(best.x - vx) ? point : best));
      rule.setAttribute('x1', nearest.x);
      rule.setAttribute('x2', nearest.x);
      rule.setAttribute('visibility', 'visible');
      tip.hidden = false;
      tip.innerHTML = `<strong>${esc(nearest.name)}</strong><span>${esc(nearest.line)}</span>`;
      const left = (nearest.x / viewWidth) * box.width;
      tip.style.left = `${Math.min(Math.max(left - tip.offsetWidth / 2, 0), box.width - tip.offsetWidth)}px`;
    });
    svg.addEventListener('mouseleave', () => {
      rule.setAttribute('visibility', 'hidden');
      tip.hidden = true;
    });
  }
}
