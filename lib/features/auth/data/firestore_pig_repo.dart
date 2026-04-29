import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../domain/models/app_pig.dart';
import '../domain/models/app_weight_history.dart';
import '../domain/repo/pig_repo.dart';

class FirebasePigRepo implements PigRepo{
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Collection Reference
  CollectionReference get _pigsCollection => _firestore.collection('pigs');

  // --- READ ---
  @override
  Stream<List<AppPig>> streamPigs(String userId) {
    return _pigsCollection
        .where('userId', isEqualTo: userId) // Only fetch this user's pigs
        .orderBy('createdAt', descending: true)
        .snapshots()
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
      //Grab the logged-in user's ID
      final userId = FirebaseAuth.instance.currentUser?.uid;

      final docRef = _pigsCollection.doc();

      // Create a map of the pig data, and inject the userId and pigId!
      final pigData = pig.toJson();
      pigData['userId'] = userId;
      pigData['pigId'] = docRef.id;

      // --- ID GENERATOR LOGIC ---
      // Count existing pigs belonging to this specific user
      final snapshot = await _pigsCollection
          .where('userId', isEqualTo: userId)
          .count()
          .get();

      final int currentTotal = snapshot.count ?? 0;
      final int nextNumber = currentTotal + 1;

      // Format the ID (e.g., P-001) and inject it
      pigData['displayId'] = 'P-${nextNumber.toString().padLeft(3, '0')}';

      await docRef.set(pigData);

      //add initial weight upon creation
      await docRef.collection('weight_history').add({
        'weightKg': pig.currentWeightKg,
        'dateRecorded': FieldValue.serverTimestamp(),
        'notes': 'Initial weight',
      });

    } catch (e) {
      throw Exception("Error adding pig: $e");
    }
  }

  // --- UPDATE PIG PROFILE ---
  @override
  Future<void> updatePigProfile(AppPig updatedPig) async {
    try {
      // Get a reference to the document
      final docRef = _pigsCollection.doc(updatedPig.pigId);

      // Fetch the current data from Firestore to see what the old weight was
      final snapshot = await docRef.get();
      if (!snapshot.exists) throw Exception("Pig profile not found");

      // Explicitly cast the data to a Map so Dart knows how to read it
      final data = snapshot.data() as Map<String, dynamic>?;

      final oldWeight = (data?['currentWeightKg'] ?? 0).toDouble();

      //Create a batch to execute multiple writes simultaneously
      final batch = FirebaseFirestore.instance.batch();

      // Queue the main profile update
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

      // If the weight changed, queue a new document in the weight_history subcollection
      if (oldWeight != updatedPig.currentWeightKg) {
        final historyRef = docRef.collection('weight_history').doc();
        batch.set(historyRef, {
          'weightKg': updatedPig.currentWeightKg,
          'dateRecorded': FieldValue.serverTimestamp(),
          'notes': 'Updated via Profile Edit', // Helps you identify where the change came from
        });
      }

      // 6. Commit the batch to Firebase
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

      // Update the main document
      await docRef.update({
        'currentWeightKg': newWeight,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Add to the weight history subcollection
      await docRef.collection('weight_history').add({
        'weightKg': newWeight,
        'dateRecorded': FieldValue.serverTimestamp(),
        'notes': 'Manual update',
      });
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
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return AppWeightRecord.fromJson(doc.data(), doc.id);
      }).toList();
    });
  }

  // --- DELETE ---
  @override
  Future<void> deletePig(String pigId) async {
    try {
      await _pigsCollection.doc(pigId).delete();
      // Note: In Firestore, deleting a document doesn't automatically delete its subcollections.
      // For a production app, you might need a Cloud Function to clean up the subcollections,
      // but deleting the main doc is enough to remove it from your UI.
    } catch (e) {
      throw Exception("Error deleting pig: $e");
    }
  }
}