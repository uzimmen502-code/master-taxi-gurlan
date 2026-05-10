class BreadModel {
  final String id;
  final String name;
  final String description;
  final double price;
  final String imageUrl;
  final bool isBakingService; // true = ёпиб бериш, false = тайёр нон
  final double flourPerUnit; // 1 дона учун ун (кг)
  final double milkPerUnit;  // 1 дона учун сут (литр)

  BreadModel({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.imageUrl,
    required this.isBakingService,
    this.flourPerUnit = 0.5,
    this.milkPerUnit = 0.1,
  });

  // Ёпиб бериш хизмати учун масаллиқ ҳисоби
  Map<String, double> getIngredients(int quantity) {
    return {
      'flour': flourPerUnit * quantity,
      'milk': milkPerUnit * quantity,
    };
  }
}