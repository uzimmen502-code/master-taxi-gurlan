const fs   = require('fs');
const path = require('path');

const PROJECTS = [
  { name: 'master_taxi_gurlan',  pkg: 'com.example.master_taxi_gurlan'  },
  { name: 'master_taxi_driver',  pkg: 'com.example.master_taxi_gurlan_driver' },
  { name: 'master_taxi_courier', pkg: 'com.example.master_taxi_courier' },
];

const ROOT = path.join(__dirname, '..');
let passed = 0;
let failed = 0;

function check(label, ok, detail = '') {
  if (ok) {
    console.log(`  ✅ ${label}`);
    passed++;
  } else {
    console.log(`  ❌ ${label}${detail ? ' — ' + detail : ''}`);
    failed++;
  }
}

for (const project of PROJECTS) {
  console.log(`\n📱 ${project.name} (${project.pkg})`);
  console.log('─'.repeat(60));

  const base = path.join(ROOT, '..', project.name);

  // 1. google-services.json mavjudligi
  const gsJson = path.join(base, 'android', 'app', 'google-services.json');
  const gsExists = fs.existsSync(gsJson);
  check('google-services.json mavjud', gsExists);

  if (gsExists) {
    const gs = JSON.parse(fs.readFileSync(gsJson, 'utf8'));

    // 2. project_id to'g'rimi
    const projectId = gs.project_info?.project_id;
    check('project_id = master-taxi-gurlan',
      projectId === 'master-taxi-gurlan',
      `topilgan: ${projectId}`);

    // 3. Package name mos keladi
    const client = gs.client?.find(
      c => c.client_info?.android_client_info?.package_name === project.pkg);
    check(`package_name = ${project.pkg}`, !!client);

    // 4. SHA-1 qo'shilganmi (certificate_hash)
    const certs = client?.client_info?.android_client_info
      ?.certificate_hash ?? [];
    // Newer format
    const services = client?.services;
    // Check oauth_client for sha cert or check via different path
    // google-services.json da SHA directly ko'rinmaydi — Firebase Console'dan olinadi
    // Shuning uchun faqat client mavjudligini tekshiramiz
    check('Client Firebase\'da ro\'yxatdan o\'tgan', !!client);
  }

  // 5. AndroidManifest.xml - INTERNET permission
  const manifest = path.join(base, 'android', 'app', 'src', 'main',
      'AndroidManifest.xml');
  if (fs.existsSync(manifest)) {
    const content = fs.readFileSync(manifest, 'utf8');
    check('INTERNET permission', content.includes('INTERNET'));
    check('Maps API key meta-data',
      content.includes('com.google.android.geo.API_KEY'));
    check('flutterEmbedding v2',
      content.includes('flutterEmbedding'));
  }

  // 6. pubspec.yaml - firebase_auth mavjud
  const pubspec = path.join(base, 'pubspec.yaml');
  if (fs.existsSync(pubspec)) {
    const content = fs.readFileSync(pubspec, 'utf8');
    check('firebase_auth dependency', content.includes('firebase_auth'));
    check('firebase_core dependency', content.includes('firebase_core'));
    check('google_maps_flutter dependency',
      content.includes('google_maps_flutter'));
  }

  // 7. firebase_options.dart mavjud
  const opts = path.join(base, 'lib', 'firebase_options.dart');
  check('firebase_options.dart mavjud', fs.existsSync(opts));

  // 8. config.dart - placeholder tekshiruvi
  const config = path.join(base, 'lib', 'config.dart');
  if (fs.existsSync(config)) {
    const content = fs.readFileSync(config, 'utf8');
    const hasPlaceholder = content.includes('PLACEHOLDER');
    check('Maps API key o\'rnatilgan (placeholder yo\'q)', !hasPlaceholder,
      hasPlaceholder ? 'MAPS_API_KEY_PLACEHOLDER hali almashtirilmagan!' : '');
  }
}

// Production checklist
console.log('\n' + '═'.repeat(60));
console.log('📋 PRODUCTION CHECKLIST (qo\'lda tekshirish):');
console.log('═'.repeat(60));
const checklist = [
  'Firebase Console → Auth → Sign-in method → Phone → ENABLED',
  'Har 3 app uchun SHA-1 Firebase Console\'da ro\'yxatdan o\'tgan',
  'Har 3 app uchun SHA-256 Firebase Console\'da ro\'yxatdan o\'tgan',
  'Google Cloud → APIs → Identity Toolkit API → ENABLED',
  'Google Cloud → APIs → SafetyNet API → ENABLED',
  'Google Cloud → APIs → Play Integrity API → ENABLED',
  'Release keystore SHA-1/SHA-256 ham Firebase\'ga qo\'shilgan',
  'google-services.json har build\'dan keyin yangilangan',
  'Firebase Auth → Settings → Authorized domains to\'g\'ri',
  'SMS kvotasi (Firebase Spark: 10/kun, Blaze: ko\'proq)',
];
checklist.forEach((item, i) =>
  console.log(`  ${i + 1}. [ ] ${item}`));

console.log('\n' + '═'.repeat(60));
console.log(`NATIJA: ${passed} ✅  ${failed} ❌`);
if (failed === 0) {
  console.log('🎉 Barcha tekshiruvlar o\'tdi!');
} else {
  console.log('⚠️  Yuqoridagi xatolarni tuzating.');
}
console.log('═'.repeat(60));
