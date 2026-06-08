class MedicineStock {
  final String? id;
  final String medicineId;
  final String expiryDate;
  final double amount;

  MedicineStock({
    this.id,
    required this.medicineId,
    required this.expiryDate,
    required this.amount,
  });

  // Convert to Map for saving to Firestore
  Map<String, dynamic> toMap() {
    return {
      'medicineId': medicineId,
      'expiryDate': expiryDate,
      'amount': amount,
    };
  }

  // Create a MedicineStock object from a Firestore Map
  factory MedicineStock.fromMap(Map<String, dynamic> map, String documentId) {
    return MedicineStock(
      id: documentId,
      medicineId: map['medicineId'] ?? '',
      expiryDate: map['expiryDate'] ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
    );
  }

// 🔹 Creates a copy of the MedicineStock with updated fields
  MedicineStock copyWith({
    String? id, // Or whatever you named your document ID field
    String? medicineId,
    String? expiryDate,
    double? amount,
  }) {
    return MedicineStock(
      id: id ?? this.id,
      medicineId: medicineId ?? this.medicineId,
      expiryDate: expiryDate ?? this.expiryDate,
      amount: amount ?? this.amount,
    );
  }
}