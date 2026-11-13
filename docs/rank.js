// Weighted alternate ranking. Each stat is z-scored across the season's alternates and oriented so higher = better.
// dir -1 = lower raw value is better. Missing value -> 0 (neutral) for that stat.
const STATS = [
  { key: 'z_score', label: 'Score vs field', note: 'z-score vs own field (mean / stddev)', dir: -1, def: 40 },
  { key: 'robust_z', label: 'Score vs field, robust', note: 'z vs median / MAD, ignores blow-ups', dir: -1, def: 0 },
  { key: 'season_z_score', label: 'To-par vs season', note: 'z of to-par vs every side that season', dir: -1, def: 0 },
  { key: 'strokes_from_qualifying', label: 'Strokes from qualifying', note: '+1 = missed by one', dir: -1, def: 20 },
  { key: 'score_vs_rating', label: 'Score vs course rating', note: 'gross minus course rating', dir: -1, def: 0 },
  { key: 'wagr_strength_z', label: 'WAGR strength of field', note: 'ranked players per side vs the season', dir: 1, def: 25 },
  { key: 'field_strength', label: 'Field scoring strength', note: 'field mean to-par vs season; lower = tougher', dir: -1, def: 15 },
];
const DEFAULTS = Object.fromEntries(STATS.map(s => [s.key, s.def]));

const zScores = rows => {
  const out = rows.map(() => ({}));
  for (const s of STATS) {
    const vals = rows.map(r => r[s.key]).filter(v => v != null);
    const mean = vals.reduce((a, b) => a + b, 0) / (vals.length || 1);
    const sd = Math.sqrt(vals.reduce((a, v) => a + (v - mean) ** 2, 0) / ((vals.length - 1) || 1)) || 1;
    rows.forEach((r, i) => { out[i][s.key] = r[s.key] == null ? 0 : s.dir * (r[s.key] - mean) / sd; });
  }
  return out;
};

// rows: one season's alternates. weights: {key: 0..100}. Returns rows sorted best first with .score and .rank.
const rank = (rows, weights) => {
  const z = zScores(rows);
  const total = STATS.reduce((a, s) => a + (weights[s.key] || 0), 0) || 1;
  return rows
    .map((r, i) => ({ ...r, z: z[i], score: STATS.reduce((a, s) => a + (weights[s.key] || 0) * z[i][s.key], 0) / total }))
    .sort((a, b) => b.score - a.score || (a.alternate_number ?? 9) - (b.alternate_number ?? 9) || a.gross - b.gross)
    .map((r, i) => ({ ...r, rank: i + 1 }));
};

if (typeof module !== 'undefined') module.exports = { STATS, DEFAULTS, zScores, rank };
