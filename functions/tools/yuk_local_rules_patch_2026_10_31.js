// yuk_local_drivers rules патчи (аудит 2026-10-31: Y-2 телефон, Y-3 isDemo, O-2 турлар/калитлар,
// O-7 ўқиш фақат телефон билан кирганларга). ЖОНЛИ ruleset матнига қўлланади (hosting
// lineage'даги firestore.rules эскирган бўлиши мумкин — reference-firebase-rules-api).
//   node yuk_local_rules_patch.js <live.rules> <out.rules>
'use strict';
const fs = require('fs');
const [, , inPath, outPath] = process.argv;
if (!inPath || !outPath) throw new Error('usage: <in> <out>');
const raw = fs.readFileSync(inPath, 'utf8');
// Жонли матн CRLF бўлиши мумкин — LF да ишлаб, охирида аслига қайтарилади.
const crlf = raw.includes('\r\n');
const src = crlf ? raw.replace(/\r\n/g, '\n') : raw;

const START = '    // ─── Туман ичида юк (live машиналар) ───';
const END_MARK = '    // Биринчи эълон TTL (60 кун) учун тарихий белги.\n';
const a = src.indexOf(START);
const b = src.indexOf(END_MARK);
if (a < 0 || b < 0 || b < a) throw new Error(`anchors not found: start=${a} end=${b}`);
const old = src.slice(a, b + END_MARK.length);
if (!old.includes('match /yuk_local_drivers/{driverId}')) throw new Error('unexpected block');

// Ҳажм чеклови (256 KiB, жонли файл тўла) — ихчам ёзилган; изоҳ битта қатор.
const NEW = `    // Туман ичида юк. Муддат/isDemo/рейтинг — сервер (functions/yuk_local.js), аудит 2026-10-31.
    function ykK() {
      return ['ownerName','phone','vehicleType','plateNumber','capacityKg','capacityTons','bodyLengthM','bodyWidthM','bodyHeightM','acceptRadiusKm','loadStatus','lat','lng','locationLabel','workStartMinutes','workEndMinutes','updatedAt','regionId','districtId','serviceAreaId','online','lastOnlineAt'];
    }
    function ykD(d) {
      let me = userDocIdFromPhoneToken();
      return me != '' && d.vehicleType is string && d.ownerName is string && d.lat is number && d.lng is number
        && d.get('workStartMinutes', 0) is int && d.get('workEndMinutes', 0) is int && d.get('districtId', '') is string
        && d.get('loadStatus', 'empty') in ['empty', 'busy', 'offline']
        && d.phone is string && phoneDocIdsMatch(me, d.phone.replace('[^0-9]', ''));
    }
    function yukLocalDriverCreateOk() {
      let d = request.resource.data;
      return ykD(d) && phoneDocIdsMatch(userDocIdFromPhoneToken(), d.ownerId)
        && d.keys().hasOnly(ykK().concat(['ownerId', 'rating', 'completedLoads', 'createdAt', 'expiresAt']))
        && d.loadStatus is string && d.workStartMinutes is int && d.workEndMinutes is int
        && d.get('rating', 0) == 0 && d.get('completedLoads', 0) == 0
        && (!('expiresAt' in d) || (d.expiresAt is timestamp && d.expiresAt <= request.time + duration.value(65, 'd')));
    }
    function yukLocalDriverOwnerUpdateOk() {
      return ykD(request.resource.data) && phoneDocIdsMatch(userDocIdFromPhoneToken(), resource.data.ownerId)
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly(ykK());
    }
    match /yuk_local_drivers/{driverId} {
      allow read: if isAdmin() || userDocIdFromPhoneToken() != '';
      allow create: if yukLocalDriverCreateOk();
      allow update: if isAdmin() || yukLocalDriverOwnerUpdateOk();
      allow delete: if isAdmin() || (isAuth() && phoneDocIdsMatch(userDocIdFromPhoneToken(), resource.data.ownerId));
    }
`;
const outLf = src.slice(0, a) + NEW + src.slice(b + END_MARK.length);
const out = crlf ? outLf.replace(/\n/g, '\r\n') : outLf;
fs.writeFileSync(outPath, out, 'utf8');
const bytes = Buffer.byteLength(out, 'utf8');
console.log(JSON.stringify({ inBytes: Buffer.byteLength(src, 'utf8'), outBytes: bytes, limit: 262144, left: 262144 - bytes, oldBlock: Buffer.byteLength(old, 'utf8'), newBlock: Buffer.byteLength(NEW, 'utf8') }));
