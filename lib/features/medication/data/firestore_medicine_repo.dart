import 'package:cloud_firestore/cloud_firestore.dart';
import '../domain/model/app_medicine.dart';
import '../domain/model/app_medicine_intake.dart';
import '../domain/model/app_medicine_stock.dart';
import '../domain/repo/medicine_repo.dart';

class FirestoreMedicineRepo implements MedicineRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Stream<List<Medicine>> streamMedicines(String userId) {
    return _firestore
        .collection('medicines')
        .where('userId', isEqualTo: userId)
    // ignoreMetadataChanges prevents extra reads during local sync
        .snapshots(includeMetadataChanges: false)
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => Medicine.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  @override
  Stream<List<MedicineIntake>> streamUpcomingIntakes(String userId) {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);

    return _firestore
        .collectionGroup('medicine_intakes')
        .where('userId', isEqualTo: userId)
        .where(
      'nextSchedule',
      // 🔹 Compare Timestamp to Timestamp — no more string-comparison bug.
      isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday),
    )
        .orderBy('nextSchedule')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => MedicineIntake.fromMap(doc.data(), documentId: doc.id))
          .toList();
    });
  }

  @override
  Stream<List<MedicineIntake>> streamIntakes(String userId) {
    return _firestore
        .collectionGroup('medicine_intakes')
        .where('userId', isEqualTo: userId)
        .orderBy('dateTaken', descending: true) // server sorts; no Dart sort needed
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => MedicineIntake.fromMap(doc.data(), documentId: doc.id))
          .toList();
    });
  }

  @override
  Future<void> addMedicineWithInitialStock({
    required Medicine medicine,
    required MedicineStock initialBatch,
  }) async {
    final batch = _firestore.batch();
    final medicineRef =
    _firestore.collection('medicines').doc(medicine.medId);
    batch.set(medicineRef, medicine.toMap());

    final stockRef = medicineRef.collection('medicine_stock').doc();
    batch.set(stockRef, initialBatch.toMap());

    await batch.commit();
  }

  @override
  Future<List<MedicineStock>> getMedicineStocks(String medicineId) async {
    final snapshot = await _firestore
        .collection('medicines')
        .doc(medicineId)
        .collection('medicine_stock')
        .get();

    return snapshot.docs
        .map((doc) => MedicineStock.fromMap(doc.data(), doc.id))
        .toList();
  }

  @override
  Future<void> updateMedicineAndStock({
    required Medicine medicine,
    required MedicineStock updatedStock,
    required String stockDocId,
    required double oldStockAmount,
  }) async {
    final medRef = _firestore.collection('medicines').doc(medicine.medId);
    final stockCollectionRef = medRef.collection('medicine_stock');
    final currentStockRef = stockCollectionRef.doc(stockDocId);

    final batch = _firestore.batch();

    // 1. ZERO STOCK CASE: Delete the batch document entirely
    if (updatedStock.amount == 0) {
      batch.delete(currentStockRef);
    }
    // 2. NORMAL / MERGE CASES
    else {
      // FIX: removed cache-first attempt — a Source.cache query that finds
      // nothing returns an empty snapshot (it does NOT throw), so the old
      // try/catch silently treated "not in cache" as "doesn't exist",
      // risking duplicate batches with the same expiry date.
      final QuerySnapshot querySnapshot = await stockCollectionRef
          .where('expiryDate', isEqualTo: updatedStock.expiryDate)
          .limit(1)
          .get();

      final existingDocsWithSameDate =
      querySnapshot.docs.where((doc) => doc.id != stockDocId).toList();

      if (existingDocsWithSameDate.isNotEmpty) {
        // Merge Case
        final targetDoc = existingDocsWithSameDate.first;
        final docData = targetDoc.data() as Map<String, dynamic>?;
        final double existingAmount =
            (docData?['amount'] as num?)?.toDouble() ?? 0.0;
        final double mergedAmount = existingAmount + updatedStock.amount;

        batch.update(targetDoc.reference, {'amount': mergedAmount});
        batch.delete(currentStockRef);
      } else {
        // Normal Case
        batch.update(currentStockRef, {
          'amount': updatedStock.amount,
          'expiryDate': updatedStock.expiryDate,
        });
      }
    }

    // Math works out automatically: (Current Total - Old Batch Size) + 0 = Correct new total
    final double stockDifference = updatedStock.amount - oldStockAmount;
    final double newTotalStock = medicine.totalStock + stockDifference;

    batch.update(medRef, {
      'name': medicine.name,
      'reorderLevel': medicine.reorderLevel,
      'totalStock': newTotalStock,
    });

    await batch.commit();
  }

  @override
  Future<void> addNewStockBatch({
    required Medicine medicine,
    required MedicineStock newStock,
  }) async {
    final medRef = _firestore.collection('medicines').doc(medicine.medId);
    final stockCollectionRef = medRef.collection('medicine_stock');

    final querySnapshot = await stockCollectionRef
        .where('expiryDate', isEqualTo: newStock.expiryDate)
        .limit(1)
        .get();

    final batch = _firestore.batch();

    if (querySnapshot.docs.isNotEmpty) {
      // MATCH FOUND: Merge into existing batch
      final existingDoc = querySnapshot.docs.first;
      final existingAmount =
          (existingDoc.data()['amount'] as num?)?.toDouble() ?? 0.0;
      final updatedBatchAmount = existingAmount + newStock.amount;

      batch.update(existingDoc.reference, {'amount': updatedBatchAmount});
    } else {
      // NO MATCH: Create a new batch document
      final newStockRef = stockCollectionRef.doc();
      batch.set(newStockRef, {
        'amount': newStock.amount,
        'expiryDate': newStock.expiryDate,
        'medicineId': medicine.medId,
      });
    }

    final double newTotalStock = medicine.totalStock + newStock.amount;
    batch.update(medRef, {'totalStock': newTotalStock});

    await batch.commit();
  }

  @override
  Future<void> addIntakeAndReduceStock({
    required MedicineIntake intake,
    required MedicineStock selectedStock,
    required String medicineId,
  }) async {
    final double dosageAmount = double.tryParse(intake.dosage) ?? 0.0;
    final double currentStockAmount =
        double.tryParse(selectedStock.amount.toString()) ?? 0.0;
    final String? stockDocId = selectedStock.id;

    if (dosageAmount <= 0) {
      throw Exception('Dosage must be greater than zero.');
    }
    if (dosageAmount > currentStockAmount) {
      throw Exception('Insufficient stock for this batch.');
    }
    if (stockDocId == null) {
      throw Exception('No stock batch selected.');
    }

    final double newStockAmount = currentStockAmount - dosageAmount;
    final WriteBatch batch = _firestore.batch();

    // A. Create Intake Record
    final intakeRef = _firestore
        .collection('pigs')
        .doc(intake.pigId)
        .collection('medicine_intakes')
        .doc();

    final intakeWithData = intake.copyWith(id: intakeRef.id);
    batch.set(intakeRef, intakeWithData.toMap());

    // B. Reduce Batch Stock OR Delete if empty
    final stockRef = _firestore
        .collection('medicines')
        .doc(medicineId)
        .collection('medicine_stock')
        .doc(stockDocId);

    if (newStockAmount <= 0) {
      batch.delete(stockRef);
    } else {
      batch.update(stockRef, {'amount': newStockAmount});
    }

    // C. Reduce Total Parent Medicine Stock
    final parentMedicineRef =
    _firestore.collection('medicines').doc(medicineId);

    batch.update(parentMedicineRef, {
      'totalStock': FieldValue.increment(-dosageAmount),
    });

    // D. Update Pig's Last Intake Data (Denormalization)
    final pigRef = _firestore.collection('pigs').doc(intake.pigId);

    batch.update(pigRef, {
      'lastIntakeDate': Timestamp.fromDate(intake.dateTaken),
      'lastIntakeName': intake.medName,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }
}