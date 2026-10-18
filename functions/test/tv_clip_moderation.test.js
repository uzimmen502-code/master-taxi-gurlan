/**
 * TV клип модерацияси: «тасдиқланди» хабари қачон юборилади —
 * `functions/tv_clip_moderation.js`.
 *
 * Ишлатиш (functions/ ичидан):
 *   npm run test:tv-clip-moderation
 */
'use strict';
const {tvClipBecameApproved} = require('../tv_clip_moderation');

const results = [];
function check(name, pass) {
  results.push({name, pass});
  console.log(`${pass ? '  ok  ' : ' FAIL '} ${name}`);
}

// Ижобий: қўлда модерацияда админ тасдиқлади.
check('pending → active: хабар бор',
    tvClipBecameApproved({status: 'pending'}, {status: 'active'}) === true);
check('product/service/news ҳам',
    ['product', 'service', 'news'].every((category) => tvClipBecameApproved(
        {status: 'pending', category}, {status: 'active', category}) === true));

// Салбий.
check('пуллик реклама (ad) — йўқ',
    tvClipBecameApproved({status: 'pending', category: 'ad'},
        {status: 'active', category: 'ad'}) === false);
check('active → active (бошқа майдон ўзгарди) — йўқ',
    tvClipBecameApproved({status: 'active'}, {status: 'active'}) === false);
check('pending → pending — йўқ',
    tvClipBecameApproved({status: 'pending'}, {status: 'pending'}) === false);
check('pending → blocked — йўқ (бу onTvClipRejected)',
    tvClipBecameApproved({status: 'pending'}, {status: 'blocked'}) === false);
check('blocked → active (админ тиклади) — йўқ',
    tvClipBecameApproved({status: 'blocked'}, {status: 'active'}) === false);
check('expired → active — йўқ',
    tvClipBecameApproved({status: 'expired'}, {status: 'active'}) === false);

// Чегара: бўш/етишмайдиган маълумот йиқилмайди.
check('undefined before/after — йиқилмайди',
    tvClipBecameApproved(undefined, undefined) === false);
check('before статуссиз (эски ҳужжат) — йўқ',
    tvClipBecameApproved({}, {status: 'active'}) === false);

const failed = results.filter((r) => !r.pass);
console.log(`\n${results.length - failed.length}/${results.length} passed`);
process.exit(failed.length ? 1 : 0);
