import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart'; // For picking images
import 'dart:io'; // For File
import '../services/auth_service.dart'; // Import your AuthService

class AccountDetailsScreen extends StatefulWidget {
  const AccountDetailsScreen({Key? key}) : super(key: key);

  @override
  State<AccountDetailsScreen> createState() => _AccountDetailsScreenState();
}

class _AccountDetailsScreenState extends State<AccountDetailsScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController(); // Not editable, but for display
  final TextEditingController _phoneNumberController = TextEditingController();
  final TextEditingController _streetController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _postcodeController = TextEditingController();

  final AuthService _authService = AuthService();
  final ImagePicker _picker = ImagePicker(); // Initialize ImagePicker

  bool _isLoading = false;
  bool _isLender = false; // Current lender status from Firestore
  bool _lenderRequestPending = false; // Current lender request status
  String? _currentUserId;
  XFile? _pickedProfileImage; // To hold the newly picked image file

  @override
  void initState() {
    super.initState();
    _currentUserId = _authService.getCurrentUserUid();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    if (_currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not logged in.')),
      );
      Navigator.pop(context); // Go back if no user
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      Map<String, dynamic>? userData = await _authService.getUserProfile(_currentUserId!);
      if (userData != null) {
        _nameController.text = userData['name'] ?? '';
        _emailController.text = userData['email'] ?? ''; // Email from Firestore or Auth
        _phoneNumberController.text = userData['phoneNumber'] ?? '';
        
        // Load address map
        Map<String, dynamic> addressData = (userData['address'] as Map<String, dynamic>?) ?? {};
        _streetController.text = addressData['street'] ?? '';
        _cityController.text = addressData['city'] ?? '';
        _postcodeController.text = addressData['postcode'] ?? '';

        _isLender = userData['isLender'] ?? false; // Load isLender status
        _lenderRequestPending = userData['lenderRequestPending'] ?? false; // Load lender request status
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load user data.')),
        );
      }
    } on Exception catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Method to pick an image from gallery
  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _pickedProfileImage = image; // Retain the picked image
      });
      // No Snackbar needed here; the image will be uploaded on profile update
    }
  }

  Future<void> _updateProfile() async {
    if (_currentUserId == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      String? newProfilePictureUrl;
      // 1. Upload new profile image if selected
      if (_pickedProfileImage != null) {
        newProfilePictureUrl = await _authService.uploadProfileImage(
            _pickedProfileImage!, _currentUserId!);
      }

      // 2. Prepare data for Firestore update
      Map<String, dynamic> updateData = {
        'name': _nameController.text.trim(),
        'phoneNumber': _phoneNumberController.text.trim(),
        'address': {
          'street': _streetController.text.trim(),
          'city': _cityController.text.trim(),
          'postcode': _postcodeController.text.trim(),
        },
      };

      if (newProfilePictureUrl != null && newProfilePictureUrl.isNotEmpty) {
        updateData['profilePictureUrl'] = newProfilePictureUrl; // Update Firestore with new URL
      }

      // 3. Update Firestore profile
      await _authService.updateFirestoreUserProfile(_currentUserId!, updateData);

      // 4. Update Firebase Auth profile (display name and photoURL)
      // Note: Firebase Auth's photoURL is often preferred for display in UIs like Drawer header.
      // Update Auth's photoURL only if a new image was uploaded.
      await _authService.updateAuthProfile(
        _nameController.text.trim(),
        newProfilePictureUrl, // Pass the new photoURL here
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully!')),
      );
      Navigator.pop(context); // Go back after update
    } on Exception catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _requestLenderStatus() async {
    if (_currentUserId == null) return;
    setState(() {
      _isLoading = true;
    });
    try {
      // Update Firestore to set lenderRequestPending to true
      await _authService.updateFirestoreUserProfile(_currentUserId!, {
        'lenderRequestPending': true,
      });
      setState(() {
        _lenderRequestPending = true; // Update local state
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lender request sent for admin approval.')),
      );
    } on Exception catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneNumberController.dispose();
    _streetController.dispose();
    _cityController.dispose();
    _postcodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Determine which image to display for the CircleAvatar
    ImageProvider avatarImage;
    if (_pickedProfileImage != null) {
      // Show the newly picked image immediately for user feedback
      avatarImage = FileImage(File(_pickedProfileImage!.path));
    } else if (FirebaseAuth.instance.currentUser?.photoURL != null && FirebaseAuth.instance.currentUser!.photoURL!.isNotEmpty) {
      // Otherwise, use the photoURL from Firebase Auth (which reflects uploaded images)
      avatarImage = NetworkImage(FirebaseAuth.instance.currentUser!.photoURL!);
    } else {
      // Fallback to the placeholder asset
      avatarImage = const AssetImage('assets/images/Profile_Placeholder.png');
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account Details'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: _pickImage,
                      child: CircleAvatar(
                        radius: 60,
                        backgroundColor: Colors.grey[200],
                        backgroundImage: avatarImage, // Use the determined avatarImage
                        child: _pickedProfileImage == null && (FirebaseAuth.instance.currentUser?.photoURL == null || FirebaseAuth.instance.currentUser!.photoURL!.isEmpty)
                            ? const Icon(Icons.camera_alt, size: 40, color: Colors.grey)
                            : null, // Only show icon if no image is present/picked
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'Full Name',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        prefixIcon: const Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _emailController,
                      readOnly: true, // Email from Firebase Auth is generally not changed via profile screen
                      decoration: InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        prefixIcon: const Icon(Icons.email),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _phoneNumberController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'Phone Number',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        prefixIcon: const Icon(Icons.phone),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Address Fields
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Address Details:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _streetController,
                      decoration: InputDecoration(
                        labelText: 'Street',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        prefixIcon: const Icon(Icons.location_on),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _cityController,
                      decoration: InputDecoration(
                        labelText: 'City',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        prefixIcon: const Icon(Icons.location_city),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _postcodeController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Postcode',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        prefixIcon: const Icon(Icons.local_post_office),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Lender Status Display:
                    if (_isLender) // If the user IS a lender
                      Row(
                        children: [
                          Checkbox(
                            value: _isLender,
                            onChanged: null, // Not editable by user
                            activeColor: Colors.green,
                          ),
                          Text(
                            'You are a Lender',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green[700],
                            ),
                          ),
                        ],
                      )
                    else if (_lenderRequestPending) // If not a lender but request is pending
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          'Lender Request Pending Approval',
                          style: TextStyle(fontStyle: FontStyle.italic, color: Colors.orange[800]),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else // If not a lender and no request is pending
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _requestLenderStatus,
                          icon: const Icon(Icons.business_center),
                          label: const Text('Request to Become a Lender'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.blue[800],
                            side: BorderSide(color: Colors.blue[800]!),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _updateProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[800],
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text(
                          'Update Profile',
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton(
                        onPressed: () async {
                          await _authService.signOut();
                          // Navigate to home and remove all previous routes
                          Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red[800],
                          side: BorderSide(color: Colors.red[800]!),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text(
                          'Logout',
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
