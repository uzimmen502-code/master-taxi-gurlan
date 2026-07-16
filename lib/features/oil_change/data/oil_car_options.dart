/// Мой setup / онбординг учун умумий автотўлдирув рўйхатлари.
class OilCarOptions {
  OilCarOptions._();

  static const brands = ['Chevrolet', 'Daewoo', 'Kia', 'Hyundai'];
  static const models = [
    'Damas',
    'Matiz',
    'Nexia',
    'Nexia 3',
    'Spark',
    'Cobalt',
    'Gentra',
    'Lacetti',
    'Malibu',
    'Tracker',
  ];
  static const years = [2024, 2023, 2022, 2021, 2020, 2019, 2018];
  static const engines = ['1.2', '1.5', '1.6', '1.8'];

  // Kalitlar (label'lar l10n orqali: oil_fuel_${key} / oil_usage_${key}).
  static const fuels = <String>['petrol', 'cng', 'lpg'];
  static const usages = <String>['personal', 'taxi', 'corp', 'dust', 'long'];
}
