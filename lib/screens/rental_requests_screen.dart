import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../services/auth_service.dart'; // Assuming AuthService for current user

class RentalRequestsScreen extends StatefulWidget {
  const RentalRequestsScreen({Key? key}) : super(key: key);

  @override
  State<RentalRequestsScreen> createState() => _RentalRequestsScreenState();
}

class _RentalRequestsScreenState extends State<RentalRequestsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();
  User? _currentUser;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _currentUser = _authService.getCurrentUser();
    if (_currentUser == null) {
      // Redirect to login if not authenticated
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please log in to view rental requests.')),
          );
          Navigator.pushReplacementNamed(context, '/login');
        }
      });
    } else {
      _isLoading = false; // Not loading if user is already known
    }
  }

  // Function to show the protection plan dialog
  Future<void> _showProtectionPlanDialog(String orderId) async {
    bool? addProtectionPlan = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // User must choose an option
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Text(
            'Optional Protection Plan',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Would you like to offer a protection plan for this booking?',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.security, color: Colors.green),
                  const SizedBox(width: 8),
                  Text(
                    'Optional RM10.00 will be charged.',
                    style: TextStyle(fontSize: 15, color: Colors.grey[700]),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Text(
                'This plan helps cover minor damages during the rental period.',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('No, proceed without plan', style: TextStyle(color: Colors.red)),
              onPressed: () {
                Navigator.of(context).pop(false); // Lender chooses NOT to add plan
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[800],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Yes, add plan'),
              onPressed: () {
                Navigator.of(context).pop(true); // Lender chooses to add plan
              },
            ),
          ],
        );
      },
    );

    if (addProtectionPlan != null) {
      // If the lender made a choice, proceed to update booking status
      await _updateBookingStatus(orderId, 'approved', addProtectionPlan: addProtectionPlan);
    }
    // If addProtectionPlan is null, the dialog was dismissed, do nothing or show a message
  }

  // Modified _updateBookingStatus to include protection plan logic
  Future<void> _updateBookingStatus(String orderId, String status, {bool addProtectionPlan = false}) async {
    setState(() {
      _isLoading = true; // Show loading indicator during update
    });
    try {
      Map<String, dynamic> updateData = {
        'status': status,
        'lastUpdatedAt': FieldValue.serverTimestamp(),
      };

      if (status == 'approved') {
        updateData['approvedAt'] = FieldValue.serverTimestamp();
        updateData['isUnderProtectionPlan'] = addProtectionPlan;
        updateData['protectionPlanFee'] = addProtectionPlan ? 10.0 : 0.0;
        // Optionally, update totalPrice if the protection plan fee affects it directly
        // This depends on whether totalPrice in 'orders' is truly final or a base price.
        // For simplicity, let's assume total price stored in the order already accounts for this if needed by business logic.
        // If not, you might want to add:
        // updateData['totalPrice'] = FieldValue.increment(addProtectionPlan ? 10.0 : 0.0);
      } else if (status == 'rejected') {
        updateData['rejectedAt'] = FieldValue.serverTimestamp();
      }

      await _firestore.collection('orders').doc(orderId).update(updateData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Booking request ${status} successfully!')),
        );
      }
    } catch (e) {
      print("Error updating booking status: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update booking status: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Rental Requests'),
          backgroundColor: Colors.blue[800],
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text('You must be logged in to view rental requests.')),
      );
    }

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Rental Requests'),
          backgroundColor: Colors.blue[800],
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Booking Requests'), // Changed title to match image
        backgroundColor: Colors.white, // Changed background to white
        foregroundColor: Colors.black, // Changed foreground to black
        elevation: 0, // Removed elevation
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('orders')
            .where('ownerId', isEqualTo: _currentUser!.uid)
            .where('status', isEqualTo: 'pending') // Only show pending requests
            .orderBy('createdAt', descending: true) // Order by creation date
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No pending rental requests.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              DocumentSnapshot orderDoc = snapshot.data!.docs[index];
              Map<String, dynamic> orderData = orderDoc.data()! as Map<String, dynamic>;

              // Extract order details
              String orderId = orderDoc.id;
              String itemId = orderData['itemId'] ?? '';
              String renterId = orderData['renterId'] ?? '';
              Timestamp startDate = orderData['startDate'] as Timestamp;
              Timestamp endDate = orderData['endDate'] as Timestamp;
              double totalPrice = (orderData['totalPrice'] as num?)?.toDouble() ?? 0.0;
              double depositPaid = (orderData['depositPaid'] as num?)?.toDouble() ?? 0.0;
              String deliveryOptionType = orderData['deliveryOptionType'] ?? 'N/A';
              String meetUpNotes = orderData['meetUpLocationNotes'] ?? 'No notes';
              Map<String, dynamic> deliveryAddress = (orderData['deliveryAddress'] as Map<String, dynamic>?) ?? {};

              // Fetch item details (for item name and image) and renter details (for renter name)
              return FutureBuilder<Map<String, dynamic>>(
                future: _fetchRelatedDetails(itemId, renterId),
                builder: (context, detailsSnapshot) {
                  String itemName = 'Loading Item Name...';
                  String itemImageUrl = 'https://placehold.co/600x400/cccccc/000000?text=No+Image';
                  String renterName = 'Loading Renter Name...';
                  String renterProfilePicUrl = 'assets/images/Profile_Placeholder.png'; // Default
                  double renterSmartTrustScore = 0.0;
                  int renterReturnRate = 0;
                  bool renterIdVerified = false;
                  int renterPastRentals = 0;


                  if (detailsSnapshot.connectionState == ConnectionState.done && detailsSnapshot.hasData) {
                    itemName = detailsSnapshot.data!['itemName'] ?? 'Unknown Item';
                    itemImageUrl = detailsSnapshot.data!['itemImageUrl'] ?? itemImageUrl;
                    renterName = detailsSnapshot.data!['renterName'] ?? 'Unknown Renter';
                    renterProfilePicUrl = detailsSnapshot.data!['renterProfilePicUrl'] ?? 'assets/images/Profile_Placeholder.png';
                    renterSmartTrustScore = (detailsSnapshot.data!['renterSmartTrustScore'] as num?)?.toDouble() ?? 0.0; // Assuming this field exists
                    renterReturnRate = (detailsSnapshot.data!['renterReturnRate'] as int?) ?? 0; // Assuming this field exists
                    renterIdVerified = detailsSnapshot.data!['renterIdVerified'] ?? false; // Assuming this field exists
                    renterPastRentals = (detailsSnapshot.data!['renterPastRentals'] as int?) ?? 0; // Assuming this field exists
                  }

                  return Card(
                    margin: const EdgeInsets.only(bottom: 15),
                    elevation: 3,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Renter Info Section (matches image)
                          Center(
                            child: Column(
                              children: [
                                CircleAvatar(
                                  radius: 40,
                                  backgroundImage: renterProfilePicUrl.startsWith('http')
                                      ? NetworkImage(renterProfilePicUrl)
                                      : AssetImage(renterProfilePicUrl) as ImageProvider,
                                  backgroundColor: Colors.grey[200],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  renterName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                                ),
                                Text(
                                  'Trusted Renter', // Static for now, can be dynamic
                                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                                ),
                                const SizedBox(height: 15),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    _buildRenterMetric('Return Rate', '${renterReturnRate}%', Icons.refresh),
                                    _buildRenterMetric('Smart Trust Score', '${renterSmartTrustScore.toStringAsFixed(1)}', Icons.star),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                if (renterIdVerified)
                                  _buildRenterFeatureRow('ID Verified', Icons.check_circle_outline, Colors.green),
                                const SizedBox(height: 5),
                                _buildRenterFeatureRow('$renterPastRentals past rentals', Icons.history, Colors.grey[700]!),
                              ],
                            ),
                          ),
                          const Divider(height: 30, thickness: 1),

                          // Item Details Section
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  itemImageUrl,
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => Container(
                                    width: 80,
                                    height: 80,
                                    color: Colors.grey[300],
                                    child: const Icon(Icons.broken_image, color: Colors.grey),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      itemName,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold, fontSize: 18),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${DateFormat('dd MMM').format(startDate.toDate())} - ${DateFormat('dd MMM').format(endDate.toDate())} (${endDate.toDate().difference(startDate.toDate()).inDays + 1} days)',
                                      style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Total Price: RM${totalPrice.toStringAsFixed(2)}',
                                      style: TextStyle(fontSize: 14, color: Colors.blue[700], fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      'Deposit: RM${depositPaid.toStringAsFixed(2)}',
                                      style: TextStyle(fontSize: 14, color: Colors.red[700]),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 20),
                          _buildDetailRow('Delivery Type:', deliveryOptionType == 'meet_up' ? 'Meet Up' : 'Delivery'),
                          if (deliveryOptionType == 'meet_up')
                            _buildDetailRow('Meet Up Notes:', meetUpNotes),
                          if (deliveryOptionType == 'delivery')
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildDetailRow('Delivery Address:', ''),
                                Padding(
                                  padding: const EdgeInsets.only(left: 16.0),
                                  child: Text(
                                    '${deliveryAddress['building'] ?? ''}, ${deliveryAddress['street'] ?? ''},\n'
                                    '${deliveryAddress['city'] ?? ''}, ${deliveryAddress['postcode'] ?? ''}, ${deliveryAddress['state'] ?? ''}',
                                    style: TextStyle(fontSize: 14, color: Colors.grey[800]),
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 15),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () => _updateBookingStatus(orderId, 'rejected'), // Reject directly
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                  child: const Text('Reject'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () => _showProtectionPlanDialog(orderId), // Show dialog on Accept
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue[800],
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                  child: const Text('Accept'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Center(
                            child: TextButton(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Learn more about our per-rental protection plan clicked!')),
                                );
                              },
                              child: Text(
                                'Learn more about our per-rental protection plan',
                                style: TextStyle(color: Colors.blue[700], fontSize: 13, decoration: TextDecoration.underline),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120, // Fixed width for labels
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 14, color: Colors.grey[800]),
            ),
          ),
        ],
      ),
    );
  }

  // New widget to build renter metrics (Return Rate, Smart Trust Score)
  Widget _buildRenterMetric(String title, String value, IconData icon) {
    return Column(
      children: [
        CircleAvatar(
          radius: 25,
          backgroundColor: Colors.grey[100],
          child: Icon(icon, color: Colors.blue[800], size: 25), // Icon
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        Text(
          title,
          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
        ),
      ],
    );
  }

  // New widget to build renter features (ID Verified, past rentals)
  Widget _buildRenterFeatureRow(String text, IconData icon, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(fontSize: 14, color: Colors.grey[800])),
      ],
    );
  }

  Future<Map<String, dynamic>> _fetchRelatedDetails(String itemId, String renterId) async {
    String itemName = 'Unknown Item';
    String itemImageUrl = 'https://placehold.co/600x400/cccccc/000000?text=No+Image';
    String renterName = 'Unknown Renter';
    String renterProfilePicUrl = 'assets/images/Profile_Placeholder.png';
    double renterSmartTrustScore = 0.0;
    int renterReturnRate = 0;
    bool renterIdVerified = false;
    int renterPastRentals = 0;

    // Fetch item details
    try {
      DocumentSnapshot itemDoc = await _firestore.collection('items').doc(itemId).get();
      if (itemDoc.exists) {
        final itemData = itemDoc.data() as Map<String, dynamic>;
        itemName = itemData['name'] ?? 'Unknown Item';
        if (itemData['images'] != null && itemData['images'] is List && itemData['images'].isNotEmpty && itemData['images'][0] is String) {
          itemImageUrl = itemData['images'][0];
        }
      }
    } catch (e) {
      print("Error fetching item details for request: $e");
    }

    // Fetch renter details
    try {
      DocumentSnapshot renterDoc = await _firestore.collection('users').doc(renterId).get();
      if (renterDoc.exists) {
        final renterData = renterDoc.data() as Map<String, dynamic>;
        renterName = renterData['name'] ?? 'Unknown Renter';
        renterProfilePicUrl = renterData['profilePictureUrl'] ?? 'assets/images/Profile_Placeholder.png';
        renterSmartTrustScore = (renterData['smartTrustScore'] as num?)?.toDouble() ?? 0.0; // Assuming this field exists
        renterReturnRate = (renterData['returnRate'] as int?) ?? 0; // Assuming this field exists
        renterIdVerified = renterData['idVerified'] ?? false; // Assuming this field exists
        renterPastRentals = (renterData['pastRentals'] as int?) ?? 0; // Assuming this field exists
      }
    } catch (e) {
      print("Error fetching renter details for request: $e");
    }

    return {
      'itemName': itemName,
      'itemImageUrl': itemImageUrl,
      'renterName': renterName,
      'renterProfilePicUrl': renterProfilePicUrl,
      'renterSmartTrustScore': renterSmartTrustScore,
      'renterReturnRate': renterReturnRate,
      'renterIdVerified': renterIdVerified,
      'renterPastRentals': renterPastRentals,
    };
  }
}
