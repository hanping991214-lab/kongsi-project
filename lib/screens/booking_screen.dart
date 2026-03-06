import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; // For date formatting

import '../services/auth_service.dart'; // Assuming you have an AuthService

class BookingPage extends StatefulWidget {
  final String itemId; // Item ID passed from the Item Detail page

  const BookingPage({Key? key, required this.itemId}) : super(key: key);

  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();
  User? _currentUser; // Current authenticated user

  DocumentSnapshot? _itemData; // To store fetched item details
  DocumentSnapshot? _userProfile; // To store current user's profile (for membership and KYC check)

  bool _isLoading = true; // Overall loading state for fetching item and user data
  bool _isMember = false; // To determine if the user is a member for deposit options
  bool _isUserKycVerified = false; // To determine if the user has completed KYC

  DateTime? _startDate; // Selected start date for rental
  int _rentalDays = 1; // Number of days for rental, default to 1

  // Deposit options
  bool _rentWithDeposit = true; // Default to renting with deposit

  // Delivery options
  String _deliveryOptionType = 'meet_up'; // 'meet_up' or 'delivery'
  final TextEditingController _meetUpLocationNotesController = TextEditingController();
  final TextEditingController _deliveryBuildingController = TextEditingController();
  final TextEditingController _deliveryStreetController = TextEditingController();
  final TextEditingController _deliveryCityController = TextEditingController();
  final TextEditingController _deliveryPostcodeController = TextEditingController();
  final TextEditingController _deliveryStateController = TextEditingController();

  double _deliveryFee = 0.0; // Default delivery fee

  // State for T&C checkbox on the main page
  bool _agreedToTerms = false;

  @override
  void initState() {
    super.initState();
    _currentUser = _authService.getCurrentUser();
    _fetchBookingData();
  }

  @override
  void dispose() {
    _meetUpLocationNotesController.dispose();
    _deliveryBuildingController.dispose();
    _deliveryStreetController.dispose();
    _deliveryCityController.dispose();
    _deliveryPostcodeController.dispose();
    _deliveryStateController.dispose();
    super.dispose();
  }

  Future<void> _fetchBookingData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Fetch item details
      DocumentSnapshot itemDoc = await _firestore.collection('items').doc(widget.itemId).get();
      if (!itemDoc.exists) {
        throw Exception("Item not found!");
      }
      _itemData = itemDoc;

      // Fetch user profile for membership status and KYC status
      if (_currentUser != null) {
        DocumentSnapshot userProfileDoc = await _firestore.collection('users').doc(_currentUser!.uid).get();
        if (userProfileDoc.exists && userProfileDoc.data() != null) {
          _userProfile = userProfileDoc;
          final userData = _userProfile!.data() as Map<String, dynamic>;
          _isMember = userData['isMember'] ?? false;
          _isUserKycVerified = userData['isKycVerified'] ?? false; // Get KYC status
        } else {
          _isMember = false;
          _isUserKycVerified = false; // Default to false if profile not found
        }
      } else {
        _isMember = false;
        _isUserKycVerified = false; // Not logged in, so not KYC verified
      }
    } catch (e) {
      // debugPrint("Error fetching booking data: $e"); // Removed debugPrint
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load booking data: ${e.toString().replaceFirst('Exception: ', '')}')),
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

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)), // Allow booking up to 1 year in advance
    );
    if (picked != null && picked != _startDate) {
      setState(() {
        _startDate = picked;
      });
    }
  }

  // Calculate the end date based on start date and rental days
  DateTime? _calculateEndDate() {
    if (_startDate == null) return null;
    return _startDate!.add(Duration(days: _rentalDays - 1)); // -1 because startDate is day 1
  }

  // Calculate total rental price
  double _calculateTotalPrice() {
    if (_itemData == null || _rentalDays <= 0) return 0.0;
    final itemPricePerDay = (_itemData!.data() as Map<String, dynamic>)['pricePerDay'] as num? ?? 0.0;
    return (itemPricePerDay * _rentalDays) + _deliveryFee;
  }

  // Calculate deposit amount
  double _calculateDepositAmount() {
    if (_rentWithDeposit && _itemData != null) {
      return ((_itemData!.data() as Map<String, dynamic>)['depositAmount'] as num? ?? 0.0).toDouble();
    }
    return 0.0;
  }

  // Function to show the Digital Rental Agreement dialog
  Future<bool?> _showDigitalRentalAgreementDialog() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false, // User must interact with the dialog
      builder: (BuildContext context) {
        // Declare state variables outside StatefulBuilder's builder method
        // so their state persists across rebuilds.
        bool _hasScrolledToEnd = false;
        bool _internalAgreedToTerms = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final ScrollController scrollController = ScrollController();

            // Initial check and listener setup
            void checkScrollPosition() {
              if (scrollController.hasClients) {
                final double maxScroll = scrollController.position.maxScrollExtent;
                final double currentScroll = scrollController.position.pixels;
                // debugPrint('DRA - Pixels: $currentScroll, Max: $maxScroll, hasScrolledToEnd: $_hasScrolledToEnd, internalAgreedToTerms: $_internalAgreedToTerms'); // Removed debugPrint
                // Use a small tolerance for floating point comparison
                if (maxScroll > 0 && currentScroll >= maxScroll - 10 && !_hasScrolledToEnd) {
                  setDialogState(() {
                    _hasScrolledToEnd = true; // User has scrolled to the end
                    // debugPrint('DRA - Scrolled to end!'); // Removed debugPrint
                  });
                }
              }
            }

            // Add a listener to the scroll controller
            scrollController.addListener(checkScrollPosition);

            // Perform an initial check after the first frame is rendered
            WidgetsBinding.instance.addPostFrameCallback((_) {
              checkScrollPosition();
            });

            return AlertDialog(
              title: const Text('Digital Rental Agreement'),
              content: SingleChildScrollView(
                controller: scrollController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[ // Removed 'const' here
                    const Text(
                      '8. Renter Responsibility & Damage Liability',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      '8.1 Condition of Return',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 5),
                    const Text('All items must be returned:', style: TextStyle(fontSize: 14)),
                    const Text('• In the same condition as received', style: TextStyle(fontSize: 14)),
                    const Text('• On or before the agreed return date and time', style: TextStyle(fontSize: 14)),
                    const Text('Failure to do so may result in penalties, including but not limited to late fees, damage fees, or replacement costs.', style: TextStyle(fontSize: 14)),
                    const SizedBox(height: 10),
                    const Text(
                      '8.2 Damage Waiver & Deposit-Free Rentals',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 5),
                    const Text('If you opt for a zero-deposit rental, you acknowledge that:', style: TextStyle(fontSize: 14)),
                    const Text('• You waive the need to pay a security deposit upfront', style: TextStyle(fontSize: 14)),
                    const Text('• You remain fully liable for any verified damages or losses', style: TextStyle(fontSize: 14)),
                    const Text('• KONGSI reserves the right to recover the cost of repair or replacement (up to RM1000) based on item value', style: TextStyle(fontSize: 14)),
                    const SizedBox(height: 10),
                    const Text(
                      '8.3 Payment of Damages',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 5),
                    const Text('In the event of verified damage:', style: TextStyle(fontSize: 14)),
                    const Text('• You agree to pay the amount specified by KONGSI’s damage assessment process within 7 days of notice', style: TextStyle(fontSize: 14)),
                    const Text('• Failure to settle the amount may result in account suspension or permanent ban', style: TextStyle(fontSize: 14)),
                    const Text('• KONGSI reserves the right to pursue legal recovery under Malaysian law', style: TextStyle(fontSize: 14)),
                    const SizedBox(height: 10),
                    const Text(
                      '8.4 Dispute Resolution',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 5),
                    const Text('If you dispute a damage claim:', style: TextStyle(fontSize: 14)),
                    const Text('• You must submit supporting evidence within 3 days of being notified', style: TextStyle(fontSize: 14)),
                    const Text('• KONGSI will mediate the case based on submitted evidence from both renter and lender', style: TextStyle(fontSize: 14)),
                    const Text('• All decisions by KONGSI are final and binding for platform use', style: TextStyle(fontSize: 14)),
                    const SizedBox(height: 20), // Spacing before the checkbox

                    // Internal checkbox for Digital Rental Agreement
                    Row(
                      children: [
                        Checkbox(
                          value: _internalAgreedToTerms,
                          onChanged: _hasScrolledToEnd // Only enable checkbox if user has scrolled to end
                              ? (bool? newValue) {
                                  setDialogState(() {
                                    _internalAgreedToTerms = newValue ?? false;
                                  });
                                }
                              : null,
                        ),
                        Expanded(
                          child: Text(
                            'I have read and agree to KONGSI\'s Terms of Use, including the Damage Liability Clause. I understand that I am financially responsible for any damage or loss to the rented item, even if I selected the Zero-Deposit option.',
                            style: TextStyle(fontSize: 14, color: Colors.grey[800]),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'By ticking this box, you also:',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const Text('• Confirm your identity through KYC', style: TextStyle(fontSize: 14)),
                    const Text('• Accept that KONGSI may pursue recovery via Small Claims Court if terms are violated', style: TextStyle(fontSize: 14)),
                    const Text('• Accept potential penalties, account bans, and legal enforcement for non-compliance', style: TextStyle(fontSize: 14)),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  // Button is disabled until user scrolls to the end AND ticks the internal checkbox
                  onPressed: _hasScrolledToEnd && _internalAgreedToTerms
                      ? () {
                          Navigator.of(context).pop(true); // Return true if both conditions met
                        }
                      : null,
                  child: const Text('Agree & Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Modified: Function to show the initial KONGSI T&C dialog
  void _showTermsAndConditionsDialog() async {
    // Show the first dialog and wait for a result (true if user clicked continue)
    final bool? continued = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // User must interact with the dialog
      builder: (BuildContext context) {
        // Declare state variables outside StatefulBuilder's builder method
        // so their state persists across rebuilds.
        bool _hasScrolledToEnd = false;
        bool _internalAgreedToFirstTerms = false; // Internal checkbox state for first dialog

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final ScrollController scrollController = ScrollController();

            // Initial check and listener setup
            void checkScrollPosition() {
              if (scrollController.hasClients) {
                final double maxScroll = scrollController.position.maxScrollExtent;
                final double currentScroll = scrollController.position.pixels;
                // debugPrint('KONGSI T&C - Pixels: $currentScroll, Max: $maxScroll, hasScrolledToEnd: $_hasScrolledToEnd, internalAgreedToFirstTerms: $_internalAgreedToFirstTerms'); // Removed debugPrint
                // Use a small tolerance for floating point comparison
                if (maxScroll > 0 && currentScroll >= maxScroll - 10 && !_hasScrolledToEnd) {
                  setDialogState(() {
                    _hasScrolledToEnd = true;
                    // debugPrint('KONGSI T&C - Scrolled to end!'); // Removed debugPrint
                  });
                }
              }
            }

            // Add a listener to the scroll controller
            scrollController.addListener(checkScrollPosition);

            // Perform an initial check after the first frame is rendered
            WidgetsBinding.instance.addPostFrameCallback((_) {
              checkScrollPosition();
            });

            return AlertDialog(
              title: const Text('KONGSI Terms & Conditions'),
              content: SingleChildScrollView(
                controller: scrollController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[ // Removed 'const' here
                    const Text(
                      '1. Introduction',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'By using the KONGSI platform, you agree to abide by the following Terms and Conditions. These terms govern your access to and use of the KONGSI website, app, and services. The platform connects individuals who wish to rent items ("Renters") with those willing to lend them ("Lenders").',
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 15),
                    const Text(
                      '2. User Eligibility & Verification',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 5),
                    const Text('• All users must be at least 18 years old.', style: TextStyle(fontSize: 14)),
                    const Text('• Users agree to undergo KYC verification if required.', style: TextStyle(fontSize: 14)),
                    const Text('• KONGSI reserves the right to suspend or terminate accounts for fraudulent behavior, unverified identity, or breach of terms.', style: TextStyle(fontSize: 14)),
                    const SizedBox(height: 15),
                    const Text(
                      '3. Platform Rules',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 5),
                    const Text('• Users are responsible for the accuracy of listing and rental information.', style: TextStyle(fontSize: 14)),
                    const Text('• No illegal, counterfeit, or hazardous items may be listed or rented.', style: TextStyle(fontSize: 14)),
                    const Text('• KONGSI may remove listings that violate guidelines without notice.', style: TextStyle(fontSize: 14)),
                    const SizedBox(height: 15),
                    const Text(
                      '4. Payments & Fees',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 5),
                    const Text('• KONGSI may charge service fees for transactions.', style: TextStyle(fontSize: 14)),
                    const Text('• Renters agree to pay rental fees and any applicable damage or late fees.', style: TextStyle(fontSize: 14)),
                    const Text('• Lenders receive rental earnings less any applicable service fees.', style: TextStyle(fontSize: 14)),
                    const SizedBox(height: 15),
                    const Text(
                      '5. Liability & Insurance',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 5),
                    const Text('• Renters are financially responsible for items during the rental period.', style: TextStyle(fontSize: 14)),
                    const Text('• KONGSI is not liable for disputes between users but may assist in mediation.', style: TextStyle(fontSize: 14)),
                    const SizedBox(height: 15),
                    const Text(
                      '6. Account Termination',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 5),
                    const Text('• KONGSI reserves the right to terminate accounts for violations of these terms.', style: TextStyle(fontSize: 14)),
                    const Text('• Users may request account deletion at any time.', style: TextStyle(fontSize: 14)),
                    const SizedBox(height: 15),
                    const Text(
                      '7. Legal Enforcement',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 5),
                    const Text('• Malaysian law governs this agreement.', style: TextStyle(fontSize: 14)),
                    const Text('• KONGSI may pursue Small Claims Court action for unresolved damages or payment issues.', style: TextStyle(fontSize: 14)),
                    const SizedBox(height: 20), // Spacing before the checkbox

                    // Internal checkbox for KONGSI Terms & Conditions
                    Row(
                      children: [
                        Checkbox(
                          value: _internalAgreedToFirstTerms,
                          onChanged: _hasScrolledToEnd // Only enable checkbox if user has scrolled to end
                              ? (bool? newValue) {
                                  setDialogState(() {
                                    _internalAgreedToFirstTerms = newValue ?? false;
                                  });
                                }
                              : null,
                        ),
                        const Expanded(
                          child: Text(
                            'I have read and understood the KONGSI Terms & Conditions.',
                            style: TextStyle(fontSize: 14, color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  // Button is disabled until user scrolls to the end AND ticks the internal checkbox
                  onPressed: _hasScrolledToEnd && _internalAgreedToFirstTerms
                      ? () {
                          Navigator.of(context).pop(true); // Return true to indicate continuation
                        }
                      : null,
                  child: const Text('Continue'),
                ),
              ],
            );
          },
        );
      },
    );

    // If the user clicked 'Continue' in the first dialog, show the second dialog
    if (continued == true) {
      final bool? agreed = await _showDigitalRentalAgreementDialog();
      if (agreed == true) {
        setState(() {
          _agreedToTerms = true; // Automatically tick the main checkbox
        });
      }
    }
  }

  // Function to place the booking request
  Future<void> _placeBookingRequest() async {
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to place a booking request.')),
      );
      Navigator.pushNamed(context, '/login');
      return;
    }
    if (_startDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a start date.')),
      );
      return;
    }
    if (_rentalDays <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least 1 rental day.')),
      );
      return;
    }
    if (_deliveryOptionType == 'delivery' && (_deliveryBuildingController.text.isEmpty || _deliveryStreetController.text.isEmpty || _deliveryCityController.text.isEmpty || _deliveryPostcodeController.text.isEmpty || _deliveryStateController.text.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all delivery address details.')),
      );
      return;
    }

    // Check if T&C are agreed upon before placing booking
    if (!_agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please agree to the Terms & Conditions to proceed.')),
      );
      return;
    }

    setState(() {
      _isLoading = true; // Show loading indicator during submission
    });

    try {
      final Timestamp startDateTimestamp = Timestamp.fromDate(_startDate!);
      final Timestamp endDateTimestamp = Timestamp.fromDate(_calculateEndDate()!);
      final double totalPrice = _calculateTotalPrice();
      final double depositPaid = _calculateDepositAmount();

      Map<String, dynamic> orderData = {
        'itemId': widget.itemId,
        'renterId': _currentUser!.uid,
        'ownerId': (_itemData!.data() as Map<String, dynamic>)['ownerId'] ?? 'unknown_owner',
        'startDate': startDateTimestamp,
        'endDate': endDateTimestamp,
        'totalPrice': totalPrice,
        'depositPaid': depositPaid,
        'status': 'pending', // Initial status
        'paymentIntentId': 'placeholder_payment_id_${DateTime.now().millisecondsSinceEpoch}', // Placeholder
        'isUnderProtectionPlan': false, // Changed to false: Lender decides this post-acceptance
        'protectionPlanFee': 0.0, // Initialize protection plan fee to 0.0
        'deliveryOptionType': _deliveryOptionType,
        'deliveryFee': _deliveryFee,
        'createdAt': Timestamp.now(),
        'lastUpdatedAt': Timestamp.now(),
      };

      if (_deliveryOptionType == 'delivery') {
        orderData['deliveryAddress'] = {
          'building': _deliveryBuildingController.text.trim(),
          'street': _deliveryStreetController.text.trim(),
          'city': _deliveryCityController.text.trim(),
          'postcode': _deliveryPostcodeController.text.trim(),
          'state': _deliveryStateController.text.trim(),
        };
        orderData['trackingNumber'] = ''; // Empty initially
      } else { // meet_up
        orderData['meetUpLocationNotes'] = _meetUpLocationNotesController.text.trim();
      }

      // Add the order to Firestore
      await _firestore.collection('orders').add(orderData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Booking request sent successfully!')),
        );
        Navigator.pop(context); // Go back to item detail page
      }
    } catch (e) {
      // debugPrint("Error placing booking request: $e"); // Removed debugPrint
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send booking request: ${e.toString()}')),
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
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Book Item'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_itemData == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Book Item'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
        ),
        body: const Center(child: Text('Item data could not be loaded.')),
      );
    }

    final item = _itemData!.data() as Map<String, dynamic>;
    final String itemName = item['name'] ?? 'Untitled Item';
    final double itemPricePerDay = (item['pricePerDay'] as num?)?.toDouble() ?? 0.0;
    final double itemDepositAmount = (item['depositAmount'] as num?)?.toDouble() ?? 0.0;

    // Calculate total price and deposit to be shown to the user
    final double calculatedTotalPrice = _calculateTotalPrice();
    final double calculatedDepositAmount = _calculateDepositAmount();

    return Scaffold(
      appBar: AppBar(
        title: Text('Book "$itemName"'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Item Summary
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      itemName,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'RM${itemPricePerDay.toStringAsFixed(2)} / day',
                      style: TextStyle(fontSize: 18, color: Colors.blue[700], fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Deposit: RM${itemDepositAmount.toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Date Selection
            Text(
              'Rental Period',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[800]),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _selectDate(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 20, color: Colors.grey),
                          const SizedBox(width: 10),
                          Text(
                            _startDate == null
                                ? 'Select Start Date'
                                : DateFormat('dd MMMEEEE').format(_startDate!),
                            style: const TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _rentalDays,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      labelText: 'Rental Days',
                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                    ),
                    items: List.generate(30, (index) => index + 1).map((days) {
                      return DropdownMenuItem(
                        value: days,
                        child: Text('$days Day${days > 1 ? 's' : ''}'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _rentalDays = value;
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_startDate != null && _calculateEndDate() != null)
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'End Date: ${DateFormat('dd MMMEEEE').format(_calculateEndDate()!)}',
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
              ),
            const SizedBox(height: 20),

            // Deposit Option
            Text(
              'Deposit Option',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[800]),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  RadioListTile<bool>(
                    title: const Text('Rent with Deposit'),
                    subtitle: Text('A deposit of RM${itemDepositAmount.toStringAsFixed(2)} is required.'),
                    value: true,
                    groupValue: _rentWithDeposit,
                    onChanged: (bool? value) {
                      if (value != null) {
                        setState(() {
                          _rentWithDeposit = value;
                        });
                      }
                    },
                  ),
                  RadioListTile<bool>(
                    title: const Text('Rent without Deposit (Membership Pass)'),
                    subtitle: _isMember
                        ? const Text('Available for members.')
                        : const Text('Requires a valid membership pass.', style: TextStyle(color: Colors.red)),
                    value: false,
                    groupValue: _rentWithDeposit,
                    onChanged: (bool? value) {
                      if (value != null) {
                        if (!_isUserKycVerified) { // KYC check for "Rent without Deposit"
                          showDialog(
                            context: context,
                            builder: (BuildContext context) {
                              return AlertDialog(
                                title: const Text('KYC Verification Required'),
                                content: const Text('Please complete your KYC verification to use the "Rent without Deposit" option.'),
                                actions: <Widget>[
                                  TextButton(
                                    child: const Text('OK'),
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                    },
                                  ),
                                  // Optional: Add a button to navigate to KYC screen
                                  // TextButton(
                                  //   child: const Text('Go to KYC'),
                                  //   onPressed: () {
                                  //     Navigator.of(context).pop();
                                  //     Navigator.pushNamed(context, '/kyc_verification');
                                  //   },
                                  // ),
                                ],
                              );
                            },
                          );
                          // Do not change the radio button selection if KYC is not verified
                          return; 
                        }

                        // If KYC is verified AND user is a member, allow selection
                        if (_isMember) {
                          setState(() {
                            _rentWithDeposit = value;
                          });
                        } else {
                          // This case should ideally be covered by the disabled state,
                          // but as a fallback, show a message if somehow selected.
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('You need a valid membership pass to use this option.')),
                          );
                        }
                      }
                    },
                    activeColor: _isMember ? Theme.of(context).primaryColor : Colors.grey,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Delivery Option
            Text(
              'Delivery Option',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[800]),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  RadioListTile<String>(
                    title: const Text('Meet Up'),
                    value: 'meet_up',
                    groupValue: _deliveryOptionType,
                    onChanged: (String? value) {
                      if (value != null) {
                        setState(() {
                          _deliveryOptionType = value;
                          _deliveryFee = 0.0; // No delivery fee for meet up
                        });
                      }
                    },
                  ),
                  if (_deliveryOptionType == 'meet_up')
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: TextField(
                        controller: _meetUpLocationNotesController,
                        decoration: const InputDecoration(
                          labelText: 'Meet Up Notes (e.g., "Meet at Sunway Pyramid entrance")',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                      ),
                    ),
                  RadioListTile<String>(
                    title: const Text('Delivery'),
                    value: 'delivery',
                    groupValue: _deliveryOptionType,
                    onChanged: (String? value) {
                      if (value != null) {
                        setState(() {
                          _deliveryOptionType = value;
                          _deliveryFee = 5.0; // Example delivery fee
                        });
                      }
                    },
                  ),
                  if (_deliveryOptionType == 'delivery')
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Column(
                        children: [
                          TextField(
                            controller: _deliveryBuildingController,
                            decoration: const InputDecoration(
                              labelText: 'Building / House No.',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _deliveryStreetController,
                            decoration: const InputDecoration(
                              labelText: 'Street',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _deliveryCityController,
                            decoration: const InputDecoration(
                              labelText: 'City',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _deliveryPostcodeController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Postcode',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _deliveryStateController,
                            decoration: const InputDecoration(
                              labelText: 'State',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Terms & Conditions Checkbox (External)
            Row(
              children: [
                Checkbox(
                  value: _agreedToTerms,
                  // This checkbox can only be UNCHECKED manually.
                  // It's automatically checked by the dialog flow.
                  onChanged: _agreedToTerms
                      ? (bool? newValue) {
                          setState(() {
                            _agreedToTerms = newValue ?? false;
                          });
                        }
                      : null, // Disabled if not yet agreed via dialog
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: _showTermsAndConditionsDialog, // Triggers the first T&C dialog
                    child: RichText(
                      text: TextSpan(
                        text: 'I agree to the ',
                        style: TextStyle(fontSize: 14, color: Colors.grey[800]),
                        children: <TextSpan>[
                          TextSpan(
                            text: 'Terms & Conditions',
                            style: TextStyle(
                              color: Colors.blue[700],
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Price Summary
            Text(
              'Order Summary',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[800]),
            ),
            const SizedBox(height: 10),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Rental Cost (${_rentalDays} days)'),
                        Text('RM${(itemPricePerDay * _rentalDays).toStringAsFixed(2)}'),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Delivery Fee'),
                        Text('RM${_deliveryFee.toStringAsFixed(2)}'),
                      ],
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Rental Price', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('RM${calculatedTotalPrice.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Deposit Due', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                        Text('RM${calculatedDepositAmount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Confirm Booking Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                // Button is enabled only if _agreedToTerms is true
                onPressed: _agreedToTerms ? _placeBookingRequest : null, 
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[800],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(fontSize: 18),
                ),
                child: const Text('Request Booking'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
