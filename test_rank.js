// node test_rank.js
const assert = require('assert');
const { rank } = require('./docs/rank.js');

const row = (side_id, z_score, wagr_strength_z, gross = 66) => ({ side_id, gross, z_score, wagr_strength_z });
const rows = [row('a', -2, 0), row('b', -1, 2), row('c', 0, null)];
const ids = r => r.map(x => x.side_id).join('');

assert.strictEqual(ids(rank(rows, { z_score: 100 })), 'abc');               // lower z ranks higher
assert.strictEqual(ids(rank(rows, { wagr_strength_z: 100 })), 'bca');       // WAGR: higher is better; missing (c) = neutral 0, above a's below-mean field
assert.strictEqual(rank(rows, { wagr_strength_z: 100 })[1].z.wagr_strength_z, 0);  // c's null stays 0
assert.ok(rank(rows, {}).every(r => r.score === 0));                         // zero weights -> all equal
assert.deepStrictEqual(rank(rows, { z_score: 50 }).map(r => r.score), rank(rows, { z_score: 100 }).map(r => r.score)); // normalized
console.log('rank ok');
