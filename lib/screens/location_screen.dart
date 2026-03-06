import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Import Firestore
import 'package:firebase_auth/firebase_auth.dart'; // Import FirebaseAuth for current user
import 'package:geolocator/geolocator.dart'; // For current location
import 'package:geocoding/geocoding.dart'; // For geocoding/reverse geocoding
import 'dart:async'; // For StreamSubscription

import '../services/auth_service.dart'; // Import your AuthService

class LocationScreen extends StatefulWidget {
  const LocationScreen({Key? key}) : super(key: key);

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  GoogleMapController? _mapController; // Controller for the Google Map
  Set<Marker> _markers = {}; // Set to store your map markers

  Map<String, dynamic>? _selectedItemData; // Stores the selected item's Firestore data

  bool _isLoadingMap = true; // For initial map and data loading (getting location, animating map)
  Position? _currentLocation; // User's current geographical location, updated by Geolocator

  final AuthService _authService = AuthService();
  User? _currentUser; // Current authenticated user

  StreamSubscription<QuerySnapshot>? _itemsSubscription; // Subscription to Firestore items
  StreamSubscription<User?>? _authStateSubscription; // Subscription to auth state

  // Define the search radius in kilometers
  double _searchRadiusKm = 20.0; // Default search radius of 20 km (can be 50.0 etc.)

  // Initial camera position (fallback if user location not available quickly or permissions denied)
  static const CameraPosition _initialCameraPosition = CameraPosition(
    target: LatLng(3.0735, 101.6074), // Sunway Pyramid coordinates
    zoom: 14.0, // Adjust zoom level as needed
  );

  @override
  void initState() {
    super.initState();
    _currentUser = _authService.getCurrentUser(); // Initialize current user
    // Start determining the initial map position and user's location.
    // _updateMarkers will be called after _currentLocation is set in _determineAndSetInitialMapPosition.
    _determineAndSetInitialMapPosition(); 
    _subscribeToItems(); // Start listening to Firestore items regardless of initial location
    
    // Subscribe to auth state changes to update _currentUser
    _authStateSubscription = _authService.authStateChanges.listen((user) {
      if (mounted) {
        setState(() {
          _currentUser = user;
        });
      }
    });
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _itemsSubscription?.cancel(); // Cancel Firestore items subscription
    _authStateSubscription?.cancel(); // Cancel auth state subscription
    super.dispose();
  }

  // Centralized logic to determine initial map position and user's current location
  Future<void> _determineAndSetInitialMapPosition() async {
    setState(() {
      _isLoadingMap = true; // Start loading indicator
    });
    Position? position;
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Location permissions are denied. Showing all items (no radius filter).')),
            );
          }
          position = null; // No current location for filtering
        }
      }

      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 10));
        _currentLocation = position; // Store current location if successful
      }
    } catch (e) {
      print('Error getting current location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not get current location: ${e.toString().replaceFirst('Exception: ', '')}. Showing all items (no radius filter).')),
        );
      }
      position = null; // Ensure position is null on error
    } finally {
      if (mounted) {
        // Animate camera to user's location or default position
        if (_mapController != null) {
          await _mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(
              LatLng(
                position?.latitude ?? _initialCameraPosition.target.latitude,
                position?.longitude ?? _initialCameraPosition.target.longitude,
              ),
              position != null ? 14.0 : _initialCameraPosition.zoom, // Use closer zoom if actual location, else default
            ),
          );
        }
        setState(() {
          _isLoadingMap = false; // End loading indicator
        });
        // After fetching location, force marker update to apply filter
        // This is crucial for applying the filter after _currentLocation is available.
        _itemsSubscription?.pause(); // Temporarily pause to avoid double processing if a snapshot comes in immediately
        _subscribeToItems(); // Re-subscribe to trigger _updateMarkers with new _currentLocation
      }
    }
  }


  // Subscribes to real-time updates from the 'items' collection
  void _subscribeToItems() {
    _itemsSubscription?.cancel(); // Cancel any existing subscription
    _itemsSubscription = FirebaseFirestore.instance.collection('items').snapshots().listen((snapshot) {
      if (mounted) {
        _updateMarkers(snapshot.docs); // Update markers with the latest data
      }
    }, onError: (error) {
      print('Error fetching items: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading items: ${error.toString()}')),
        );
      }
    });
  }

  // Updates map markers based on fetched item documents and applies radius filter
  void _updateMarkers(List<DocumentSnapshot> itemDocs) {
    Set<Marker> newMarkers = {};
    for (var doc in itemDocs) {
      // Create a mutable map from the Firestore document data
      final Map<String, dynamic> itemData = doc.data() as Map<String, dynamic>;
      final Map<String, dynamic> mutableItemData = Map.from(itemData); // Create a mutable copy
      mutableItemData['id'] = doc.id; // Store the document ID

      LatLng? itemLatLng;
      dynamic locationRaw = itemData['location']; // Can be GeoPoint or String

      if (locationRaw is GeoPoint) {
        itemLatLng = LatLng(locationRaw.latitude, locationRaw.longitude);
      } else if (locationRaw is String) {
        try {
          final parts = locationRaw.split(',');
          if (parts.length == 2) {
            final double lat = double.parse(parts[0].trim());
            final double lng = double.parse(parts[1].trim());
            itemLatLng = LatLng(lat, lng);
          } else {
            print('Invalid location string format for item ${doc.id}: "$locationRaw". Expected "latitude,longitude".');
          }
        } catch (e) {
          print('Error parsing location string for item ${doc.id} "$locationRaw": $e');
        }
      }

      // Apply radius filter here
      if (itemLatLng != null) { // Only proceed if LatLng was successfully determined
        double? distInMeters;
        String distanceText = 'N/A';

        if (_currentLocation != null) {
          distInMeters = Geolocator.distanceBetween(
            _currentLocation!.latitude,
            _currentLocation!.longitude,
            itemLatLng.latitude,
            itemLatLng.longitude,
          );

          if (distInMeters < 1000) {
            distanceText = '${distInMeters.round()} m away';
          } else {
            distanceText = '${(distInMeters / 1000).toStringAsFixed(1)} km away';
          }
        }

        // Only add marker if _currentLocation is NOT available (show all)
        // OR if _currentLocation IS available AND the item is within the search radius
        if (_currentLocation == null || (distInMeters != null && distInMeters <= _searchRadiusKm * 1000)) {
          final String itemName = itemData['name'] ?? 'Untitled Item';
          final String itemPrice = 'RM${(itemData['pricePerDay'] as num?)?.toStringAsFixed(2) ?? '0.00'}/day';
          
          newMarkers.add(
            Marker(
              markerId: MarkerId(doc.id), // Use doc.id for markerId
              position: itemLatLng, // <-- This uses the parsed LatLng
              infoWindow: InfoWindow(
                title: itemName,
                snippet: '$itemPrice - $distanceText', // Use calculated distance
                onTap: () {
                  // InfoWindow tap navigation already uses doc.id, which is correct
                  Navigator.pushNamed(context, '/item_detail', arguments: doc.id);
                },
              ),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
              onTap: () {
                if (mounted) {
                  setState(() {
                    _selectedItemData = mutableItemData; // <-- Set the mutable map with 'id'
                  });
                }
              },
            ),
          );
        }
      }
    }
    if (mounted) {
      setState(() {
        _markers = newMarkers;
      });
    }
  }

  // Function to perform reverse geocoding for location display (copied from ItemCard/HomePage)
  Future<String> _getReadableLocation(dynamic location) async {
    LatLng? coordinates;
    if (location is GeoPoint) {
      coordinates = LatLng(location.latitude, location.longitude);
    } else if (location is String) {
      try {
        final parts = location.split(',');
        if (parts.length == 2) {
          final double lat = double.parse(parts[0].trim());
          final double lng = double.parse(parts[1].trim());
          coordinates = LatLng(lat, lng);
        }
      } catch (e) {
        print('Error parsing location string for readable address: $e');
      }
    }

    if (coordinates != null) {
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(coordinates.latitude, coordinates.longitude);
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks.first;
          // You can customize the format based on what you need
          // e.g., "${place.street}, ${place.locality}, ${place.postalCode}"
          return "${place.street ?? ''}, ${place.locality ?? place.subLocality ?? ''}, ${place.postalCode ?? ''}";
        }
      } catch (e) {
        print("Error during reverse geocoding in LocationScreen: $e");
        return 'Lat: ${coordinates.latitude.toStringAsFixed(4)}, Lng: ${coordinates.longitude.toStringAsFixed(4)} (Geocoding failed)';
      }
    }
    return 'Unknown Location';
  }


  // Callback when the map is created
  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    // _determineAndSetInitialMapPosition is already called in initState
    // and handles camera animation and marker filtering.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: const Text(
          'Search for an item',
          style: TextStyle(color: Colors.black, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ElevatedButton(
              onPressed: () {
                // Dummy filter action
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Filter functionality to be implemented.')),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[800],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Filters'),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // ACTUAL Google Map Widget
          Positioned.fill(
            child: _isLoadingMap
                ? const Center(child: CircularProgressIndicator())
                : GoogleMap(
                    onMapCreated: _onMapCreated,
                    initialCameraPosition: _initialCameraPosition, // This is the initial fallback camera position
                    markers: _markers, // Display the filtered markers
                    myLocationEnabled: true, // Shows the user's current location dot
                    myLocationButtonEnabled: true, // Shows a button to recenter on user's location
                    zoomControlsEnabled: false, // Hide default zoom controls if you want custom ones
                    // When the map is tapped, deselect any item preview card
                    onTap: (latLng) {
                      if (mounted) {
                        setState(() {
                          _selectedItemData = null;
                        });
                      }
                    },
                  ),
          ),

          // Information Banner (Overlay on top of map)
          Positioned(
            top: 10,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[800], size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Verify your ID to book rentals. Lets help to build a safe and trusted community.',
                      style: TextStyle(color: Colors.blue[800], fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Item Detail Preview Card (appears from bottom)
          if (_selectedItemData != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildItemPreviewCard(_selectedItemData!),
            ),
        ],
      ),
    );
  }

  // Builds the preview card for the selected item using real Firestore data
  Widget _buildItemPreviewCard(Map<String, dynamic> itemData) {
    // This now correctly gets the 'id' field which was explicitly added in _updateMarkers
    final String itemId = itemData['id'] ?? 'N/A'; 
    final String itemName = itemData['name'] ?? 'Untitled Item';
    final String itemPrice = 'RM${(itemData['pricePerDay'] as num?)?.toStringAsFixed(2) ?? '0.00'}/day';
    final String ownerId = itemData['ownerId'] ?? '';
    
    // Extract image URL (first one if available, otherwise fallback)
    final List<String> imageUrls = (itemData['images'] is List)
        ? List<String>.from(itemData['images'])
        : [];
    final String imageUrl = imageUrls.isNotEmpty
        ? imageUrls[0]
        : 'assets/images/examples.png'; // Fallback image

    // Determine LatLng for distance calculation from GeoPoint or String
    LatLng? itemLatLngForCalculation;
    dynamic rawLocation = itemData['location'];

    if (rawLocation is GeoPoint) {
      itemLatLngForCalculation = LatLng(rawLocation.latitude, rawLocation.longitude);
    } else if (rawLocation is String) {
      try {
        final parts = rawLocation.split(',');
        if (parts.length == 2) {
          final double lat = double.parse(parts[0].trim());
          final double lng = double.parse(parts[1].trim());
          itemLatLngForCalculation = LatLng(lat, lng);
        }
      } catch (e) {
        print('Error parsing location string for distance calculation "$rawLocation": $e');
      }
    }

    // Calculate distance for display in the card
    String distance = 'N/A';
    if (_currentLocation != null && itemLatLngForCalculation != null) {
      double distInMeters = Geolocator.distanceBetween(
        _currentLocation!.latitude,
        _currentLocation!.longitude,
        itemLatLngForCalculation.latitude,
        itemLatLngForCalculation.longitude,
      );
      if (distInMeters < 1000) {
        distance = '${distInMeters.round()} m away';
      } else {
        distance = '${(distInMeters / 1000).toStringAsFixed(1)} km away';
      }
    }
    
    // Get availability status (assuming 'status' field in Firestore)
    final String status = itemData['status'] ?? 'unknown';
    bool isAvailable = status.toLowerCase() == 'available';


    return Container(
      margin: const EdgeInsets.all(16.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            spreadRadius: 2,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: imageUrl.startsWith('http') // Check if it's a network URL
                    ? Image.network(
                        imageUrl,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Image.asset(
                          'assets/images/examples.png', // Fallback for network image errors
                          fit: BoxFit.cover,
                        ),
                      )
                    : Image.asset(
                        imageUrl, // Assume it's an asset if not http
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
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      itemName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                      maxLines: 1, // Ensure text doesn't overflow
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      itemPrice,
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(Icons.location_on, color: Colors.grey[600], size: 16),
                        const SizedBox(width: 5),
                        Text(
                          distance, // Display calculated distance
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.grey),
                onPressed: () {
                  setState(() {
                    _selectedItemData = null; // Close the preview card
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Availability status from Firestore item data
          Row(
            children: [
              Icon(
                isAvailable ? Icons.check_circle_outline : Icons.cancel_outlined,
                color: isAvailable ? Colors.green : Colors.red,
                size: 18,
              ),
              const SizedBox(width: 5),
              Text(
                isAvailable ? 'Available' : 'Not Available',
                style: TextStyle(
                  color: isAvailable ? Colors.green : Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    // Navigate to Item Details Page with actual item ID
                    Navigator.pushNamed(context, '/item_detail', arguments: itemId);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[800],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'View Details',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(width: 10), // Spacing between buttons
              // Chat with Owner Button (conditional on user login and not being owner)
              if (_currentUser != null && _currentUser!.uid != ownerId) // Only show if logged in and not owner
                SizedBox(
                  width: 50, // Fixed width for icon button
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Chat with owner ${ownerId} - Coming Soon!')),
                      );
                      // TODO: Implement actual navigation to chat screen
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[800],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: EdgeInsets.zero, // No padding for icon button
                    ),
                    child: const Icon(Icons.chat_bubble_outline), // Chat icon
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
