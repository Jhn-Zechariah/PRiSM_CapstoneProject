class AppPig {
  final String name;
  final String breed;
  final String birthdate; // Added birthdate
  final String sex;
  final String weight;
  final String note;

  AppPig({
    required this.name,
    required this.breed,
    required this.birthdate,
    required this.sex,
    required this.weight,
    required this.note,
  });

  // Convert AppPig --> JSON
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'breed': breed,
      'birthdate': birthdate,
      'sex': sex,
      'weight': weight,
      'note': note,
    };
  }

  // Convert JSON --> AppPig
  factory AppPig.fromJson(Map<String, dynamic> json) {
    return AppPig(
      name: json['name'] as String? ?? 'Unknown Pig',
      breed: json['breed'] as String? ?? 'Unknown Breed',
      birthdate: json['birthdate'] as String? ?? 'Unknown Date',
      sex: json['sex'] as String? ?? 'Unknown',
      weight: json['weight'] as String? ?? '0',
      note: json['note'] as String? ?? '',
    );
  }
}