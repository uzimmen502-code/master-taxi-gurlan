import 'package:cloud_functions/cloud_functions.dart';

/// Auth / device-binding callables — Europe (Firestore `eur3` ga yaqin).
class AvaFunctions {
  AvaFunctions._();

  static const authRegion = 'europe-west1';

  static FirebaseFunctions get auth =>
      FirebaseFunctions.instanceFor(region: authRegion);
}
