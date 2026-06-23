import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../domain/model/app_pig.dart';
import '../domain/model/app_weight_history.dart';
import '../domain/repo/pig_repo.dart';


class FirebasePigRepo implements PigRepo {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late final CollectionReference _pigsCollection = _firestore.collection('pigs');
  late final CollectionReference _countersCollection = _firestore.collection('counters');


  // --- READ ---
  @override
  Stream<List<AppPig>> streamPigs(String userId) {
    // 🔹 Use includeMetadataChanges: false to ignore internal Firestore sync updates
    return _pigsCollection
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots(includeMetadataChanges: false)
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return AppPig.fromJson(doc.data() as Map<String, dynamic>, doc.id);
      }).toList();
    });
  }


  // --- CREATE/ADD PIG ---
  @override
  Future<void> addPig(AppPig pig) async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        throw Exception("No authenticated user");
      }


      final docRef = _pigsCollection.doc();
      final counterRef = _countersCollection.doc(userId);


      await _firestore.runTransaction((transaction) async {
        final counterSnap = await transaction.get(counterRef);


        final int currentTotal = (counterSnap.exists
            ? (counterSnap.data() as Map<String, dynamic>)['pigCount'] ?? 0
            : 0) as int;
        final int nextNumber = currentTotal + 1;


        final pigData = pig.toJson();
        pigData['userId'] = userId;
        pigData['pigId'] = docRef.id;
        pigData['displayId'] = 'P-${nextNumber.toString().padLeft(3, '0')}';
        pigData['createdAt'] = FieldValue.serverTimestamp();


        transaction.set(docRef, pigData);


        transaction.set(
          counterRef,
          {'pigCount': nextNumber},
          SetOptions(merge: true),
        );


        // Initial weight history entry, folded into the same transaction
        // instead of a separate .add() call after the fact.
        final historyRef = docRef.collection('weight_history').doc();
        transaction.set(historyRef, {
          'weightKg': pig.currentWeightKg,
          'dateRecorded': FieldValue.serverTimestamp(),
          'notes': 'Birth weight',
        });
      });
    } catch (e) {
      throw Exception("Error adding pig: $e");
    }
  }


  // --- UPDATE PIG PROFILE (Optimization) ---
  @override
  Future<void> updatePigProfile(
      AppPig updatedPig, {
        required double oldWeightKg,
      }) async {
    try {
      final docRef = _pigsCollection.doc(updatedPig.pigId);
      final batch = _firestore.batch();


      batch.update(docRef, {
        'breed': updatedPig.breed,
        'currentWeightKg': updatedPig.currentWeightKg,
        'birthDate': updatedPig.birthDate,
        'sex': updatedPig.sex,
        'notes': updatedPig.notes,
        'stage': updatedPig.stage,
        'status': updatedPig.status,
        'updatedAt': FieldValue.serverTimestamp(),
      });


      if (oldWeightKg != updatedPig.currentWeightKg) {
        final historyRef = docRef.collection('weight_history').doc();
        batch.set(historyRef, {
          'weightKg': updatedPig.currentWeightKg,
          'dateRecorded': FieldValue.serverTimestamp(),
          'notes': 'Updated via Profile Edit',
        });
      }


      await batch.commit();
    } catch (e) {
      throw Exception("Error updating pig profile: $e");
    }
  }


  // --- UPDATE WEIGHT ---
  @override
  Future<void> updatePigWeight(String pigId, double newWeight) async {
    try {
      final docRef = _pigsCollection.doc(pigId);
      final historyRef = docRef.collection('weight_history').doc();
      final batch = _firestore.batch();


      batch.update(docRef, {
        'currentWeightKg': newWeight,
        'updatedAt': FieldValue.serverTimestamp(),
      });


      batch.set(historyRef, {
        'weightKg': newWeight,
        'dateRecorded': FieldValue.serverTimestamp(),
        'notes': 'Manual update',
      });


      await batch.commit();
    } catch (e) {
      throw Exception("Error updating weight: $e");
    }
  }


  @override
  Stream<List<AppWeightRecord>> streamWeightHistory(String pigId) {
    return _pigsCollection
        .doc(pigId)
        .collection('weight_history')
        .orderBy('dateRecorded', descending: true)
        .snapshots(includeMetadataChanges: false)
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return AppWeightRecord.fromJson(doc.data(), doc.id);
      }).toList();
    });
  }


  // // --- DELETE ---
  // @override
  // Future<void> deletePig(String pigId) async {
  //   try {
  //     await _pigsCollection.doc(pigId).delete();
  //
  //   } catch (e) {
  //     throw Exception("Error deleting pig: $e");
  //   }
  // } for future use if needed


  // --- ONE-TIME MIGRATION HELPER ---
  Future<void> migrateCounterForUser(String userId) async {
    final counterRef = _countersCollection.doc(userId);
    final counterSnap = await counterRef.get();
    if (counterSnap.exists) return; // already migrated


    final countSnapshot = await _pigsCollection
        .where('userId', isEqualTo: userId)
        .count()
        .get();


    final int existingCount = countSnapshot.count ?? 0;


    await counterRef.set({'pigCount': existingCount});
  }
}