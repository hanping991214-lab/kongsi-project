import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart'; // For picking images
import 'package:firebase_storage/firebase_storage.dart'; // For uploading images
import 'dart:io'; // For File operations
import 'package:geolocator/geolocator.dart'; // For current location
import 'package:geocoding/geocoding.dart'; // For geocoding/reverse geocoding
import 'package:uuid/uuid.dart'; // Re-enabled: For generating unique IDs
import '../services/auth_service.dart'; // Assuming AuthService

class UploadItemScreen extends StatefulWidget {
  final String? itemIdForEdit; // Optional: Pass item ID if editing existing item

  const UploadItemScreen({Key? key, this.itemIdForEdit}) : super(key: key);

  @override
  State<UploadItemScreen> createState() => _UploadItemScreenState();
}

class _UploadItemScreenState extends State<UploadItemScreen> with AutomaticKeepAliveClientMixin {
  final _authService = AuthService();
  User? _currentUser;
  bool _isLoading = false;
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Step 2 (now): Product Details Controllers
  final TextEditingController _itemNameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _conditionController = TextEditingController(); // For "Condition" text field
  final TextEditingController _rentalPriceController = TextEditingController(); // For "Rental Price"
  // _requiresDepositOnly is true if lender ONLY offers with deposit, false if both options
  bool _requiresDepositOnly = true; 
  final List<String> _tags = []; // For tags

  List<XFile> _selectedImages = []; // Stores selected images (from gallery/camera)
  List<String> _existingImageUrls = []; // Stores existing image URLs for edit mode

  // Step 1 (now): Location & Details Controllers
  final TextEditingController _searchAddressController = TextEditingController();
  final TextEditingController _pickupNotesController = TextEditingController();
  GeoPoint? _selectedGeoPoint; // To store GeoPoint for internal geocoding purposes
  bool _isLocationConfirmed = false; // Flag to confirm location has been successfully set

  // Step 3 (remains): Listing Preferences & Protection
  bool _allowInstantBooking = false;
  bool _autoProtectionPlan = true; // Default to true as per screenshot
  String _cancellationPolicy = 'Flexible'; // Default cancellation policy

  // Form keys now explicitly named for clarity based on new page order
  final _formKeyStep1_LocationDetails = GlobalKey<FormState>(); // For Step 1 (Location & Details)
  final _formKeyStep2_ProductDetails = GlobalKey<FormState>();    // For Step 2 (Product Details)
  final _formKeyStep3 = GlobalKey<FormState>();                 // For Step 3 (Listing Preferences)

  @override
  bool get wantKeepAlive => true; // Keep the state alive across page views


  @override
  void initState() {
    super.initState();
    _currentUser = _authService.getCurrentUser();
    if (_currentUser == null) {
      // Redirect to login if not authenticated
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please log in to upload an item.')),
          );
          Navigator.pushReplacementNamed(context, '/login');
        }
      });
    } else {
      if (widget.itemIdForEdit != null) {
        _loadItemForEdit(widget.itemIdForEdit!);
      } else {
        // If it's a new item, try to load user's address
        _loadUserAddressAndSetItemLocation();
      }
    }
    _pageController.addListener(() {
      if (mounted) { // Ensure mounted before setState in listener
        setState(() {
          _currentPage = _pageController.page!.round();
        });
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _itemNameController.dispose();
    _descriptionController.dispose();
    _conditionController.dispose();
    _rentalPriceController.dispose();
    _searchAddressController.dispose();
    _pickupNotesController.dispose();
    super.dispose();
  }

  Future<void> _loadItemForEdit(String itemId) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });
    try {
      DocumentSnapshot itemDoc = await FirebaseFirestore.instance
          .collection('items')
          .doc(itemId)
          .get();

      if (itemDoc.exists) {
        Map<String, dynamic> data = itemDoc.data() as Map<String, dynamic>;
        if (mounted) {
          _itemNameController.text = data['name'] ?? '';
          _descriptionController.text = data['description'] ?? '';
          _conditionController.text = data['condition'] ?? '';
          _rentalPriceController.text = (data['pricePerDay'] as num?)?.toString() ?? '';
          
          _requiresDepositOnly = data['requiresDepositOnly'] ?? true; 
          
          if (data['tags'] is List) {
            _tags.addAll(List<String>.from(data['tags']));
          }
          if (data['images'] is List) {
            _existingImageUrls.addAll(List<String>.from(data['images']));
          }
          
          // --- Load Location (Crucial Part for Edit Mode) ---
          dynamic itemLocation = data['location'];
          if (itemLocation is GeoPoint) {
            _selectedGeoPoint = itemLocation;
            // Convert GeoPoint back to a readable address for the TextFormField
            _searchAddressController.text = await _getReadableLocation(itemLocation);
            _isLocationConfirmed = true; // For edit mode, assume pre-filled location is confirmed
          } else if (itemLocation is String && itemLocation.contains(',')) {
            // Attempt to parse "latitude,longitude" string if it was saved this way
            try {
              final parts = itemLocation.split(',');
              final double lat = double.parse(parts[0].trim());
              final double lng = double.parse(parts[1].trim());
              _selectedGeoPoint = GeoPoint(lat, lng);
              _searchAddressController.text = await _getReadableLocation(_selectedGeoPoint!);
              _isLocationConfirmed = true; // For edit mode, assume pre-filled location is confirmed
            } catch (e) {
              print('Error parsing location string from Firestore during edit load: $e');
              _searchAddressController.text = itemLocation; // Fallback to raw string if parsing fails
              _isLocationConfirmed = false;
            }
          } else if (itemLocation is String) {
            // If it's a plain address string (from old data), try to geocode it
            _searchAddressController.text = itemLocation;
            // Pass `false` for `manageLoading` as _loadItemForEdit is already handling it
            await _searchAndSetLocationInternal(itemLocation, manageLoading: false); 
            _isLocationConfirmed = true; // For edit mode, assume pre-filled location is confirmed
          }
          // --- End Load Location ---

          _pickupNotesController.text = data['pickupNotes'] ?? '';

          _allowInstantBooking = data['allowInstantBooking'] ?? false;
          _autoProtectionPlan = data['autoProtectionPlan'] ?? true;
          _cancellationPolicy = data['cancellationPolicy'] ?? 'Flexible';
        }

      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Item for edit not found.')),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading item for edit: $e')),
        );
        Navigator.pop(context);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadUserAddressAndSetItemLocation() async {
    if (_currentUser == null || !mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .get();

      if (userDoc.exists) {
        Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
        Map<String, dynamic>? userAddressMap = userData['address'] as Map<String, dynamic>?;

        if (userAddressMap != null && userAddressMap.isNotEmpty) {
            String street = userAddressMap['street'] ?? '';
            String city = userAddressMap['city'] ?? '';
            String postcode = userAddressMap['postcode'] ?? '';
            String fullAddress = '';
            if (street.isNotEmpty) fullAddress += street;
            if (city.isNotEmpty) fullAddress += (fullAddress.isNotEmpty ? ', ' : '') + city;
            if (postcode.isNotEmpty) fullAddress += (fullAddress.isNotEmpty ? ', ' : '') + postcode;

            if (fullAddress.isNotEmpty) {
              // Perform geocoding directly for pre-filled address
              List<Location> locations = await locationFromAddress(fullAddress);
              if (locations.isNotEmpty) {
                GeoPoint geoPoint = GeoPoint(locations.first.latitude, locations.first.longitude);
                String readableAddress = await _getReadableLocation(geoPoint);
                if (mounted) {
                  setState(() {
                    _selectedGeoPoint = geoPoint;
                    _searchAddressController.text = readableAddress;
                    _isLocationConfirmed = true; // Automatically confirm pre-filled location
                  });
                  // Trigger validation after the next frame to ensure state is updated
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      _formKeyStep1_LocationDetails.currentState?.validate(); // Force re-validation
                    }
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Item location pre-filled from your profile address and confirmed.')),
                  );
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not geocode pre-filled address. Please confirm manually.')),
                  );
                  setState(() {
                    _isLocationConfirmed = false;
                    _selectedGeoPoint = null;
                  });
                }
              }
            }
        }
      }
    } catch (e) {
      print('Error loading user address: $e');
      if (mounted) { // Ensure mounted before showing SnackBar
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error pre-filling location from profile: ${e.toString().replaceFirst('Exception: ', '')}')),
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


  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final List<XFile>? images = await picker.pickMultiImage();
    if (images != null && images.isNotEmpty) {
      if (mounted) { // Ensure mounted before setState
        setState(() {
          _selectedImages.addAll(images);
        });
      }
    }
  }

  void _removeSelectedImage(int index) {
    if (mounted) { // Ensure mounted before setState
      setState(() {
        _selectedImages.removeAt(index);
      });
    }
  }

  void _removeExistingImage(int index) {
    if (mounted) { // Ensure mounted before setState
      setState(() {
        _existingImageUrls.removeAt(index);
      });
    }
  }

  Future<String> _uploadImage(XFile imageFile) async {
    // Generate a unique ID for the image filename using Uuid
    String uniqueFileName = const Uuid().v4(); // Use Uuid here
    String fileName = 'item_images/${_currentUser!.uid}/$uniqueFileName.jpg'; // Consistent file extension
    Reference storageRef = FirebaseStorage.instance.ref().child(fileName);
    UploadTask uploadTask = storageRef.putFile(File(imageFile.path));
    TaskSnapshot snapshot = await uploadTask;
    return await snapshot.ref.getDownloadURL();
  }

  // Renamed to internal to avoid direct public calls from UI elements (managed by Confirm button)
  Future<void> _getCurrentLocationAndGeocodeInternal({bool manageLoading = true}) async {
    if (!mounted) return;
    if (manageLoading) { 
      setState(() { _isLoading = true; });
    }
    setState(() { 
      _selectedGeoPoint = null; 
      _isLocationConfirmed = false; // Always set to false when fetching/searching
    });
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Location permissions are denied.')),
            );
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permissions are permanently denied, enable them in settings.')),
          );
        }
        return;
      }

      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      String readableAddress = await _getReadableLocation(GeoPoint(position.latitude, position.longitude));
      
      if (mounted) { 
        setState(() {
          _selectedGeoPoint = GeoPoint(position.latitude, position.longitude);
          _searchAddressController.text = readableAddress; 
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error getting location: ${e.toString().replaceFirst('Exception: ', '')}')),
        );
        setState(() { 
          _selectedGeoPoint = null;
          _isLocationConfirmed = false; 
        });
      }
    } finally {
      if (manageLoading) { 
        if (mounted) {
          setState(() { _isLoading = false; });
        }
      }
    }
  }

  // Renamed to internal to avoid direct public calls from UI elements (managed by Confirm button)
  Future<void> _searchAndSetLocationInternal(String address, {bool manageLoading = true}) async {
    if (!mounted) return;
    if (manageLoading) { 
      setState(() { _isLoading = true; });
    }
    setState(() { 
      _selectedGeoPoint = null; 
      _isLocationConfirmed = false; // Always set to false when fetching/searching
    });
    try {
      List<Location> locations = await locationFromAddress(address);
      if (locations.isNotEmpty) {
        String readableAddress = await _getReadableLocation(GeoPoint(locations.first.latitude, locations.first.longitude));
        if (mounted) { 
          setState(() {
            _selectedGeoPoint = GeoPoint(locations.first.latitude, locations.first.longitude);
            _searchAddressController.text = readableAddress; 
          });
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No location found for this address. Please try another.')),
          );
          setState(() { 
            _selectedGeoPoint = null;
            _isLocationConfirmed = false; 
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error searching address: ${e.toString().replaceFirst('Exception: ', '')}')),
        );
        setState(() { 
          _selectedGeoPoint = null;
          _isLocationConfirmed = false; 
        });
      }
    } finally {
      if (manageLoading) { 
        if (mounted) {
          setState(() { _isLoading = false; });
        }
      }
    }
  }

  Future<String> _getReadableLocation(dynamic location) async {
    if (location is GeoPoint) {
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(location.latitude, location.longitude);
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks.first;
          // MODIFIED: Return more detailed address including street, sub-locality/locality, sub-administrative area/administrative area, and postal code
          String street = place.street ?? '';
          String subLocalityOrLocality = place.subLocality ?? place.locality ?? '';
          String subAdminOrAdminArea = place.administrativeArea ?? place.subAdministrativeArea ?? '';
          String postalCode = place.postalCode ?? '';
          
          List<String> addressParts = [];
          if (street.isNotEmpty) addressParts.add(street);
          if (subLocalityOrLocality.isNotEmpty) addressParts.add(subLocalityOrLocality);
          if (subAdminOrAdminArea.isNotEmpty) addressParts.add(subAdminOrAdminArea);
          if (postalCode.isNotEmpty) addressParts.add(postalCode);

          return addressParts.join(', ');
        }
      } catch (e) {
        print("Error during reverse geocoding: $e");
        return 'Lat: ${location.latitude.toStringAsFixed(4)}, Lng: ${location.longitude.toStringAsFixed(4)}';
      }
    } else if (location is String && location.isNotEmpty) {
      return location;
    }
    return 'Unknown Location';
  }

  Future<void> _submitListing() async {
    // --- DEBUG LOGGING ---
    print('Attempting to submit listing...');
    print('Current user: ${_currentUser?.uid}');
    if (_currentUser == null) {
      print('DEBUG: _currentUser is NULL. Cannot submit listing.');
      if (mounted) { // Ensure mounted before showing SnackBar
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You must be logged in to list an item.')),
        );
      }
      return;
    }

    // DEBUG: Log data types and values right before validation in _submitListing
    print('DEBUG: Before Final Submission Validation in _submitListing:');
    print('  _searchAddressController.text: "${_searchAddressController.text}" (Type: ${_searchAddressController.text.runtimeType})');
    print('  _selectedGeoPoint: ${_selectedGeoPoint} (Lat: ${_selectedGeoPoint?.latitude}, Lng: ${_selectedGeoPoint?.longitude}) (Type: ${_selectedGeoPoint.runtimeType})');
    print('  _isLocationConfirmed: ${_isLocationConfirmed}');


    // Validate Step 1 (Location) form: Directly check _isLocationConfirmed and _selectedGeoPoint
    if (!_isLocationConfirmed || _selectedGeoPoint == null) {
      if (mounted) {
        String debugMessage = 'Step 1 validation failed. Debug Info:\n'
                              'Text: "${_searchAddressController.text}" (Type: ${_searchAddressController.text.runtimeType})\n'
                              'GeoPoint: ${_selectedGeoPoint} (Lat: ${_selectedGeoPoint?.latitude}, Lng: ${_selectedGeoPoint?.longitude}) (Type: ${_selectedGeoPoint.runtimeType})\n'
                              'Confirmed: ${_isLocationConfirmed}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please confirm the item location in Step 1. \n$debugMessage')),
        );
      }
      return; // Stop submission if location not confirmed
    }

    if (!mounted) {
      print('DEBUG: Widget is not mounted during _submitListing. Aborting.');
      return; // Add mounted check before setState
    }
    setState(() {
      _isLoading = true;
    });

    try {
      // ******* CRUCIAL FIX: Force refresh of ID token to get latest claims *******
      // This ensures Firestore security rules evaluate with the most up-to-date 'isLender' status.
      // This is still important even with the simplified rule 'if request.auth != null'
      // because it ensures request.auth is populated correctly.
      print('DEBUG: Forcing ID token refresh...');
      await _currentUser!.getIdToken(true); // true forces a refresh
      print('DEBUG: ID token refreshed successfully.');

      List<String> uploadedImageUrls = [];
      // Retain existing image URLs
      uploadedImageUrls.addAll(_existingImageUrls);

      // Upload new images
      for (XFile image in _selectedImages) {
        String url = await _uploadImage(image);
        uploadedImageUrls.add(url);
      }

      if (uploadedImageUrls.isEmpty) { 
        print('DEBUG: No images selected.');
        if (mounted) { // Ensure mounted before showing SnackBar
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please upload at least one image for your item.')),
          );
          setState(() { // Also reset loading state here if images are missing
            _isLoading = false;
          });
        }
        return;
      }

      double? pricePerDay = double.tryParse(_rentalPriceController.text.trim());
      if (pricePerDay == null) {
        print('DEBUG: Invalid rental price.');
        if (mounted) { // Ensure mounted before showing SnackBar
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid rental price.')),
          );
          setState(() { // Also reset loading state here if price is invalid
            _isLoading = false;
          });
        }
        return;
      }

      double depositAmountToSave = 100.00; // Hardcoded example deposit amount

      Map<String, dynamic> itemData = {
        'name': _itemNameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'ownerId': _currentUser!.uid, // Ensure ownerId is set to current user's UID
        'pricePerDay': pricePerDay,
        'currency': 'RM', 
        'requiresDepositOnly': _requiresDepositOnly, 
        'depositAmount': depositAmountToSave, 
        'images': uploadedImageUrls,
        // Store the GeoPoint directly
        'location': _selectedGeoPoint, 
        'status': 'available', 
        'condition': _conditionController.text.trim(),
        'postedAt': FieldValue.serverTimestamp(),
        'isFeatured': false, 
        'averageRating': 0.0, 
        'reviewCount': 0, 
        'specifications': _tags, 
        'pickupNotes': _pickupNotesController.text.trim(),
        'allowInstantBooking': _allowInstantBooking,
        'autoProtectionPlan': _autoProtectionPlan,
        'cancellationPolicy': _cancellationPolicy,
      };

      if (widget.itemIdForEdit != null) {
        print('DEBUG: Attempting to update item with ID: ${widget.itemIdForEdit}');
        // Update existing item
        await FirebaseFirestore.instance
            .collection('items')
            .doc(widget.itemIdForEdit)
            .update(itemData);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Item updated successfully!')),
          );
        }
      } else {
        print('DEBUG: Attempting to add new item.');
        // Add new item
        await FirebaseFirestore.instance.collection('items').add(itemData);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Item listed successfully!')),
          );
        }
      }
      print('DEBUG: Item operation successful.');
      if (mounted) {
        Navigator.pop(context); // Go back to My Listings page
      }
    } on FirebaseException catch (e) {
      print('DEBUG: FirebaseException caught: ${e.code} - ${e.message}');
      if (mounted) { // Ensure mounted before showing SnackBar
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Firebase Error: ${e.message}')),
        );
      }
    } catch (e) {
      print('DEBUG: General exception caught: $e');
      if (mounted) { // Ensure mounted before showing SnackBar
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString().replaceFirst('Exception: ', '')}')),
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

  int _rentalDays = 2; // Default for preview calculation

  double _calculateTotalRentalFee() {
    double pricePerDay = double.tryParse(_rentalPriceController.text.trim()) ?? 0.0;
    double rentalCost = pricePerDay * _rentalDays;
    double processingFee = 0.0;
    double depositAmount = 0.0; 

    if (_requiresDepositOnly) { 
      depositAmount = 100.00; 
      processingFee = 2.64; 
    } else {
      processingFee = 1.50; 
    }

    double total = rentalCost + processingFee;
    if (_requiresDepositOnly) { 
      total += depositAmount; 
    }
    return total;
  }


  @override
  Widget build(BuildContext context) {
    super.build(context); // Crucial for AutomaticKeepAliveClientMixin
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.itemIdForEdit == null ? 'List an Item' : 'Edit Item'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_currentPage == 0) { // If on the first step (Location & Details)
              Navigator.pop(context);
            } else {
              _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.ease);
            }
          },
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStepIndicator(0, 'Location & Details'), // Step 1
                _buildStepIndicator(1, 'Product Details'),    // Step 2
                _buildStepIndicator(2, 'Listing Preferences'), // Step 3
              ],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    // physics: const NeverScrollableScrollPhysics(), // Disable swipe - KeepAliveMixin handles state, no need to restrict swipe entirely
                    onPageChanged: (index) {
                      if (mounted) { // Ensure mounted before setState
                        setState(() {
                          _currentPage = index;
                        });
                      }
                    },
                    children: [
                      _buildStep1LocationDetails(),    // Renamed: Builds content for Step 1
                      _buildStep2ProductDetails(),     // Renamed: Builds content for Step 2
                      _buildStep3ListingPreferences(), // Remains: Builds content for Step 3
                    ],
                  ),
                ),
                _buildBottomNavigationButtons(),
              ],
            ),
    );
  }

  Widget _buildStepIndicator(int stepIndex, String title) {
    return Column(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _currentPage >= stepIndex ? Colors.white : Colors.blue.withOpacity(0.5),
            border: Border.all(
              color: _currentPage >= stepIndex ? Colors.white : Colors.transparent,
              width: 1,
            ),
          ),
          child: Center(
            child: Text(
              '${stepIndex + 1}',
              style: TextStyle(
                color: _currentPage >= stepIndex ? Colors.blue[800] : Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: TextStyle(
            color: _currentPage >= stepIndex ? Colors.white : Colors.blue.withOpacity(0.8),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  // Renamed to reflect it's the second step's content
  Widget _buildStep2ProductDetails() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKeyStep2_ProductDetails, // Using new key for Step 2 (Product Details)
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Step 2: Product Details', // Correct label
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _itemNameController,
              decoration: InputDecoration(
                labelText: 'Item Name',
                hintText: 'e.g., Nintendo Switch',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter item name';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Description',
                hintText: 'e.g., Barely used Nintendo Switch with 3 games.',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter description';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _conditionController,
              decoration: InputDecoration(
                labelText: 'Condition',
                hintText: 'e.g., excellent, good, fair',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter item condition';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _rentalPriceController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Rental Price (RM/day)',
                hintText: 'e.g., 35.00',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                prefixText: 'RM ',
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter rental price';
                }
                if (double.tryParse(value) == null || double.parse(value) <= 0) {
                  return 'Please enter a valid positive number';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            // Rental Options: Lend with deposit / Lend with deposit & without deposit
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Rental Options:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                // Lender chooses to ONLY lend with deposit
                RadioListTile<bool>(
                  title: const Text('Lend with deposit (only)'),
                  value: true,
                  groupValue: _requiresDepositOnly,
                  onChanged: (bool? value) {
                    if (mounted) { // Ensure mounted before setState
                      setState(() {
                        _requiresDepositOnly = value!;
                      });
                    }
                  },
                ),
                // Lender chooses to lend with deposit AND without deposit (both options for renter)
                RadioListTile<bool>(
                  title: const Text('Lend with deposit & without deposit'),
                  value: false,
                  groupValue: _requiresDepositOnly,
                  onChanged: (bool? value) {
                    if (mounted) { // Ensure mounted before setState
                      setState(() {
                        _requiresDepositOnly = value!;
                      });
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Tags
            TextFormField(
              decoration: InputDecoration(
                labelText: 'Tags (e.g., 12MP, 4 lenses, Mirrorless)',
                hintText: 'Type tag and press enter/space',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onFieldSubmitted: (value) {
                if (value.trim().isNotEmpty && !_tags.contains(value.trim())) {
                  if (mounted) { // Ensure mounted before setState
                    setState(() {
                      _tags.add(value.trim());
                    });
                  }
                }
                FocusScope.of(context).unfocus(); // Dismiss keyboard
              },
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8.0,
              children: _tags.map((tag) => Chip(
                label: Text(tag),
                onDeleted: () {
                  if (mounted) { // Ensure mounted before setState
                    setState(() {
                      _tags.remove(tag);
                    });
                  }
                },
              )).toList(),
            ),
            const SizedBox(height: 20),
            // Image Upload
            const Text(
              'Item Images:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _pickImage,
              child: DottedBorderContainer(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo, size: 40, color: Colors.grey[600]),
                      const Text('Upload Images', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Display existing images (for edit mode)
            if (_existingImageUrls.isNotEmpty)
              Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children: List.generate(_existingImageUrls.length, (index) {
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8.0),
                        child: Image.network(
                          _existingImageUrls[index],
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            width: 100,
                            height: 100,
                            color: Colors.grey[300],
                            child: const Icon(Icons.broken_image, color: Colors.grey),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        child: GestureDetector(
                          onTap: () => _removeExistingImage(index),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.close, size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            // Display newly selected images
            if (_selectedImages.isNotEmpty)
              Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children: List.generate(_selectedImages.length, (index) {
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8.0),
                        child: Image.file(
                          File(_selectedImages[index].path),
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        right: 0,
                        child: GestureDetector(
                          onTap: () => _removeSelectedImage(index),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.close, size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            if (_selectedImages.isEmpty && _existingImageUrls.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text('At least one image is required.', style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }

  // Renamed to reflect it's the first step's content
  Widget _buildStep1LocationDetails() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKeyStep1_LocationDetails, // Using new key for Step 1 (Location & Details)
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Step 1: Location & Details', // Correct label
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            const Text(
              'Provide your approximate location to receive local rental requests.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 15),
            TextFormField(
              controller: _searchAddressController,
              decoration: InputDecoration(
                labelText: 'Address', // Changed label to "Address"
                hintText: 'e.g., Sunway Pyramid',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                // Removed suffixIcon (search icon)
              ),
              onChanged: (value) {
                // When text changes, clear selected geo point and reset confirmation
                if (mounted) {
                  setState(() {
                    _isLocationConfirmed = false;
                    _selectedGeoPoint = null; 
                  });
                }
              },
              validator: (value) {
                // Only validate if the text field is empty.
                if (value == null || value.isEmpty) {
                  return 'Please enter an address or use current location.';
                }
                return null; 
              },
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async { // Made async to await the function
                  setState(() { 
                    _isLoading = true;
                    _isLocationConfirmed = false; // Reset confirmation when fetching new location
                  }); 
                  await _getCurrentLocationAndGeocodeInternal(manageLoading: false);
                  // Trigger validation after the next frame to ensure state is updated
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      _formKeyStep1_LocationDetails.currentState?.validate(); // Force re-validation
                    }
                  });
                  setState(() { _isLoading = false; }); // End loading
                },
                icon: const Icon(Icons.my_location),
                label: const Text('Use My Current Location'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue[800],
                  side: BorderSide(color: Colors.blue[800]!),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : () async {
                  setState(() { _isLoading = true; });
                  
                  // Reset confirmation status before attempting to confirm
                  _isLocationConfirmed = false; 

                  if (_searchAddressController.text.isNotEmpty) {
                    await _searchAndSetLocationInternal(_searchAddressController.text, manageLoading: false);
                  } else if (_selectedGeoPoint != null) {
                    // If text field is empty but we have a _selectedGeoPoint from 'Use My Current Location',
                    // just attempt to re-confirm the existing one to trigger validator.
                    await _getReadableLocation(_selectedGeoPoint!); 
                  } else {
                     // Neither text field has input, nor did 'Use My Current Location' return a geopoint
                     if (mounted) {
                       ScaffoldMessenger.of(context).showSnackBar(
                         const SnackBar(content: Text('Please enter an address or use "My Current Location" before confirming.')),
                       );
                     }
                     setState(() { _isLoading = false; });
                     return; // Exit early if no input
                  }

                  // Only confirm location if _selectedGeoPoint was successfully set by either method
                  if (_selectedGeoPoint != null && mounted) {
                    setState(() {
                      _isLocationConfirmed = true; // Now explicitly confirmed
                    });
                    // Trigger validation after the next frame to ensure state is updated
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        _formKeyStep1_LocationDetails.currentState?.validate(); // Force re-validation
                      }
                    });
                    ScaffoldMessenger.of(context).showSnackBar( // Added for clearer feedback
                      const SnackBar(content: Text('Location confirmed successfully!')),
                    );
                  } else if (mounted) {
                     // If _selectedGeoPoint is still null, it means there was an error in getting or searching location.
                     // The error message for the underlying issue would have been shown by _getCurrentLocationAndGeocodeInternal or _searchAndSetLocationInternal.
                     setState(() {
                       _isLocationConfirmed = false;
                     });
                     // Trigger validation after the next frame to ensure state is updated
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        _formKeyStep1_LocationDetails.currentState?.validate(); // Force re-validation
                      }
                    });
                  }
                  setState(() { _isLoading = false; });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[600],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Confirm Location', style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 10),
            if (_selectedGeoPoint != null && _isLocationConfirmed) 
              FutureBuilder<String>(
                future: _getReadableLocation(_selectedGeoPoint!),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Text('Confirmed Location: Loading...', style: TextStyle(color: Colors.grey));
                  } else if (snapshot.hasError) {
                    return Text('Confirmed Location: Error loading address: ${snapshot.error}', style: const TextStyle(color: Colors.red));
                  } else {
                    return Text('Confirmed Location: ${snapshot.data ?? 'Unknown Location'}', style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.bold));
                  }
                },
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  _searchAddressController.text.isNotEmpty && !_isLocationConfirmed
                      ? 'Location pending confirmation. Tap "Confirm Location" button.' 
                      : 'Enter an address or use "My Current Location", then tap "Confirm Location".',
                  style: TextStyle(color: Colors.orange[800], fontSize: 12),
                ),
              ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _pickupNotesController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Pick-up Notes (Optional)',
                hintText: 'E.g., Meet at loading bay on GF',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep3ListingPreferences() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKeyStep3,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Step 3: Listing Preferences & Protection',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            ListTile(
              title: const Text('Select rental dates (optional)'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 18),
              onTap: () {
                if (mounted) { // Ensure mounted before showing SnackBar
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Date selection coming soon!')),
                  );
                }
              },
            ),
            SwitchListTile(
              title: const Text('Allow instant booking'),
              value: _allowInstantBooking,
              onChanged: (bool value) {
                if (mounted) { // Ensure mounted before setState
                  setState(() {
                    _allowInstantBooking = value;
                  });
                }
              },
            ),
            ListTile(
              title: const Text('Auto Protection Plan'),
              subtitle: const Text('Automatically apply protection plan to every rental'),
              trailing: Switch(
                value: _autoProtectionPlan,
                onChanged: (bool value) {
                  if (mounted) { // Ensure mounted before setState
                    setState(() {
                      _autoProtectionPlan = value;
                    });
                  }
                },
              ),
              onTap: () {
                if (mounted) { // Ensure mounted before showing SnackBar
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Protection plan details coming soon!')),
                  );
                }
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _cancellationPolicy,
              decoration: InputDecoration(
                labelText: 'Cancellation Policy',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              items: <String>['Flexible', 'Moderate', 'Strict']
                  .map<DropdownMenuItem<String>>((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (String? newValue) {
                if (mounted) { // Ensure mounted before setState
                  setState(() {
                    _cancellationPolicy = newValue!;
                  });
                }
              },
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please select a cancellation policy';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            ListTile(
              title: const Text('Notification Preferences'),
              subtitle: const Text('Notify me via email'),
              trailing: Switch(
                value: true, 
                onChanged: (bool value) {
                  if (mounted) { // Ensure mounted before showing SnackBar
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Notification preferences coming soon!')),
                    );
                  }
                },
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavigationButtons() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow( 
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_currentPage > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.ease);
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(color: Colors.blue[800]!),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text('Back', style: TextStyle(fontSize: 16, color: Colors.blue[800])),
              ),
            ),
          if (_currentPage > 0) const SizedBox(width: 15),
          Expanded(
            child: ElevatedButton(
              onPressed: _isLoading ? null : () { // Disable button while loading/submitting
                bool currentStepValid = false;
                String validationMessage = '';

                if (_currentPage == 0) { // Step 1 (Location & Details)
                  // First, validate the text field itself
                  bool textFieldValid = _formKeyStep1_LocationDetails.currentState?.validate() ?? false;

                  // Then, directly check if the location has actually been confirmed.
                  currentStepValid = textFieldValid && _isLocationConfirmed && _selectedGeoPoint != null;

                  if (!currentStepValid) {
                    if (_searchAddressController.text.isEmpty) {
                       validationMessage = 'Please enter an address or use "My Location" for Step 1.';
                    } else if (!_isLocationConfirmed || _selectedGeoPoint == null) {
                       validationMessage = 'Please confirm your location by tapping the "Confirm Location" button for Step 1.';
                    } else {
                       validationMessage = 'Please fill all required fields in Step 1.'; // Fallback
                    }
                    // Append debug info to the validation message for Step 1
                    validationMessage += '\nDebug Info:\n'
                                       'Text: "${_searchAddressController.text}" (Type: ${_searchAddressController.text.runtimeType})\n'
                                       'GeoPoint: ${_selectedGeoPoint} (Lat: ${_selectedGeoPoint?.latitude}, Lng: ${_selectedGeoPoint?.longitude}) (Type: ${_selectedGeoPoint.runtimeType})\n'
                                       'Confirmed: ${_isLocationConfirmed}';
                  }
                } else if (_currentPage == 1) { // Step 2 (Product Details)
                  currentStepValid = (_formKeyStep2_ProductDetails.currentState?.validate() ?? false) && (_selectedImages.isNotEmpty || _existingImageUrls.isNotEmpty); // Using new key
                  if (!currentStepValid) {
                    validationMessage = 'Please fill all required fields in Step 2 and upload at least one image.';
                  }
                } else if (_currentPage == 2) { // Step 3 (Listing Preferences)
                  currentStepValid = _formKeyStep3.currentState?.validate() ?? false; // Added null check
                   if (!currentStepValid) {
                     validationMessage = 'Please fill all required fields in Step 3.';
                   }
                }

                if (currentStepValid) {
                  if (_currentPage < 2) {
                    _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.ease);
                  } else {
                    _submitListing();
                  }
                } else {
                  if (mounted) { // Ensure mounted before showing SnackBar
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(validationMessage)),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[800],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _isLoading // Show progress indicator if loading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      _currentPage == 2 ? 'Submit' : 'Continue',
                      style: const TextStyle(fontSize: 16),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// Custom widget for dotted border, used for image upload area
class DottedBorderContainer extends StatelessWidget {
  final Widget child;
  const DottedBorderContainer({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 120,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border.all(color: Colors.grey[400]!, style: BorderStyle.solid),
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }
}
