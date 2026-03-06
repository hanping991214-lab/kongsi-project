import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Import for current user check
import 'package:geocoding/geocoding.dart'; // Import the geocoding package
import '../services/auth_service.dart'; // For getting user profile and current user ID
import 'booking_screen.dart'; // Import the new BookingScreen

class ItemDetailScreen extends StatefulWidget {
  final String itemId;

  const ItemDetailScreen({Key? key, required this.itemId}) : super(key: key);

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  final AuthService _authService = AuthService();
  User? _currentUser;
  bool _isLoading = true;
  Map<String, dynamic>? _itemData; // To store fetched item data
  Map<String, dynamic>? _ownerData; // To store fetched owner data

  int _rentalDays = 2; // Default rental duration for renter's selection
  bool _rentWithDeposit = false; // True for "Rent with Deposit", false for "Rent with Zero Deposit"
  bool _lenderRequiresDepositOnly = false; // To store lender's setting

  // State variable to track user's KYC verification status
  bool _isUserKycVerified = false;

  @override
  void initState() {
    super.initState();
    _currentUser = FirebaseAuth.instance.currentUser; // Get current user on init
    _fetchItemAndOwnerDetails();
  }

  Future<void> _fetchItemAndOwnerDetails() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Fetch item details
      DocumentSnapshot itemDoc = await FirebaseFirestore.instance
          .collection('items')
          .doc(widget.itemId)
          .get();

      if (itemDoc.exists) {
        _itemData = itemDoc.data() as Map<String, dynamic>;

        _lenderRequiresDepositOnly = _itemData?['requiresDepositOnly'] ?? true; 
        
        // Set initial rental option based on lender's preference
        // If lender requires deposit only, then rentWithDeposit MUST be true.
        // Otherwise (if lender allows both), default to rentWithDeposit = true as requested.
        _rentWithDeposit = true; // Default to Rent with Deposit
        if (!_lenderRequiresDepositOnly) {
          // If lender allows both, and we want to default to Rent with Deposit,
          // this line ensures it remains true. If we wanted to default to Zero Deposit,
          // we would set _rentWithDeposit = false; here.
          // Since the request is to default to "Rent with Deposit" when both are available,
          // we keep it true.
        }


        // Fetch owner details
        String? ownerId = _itemData?['ownerId'];
        if (ownerId != null && ownerId.isNotEmpty) {
          DocumentSnapshot ownerDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(ownerId)
              .get();
          if (ownerDoc.exists) {
            _ownerData = ownerDoc.data() as Map<String, dynamic>;
          }
        }

        // Fetch current user's KYC status if logged in
        if (_currentUser != null) {
          DocumentSnapshot userProfileDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(_currentUser!.uid)
              .get();
          
          if (userProfileDoc.exists && userProfileDoc.data() != null) {
            final userData = userProfileDoc.data()! as Map<String, dynamic>;
            _isUserKycVerified = userData['isKycVerified'] ?? false;
          } else {
            _isUserKycVerified = false; // Default to false if user profile doesn't exist or data is null
          }
        }

      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Item not found.')),
          );
          Navigator.pop(context);
          return;
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading item details: ${e.toString().replaceFirst('Exception: ', '')}')),
        );
        Navigator.pop(context);
        return;
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Function to perform reverse geocoding
  Future<String> _getReadableLocation(dynamic location) async {
    if (location is GeoPoint) {
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(location.latitude, location.longitude);
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks.first;
          return "${place.street ?? ''}, ${place.locality ?? place.subLocality ?? ''}, ${place.postalCode ?? ''}";
        }
      } catch (e) {
        print("Error during reverse geocoding: $e");
        return 'Lat: ${location.latitude.toStringAsFixed(4)}, Lng: ${location.longitude.toStringAsFixed(4)} (Geocoding failed)';
      }
    } else if (location is String && location.isNotEmpty) {
      return location; // Return string location directly if already a string
    }
    return 'Unknown Location'; // Default fallback
  }

  // Calculate total rental fee dynamically based on selected options
  double _calculateTotalRentalFee() {
    if (_itemData == null) return 0.0;

    double pricePerDay = (_itemData!['pricePerDay'] as num?)?.toDouble() ?? 0.0;
    double rentalCost = pricePerDay * _rentalDays;
    double processingFee = 0.0;
    // double depositAmount = (_itemData!['depositAmount'] as num?)?.toDouble() ?? 0.0; // Not directly used in total

    if (_rentWithDeposit) {
      processingFee = 2.64; // Example fixed processing fee for with deposit
    } else {
      processingFee = 1.50; // Example fixed processing fee for zero deposit
    }

    double total = rentalCost + processingFee;
    return total;
  }

  // Function for navigating to the BookingPage
  void _navigateToBookingPage() {
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to place a booking.')),
      );
      Navigator.pushNamed(context, '/login');
      return;
    }

    if (_itemData != null && _currentUser!.uid == _itemData!['ownerId']) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You cannot rent your own item.')),
      );
      return;
    }

    // No KYC check here for _rentWithDeposit, as per new logic.
    // The KYC check for Zero-Deposit is handled directly in the onTap of the UI element.

    // Navigate to the BookingPage, passing the itemId
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BookingPage(itemId: widget.itemId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Item Details'),
          backgroundColor: Colors.blue[800],
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_itemData == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Item Details'),
          backgroundColor: Colors.blue[800],
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text('Failed to load item details.')),
      );
    }

    List<String> imageUrls = [];
    if (_itemData!['images'] != null && _itemData!['images'] is List) {
      imageUrls = List<String>.from(_itemData!['images']);
    }

    String pricePerDay = 'RM${(_itemData!['pricePerDay'] as num?)?.toStringAsFixed(2) ?? '0.00'}/day';
    double calculatedTotal = _calculateTotalRentalFee();

    // Owner info
    String ownerName = _ownerData?['name'] ?? 'Unknown Owner';
    String ownerProfilePicUrl = _ownerData?['profilePictureUrl'] ?? '';
    // Fallback logic for ownerProfilePicUrl
    if (ownerProfilePicUrl.isEmpty) {
        // You might consider a generic asset or default network image here
        // For now, it will use the placeholder asset.
    }

    // Specifications display
    List<String> specifications = [];
    if (_itemData!['specifications'] != null && _itemData!['specifications'] is List) {
      specifications = List<String>.from(_itemData!['specifications']);
    }

    // Likes and Rates (assuming fields exist in Firestore)
    int likesCount = (_itemData!['likesCount'] as int?) ?? 0;
    double averageRating = (_itemData!['averageRating'] as num?)?.toDouble() ?? 0.0;
    int reviewCount = (_itemData!['reviewCount'] as int?) ?? 0;


    return Scaffold(
      appBar: AppBar(
        title: const Text('Item Details'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Item Images Carousel
            Container(
              height: 250,
              color: Colors.grey[200], // Placeholder color if no image
              child: imageUrls.isNotEmpty
                  ? PageView.builder(
                      itemCount: imageUrls.length,
                      itemBuilder: (context, index) {
                        return Image.network(
                          imageUrls[index],
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (context, error, stackTrace) => Image.asset(
                            'assets/images/examples.png', // Fallback for network image errors
                            fit: BoxFit.cover,
                          ),
                        );
                      },
                    )
                  : Center(
                      child: Image.asset(
                        'assets/images/examples.png', // Default image if no URLs provided
                        fit: BoxFit.cover,
                        width: double.infinity,
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _itemData!['name'] ?? 'Item Name Not Available',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        pricePerDay,
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[700]),
                      ),
                      Row(
                        children: [
                          Icon(Icons.thumb_up, size: 18, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text('$likesCount Likes', style: TextStyle(fontSize: 14, color: Colors.grey[700])),
                          const SizedBox(width: 10),
                          Icon(Icons.star, size: 18, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text('${averageRating.toStringAsFixed(1)} Rates', style: TextStyle(fontSize: 14, color: Colors.grey[700])),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  Text(
                    _itemData!['description'] ?? 'No description provided.',
                    style: TextStyle(fontSize: 16, color: Colors.grey[800]),
                  ),
                  const SizedBox(height: 20),

                  // Specifications Section
                  if (specifications.isNotEmpty) ...[
                    const Text(
                      'Specifications:',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: specifications.map((spec) => Padding(
                        padding: const EdgeInsets.only(bottom: 4.0),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_outline, size: 18, color: Colors.green[700]),
                            const SizedBox(width: 8),
                            Text(spec, style: TextStyle(fontSize: 15, color: Colors.grey[800])),
                          ],
                        ),
                      )).toList(),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Location Display with FutureBuilder for reverse geocoding
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start, // Align icon and text to start
                    children: [
                      Icon(Icons.location_on, size: 20, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Expanded( // <--- Wrapped FutureBuilder with Expanded
                        child: FutureBuilder<String>(
                          future: _getReadableLocation(_itemData!['location']),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Text('Loading location...', style: TextStyle(fontSize: 16, color: Colors.grey));
                            } else if (snapshot.hasError) {
                              return Text('Error: ${snapshot.error}', style: TextStyle(fontSize: 16, color: Colors.red));
                            } else {
                              return Text(
                                snapshot.data ?? 'Unknown Location',
                                style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                                maxLines: 2, // Allow text to wrap to 2 lines
                                overflow: TextOverflow.ellipsis, // Add ellipses if text still overflows
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const SizedBox(height: 20),

                  // Rental Options Section
                  const Text(
                    'Rental Options:',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),

                  // Rent with Zero Deposit Option (Yellow Box) - Conditionally displayed
                  if (!_lenderRequiresDepositOnly) // Only show if lender allows zero deposit
                    GestureDetector(
                      onTap: () {
                        if (_currentUser == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please log in to select this option.')),
                          );
                          Navigator.pushNamed(context, '/login');
                          return;
                        }
                        if (!_isUserKycVerified) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please complete KYC verification to use "Rent without Deposit" option.')),
                          );
                          return;
                        }
                        setState(() {
                          _rentWithDeposit = false;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _rentWithDeposit ? Colors.grey[200] : Colors.yellow[100],
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _rentWithDeposit ? Colors.grey : Colors.yellow.shade400,
                            width: _rentWithDeposit ? 1 : 2,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Rent with Zero Deposit',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: _rentWithDeposit ? Colors.grey[700] : Colors.orange[800],
                                  ),
                                ),
                                Icon(
                                  _rentWithDeposit ? Icons.radio_button_off : Icons.radio_button_on,
                                  color: _rentWithDeposit ? Colors.grey : Colors.orange[800],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text('• ${(_itemData!['pricePerDay'] as num?)?.toStringAsFixed(2) ?? '0.00'} x $_rentalDays Days Rental Fee',
                              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                            ),
                            Text('• Membership Pass (if applicable)',
                              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                            ),
                            Text('• Processing Fee: RM1.50', // Example fixed processing fee
                              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (!_lenderRequiresDepositOnly) // Add spacing only if zero deposit option is visible
                    const SizedBox(height: 15),

                  // Rent with Deposit Option (Blue Box)
                  GestureDetector(
                    onTap: () {
                      if (_currentUser == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please log in to select this option.')),
                        );
                        Navigator.pushNamed(context, '/login');
                        return;
                      }
                      // No KYC check needed here for "Rent with Deposit"
                      setState(() {
                        _rentWithDeposit = true;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _rentWithDeposit ? Colors.blue[50] : Colors.grey[200],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _rentWithDeposit ? Colors.blue.shade400 : Colors.grey,
                          width: _rentWithDeposit ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Rent with Deposit',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: _rentWithDeposit ? Colors.blue[800] : Colors.grey[700],
                                ),
                              ),
                              Icon(
                                _rentWithDeposit ? Icons.radio_button_on : Icons.radio_button_off,
                                color: _rentWithDeposit ? Colors.blue[800] : Colors.grey,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text('• ${(_itemData!['pricePerDay'] as num?)?.toStringAsFixed(2) ?? '0.00'} x $_rentalDays Days Rental Fee',
                            style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                          ),
                          Text('• Deposit (refundable): RM${(_itemData!['depositAmount'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                            style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                          ),
                          Text('• Processing Fee: RM2.64', // Example fixed processing fee
                            style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Rental Duration Selector and Book Now Button
                  Row(
                    children: [
                      // Minus button
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: OutlinedButton(
                          onPressed: () {
                            setState(() {
                              if (_rentalDays > 1) _rentalDays--;
                            });
                          },
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            side: BorderSide(color: Colors.blue[800]!),
                          ),
                          child: Icon(Icons.remove, color: Colors.blue[800]),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Days display
                      Expanded(
                        child: Container(
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$_rentalDays Days',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Plus button
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _rentalDays++;
                            });
                          },
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            side: BorderSide(color: Colors.blue[800]!),
                          ),
                          child: Icon(Icons.add, color: Colors.blue[800]),
                        ),
                      ),
                      const SizedBox(width: 15),
                      // Book Now Button (updated to reflect total)
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: _navigateToBookingPage, // Changed to navigate to booking page
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue[800],
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(
                            'Book Now (RM${calculatedTotal.toStringAsFixed(2)})',
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 30),
                  // Owner Info
                  const Text(
                    'Lender Information',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    leading: CircleAvatar(
                      radius: 25,
                      backgroundImage: ownerProfilePicUrl.isNotEmpty
                          ? NetworkImage(ownerProfilePicUrl)
                          : const AssetImage('assets/images/Profile_Placeholder.png') as ImageProvider,
                    ),
                    title: Text(
                      ownerName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: const Text('Owner of this item'),
                    trailing: IconButton(
                      icon: Icon(Icons.chat_bubble_outline, color: Colors.blue[700]),
                      onPressed: () {
                        if (_currentUser == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please log in to chat with the owner.')),
                          );
                          Navigator.pushNamed(context, '/login');
                          return;
                        }
                        // TODO: Navigate to chat screen with ownerId
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Chat with ${ownerName} (${_itemData!['ownerId']}) - Coming Soon!')),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
