import 'package:cloud_firestore/cloud_firestore.dart';
import '../domain/model/app_medicine.dart';
import '../domain/model/app_medicine_intake.dart';
import '../domain/model/app_medicine_stock.dart';
import '../domain/repo/medicine_repo.dart';

class FirestoreMedicineRepo implements MedicineRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 🔹 Updated to filter streams by the specific logged-in farmer/user
  Stream<List<Medicine>> streamMedicines(String userId) {
    return _firestore
        .collection('medicines')
        .where('userId', isEqualTo: userId) // 🔹 Filters out other users' data
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => Medicine.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  @override
  Future<void> addMedicineWithInitialStock({
    required Medicine medicine,
    required MedicineStock initialBatch,
  }) async {
    final batch = _firestore.batch();
    final medicineRef = _firestore.collection('medicines').doc(medicine.medId);
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

    // Assuming your MedicineStock.fromMap takes the document data and the document ID
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
    final batch = _firestore.batch();

    final medRef = _firestore.collection('medicines').doc(medicine.medId);
    final stockCollectionRef = medRef.collection('medicine_stock');
    final currentStockRef = stockCollectionRef.doc(stockDocId);

    // 1. Check if another document already uses the NEW expiry date
    final querySnapshot = await stockCollectionRef
        .where('expiry_date', isEqualTo: updatedStock.expiryDate)
        .get();

    // Filter out the current document we are updating to avoid matching itself
    final existingDocsWithSameDate = querySnapshot.docs.where((doc) => doc.id != stockDocId).toList();

    if (existingDocsWithSameDate.isNotEmpty) {
      // 🔹 MERGE CASE: Another batch with this expiry date exists!
      final targetDoc = existingDocsWithSameDate.first;
      final double existingAmount = (targetDoc.data()['amount'] as num?)?.toDouble() ?? 0.0;

      // Calculate new merged amount: Current existing amount + newly specified amount
      final double mergedAmount = existingAmount + updatedStock.amount;

      // Update the target batch document with the combined amount
      batch.update(targetDoc.reference, {
        'amount': mergedAmount,
      });

      // Delete the old batch document since its contents merged into the other document
      batch.delete(currentStockRef);

    } else {
      // 🔹 NORMAL CASE: No conflicts found. Update the current batch document normally.
      batch.update(currentStockRef, {
        'amount': updatedStock.amount,
        'expiry_date': updatedStock.expiryDate,
      });
    }

    // 2. Re-calculate the grand total stock tally for the main Medicine document
    // Formula: (Current Total - Old Batch Size) + New Batch Size
    final double stockDifference = updatedStock.amount - oldStockAmount;
    final double newTotalStock = medicine.totalStock + stockDifference;

    batch.update(medRef, {
      'name': medicine.name,
      'reorder_level': medicine.reorderLevel,
      'total_stock': newTotalStock,
    });

    // 3. Fire all operations atomically
    await batch.commit();
  }

  @override
  Future<void> addNewStockBatch({
    required Medicine medicine,
    required MedicineStock newStock,
  }) async {
    // 1. Define the paths
    final medRef = _firestore.collection('medicines').doc(medicine.medId);
    final stockCollectionRef = medRef.collection('medicine_stock');

    // 2. Query Firestore to see if this EXACT expiry date already exists
    final querySnapshot = await stockCollectionRef
        .where('expiry_date', isEqualTo: newStock.expiryDate)
        .limit(1)
        .get();

    // Initialize the batch
    final batch = _firestore.batch();

    // 3. Check the results and decide whether to UPDATE or CREATE
    if (querySnapshot.docs.isNotEmpty) {
      // 🔹 MATCH FOUND: Update the existing batch
      final existingDoc = querySnapshot.docs.first;

      // Safely get the existing amount (fallback to 0.0 if null)
      final existingAmount = (existingDoc.data()['amount'] as num?)?.toDouble() ?? 0.0;
      final updatedBatchAmount = existingAmount + newStock.amount;

      batch.update(existingDoc.reference, {
        'amount': updatedBatchAmount,
      });

    } else {
      // 🔹 NO MATCH FOUND: Create a brand new batch document
      final newStockRef = stockCollectionRef.doc();


      batch.set(newStockRef, {
        'amount': newStock.amount,
        'expiry_date': newStock.expiryDate,
        'medicine_id': medicine.medId,
      });
    }

    // 4. Update the main Medicine document's overall total stock
    // (Old Total + New Added Amount)
    final double newTotalStock = medicine.totalStock + newStock.amount;

    batch.update(medRef, {
      'total_stock': newTotalStock,
    });

    // 5. Commit everything to Firestore safely at the same time
    await batch.commit();
  }

  @override
  Future<void> addIntakeAndReduceStock({
    required MedicineIntake intake,
    required MedicineStock selectedStock,
    required String medicineId,
  }) async {
    final double dosageAmount = double.tryParse(intake.dosage) ?? 0.0;
    final double currentStockAmount = double.tryParse(selectedStock.amount.toString()) ?? 0.0;
    final String? stockDocId = selectedStock.id;

    if (dosageAmount <= 0) throw Exception('Dosage must be greater than zero.');
    if (dosageAmount > currentStockAmount) throw Exception('Insufficient stock for this batch.');
    if (stockDocId == null) throw Exception('No stock batch selected.');

    final double newStockAmount = currentStockAmount - dosageAmount;
    final WriteBatch batch = _firestore.batch();

    // A. Create Intake Record
    final intakeRef = _firestore
        .collection('pigs')
        .doc(intake.pigId)
        .collection('medicine_intakes')
        .doc();

    final intakeWithId = intake.copyWith(id: intakeRef.id);
    batch.set(intakeRef, intakeWithId.toMap());

    // B. Reduce Batch Stock OR Delete if empty
    final stockRef = _firestore
        .collection('medicines')
        .doc(medicineId)
        .collection('medicine_stock')
        .doc(stockDocId);

    if (newStockAmount <= 0) {
      // 🔹 If the stock reaches 0, delete the batch completely
      batch.delete(stockRef);
    } else {
      // 🔹 Otherwise, just update the remaining amount
      batch.update(stockRef, {'amount': newStockAmount});
    }

    // C. Reduce Total Parent Medicine Stock
    final parentMedicineRef = _firestore
        .collection('medicines')
        .doc(medicineId);

    batch.update(parentMedicineRef, {
      'total_stock': FieldValue.increment(-dosageAmount)
    });

    // 🔹 D. Update Pig's Last Intake Data (Denormalization)
    final pigRef = _firestore.collection('pigs').doc(intake.pigId);

    batch.update(pigRef, {
      'lastIntakeDate': Timestamp.fromDate(intake.dateTaken),
      'lastIntakeName': intake.medName,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Execute all operations together
    await batch.commit();
  }

}