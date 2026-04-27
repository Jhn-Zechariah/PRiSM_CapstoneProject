import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../domain/models/app_pig.dart';
import '../domain/repo/pig_repo.dart';

class FirebasePigRepo implements PigRepo{
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance; // 👇 Get Auth Instance

  // Collection Reference
  CollectionReference get _pigsCollection => _firestore.collection('pigs');

  // Helper to get current user ID
  String? get _currentUserId => _auth.currentUser?.uid;

  // --- CREATE ---
  @override
  Future<void> addPig(AppPig pig) async {
    try {
      final uid = _currentUserId;
      if (uid == null) throw Exception("User is not logged in!");

      final docRef = pig.pigId.isEmpty
          ? _pigsCollection.doc()
          : _pigsCollection.doc(pig.pigId);

      final pigToSave = AppPig(
        pigId: docRef.id,
        userId: uid,
        breed: pig.breed,
        birthDate: pig.birthDate,
        sex: pig.sex,
        currentWeightKg: pig.currentWeightKg,
        notes: pig.notes,
        stage: pig.stage,
        status: pig.status,
      );

      await docRef.set(pigToSave.toJson());

      // Also initialize the first weight in the history subcollection
      await docRef.collection('weight_history').add({
        'weightKg': pig.currentWeightKg,
        'dateRecorded': FieldValue.serverTimestamp(),
        'notes': 'Initial weight',
      });

    } catch (e) {
      throw Exception("Error adding pig: $e");
    }
  }

  // --- READ ---
  Stream<List<AppPig>> streamPigs() {
    final uid = _currentUserId;
    if (uid == null) return Stream.value([]); // Return empty list if not logged in
    return _pigsCollection
        .where('userId', isEqualTo: uid) // Only fetch this user's pigs
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return AppPig.fromJson(doc.data() as Map<String, dynamic>, doc.id);
      }).toList();
    });
  }

  // --- UPDATE WEIGHT ---
  Future<void> updatePigWeight(String pigId, double newWeight) async {
    try {
      final docRef = _pigsCollection.doc(pigId);

      // 1. Update the main document
      await docRef.update({
        'currentWeightKg': newWeight,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 2. Add to the weight history subcollection
      await docRef.collection('weight_history').add({
        'weightKg': newWeight,
        'dateRecorded': FieldValue.serverTimestamp(),
        'notes': 'Manual update',
      });
    } catch (e) {
      throw Exception("Error updating weight: $e");
    }
  }

  // --- DELETE ---
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