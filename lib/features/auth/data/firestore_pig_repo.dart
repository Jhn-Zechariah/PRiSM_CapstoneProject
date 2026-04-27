import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../domain/models/app_pig.dart';
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

      final docRef = pig.pigId.isEmpty
          ? _pigsCollection.doc()
          : _pigsCollection.doc(pig.pigId);

      // Create a map of the pig data, and inject the userId and pigId!
      final pigData = pig.toJson();
      pigData['userId'] = userId;
      pigData['pigId'] = docRef.id;

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

      // Update the main document
      await docRef.update({
        'breed': updatedPig.breed,
        'currentWeightKg': updatedPig.currentWeightKg,
        'birthDate': updatedPig.birthDate,
        'sex': updatedPig.sex,
        'notes': updatedPig.notes,
        'stage': updatedPig.stage,
        'status': updatedPig.status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
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