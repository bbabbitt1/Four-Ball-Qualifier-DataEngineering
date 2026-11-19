// node test_rank.js
const assert = require('assert');
const { rank, rankSites, alternateOrder } = require('./docs/rank.js');

const row = (side_id, z_score, wagr_strength_z, gross = 66) => ({ side_id, gross, z_score, wagr_strength_z });
const rows = [row('a', -2, 0), row('b', -1, 2), row('c', 0, null)];
const ids = r => r.map(x => x.side_id).join('');

assert.strictEqual(ids(rank(rows, { z_score: 100 })), 'abc');               // lower z ranks higher
assert.strictEqual(ids(rank(rows, { wagr_strength_z: 100 })), 'bca');       // WAGR: higher is better; missing (c) = neutral 0, above a's below-mean field
assert.strictEqual(rank(rows, { wagr_strength_z: 100 })[1].z.wagr_strength_z, 0);  // c's null stays 0
assert.ok(rank(rows, {}).every(r => r.score === 0));                         // zero weights -> all equal
assert.deepStrictEqual(rank(rows, { z_score: 50 }).map(r => r.score), rank(rows, { z_score: 100 }).map(r => r.score)); // normalized
const site = (qualifier_key, sides_per_spot, wagr_strength_z) => ({ qualifier_key, sides_per_spot, wagr_strength_z });
const sites = [site('a', 20, -1), site('b', 15, 2), site('c', 10, null)];
const keys = r => r.map(x => x.qualifier_key).join('');
assert.strictEqual(keys(rankSites(sites, 0)), 'abc');     // pure sides per spot
assert.strictEqual(keys(rankSites(sites, 100)), 'bca');   // pure SoF; missing (c) = neutral
assert.strictEqual(rankSites(sites, 0)[0].rank, 1);
const order = alternateOrder(rankSites(sites, 0), { a: [{ side_id: 'a1' }, { side_id: 'a2' }], b: [{ side_id: 'b1' }], c: [{ side_id: 'c1' }, { side_id: 'c2' }] });
assert.strictEqual(order.map(r => r.side_id).join(), 'a1,b1,c1,a2,c2');   // all 1sts by site rank, then 2nds; b has no 2nd
assert.deepStrictEqual(order.map(r => r.slot), [1, 1, 1, 2, 2]);
console.log('rank ok');
