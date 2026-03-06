import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; // Required for DateFormat

import '../services/auth_service.dart'; // Make sure this path is correct for your project

class RenterOrdersScreen extends StatefulWidget {
  const RenterOrdersScreen({Key? key}) : super(key: key);

  @override
  State<RenterOrdersScreen> createState() => _RenterOrdersScreenState();
}

class _RenterOrdersScreenState extends State<RenterOrdersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService(); // Your authentication service
  User? _currentUser;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _currentUser = _authService.getCurrentUser();
    
    // Check if user is logged in. If not, show snackbar and redirect.
    if (_currentUser == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please log in to view your orders.')),
          );
          // Assuming '/login' is your login route
          Navigator.pushReplacementNamed(context, '/login'); 
        }
      });
    } else {
      _isLoading = false;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Function to show the order confirmation dialog for delivery orders
  // This dialog handles logistics selection for APPROVED orders
  Future<void> _showOrderConfirmationDialog(Map<String, dynamic> orderData) async {
    final String itemName = orderData['itemName'] ?? 'Item';
    final String orderId = orderData['orderId'] ?? ''; // Ensure orderId is passed
    final String deliveryType = orderData['deliveryOptionType'] ?? 'meet_up';
    final String startDate = DateFormat('dd MMM').format((orderData['startDate'] as Timestamp).toDate());
    final String endDate = DateFormat('dd MMM').format((orderData['endDate'] as Timestamp).toDate());
    final double totalPrice = (orderData['totalPrice'] as num?)?.toDouble() ?? 0.0;
    final double protectionPlanFee = (orderData['protectionPlanFee'] as num?)?.toDouble() ?? 0.0;
    final Map<String, dynamic> deliveryAddress = orderData['deliveryAddress'] ?? {};
    String selectedLogistics = 'J&T'; // Default selection

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              title: Text('Booking Confirmation: "$itemName"'),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Your order has been approved!',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green),
                    ),
                    const SizedBox(height: 10),
                    Text('Rental Period: $startDate - $endDate'),
                    Text('Total Price: RM${totalPrice.toStringAsFixed(2)}'),
                    if (protectionPlanFee > 0)
                      Text('Protection Plan: RM${protectionPlanFee.toStringAsFixed(2)}'),
                    const SizedBox(height: 15),

                    if (deliveryType == 'delivery') ...[
                      const Text('Select Your Logistics:', style: TextStyle(fontWeight: FontWeight.bold)),
                      RadioListTile(
                        title: const Text('J&T'),
                        value: 'J&T',
                        groupValue: selectedLogistics,
                        onChanged: (value) => setState(() => selectedLogistics = value.toString()),
                      ),
                      RadioListTile(
                        title: const Text('Pos Laju'),
                        value: 'Pos Laju',
                        groupValue: selectedLogistics,
                        onChanged: (value) => setState(() => selectedLogistics = value.toString()),
                      ),
                      RadioListTile(
                        title: const Text('Ninja Van'),
                        value: 'Ninja Van',
                        groupValue: selectedLogistics,
                        onChanged: (value) => setState(() => selectedLogistics = value.toString()),
                      ),
                      const SizedBox(height: 10),
                      const Text('Delivery Address:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('${deliveryAddress['building'] ?? ''}, ${deliveryAddress['street'] ?? ''}'),
                      Text('${deliveryAddress['city'] ?? ''}, ${deliveryAddress['postcode'] ?? ''}, ${deliveryAddress['state'] ?? ''}'),
                    ] else ...[
                      const Text('Meet-Up Option:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const Text('Please coordinate with the lender for the meet-up time and location.'),
                    ],
                  ],
                ),
              ),
              actions: <Widget>[
                if (deliveryType == 'delivery')
                  ElevatedButton(
                    onPressed: () async {
                      try {
                        await FirebaseFirestore.instance.collection('orders').doc(orderId).update({
                          'selectedLogistics': selectedLogistics,
                          'logisticsSelectedAt': FieldValue.serverTimestamp(),
                        });
                        if (mounted) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('You selected "$selectedLogistics" for delivery.')),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to save logistics: ${e.toString()}')),
                          );
                        }
                      }
                    },
                    child: const Text('Confirm Logistics'),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Function to confirm and cancel an order
  Future<void> _cancelOrder(String orderId, String itemName) async {
    bool? confirmCancel = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Text('Cancel Order?', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          content: Text('Are you sure you want to cancel the order for "$itemName"? This action cannot be undone.'),
          actions: <Widget>[
            TextButton(
              child: const Text('No'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Yes, Cancel'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );

    if (confirmCancel == true) {
      setState(() {
        _isLoading = true; // Show loading indicator
      });
      try {
        await _firestore.collection('orders').doc(orderId).update({
          'status': 'cancelled',
          'lastUpdatedAt': FieldValue.serverTimestamp(),
          'cancelledAt': FieldValue.serverTimestamp(),
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Order for "$itemName" cancelled successfully.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to cancel order: ${e.toString()}')),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false; // Hide loading indicator
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // If user is null (not logged in), show a simple message
    if (_currentUser == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('My Orders'),
          backgroundColor: Colors.blue[800],
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text('You must be logged in to view your orders.')),
      );
    }

    // Show loading indicator if initial data is being fetched
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('My Orders'),
          backgroundColor: Colors.blue[800],
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Orders'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Pending'),
            Tab(text: 'Approved'),
            Tab(text: 'Rejected'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Each tab view builds a list of orders based on the filter
          _buildOrderItemList('All'),
          _buildOrderItemList('pending'),
          _buildOrderItemList('approved'),
          _buildOrderItemList('rejected'),
        ],
      ),
    );
  }

  // Builds the list of order items for a specific status filter
  Widget _buildOrderItemList(String statusFilter) {
    Stream<QuerySnapshot> orderStream;
    // Construct Firestore query based on status filter
    if (statusFilter == 'All') {
      orderStream = _firestore
          .collection('orders')
          .where('renterId', isEqualTo: _currentUser!.uid)
          .orderBy('createdAt', descending: true)
          .snapshots();
    } else {
      orderStream = _firestore
          .collection('orders')
          .where('renterId', isEqualTo: _currentUser!.uid)
          .where('status', isEqualTo: statusFilter)
          .orderBy('createdAt', descending: true)
          .snapshots();
    }

    return StreamBuilder<QuerySnapshot>(
      stream: orderStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Text(
              statusFilter == 'All'
                  ? 'You have no orders yet.'
                  : 'No ${statusFilter.toLowerCase()} orders.',
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16.0),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            DocumentSnapshot orderDoc = snapshot.data!.docs[index];
            Map<String, dynamic> orderData = orderDoc.data()! as Map<String, dynamic>;

            // Extract order details
            String orderId = orderDoc.id; // Get the document ID as orderId
            String itemId = orderData['itemId'] ?? '';
            Timestamp startDate = orderData['startDate'] as Timestamp;
            Timestamp endDate = orderData['endDate'] as Timestamp;
            String status = orderData['status'] ?? 'unknown';
            double totalPrice = (orderData['totalPrice'] as num?)?.toDouble() ?? 0.0;
            double protectionPlanFee = (orderData['protectionPlanFee'] as num?)?.toDouble() ?? 0.0;
            String deliveryOptionType = orderData['deliveryOptionType'] ?? 'meet_up';
            
            // Use FutureBuilder to get item details (name, image) for each order card
            return FutureBuilder<DocumentSnapshot>(
              future: _firestore.collection('items').doc(itemId).get(),
              builder: (context, itemSnapshot) {
                String itemName = 'Loading Item...';
                String itemImageUrl = 'assets/images/examples.png'; // Fallback for local assets or errors

                if (itemSnapshot.connectionState == ConnectionState.done &&
                    itemSnapshot.hasData &&
                    itemSnapshot.data!.exists) {
                  final itemData = itemSnapshot.data!.data() as Map<String, dynamic>;
                  itemName = itemData['name'] ?? 'Unknown Item';
                  // Check if images list exists, is not empty, and first element is a non-empty string URL
                  if (itemData['images'] != null &&
                      itemData['images'] is List &&
                      itemData['images'].isNotEmpty &&
                      itemData['images'][0] is String &&
                      (itemData['images'][0] as String).isNotEmpty) {
                    itemImageUrl = itemData['images'][0];
                  }
                }

                // Determine status color for UI display
                Color statusColor;
                switch (status.toLowerCase()) {
                  case 'pending':
                    statusColor = Colors.orange;
                    break;
                  case 'approved':
                    statusColor = Colors.green;
                    break;
                  case 'rejected':
                    statusColor = Colors.red;
                    break;
                  case 'cancelled':
                    statusColor = Colors.grey;
                    break;
                  case 'completed':
                    statusColor = Colors.blue;
                    break;
                  default:
                    statusColor = Colors.grey; // Default for 'unknown' or other statuses
                    break;
                }

                // UI for each order card
                return Card(
                  margin: const EdgeInsets.only(bottom: 15),
                  elevation: 3,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: () {
                            // Only show confirmation dialog for approved orders
                            if (status == 'approved') {
                              // Prepare data for the confirmation dialog
                              Map<String, dynamic> fullOrderData = Map<String, dynamic>.from(orderData);
                              fullOrderData['itemName'] = itemName;
                              fullOrderData['itemImageUrl'] = itemImageUrl;
                              fullOrderData['orderId'] = orderId; // Ensure orderId is explicitly added
                              _showOrderConfirmationDialog(fullOrderData);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Order for "$itemName" is currently $status.')),
                              );
                            }
                          },
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: itemImageUrl.startsWith('http') // Check if it's a network image
                                    ? Image.network(
                                        itemImageUrl,
                                        width: 80,
                                        height: 80,
                                        fit: BoxFit.cover,
                                        // Error builder for network images
                                        errorBuilder: (context, error, stackTrace) => Image.asset(
                                          'assets/images/examples.png', // Fallback local asset for network errors
                                          fit: BoxFit.cover,
                                          width: 80, height: 80, // Ensure dimensions for fallback
                                        ),
                                      )
                                    : Image.asset( // Assume it's a local asset
                                        itemImageUrl,
                                        width: 80,
                                        height: 80,
                                        fit: BoxFit.cover,
                                        // Error builder for local assets
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
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${DateFormat('dd MMM').format(startDate.toDate())} - ${DateFormat('dd MMM').format(endDate.toDate())}',
                                      style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Total: RM${totalPrice.toStringAsFixed(2)}',
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue[700]),
                                    ),
                                    if (protectionPlanFee > 0)
                                      Text(
                                        'Protection: RM${protectionPlanFee.toStringAsFixed(2)}',
                                        style: TextStyle(fontSize: 12, color: Colors.green[700]),
                                      ),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: statusColor,
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: Text(
                                        status.toUpperCase(),
                                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Display Cancel Order button for pending orders
                        if (status == 'pending')
                          Padding(
                            padding: const EdgeInsets.only(top: 12.0),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: () => _cancelOrder(orderId, itemName),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text('Cancel Order'),
                              ),
                            ),
                          ),
                        
                        // Conditional "Mark as Completed" button
                        // Appears if order is approved AND end date is past
                        if (status == 'approved' && endDate.toDate().isBefore(DateTime.now()))
                          Padding(
                            padding: const EdgeInsets.only(top: 12.0),
                            child: SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  try {
                                    // 1. Update order status to 'completed' in Firestore
                                    await _firestore.collection('orders').doc(orderId).update({
                                      'status': 'completed',
                                      'completedAt': FieldValue.serverTimestamp(),
                                    });

                                    // 2. Show a success message (SnackBar)
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Order marked as complete!')),
                                    );

                                    // 3. Prompt user for review with a confirmation dialog
                                    bool? wantsToReview = await showDialog<bool>(
                                      context: context,
                                      barrierDismissible: false, // User must make a choice
                                      builder: (BuildContext dialogContext) {
                                        final dialogTheme = Theme.of(dialogContext);
                                        return AlertDialog(
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                                          title: Text('Order Completed!', style: dialogTheme.textTheme.headlineSmall),
                                          content: Text(
                                            'Your order has been marked as complete. Would you like to leave a review for "$itemName"?',
                                            style: dialogTheme.textTheme.bodyMedium,
                                          ),
                                          actions: <Widget>[
                                            TextButton(
                                              onPressed: () {
                                                Navigator.of(dialogContext).pop(false); // User declines
                                              },
                                              child: const Text('No, Thanks'),
                                            ),
                                            ElevatedButton(
                                              onPressed: () {
                                                Navigator.of(dialogContext).pop(true); // User agrees
                                              },
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: dialogTheme.colorScheme.primary,
                                                foregroundColor: dialogTheme.colorScheme.onPrimary,
                                              ),
                                              child: const Text('Leave a Review'),
                                            ),
                                          ],
                                        );
                                      },
                                    );

                                    // 4. If user agreed, show the review submission dialog
                                    if (wantsToReview == true) {
                                      double _rating = 0;
                                      TextEditingController _commentController = TextEditingController();
                                      bool _isSubmitting = false;

                                      await showDialog(
                                        context: context,
                                        barrierDismissible: false, // Prevent dismissal until action is taken
                                        builder: (context) {
                                          return StatefulBuilder( // Manages state within the dialog
                                            builder: (context, setStateInDialog) {
                                              final dialogTheme = Theme.of(context);
                                              return Dialog(
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                                backgroundColor: dialogTheme.dialogBackgroundColor,
                                                child: Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                                                  child: Column(
                                                    mainAxisSize: MainAxisSize.min,
                                                    crossAxisAlignment: CrossAxisAlignment.center,
                                                    children: [
                                                      Icon(Icons.star_rate_rounded, color: Colors.amber[700], size: 40),
                                                      const SizedBox(height: 8),
                                                      Text('Leave a Review',
                                                          style: dialogTheme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                                                      const SizedBox(height: 4),
                                                      Text('How was your experience?',
                                                          textAlign: TextAlign.center,
                                                          style: dialogTheme.textTheme.bodyMedium?.copyWith(color: dialogTheme.hintColor)),
                                                      const SizedBox(height: 18),
                                                      Row(
                                                        mainAxisAlignment: MainAxisAlignment.center,
                                                        children: List.generate(5, (index) {
                                                          return GestureDetector(
                                                            onTap: () {
                                                              setStateInDialog(() { // Update dialog's state
                                                                _rating = index + 1.0;
                                                              });
                                                            },
                                                            child: AnimatedContainer(
                                                              duration: const Duration(milliseconds: 150),
                                                              margin: const EdgeInsets.symmetric(horizontal: 4),
                                                              child: Icon(
                                                                index < _rating ? Icons.star_rounded : Icons.star_border_rounded,
                                                                color: index < _rating ? Colors.amber[700] : dialogTheme.disabledColor,
                                                                size: 36,
                                                              ),
                                                            ),
                                                          );
                                                        }),
                                                      ),
                                                      const SizedBox(height: 18),
                                                      TextField(
                                                        controller: _commentController,
                                                        decoration: InputDecoration(
                                                          labelText: 'Comment',
                                                          labelStyle: dialogTheme.textTheme.bodyMedium?.copyWith(color: dialogTheme.hintColor),
                                                          filled: true,
                                                          fillColor: dialogTheme.inputDecorationTheme.fillColor ?? dialogTheme.cardColor,
                                                          border: OutlineInputBorder(
                                                            borderRadius: BorderRadius.circular(14),
                                                            borderSide: BorderSide(color: dialogTheme.dividerColor),
                                                          ),
                                                          focusedBorder: OutlineInputBorder(
                                                            borderRadius: BorderRadius.circular(14),
                                                            borderSide: BorderSide(color: dialogTheme.colorScheme.primary, width: 2),
                                                          ),
                                                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                                        ),
                                                        minLines: 2,
                                                        maxLines: 4,
                                                      ),
                                                      const SizedBox(height: 22),
                                                      Row(
                                                        mainAxisAlignment: MainAxisAlignment.end,
                                                        children: [
                                                          if (_isSubmitting) // Show loading indicator while submitting
                                                            const SizedBox(
                                                              width: 28,
                                                              height: 28,
                                                              child: CircularProgressIndicator(strokeWidth: 2.5),
                                                            ),
                                                          if (!_isSubmitting) // Show buttons if not submitting
                                                            TextButton(
                                                              style: TextButton.styleFrom(
                                                                foregroundColor: dialogTheme.colorScheme.primary,
                                                                textStyle: dialogTheme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                                                              ),
                                                              onPressed: () async {
                                                                // Input validation
                                                                if (_rating == 0 || _commentController.text.trim().isEmpty) {
                                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                                    const SnackBar(content: Text('Please provide a rating and comment.')),
                                                                  );
                                                                  return;
                                                                }
                                                                setStateInDialog(() => _isSubmitting = true); // Set dialog to submitting state
                                                                try {
                                                                  // Add the new review document to Firestore
                                                                  await _firestore.collection('reviews').add({
                                                                    'orderId': orderId,
                                                                    'itemId': itemId,
                                                                    'userId': _currentUser?.uid,
                                                                    'rating': _rating,
                                                                    'comment': _commentController.text.trim(),
                                                                    'createdAt': FieldValue.serverTimestamp(),
                                                                  });

                                                                  // Use a Firestore Transaction to safely update item's average rating
                                                                  await _firestore.runTransaction((transaction) async {
                                                                    final itemRef = _firestore.collection('items').doc(itemId);
                                                                    final itemSnapshot = await transaction.get(itemRef);

                                                                    if (!itemSnapshot.exists) {
                                                                      throw Exception("Item with ID $itemId does not exist! Cannot update rating.");
                                                                    }

                                                                    // Retrieve current rating data from the item document
                                                                    final double currentAverageRating = itemSnapshot.data()?['averageRating']?.toDouble() ?? 0.0;
                                                                    final int currentReviewCount = itemSnapshot.data()?['reviewCount'] ?? 0;

                                                                    // Calculate new total sum of ratings and new count
                                                                    final double newTotalRatingSum = (currentAverageRating * currentReviewCount) + _rating;
                                                                    final int newReviewCount = currentReviewCount + 1;
                                                                    final double newAverageRating = newTotalRatingSum / newReviewCount;

                                                                    // Update the item document within the transaction
                                                                    transaction.update(itemRef, {
                                                                      'averageRating': newAverageRating,
                                                                      'reviewCount': newReviewCount,
                                                                    });
                                                                  });

                                                                  // If all operations succeed
                                                                  Navigator.of(context).pop(); // Close the review dialog
                                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                                    const SnackBar(content: Text('Review submitted and item rating updated!')),
                                                                  );
                                                                  // Trigger a rebuild of the parent RenterOrdersScreen
                                                                  // by changing the _isLoading state to force re-fetch of orders
                                                                  if (mounted) {
                                                                    setState(() {
                                                                      // This will cause the entire RenterOrdersScreen to refresh its StreamBuilder
                                                                      // and thus re-evaluate all order cards, hiding the 'Mark as Complete'
                                                                      // and showing the 'Review Submitted' for this order.
                                                                      _isLoading = true; // Briefly set to true to trigger reload
                                                                    });
                                                                    // After a short delay, set it back to false to show content
                                                                    Future.delayed(const Duration(milliseconds: 500), () {
                                                                      if (mounted) setState(() => _isLoading = false);
                                                                    });
                                                                  }
                                                                } catch (e) {
                                                                  setStateInDialog(() => _isSubmitting = false); // Reset dialog state
                                                                  print('Failed to submit review or update item rating: ${e.toString()}');
                                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                                    SnackBar(content: Text('Failed to submit review: ${e.toString()}')),
                                                                  );
                                                                }
                                                              },
                                                              child: const Text('Submit'),
                                                            ),
                                                          const SizedBox(width: 8),
                                                          if (!_isSubmitting)
                                                            TextButton(
                                                              style: TextButton.styleFrom(
                                                                foregroundColor: dialogTheme.colorScheme.secondary,
                                                              ),
                                                              onPressed: () => Navigator.of(context).pop(),
                                                              child: const Text('Cancel'),
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
                                      );
                                    }

                                    // After "Mark as Complete" (and potentially review) is done,
                                    // trigger a rebuild of the main RenterOrdersScreen
                                    // This ensures the order status and review prompt are updated.
                                    if (mounted) {
                                      setState(() {
                                        _isLoading = true; // Briefly set to true to trigger reload
                                      });
                                      Future.delayed(const Duration(milliseconds: 500), () {
                                        if (mounted) setState(() => _isLoading = false);
                                      });
                                    }
                                  } catch (e) {
                                    print('Failed to mark order as complete or prompt for review: ${e.toString()}');
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Operation failed: ${e.toString()}')),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.check_circle),
                                label: const Text('Mark as Completed'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue, // Primary button color for completion
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                          ),
                        
                        // Conditional display for review status or "Leave a Review" button
                        // This section appears if the order is 'completed'
                        if (status == 'completed')
                          FutureBuilder<DocumentSnapshot?>(
                            // Query the 'reviews' collection to see if the user has already reviewed this order/item
                            future: _firestore
                                .collection('reviews')
                                .where('orderId', isEqualTo: orderId)
                                .where('userId', isEqualTo: _currentUser?.uid)
                                .limit(1) // Only need to know if at least one exists
                                .get()
                                .then((query) => query.docs.isNotEmpty ? query.docs.first : null),
                            builder: (context, reviewSnapshot) {
                              if (reviewSnapshot.connectionState == ConnectionState.waiting) {
                                return const Padding(
                                  padding: EdgeInsets.only(top: 12.0),
                                  child: SizedBox(height: 48, child: Center(child: CircularProgressIndicator())),
                                );
                              }
                              if (reviewSnapshot.hasError) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 12.0),
                                  child: Text('Error loading review: ${reviewSnapshot.error}', style: const TextStyle(color: Colors.red)),
                                );
                              }
                              
                              // If a review exists, display its details
                              if (reviewSnapshot.hasData && reviewSnapshot.data != null && reviewSnapshot.data!.exists) {
                                final review = reviewSnapshot.data!.data() as Map<String, dynamic>;
                                return Padding(
                                  padding: const EdgeInsets.only(top: 12.0),
                                  child: Container(
                                    padding: const EdgeInsets.all(12.0),
                                    decoration: BoxDecoration(
                                      color: Colors.amber[50], // Light background for submitted review
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.amber[700]!),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.check_circle_outline, color: Colors.amber[700], size: 20),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Review Submitted!',
                                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.amber[800], fontWeight: FontWeight.w600),
                                              ),
                                              Text('Your rating: ${review['rating']} stars',
                                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.amber[800])),
                                              if (review['comment'] != null && (review['comment'] as String).isNotEmpty)
                                                Text('Comment: "${review['comment']}"',
                                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.amber[800], fontStyle: FontStyle.italic)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              } else {
                                // If order is completed but no review exists, show "Leave a Review" button
                                // This handles cases where user declined initial prompt or returned to screen later.
                                return Padding(
                                  padding: const EdgeInsets.only(top: 12.0),
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        double _rating = 0;
                                        TextEditingController _commentController = TextEditingController();
                                        bool _isSubmitting = false;

                                        await showDialog(
                                          context: context,
                                          barrierDismissible: false,
                                          builder: (context) {
                                            return StatefulBuilder(
                                              builder: (context, setStateInDialog) {
                                                final dialogTheme = Theme.of(context);
                                                return Dialog(
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                                  backgroundColor: dialogTheme.dialogBackgroundColor,
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                                                    child: Column(
                                                      mainAxisSize: MainAxisSize.min,
                                                      crossAxisAlignment: CrossAxisAlignment.center,
                                                      children: [
                                                        Icon(Icons.star_rate_rounded, color: Colors.amber[700], size: 40),
                                                        const SizedBox(height: 8),
                                                        Text('Leave a Review',
                                                            style: dialogTheme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                                                        const SizedBox(height: 4),
                                                        Text('How was your experience?',
                                                            textAlign: TextAlign.center,
                                                            style: dialogTheme.textTheme.bodyMedium?.copyWith(color: dialogTheme.hintColor)),
                                                        const SizedBox(height: 18),
                                                        Row(
                                                          mainAxisAlignment: MainAxisAlignment.center,
                                                          children: List.generate(5, (index) {
                                                            return GestureDetector(
                                                              onTap: () {
                                                                setStateInDialog(() {
                                                                  _rating = index + 1.0;
                                                                });
                                                              },
                                                              child: AnimatedContainer(
                                                                duration: const Duration(milliseconds: 150),
                                                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                                                child: Icon(
                                                                  index < _rating ? Icons.star_rounded : Icons.star_border_rounded,
                                                                  color: index < _rating ? Colors.amber[700] : dialogTheme.disabledColor,
                                                                  size: 36,
                                                                ),
                                                              ),
                                                            );
                                                          }),
                                                        ),
                                                        const SizedBox(height: 18),
                                                        TextField(
                                                          controller: _commentController,
                                                          decoration: InputDecoration(
                                                            labelText: 'Comment',
                                                            labelStyle: dialogTheme.textTheme.bodyMedium?.copyWith(color: dialogTheme.hintColor),
                                                            filled: true,
                                                            fillColor: dialogTheme.inputDecorationTheme.fillColor ?? dialogTheme.cardColor,
                                                            border: OutlineInputBorder(
                                                              borderRadius: BorderRadius.circular(14),
                                                              borderSide: BorderSide(color: dialogTheme.dividerColor),
                                                            ),
                                                            focusedBorder: OutlineInputBorder(
                                                              borderRadius: BorderRadius.circular(14),
                                                              borderSide: BorderSide(color: dialogTheme.colorScheme.primary, width: 2),
                                                            ),
                                                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                                          ),
                                                          minLines: 2,
                                                          maxLines: 4,
                                                        ),
                                                        const SizedBox(height: 22),
                                                        Row(
                                                          mainAxisAlignment: MainAxisAlignment.end,
                                                          children: [
                                                            if (_isSubmitting)
                                                              const SizedBox(
                                                                width: 28,
                                                                height: 28,
                                                                child: CircularProgressIndicator(strokeWidth: 2.5),
                                                              ),
                                                            if (!_isSubmitting)
                                                              TextButton(
                                                                style: TextButton.styleFrom(
                                                                  foregroundColor: dialogTheme.colorScheme.primary,
                                                                  textStyle: dialogTheme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                                                                ),
                                                                onPressed: () async {
                                                                  if (_rating == 0 || _commentController.text.trim().isEmpty) {
                                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                                      const SnackBar(content: Text('Please provide a rating and comment.')),
                                                                    );
                                                                    return;
                                                                  }
                                                                  setStateInDialog(() => _isSubmitting = true);
                                                                  try {
                                                                    await _firestore.collection('reviews').add({
                                                                      'orderId': orderId,
                                                                      'itemId': itemId,
                                                                      'userId': _currentUser?.uid,
                                                                      'rating': _rating,
                                                                      'comment': _commentController.text.trim(),
                                                                      'createdAt': FieldValue.serverTimestamp(),
                                                                    });

                                                                    await _firestore.runTransaction((transaction) async {
                                                                      final itemRef = _firestore.collection('items').doc(itemId);
                                                                      final itemSnapshot = await transaction.get(itemRef);

                                                                      if (!itemSnapshot.exists) {
                                                                        throw Exception("Item with ID $itemId does not exist! Cannot update rating.");
                                                                      }

                                                                      final double currentAverageRating = itemSnapshot.data()?['averageRating']?.toDouble() ?? 0.0;
                                                                      final int currentReviewCount = itemSnapshot.data()?['reviewCount'] ?? 0;

                                                                      final double newTotalRatingSum = (currentAverageRating * currentReviewCount) + _rating;
                                                                      final int newReviewCount = currentReviewCount + 1;
                                                                      final double newAverageRating = newTotalRatingSum / newReviewCount;

                                                                      transaction.update(itemRef, {
                                                                        'averageRating': newAverageRating,
                                                                        'reviewCount': newReviewCount,
                                                                      });
                                                                    });

                                                                    Navigator.of(context).pop(); // Close the review dialog
                                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                                      const SnackBar(content: Text('Review submitted and item rating updated!')),
                                                                    );
                                                                    // Trigger a refresh of the RenterOrdersScreen
                                                                    // to reflect the review status and hide this button
                                                                    if (mounted) {
                                                                      setState(() {
                                                                        _isLoading = true;
                                                                      });
                                                                      Future.delayed(const Duration(milliseconds: 500), () {
                                                                        if (mounted) setState(() => _isLoading = false);
                                                                      });
                                                                    }
                                                                  } catch (e) {
                                                                    setStateInDialog(() => _isSubmitting = false);
                                                                    print('Failed to submit review or update item rating: ${e.toString()}');
                                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                                      SnackBar(content: Text('Failed to submit review: ${e.toString()}')),
                                                                    );
                                                                  }
                                                                },
                                                                child: const Text('Submit'),
                                                              ),
                                                            const SizedBox(width: 8),
                                                            if (!_isSubmitting)
                                                              TextButton(
                                                                style: TextButton.styleFrom(
                                                                  foregroundColor: dialogTheme.colorScheme.secondary,
                                                                ),
                                                                onPressed: () => Navigator.of(context).pop(),
                                                                child: const Text('Cancel'),
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
                                        );
                                      },
                                      icon: const Icon(Icons.star),
                                      label: const Text('Leave a Review'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.amber[800],
                                        side: BorderSide(color: Colors.amber[800]!),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                    ),
                                  ),
                                );
                              }
                            },
                          ),
                        // This block catches statuses other than 'pending', 'approved', 'completed'
                        if (status != 'completed' && status != 'pending' && status != 'approved')
                          Padding(
                            padding: const EdgeInsets.only(top: 12.0),
                            child: Text(
                              'This order is ${status.toLowerCase()}.',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic, color: Theme.of(context).hintColor),
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
    );
  }
}