import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart'; // No longer needed directly here for now
import 'dart:io'; // No longer needed directly here for now
import 'package:firebase_storage/firebase_storage.dart'; // For profile image upload

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Stream for authentication state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Get current user UID
  String? getCurrentUserUid() {
    return _auth.currentUser?.uid;
  }

  // Get current User object (NEWLY ADDED)
  User? getCurrentUser() {
    return _auth.currentUser;
  }

  // Sign in with email and password
  Future<User?> signInWithEmailPassword(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return result.user;
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'user-not-found':
          errorMessage = 'No user found for that email.';
          break;
        case 'wrong-password':
          errorMessage = 'Wrong password provided for that user.';
          break;
        case 'invalid-email':
          errorMessage = 'The email address is not valid.';
          break;
        case 'user-disabled':
          errorMessage = 'This user has been disabled.';
          break;
        default:
          errorMessage = 'Login failed: ${e.message}';
      }
      throw Exception(errorMessage);
    } catch (e) {
      throw Exception('An unexpected error occurred: $e');
    }
  }

  // Register with email and password
  Future<User?> signUpWithEmailPassword(String email, String password, String name) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      User? user = result.user;

      if (user != null) {
        // Update user profile (display name)
        await user.updateDisplayName(name);
        // await user.reload(); // Reload user to get updated display name
        // user = _auth.currentUser; // Get the reloaded user instance

        // Create a Firestore user profile document
        await _firestore.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'email': user.email,
          'name': name, // Store display name in Firestore
          'profilePictureUrl': '', // Placeholder for profile picture URL
          'isLender': false, // Default to not a lender
          'lenderRequestPending': false, // Default to no pending request
          'phoneNumber': '',
          'address': {
            'street': '',
            'city': '',
            'postcode': '',
          },
          'myEarnings': 0.0,
          'rewardCredits': 0.0,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      return user;
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'weak-password':
          errorMessage = 'The password provided is too weak.';
          break;
        case 'email-already-in-use':
          errorMessage = 'The account already exists for that email.';
          break;
        case 'invalid-email':
          errorMessage = 'The email address is not valid.';
          break;
        default:
          errorMessage = 'Sign up failed: ${e.message}';
      }
      throw Exception(errorMessage);
    } catch (e) {
      throw Exception('An unexpected error occurred: $e');
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      throw Exception('Error signing out: $e');
    }
  }

  // Reset password
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'user-not-found':
          errorMessage = 'No user found for that email.';
          break;
        case 'invalid-email':
          errorMessage = 'The email address is not valid.';
          break;
        default:
          errorMessage = 'Password reset failed: ${e.message}';
      }
      throw Exception(errorMessage);
    } catch (e) {
      throw Exception('An unexpected error occurred: $e');
    }
  }

  // Get user profile from Firestore
  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    try {
      DocumentSnapshot doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        return doc.data() as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      throw Exception('Error fetching user profile: $e');
    }
  }

  // Get user profile stream from Firestore (for real-time updates)
  Stream<DocumentSnapshot> getUserProfileStream(String uid) {
    return _firestore.collection('users').doc(uid).snapshots();
  }

  // Update Firestore user profile
  Future<void> updateFirestoreUserProfile(String uid, Map<String, dynamic> data) async {
    try {
      await _firestore.collection('users').doc(uid).update(data);
    } catch (e) {
      throw Exception('Error updating user profile in Firestore: $e');
    }
  }

  // Update Firebase Auth profile (display name and photo URL)
  Future<void> updateAuthProfile(String? displayName, String? photoURL) async {
    User? user = _auth.currentUser;
    if (user != null) {
      try {
        if (displayName != null) {
          await user.updateDisplayName(displayName);
        }
        if (photoURL != null) {
          await user.updatePhotoURL(photoURL);
        }
        // Force a reload to ensure the latest user data is available immediately
        await user.reload();
        _auth.currentUser; // This refreshes the internal state of _auth.currentUser
      } on FirebaseAuthException catch (e) {
        throw Exception('Error updating Firebase Auth profile: ${e.message}');
      } catch (e) {
        throw Exception('An unexpected error occurred while updating Auth profile: $e');
      }
    }
  }

  // Method to upload profile image to Firebase Storage and return URL
  Future<String> uploadProfileImage(XFile imageFile, String userId) async {
    try {
      final storageRef = FirebaseStorage.instance.ref();
      final profileImagesRef = storageRef.child('profile_pictures/$userId.jpg');

      await profileImagesRef.putFile(File(imageFile.path));
      String downloadUrl = await profileImagesRef.getDownloadURL();
      return downloadUrl;
    } on FirebaseException catch (e) {
      throw Exception('Failed to upload image: ${e.message}');
    } catch (e) {
      throw Exception('An unexpected error occurred during image upload: $e');
    }
  }
}
