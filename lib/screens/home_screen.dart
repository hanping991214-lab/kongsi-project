import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geocoding/geocoding.dart';
import 'package:firebase_storage/firebase_storage.dart'; // Import Firebase Storage
import '../services/auth_service.dart';
import 'dart:async'; // Import for StreamSubscription and Timer
import 'dart:math'; // For random shuffling

// Your existing getCurrentLocation function
Future<Position?> getCurrentLocation() async {
  bool serviceEnabled;
  LocationPermission permission;

  serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    print('Location services are disabled.');
    return null;
  }

  permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      print('Location permissions are denied');
      return null;
    }
  }

  if (permission == LocationPermission.deniedForever) {
    print('Location permissions are permanently denied, we cannot request permissions.');
    return null;
  }

  try {
    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 10),
    );
    print('Current location: ${position.latitude}, ${position.longitude}');
    return position;
  } catch (e) {
    print('Error getting location: $e');
    return null;
  }
}

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  String _currentSearchLocationDisplay = 'All Locations';
  Position? _lastKnownGeolocation;
  String? _selectedCommunityFilter;

  final AuthService _authService = AuthService();
  User? _currentUser;
  bool _isCurrentUserLender = false;

  StreamSubscription<User?>? _authStateSubscription;
  StreamSubscription<DocumentSnapshot>? _userProfileSubscription;

  // NEW: List to hold advertisement image URLs
  late Future<List<String>> _adImageUrlsFuture;

  // NEW: PageController for the Ad Banner
  late PageController _pageController;
  // NEW: Timer for auto-scrolling
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _fetchInitialGeolocation();
    _authStateSubscription = _authService.authStateChanges.listen((User? user) {
      if (mounted) {
        setState(() {
          _currentUser = user;
        });
        if (user != null) {
          _subscribeToUserProfile(user.uid);
        } else {
          _userProfileSubscription?.cancel();
          if (mounted) {
            setState(() {
              _isCurrentUserLender = false;
            });
          }
        }
      }
    });

    // Initialize the future to fetch ad image URLs
    _adImageUrlsFuture = _fetchAdImageUrls();

    // NEW: Initialize PageController for the ad banner
    // Start at a high number to allow backward scrolling for infinite effect
    _pageController = PageController(initialPage: 1000); 

    // NEW: Start auto-scrolling timer after the first frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startAutoScrollTimer();
    });
  }

  // NEW: Function to start the auto-scrolling timer
  void _startAutoScrollTimer() {
    _timer?.cancel(); // Cancel any existing timer
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_pageController.hasClients) {
        // Get the current page, increment it, and animate to the next page
        int nextPage = _pageController.page!.round() + 1;
        _pageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeIn,
        );
      }
    });
  }

  // NEW: Function to fetch ad image URLs from Firebase Storage
  Future<List<String>> _fetchAdImageUrls() async {
    final FirebaseStorage storage = FirebaseStorage.instance;
    List<String> imageUrls = [];
    try {
      // List all items (files) in the 'ad_images' folder
      ListResult result = await storage.ref('ad_images').listAll();

      for (var item in result.items) {
        // Get the download URL for each item
        String url = await item.getDownloadURL();
        imageUrls.add(url);
      }
      return imageUrls;
    } catch (e) {
      print('Error fetching ad images: $e');
      // Return an empty list or a list with a placeholder if an error occurs
      return [];
    }
  }

  void _subscribeToUserProfile(String uid) {
    _userProfileSubscription?.cancel();
    _userProfileSubscription = _authService.getUserProfileStream(uid).listen((snapshot) {
      if (mounted) {
        if (snapshot.exists) {
          final userData = snapshot.data()! as Map<String, dynamic>; 
          setState(() {
            _isCurrentUserLender = userData['isLender'] ?? false;
          });
        } else {
          setState(() {
            _isCurrentUserLender = false;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel();
    _userProfileSubscription?.cancel();
    _searchController.dispose();
    // NEW: Cancel the timer and dispose the PageController
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _fetchInitialGeolocation() async {
    Position? position = await getCurrentLocation();
    if (position != null) {
      setState(() {
        _lastKnownGeolocation = position;
        if (_selectedCommunityFilter == null) {
          _currentSearchLocationDisplay = 'Current Location';
        }
      });
    } else {
      if (_selectedCommunityFilter == null) {
        setState(() {
          _currentSearchLocationDisplay = 'All Locations';
          _lastKnownGeolocation = null;
        });
      }
    }
  }

  Future<String> _getReadableLocation(dynamic location) async {
    if (location is GeoPoint) {
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(location.latitude, location.longitude);
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks.first;
          return "${place.street ?? ''}, ${place.locality ?? place.subLocality ?? ''}, ${place.postalCode ?? ''}";
        }
      } catch (e) {
        print("Error during reverse geocoding in HomePage: $e");
        return 'Lat: ${location.latitude.toStringAsFixed(4)}, Lng: ${location.longitude.toStringAsFixed(4)} (Geocoding failed)';
      }
    } else if (location is String && location.isNotEmpty) {
      return location;
    }
    return 'Unknown Location';
  }

  void _onItemTapped(int index) async {
    setState(() {
      _selectedIndex = index;
    });

    if (index == 0) {
      return;
    }

    if (_isCurrentUserLender) {
      switch (index) {
        case 1: // Items (My Listings)
          await Navigator.pushNamed(context, '/my_listings');
          break;
        case 2: // Requests
          await Navigator.pushNamed(context, '/rental_requests');
          break;
        case 3: // Inbox - NOW NAVIGATES TO DUMMY CHAT SCREEN
          await Navigator.pushNamed(context, '/chat_screen');
          break;
      }
    } else {
      // Renter/Guest Navigation
      switch (index) {
        case 1: // Feed
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Feed Screen - Still in Development!')),
          );
          break;
        case 2: // Orders (formerly Bookings)
          await Navigator.pushNamed(context, '/renter_orders');
          break;
        case 3: // Inbox - NOW NAVIGATES TO DUMMY CHAT SCREEN
          await Navigator.pushNamed(context, '/chat_screen');
          break;
      }
    }
    
    if (mounted) {
      setState(() {
        _selectedIndex = 0;
      });
    }
  }

  void _performSearch(String query) {
    String searchItem = query.trim();
    String locationContext = _currentSearchLocationDisplay;

    dynamic actualLocationData;

    if (_selectedCommunityFilter != null) {
      locationContext = _selectedCommunityFilter!;
      actualLocationData = _selectedCommunityFilter;
    } else if (_lastKnownGeolocation != null) {
      locationContext = 'near current location';
      actualLocationData = _lastKnownGeolocation;
    } else {
      actualLocationData = null;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Searching for "$searchItem" ' +
              (actualLocationData != null ? '$locationContext' : 'in all locations') +
              ' (Data: $actualLocationData)',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isLoggedIn = _currentUser != null;

    List<BottomNavigationBarItem> bottomNavItems;
    if (isLoggedIn && _isCurrentUserLender) {
      bottomNavItems = const <BottomNavigationBarItem>[
        BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.storage), label: 'Items'),
        BottomNavigationBarItem(icon: Icon(Icons.receipt_long), label: 'Requests'),
        BottomNavigationBarItem(icon: Icon(Icons.inbox), label: 'Inbox'),
      ];
    } else {
      bottomNavItems = const <BottomNavigationBarItem>[
        BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.article), label: 'Feed'),
        BottomNavigationBarItem(icon: Icon(Icons.book), label: 'Orders'),
        BottomNavigationBarItem(icon: Icon(Icons.inbox), label: 'Inbox'),
      ];
    }

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60.0),
        child: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,

          title: Container(
            height: 40,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(20),
            ),
            child: TextField(
              controller: _searchController,
              onSubmitted: _performSearch,
              decoration: InputDecoration(
                hintText: 'Products, Nearest store...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                suffixIcon: IconButton(
                  icon: Icon(Icons.my_location, color: Colors.blue[800]),
                  onPressed: () {
                    setState(() {
                      _selectedCommunityFilter = null;
                    });
                    _fetchInitialGeolocation();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Using current location for search.')),
                    );
                  },
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 10.0),
              ),
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: isLoggedIn
                  ? InkWell(
                      onTap: () {
                        Navigator.pushNamed(context, '/account_details');
                      },
                      child: StreamBuilder<DocumentSnapshot>(
                        stream: _currentUser?.uid != null
                            ? _authService.getUserProfileStream(_currentUser!.uid)
                            : null,
                        builder: (context, snapshot) {
                          ImageProvider avatarImage;
                          if (_currentUser?.photoURL != null && _currentUser!.photoURL!.isNotEmpty) {
                            avatarImage = NetworkImage(_currentUser!.photoURL!);
                          } else if (snapshot.hasData && snapshot.data!.exists) {
                            final data = snapshot.data!.data() as Map<String, dynamic>;
                            final firestoreProfilePicUrl = data['profilePictureUrl'] as String?;
                            if (firestoreProfilePicUrl != null && firestoreProfilePicUrl.isNotEmpty) {
                              avatarImage = NetworkImage(firestoreProfilePicUrl);
                            } else {
                              avatarImage = const AssetImage('assets/images/Profile_Placeholder.png');
                            }
                          } else {
                            avatarImage = const AssetImage('assets/images/Profile_Placeholder.png');
                          }

                          return CircleAvatar(
                            radius: 18,
                            backgroundImage: avatarImage,
                          );
                        },
                      ),
                    )
                  : ElevatedButton(
                      onPressed: () {
                        Navigator.pushNamed(context, '/login');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[800],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: const Text(
                        'Login',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            if (isLoggedIn)
              StreamBuilder<DocumentSnapshot>(
                stream: _currentUser?.uid != null
                    ? _authService.getUserProfileStream(_currentUser!.uid)
                    : null,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting || !snapshot.hasData || !snapshot.data!.exists) {
                    return const SizedBox();
                  }

                  Map<String, dynamic> userData = snapshot.data!.data() as Map<String, dynamic>;
                  bool isUserLender = userData['isLender'] ?? false;
                  double myEarnings = (userData['myEarnings'] as num?)?.toDouble() ?? 0.0;
                  double rewardCredits = (userData['rewardCredits'] as num?)?.toDouble() ?? 0.0;

                  if (isUserLender) {
                    return Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
                        decoration: BoxDecoration(
                          color: Colors.blue[800],
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildInfoCard(Icons.payments, 'My Earnings', 'RM ${myEarnings.toStringAsFixed(2)}'),
                            Container(
                              width: 1,
                              height: 40,
                              color: Colors.white.withOpacity(0.5),
                            ),
                            _buildInfoCard(Icons.card_giftcard, 'Reward Credits', 'RM ${rewardCredits.toStringAsFixed(2)}'),
                          ],
                        ),
                      ),
                    );
                  } else {
                    return const SizedBox();
                  }
                },
              ),

            // NEW: Ad Banner Section with auto-play and looping
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
              child: FutureBuilder<List<String>>(
                future: _adImageUrlsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Container(
                      height: 150,
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator(),
                    );
                  } else if (snapshot.hasError) {
                    return Container(
                      height: 150,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Text('Error loading ads: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
                    );
                  } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Container(
                      height: 150,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Text('No ads available.', style: TextStyle(color: Colors.grey)),
                    );
                  } else {
                    final List<String> imageUrls = snapshot.data!;
                    // If there's only one image, don't use PageView.builder with infinite loop logic
                    if (imageUrls.length == 1) {
                      return Container(
                        height: 150,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.3),
                              spreadRadius: 2,
                              blurRadius: 5,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: Image.network(
                            imageUrls[0],
                            fit: BoxFit.cover,
                            width: double.infinity,
                            errorBuilder: (context, error, stackTrace) => Container(
                              color: Colors.grey[300],
                              child: const Icon(Icons.broken_image, color: Colors.grey, size: 50),
                            ),
                          ),
                        ),
                      );
                    }
                    
                    return Container(
                      height: 150, // Fixed height for the banner
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.3),
                            spreadRadius: 2,
                            blurRadius: 5,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: PageView.builder(
                        controller: _pageController, // Assign the controller
                        // Use a very large number for itemCount to simulate infinite scrolling
                        itemCount: imageUrls.length * 1000, 
                        onPageChanged: (index) {
                          // Restart the timer when the user manually scrolls
                          _startAutoScrollTimer(); 
                        },
                        itemBuilder: (context, index) {
                          // Use modulo to loop through the actual image URLs
                          final int imageIndex = index % imageUrls.length;
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: Image.network(
                              imageUrls[imageIndex],
                              fit: BoxFit.cover,
                              width: double.infinity,
                              errorBuilder: (context, error, stackTrace) => Container(
                                color: Colors.grey[300],
                                child: const Icon(Icons.broken_image, color: Colors.grey, size: 50),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  }
                },
              ),
            ),
            // END NEW: Ad Banner Section

            // Categories Section
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Categories',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      TextButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('View More Categories clicked!')),
                          );
                        },
                        child: const Row(
                          children: [
                            Text('View More', style: TextStyle(color: Colors.blue)),
                            Icon(Icons.arrow_forward_ios, size: 12, color: Colors.blue),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 4,
                    childAspectRatio: 0.8,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    children: [
                      _buildCategoryItem(context, Icons.shopping_bag_outlined, 'Rent an Item', '/rent_item'),
                      _buildCategoryItem(context, Icons.storefront, 'Marketplace', '/marketplace'),
                      _buildCategoryItem(context, Icons.location_on, 'Locations', '/locations'),
                      _buildCategoryItem(context, Icons.local_activity, 'Activities', '/activities'),
                      _buildCategoryItem(context, Icons.thumb_up, 'Liked', '/liked'),
                      _buildCategoryItem(context, Icons.dashboard, 'Dashboard', '/dashboard'),
                      _buildCategoryItem(context, Icons.groups, 'Community', '/community'),
                      _buildCategoryItem(context, Icons.more_horiz, 'Other', '/other'),
                    ],
                  ),
                ],
              ),
            ),

            // Recommendations Section (Now fetches from Firestore and shuffles)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Recommendations',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      TextButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Explore Recommendations clicked!')),
                          );
                        },
                        child: const Row(
                          children: [
                            Text('Explore Now', style: TextStyle(color: Colors.blue)),
                            Icon(Icons.arrow_forward_ios, size: 12, color: Colors.blue),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  SizedBox(
                    height: 200, // Fixed height for horizontal list
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('items').snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError) {
                          return Center(child: Text('Error: ${snapshot.error}'));
                        }
                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return const Center(child: Text('No recommendations available.'));
                        }

                        List<DocumentSnapshot> allItems = snapshot.data!.docs;
                        allItems.shuffle(Random());
                        
                        List<DocumentSnapshot> recommendedItems = allItems.take(3).toList();

                        return ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: recommendedItems.length,
                          itemBuilder: (context, index) {
                            Map<String, dynamic> itemData = recommendedItems[index].data()! as Map<String, dynamic>;
                            String itemId = recommendedItems[index].id;
                            String title = itemData['name'] ?? 'No Name';
                            String imageUrl = (itemData['images'] != null && itemData['images'] is List && itemData['images'].isNotEmpty && itemData['images'][0] is String && itemData['images'][0].isNotEmpty)
                                ? itemData['images'][0]
                                : 'assets/images/examples.png';
                            String price = 'RM${(itemData['pricePerDay'] as num?)?.toStringAsFixed(2) ?? '0.00'}/day';
                            return _buildRecommendationCard(itemId, imageUrl, title, price);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'For You',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 15),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('items').snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              children: [
                                const Icon(Icons.error_outline, color: Colors.red, size: 40),
                                const SizedBox(height: 10),
                                Text(
                                  'Error loading items: ${snapshot.error}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.red),
                                ),
                                const Text(
                                  'Please check your Firestore Security Rules to allow read access to the "items" collection.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return const Center(child: Text('No items found for you.'));
                      }

                      return Column(
                        children: snapshot.data!.docs.map((DocumentSnapshot document) {
                          Map<String, dynamic> itemData = document.data()! as Map<String, dynamic>;
                          String itemId = document.id;

                          String title = itemData['name'] ?? 'No Name';
                          
                          String imageUrl = (itemData['images'] != null && itemData['images'] is List && itemData['images'].isNotEmpty && itemData['images'][0] is String && itemData['images'][0].isNotEmpty)
                              ? itemData['images'][0]
                              : 'assets/images/examples.png';
                          
                          String pricePerDay = 'RM${(itemData['pricePerDay'] as num?)?.toStringAsFixed(2) ?? '0.00'}/day';
                          
                          dynamic rawLocation = itemData['location']; 
                          String ownerId = itemData['ownerId'] ?? ''; 

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10.0),
                            child: ItemCard(
                              itemId: itemId,
                              imageUrl: imageUrl,
                              title: title,
                              pricePerDay: pricePerDay,
                              locationData: rawLocation,
                              getReadableLocation: _getReadableLocation,
                              ownerId: ownerId,
                              onChatWithOwner: (id) {
                                if (isLoggedIn) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Chat function is under development.')),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Please login to chat with the owner.')),
                                  );
                                  Navigator.pushNamed(context, '/login');
                                }
                              },
                              onTap: () {
                                Navigator.pushNamed(
                                  context,
                                  '/item_detail',
                                  arguments: itemId,
                                );
                              },
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: bottomNavItems,
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blue[800],
        unselectedItemColor: Colors.grey,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            DrawerHeader(
              decoration: BoxDecoration(
                color: Colors.blue[800],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StreamBuilder<DocumentSnapshot>(
                    stream: _currentUser?.uid != null
                        ? _authService.getUserProfileStream(_currentUser?.uid ?? '')
                        : null,
                    builder: (context, snapshot) {
                      ImageProvider drawerAvatarImage;
                      if (_currentUser?.photoURL != null && _currentUser!.photoURL!.isNotEmpty) {
                        drawerAvatarImage = NetworkImage(_currentUser!.photoURL!);
                      } else if (snapshot.hasData && snapshot.data!.exists) {
                        final data = snapshot.data!.data() as Map<String, dynamic>;
                        final firestoreProfilePicUrl = data['profilePictureUrl'] as String?;
                        if (firestoreProfilePicUrl != null && firestoreProfilePicUrl.isNotEmpty) {
                          drawerAvatarImage = NetworkImage(firestoreProfilePicUrl);
                        } else {
                          drawerAvatarImage = const AssetImage('assets/images/Profile_Placeholder.png');
                        }
                      } else {
                        drawerAvatarImage = const AssetImage('assets/images/Profile_Placeholder.png');
                      }
                      return CircleAvatar(
                        radius: 30,
                        backgroundImage: drawerAvatarImage,
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _currentUser?.displayName ?? 'Guest User',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _currentUser?.email ?? 'Tap to Login/Sign Up',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            if (!isLoggedIn)
              ListTile(
                leading: const Icon(Icons.login),
                title: const Text('Login / Sign Up'),
                onTap: () async {
                  Navigator.pop(context);
                  await Navigator.pushNamed(context, '/login');
                },
              ),
            if (isLoggedIn)
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('Account Details'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/account_details');
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Account Details clicked!')),
                  );
                },
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.dashboard),
              title: const Text('Dashboard'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Dashboard Clicked!')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.list_alt),
              title: const Text('My Listings'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamedAndRemoveUntil(context, '/my_listings', (route) => false);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('My Listings Clicked!')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Rental History'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Rental History Click!')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Settings Clicked!')),
                );
              },
            ),
            const Divider(),
            if (isLoggedIn)
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Logout'),
                onTap: () async {
                  Navigator.pop(context);
                  await _authService.signOut();
                  Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Logged out!')),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(IconData icon, String title, String value) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 30),
        const SizedBox(height: 5),
        Text(
          title,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        Text(
          value,
          style: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildCategoryItem(BuildContext context, IconData icon, String label, String routeName) {
    return InkWell(
      onTap: () async {
        if (routeName == '/locations') {
          Navigator.pushNamed(context, routeName);
        } else if (routeName == '/community_selection') {
          final selectedCommunity = await Navigator.pushNamed(context, routeName);
          if (selectedCommunity != null && selectedCommunity is String) {
            setState(() {
              _selectedCommunityFilter = selectedCommunity;
              _currentSearchLocationDisplay = selectedCommunity;
              _lastKnownGeolocation = null;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Searching prioritized for: $selectedCommunity')),
            );
          } else if (selectedCommunity == null) {
            setState(() {
              _selectedCommunityFilter = null;
            });
            _fetchInitialGeolocation();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Community filter cleared. Using current location/all locations.')),
            );
          }
        } else if (routeName == '/upload_item') {
          Navigator.pushNamed(context, routeName);
        }
        else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Still in Development!'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      },
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.blue[800], size: 30),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationCard(String itemId, String imageUrl, String title, String price) {
    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(
          context,
          '/item_detail',
          arguments: itemId,
        );
      },
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              spreadRadius: 1,
              blurRadius: 5,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(10)),
              child: imageUrl.startsWith('http')
                  ? Image.network(
                      imageUrl,
                      height: 100,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Image.asset(
                        'assets/images/examples.png',
                        fit: BoxFit.cover,
                      ),
                    )
                  : Image.asset(
                      imageUrl,
                      height: 100,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: Colors.grey[200],
                        child: const Icon(Icons.image_not_supported, color: Colors.grey),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    price,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ItemCard extends StatelessWidget {
  final String itemId;
  final String imageUrl;
  final String title;
  final String pricePerDay;
  final dynamic locationData;
  final String ownerId;
  final Function(String ownerId) onChatWithOwner;
  final VoidCallback onTap;
  final Future<String> Function(dynamic location) getReadableLocation;

  const ItemCard({
    Key? key,
    required this.itemId,
    required this.imageUrl,
    required this.title,
    required this.pricePerDay,
    required this.locationData,
    required this.ownerId,
    required this.onChatWithOwner,
    required this.onTap,
    required this.getReadableLocation,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 3,
        margin: const EdgeInsets.symmetric(horizontal: 0.0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: imageUrl.startsWith('http')
                  ? Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Image.asset(
                        'assets/images/examples.png',
                        fit: BoxFit.cover,
                      ),
                    )
                  : Image.asset(
                      imageUrl,
                      height: 100,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: Colors.grey[200],
                        child: const Icon(Icons.image_not_supported, color: Colors.grey),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    pricePerDay,
                    style: TextStyle(color: Colors.blue[700], fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: FutureBuilder<String>(
                          future: getReadableLocation(locationData),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Text('Loading...', style: TextStyle(fontSize: 14, color: Colors.grey));
                            } else if (snapshot.hasError) {
                              return Text('Error: ${snapshot.error}', style: TextStyle(fontSize: 14, color: Colors.red));
                            } else {
                              return Text(
                                snapshot.data ?? 'Unknown Location',
                                style: TextStyle(color: Colors.grey[600], fontSize: 14),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => onChatWithOwner(ownerId),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[700],
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 2,
                      ),
                      child: const Text('Chat With Owner', style: TextStyle(fontSize: 15)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
