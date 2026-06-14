/// Mobil ilova (APK) — bitta QR, Variant A: to'g'ridan yuklab olish havolasi.
///
/// QR generatorlar uchun: [publicApkUrl]
/// Chop etish: admin login yoki web/downloads/index.html
class AppInstall {
  AppInstall._();

  static const String host = 'https://master-taxi-gurlan.web.app';
  /// Hostingda hozirgi fayl nomi (deploy bilan mos).
  static const String apkFileName = 'master-taxi-gurlan-driver.apk';

  /// Hosting: build/hosting/downloads/ (deploy dan keyin).
  static const String apkPath = '/downloads/$apkFileName';

  static const String publicApkUrl = '$host$apkPath';

  /// Driver APK deep link (`DriverAppLauncher`): `mastertaxidriver://onboard`
  /// query: phone, name, model, color, plate, taxiType (local | marshrut | intercity).

  /// Tashqi QR rasm (admin panel, chop etish sahifasi).
  static String qrImageUrl({int size = 280}) =>
      'https://api.qrserver.com/v1/create-qr-code/?size=${size}x$size&data=${Uri.encodeComponent(publicApkUrl)}';
}
