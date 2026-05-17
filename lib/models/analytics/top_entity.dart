/// Top-N рўйхатидаги битта элемент — ҳайдовчи, маҳсулот, манзил ва ҳ.к.
class TopEntity {
  const TopEntity({
    required this.id,
    required this.label,
    required this.value,
    this.subtitle,
    this.icon,
  });

  final String id;
  final String label;
  final num value;
  final String? subtitle;
  final String? icon;
}
