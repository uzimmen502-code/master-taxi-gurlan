import 'bread_model.dart';

class CartItem {
  final BreadModel bread;
  int quantity;
  final bool useOwnIngredients; // true = ўз масаллиғи, false = нонвойхонадан

  CartItem({
    required this.bread,
    required this.quantity,
    this.useOwnIngredients = true,
  });

  double get totalPrice {
    if (bread.isBakingService) {
      return bread.price * quantity;
    } else {
      return bread.price * quantity;
    }
  }

  Map<String, double> get requiredIngredients {
    if (bread.isBakingService && useOwnIngredients) {
      return bread.getIngredients(quantity);
    }
    return {};
  }
}