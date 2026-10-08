// Рўйхатдан ўтиш / профил формаси — СОФ модел ва валидация (тестланади).
// Экран фақат майдонларни кўрсатади; сервер (`restaurantRegister`) ўз
// текширувини барибир қилади (18-қоида).

class RestaurantFormData {
  RestaurantFormData({
    this.name = '',
    this.legalType = 'individual',
    this.description = '',
    this.cuisineTags = const [],
    this.address = '',
    this.contactPhone = '',
    this.lat,
    this.lng,
    this.deliveryMode = 'ava_courier',
    this.pickup = true,
    this.ownFeeType = 'fixed',
    this.ownFeeFixed = 0,
    this.ownFeeBase = 0,
    this.ownFeePerKm = 0,
    this.ownFeeFreeAbove,
    this.ownFeeMaxKm,
    this.prepay = true,
    this.cash = true,
    this.cardNumber = '',
    this.cardHolder = '',
    this.prepTimeMin = 20,
    this.minOrderAmount = 0,
    this.alwaysOpen = true,
    this.openTime = '09:00',
    this.closeTime = '22:00',
  });

  String name;
  String legalType;
  String description;
  List<String> cuisineTags;
  String address;
  String contactPhone;
  double? lat;
  double? lng;

  /// `ava_courier` · `own_courier` · `none`.
  String deliveryMode;
  bool pickup;
  String ownFeeType;
  int ownFeeFixed;
  int ownFeeBase;
  int ownFeePerKm;
  int? ownFeeFreeAbove;
  int? ownFeeMaxKm;
  bool prepay;
  bool cash;
  String cardNumber;
  String cardHolder;
  int prepTimeMin;
  int minOrderAmount;
  bool alwaysOpen;
  String openTime;
  String closeTime;

  static const legalTypes = ['individual', 'yatt', 'llc'];
  static const deliveryModes = ['ava_courier', 'own_courier', 'none'];

  /// Тавсия этиладиган ошхона турлари (PROPOSED; матн калитлари
  /// `restaurants_cuisine_*`). Ресторан 1–3 та танлайди.
  static const cuisineOptions = ['milliy', 'fastfood', 'pizza', 'shashlik', 'sweets', 'drinks', 'home'];

  bool get hasLocation => lat != null && lng != null;

  /// Хато калитлари (`restaurants_m_err_*`). Бўш — форма тўғри.
  List<String> validate() {
    final errs = <String>[];
    if (name.trim().length < 2) errs.add('name');
    if (!hasLocation) errs.add('location');
    if (address.trim().isEmpty) errs.add('address');
    if (!legalTypes.contains(legalType)) errs.add('legal_type');
    if (!deliveryModes.contains(deliveryMode)) errs.add('delivery_mode');
    if (deliveryMode == 'none' && !pickup) errs.add('delivery_or_pickup');
    if (!prepay && !cash) errs.add('payment_method');
    final card = cardNumber.replaceAll(RegExp(r'\D'), '');
    if (prepay && card.isNotEmpty && card.length != 16) errs.add('card_number');
    if (prepTimeMin < 5 || prepTimeMin > 180) errs.add('prep_time');
    if (minOrderAmount < 0) errs.add('min_order');
    if (deliveryMode == 'own_courier' && ownFeeType == 'distance' && ownFeePerKm < 0) errs.add('own_fee');
    if (!alwaysOpen && (!_hhmm(openTime) || !_hhmm(closeTime))) errs.add('hours');
    return errs;
  }

  static bool _hhmm(String s) => RegExp(r'^\d{1,2}:\d{2}$').hasMatch(s.trim());

  Map<String, dynamic> _delivery() => {
        'mode': deliveryMode,
        'pickup': pickup,
        'ownFee': {
          'type': ownFeeType,
          'fixed': ownFeeFixed,
          'base': ownFeeBase,
          'perKm': ownFeePerKm,
          'freeAbove': ownFeeFreeAbove,
          'maxKm': ownFeeMaxKm,
        },
      };

  /// `restaurantRegister` callable учун.
  Map<String, dynamic> toRegisterPayload() => {
        'name': name.trim(),
        'legalType': legalType,
        'description': description.trim(),
        'cuisineTags': cuisineTags.take(3).toList(),
        'address': address.trim(),
        'contactPhone': contactPhone.trim(),
        'lat': lat,
        'lng': lng,
        'delivery': _delivery(),
        'payment': {
          'prepay': prepay,
          'cash': cash,
          'cardNumber': cardNumber.replaceAll(RegExp(r'\D'), ''),
          'cardHolder': cardHolder.trim(),
        },
        'prepTimeMin': prepTimeMin,
        'minOrderAmount': minOrderAmount,
        'openingHours': alwaysOpen ? null : {'open': openTime.trim(), 'close': closeTime.trim()},
      };

  /// Профилни таҳрирлаш учун (`updateProfile`, қоида whitelist'и).
  Map<String, dynamic> toProfilePatch() => {
        'name': name.trim(),
        'description': description.trim(),
        'cuisineTags': cuisineTags.take(3).toList(),
        'address': address.trim(),
        'contactPhone': contactPhone.trim(),
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        'openingHours': alwaysOpen ? null : {'open': openTime.trim(), 'close': closeTime.trim()},
        'prepTimeMin': prepTimeMin,
        'minOrderAmount': minOrderAmount,
        'delivery': _delivery(),
        'payment': {'prepay': prepay, 'cash': cash},
      };
}
