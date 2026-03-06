import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart'; // Assuming you have AuthService
import 'package:geocoding/geocoding.dart'; // For reverse geocoding on listings

class MyListingsScreen extends StatefulWidget {
  const MyListingsScreen({Key? key}) : super(key: key);

  @override
  State<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<MyListingsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final AuthService _authService = AuthService();
  User? _currentUser;
  String _currentFilter = 'All'; // Default filter for tabs
  bool _isCheckingLenderStatus = false; // New state to manage loading for lender check

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this); // All, Active, Booked, Under Review
    _currentUser = FirebaseAuth.instance.currentUser;
    _tabController.addListener(_handleTabSelection);
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabSelection() {
    if (_tabController.indexIsChanging || _tabController.index != _tabController.previousIndex) {
      if (mounted) { // Ensure widget is still mounted before calling setState
        setState(() {
          switch (_tabController.index) {
            case 0:
              _currentFilter = 'All';
              break;
            case 1:
              _currentFilter = 'Active'; // Corresponds to 'available' status
              break;
            case 2:
              _currentFilter = 'Booked'; // Corresponds to 'rented' status
              break;
            case 3:
              _currentFilter = 'Under Review'; // Corresponds to 'draft' or 'pending_review' status
              break;
          }
        });
      }
    }
  }

  // Function to perform reverse geocoding for location display
  Future<String> _getReadableLocation(dynamic location) async {
    if (location is GeoPoint) {
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(location.latitude, location.longitude);
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks.first;
          return "${place.street ?? ''}, ${place.locality ?? place.subLocality ?? ''}";
        }
      } catch (e) {
        print("Error during reverse geocoding in MyListingsScreen: $e");
        return 'Lat: ${location.latitude.toStringAsFixed(4)}, Lng: ${location.longitude.toStringAsFixed(4)}';
      }
    } else if (location is String && location.isNotEmpty) {
      return location;
    }
    return 'Unknown Location';
  }

  // Function to check lender status and navigate to upload screen
  Future<void> _checkLenderStatusAndNavigate() async {
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to upload items.')),
      );
      Navigator.pushNamed(context, '/login');
      return;
    }

    if (mounted) {
      setState(() {
        _isCheckingLenderStatus = true; // Show loading indicator
      });
    }

    try {
      // Fetch the latest user profile directly from Firestore
      DocumentSnapshot userProfileSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .get();

      if (userProfileSnapshot.exists) {
        // Explicitly cast the data to Map<String, dynamic>
        bool isLender = (userProfileSnapshot.data() as Map<String, dynamic>)?['isLender'] ?? false;
        if (isLender) {
          Navigator.pushNamed(context, '/upload_item');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You must be a lender to upload items. Please update your profile.')),
          );
          // Optionally, navigate to update profile screen
          Navigator.pushNamed(context, '/account_details');
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User profile not found. Please complete your profile.')),
        );
        Navigator.pushNamed(context, '/account_details');
      }
    } catch (e) {
      print("Error checking lender status: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error checking lender status: ${e.toString()}')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingLenderStatus = false; // Hide loading indicator
        });
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('My Listings'),
          backgroundColor: Colors.blue[800],
          foregroundColor: Colors.white,
          leading: IconButton( // Add a back button
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
        ),
        body: const Center(
          child: Text('Please log in to view your listings.'),
        ),
      );
    }

    Query<Map<String, dynamic>> itemsQuery = FirebaseFirestore.instance
        .collection('items')
        .where('ownerId', isEqualTo: _currentUser!.uid);

    // Apply filter based on selected tab
    if (_currentFilter == 'Active') {
      itemsQuery = itemsQuery.where('status', isEqualTo: 'available');
    } else if (_currentFilter == 'Booked') {
      itemsQuery = itemsQuery.where('status', isEqualTo: 'rented');
    } else if (_currentFilter == 'Under Review') {
      itemsQuery = itemsQuery.where('status', isEqualTo: 'draft'); // Assuming 'draft' or a specific 'pending' status
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Listings'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        leading: IconButton( // Add a back button
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        actions: [
          IconButton(
            icon: _isCheckingLenderStatus
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                    ),
                  )
                : const Icon(Icons.add, color: Colors.blue),
            onPressed: _isCheckingLenderStatus ? null : _checkLenderStatusAndNavigate, // Disable button while checking
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.blue[800],
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.blue[800],
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Active'),
            Tab(text: 'Booked'),
            Tab(text: 'Under Review'),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: itemsQuery.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No listings found.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              DocumentSnapshot document = snapshot.data!.docs[index];
              Map<String, dynamic> itemData = document.data()! as Map<String, dynamic>;

              String itemName = itemData['name'] ?? 'Unnamed Item';
              String itemDescription = itemData['description'] ?? ''; // You might use a short description here
              String itemStatus = itemData['status'] ?? 'unknown'; // available, rented, draft etc.
              String imageUrl = (itemData['images'] != null && itemData['images'] is List && itemData['images'].isNotEmpty && itemData['images'][0] is String && itemData['images'][0].isNotEmpty)
                  ? itemData['images'][0]
                  : 'assets/images/examples.png'; // Fallback
              String pricePerDay = 'RM${(itemData['pricePerDay'] as num?)?.toStringAsFixed(2) ?? '0.00'}/day';
              double averageRating = (itemData['averageRating'] as num?)?.toDouble() ?? 0.0;


              return Card(
                margin: const EdgeInsets.only(bottom: 15.0),
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              imageUrl,
                              width: 90,
                              height: 90,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Image.asset(
                                'assets/images/examples.png',
                                width: 90,
                                height: 90,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  itemName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 16),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  itemDescription,
                                  style: TextStyle(color: Colors.grey[700], fontSize: 14),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(Icons.star, color: Colors.amber, size: 16),
                                    const SizedBox(width: 4),
                                    Text('${averageRating.toStringAsFixed(1)} Ratings',
                                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.blue[50],
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    itemStatus.toUpperCase(),
                                    style: TextStyle(color: Colors.blue[800], fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () {
                              // Handle Edit
                              Navigator.pushNamed(
                                context,
                                '/upload_item', // Use the multi-step form for editing as well
                                arguments: document.id, // Pass the item ID for editing
                              );
                            },
                            child: const Text('Edit', style: TextStyle(color: Colors.blue)),
                          ),
                          const SizedBox(width: 10),
                          TextButton(
                            onPressed: () {
                              // Handle View Analytics / Deactivate / Duplicate
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('${itemStatus == 'available' ? 'View Analytics' : (itemStatus == 'rented' ? 'Deactivate' : 'Duplicate')} clicked for ${itemName}')),
                              );
                            },
                            child: Text(
                              itemStatus == 'available' ? 'View Analytics' : (itemStatus == 'rented' ? 'Deactivate' : 'Duplicate'),
                              style: const TextStyle(color: Colors.blue),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
