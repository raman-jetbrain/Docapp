class DescriptionEntry {
  final String title;
  final String category;
  final double amount;
  final String icon;

  DescriptionEntry({
    required this.title,
    required this.category,
    required this.amount,
    required this.icon,
  });

  factory DescriptionEntry.fromMap(Map<String, dynamic> map) {
    return DescriptionEntry(
      title: map['title'],
      category: map['category'],
      amount: map['amount'],
      icon: map['icon'],
    );
  }
}