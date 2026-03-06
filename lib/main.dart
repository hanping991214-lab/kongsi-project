import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Import FirebaseAuth if needed directly in main for checks

import 'firebase_options.dart';

// Import screens using relative paths as requested
import 'screens/splash_screen.dart'; // Keep SplashScreen in its own file
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/home_screen.dart';
import 'screens/account_details_screen.dart';
import 'screens/upload_item_screen.dart'; // Import the new UploadItemScreen
import 'screens/item_detail_screen.dart'; // Import the new ItemDetailScreen
import 'screens/location_screen.dart'; // Import the LocationScreen
import 'screens/my_listings_screen.dart'; // Import the MyListingsScreen
import 'screens/booking_screen.dart'; // Import the BookingScreen
import 'screens/rental_requests_screen.dart'; // Import the RentalRequestsScreen
import 'screens/renter_orders_screen.dart'; // NEW: Import the RenterOrdersScreen (renamed)
import 'screens/chat_screen.dart'; // NEW: Import the ChatScreen (dummy or real)

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KongSI',
      debugShowCheckedModeBanner: false, // Set to false to remove the debug banner
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        appBarTheme: const AppBarTheme(
          elevation: 0, // Remove shadow for cleaner look
          color: Colors.white,
          foregroundColor: Colors.black,
        ),
      ),
      initialRoute: '/', // SplashScreen is the initial route
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/signup': (context) => const SignUpScreen(),
        '/forgot_password': (context) => const ForgotPasswordScreen(),
        '/home': (context) => const HomePage(),
        '/account_details': (context) => const AccountDetailsScreen(),
        '/upload_item': (context) => const UploadItemScreen(), // Route for Upload Item
        '/item_detail': (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          if (args is String) {
            return ItemDetailScreen(itemId: args);
          }
          // Handle invalid arguments or provide a default/error screen
          return Scaffold(
            appBar: AppBar(title: const Text('Error')),
            body: const Center(child: Text('Invalid Item ID')),
          );
        },
        '/locations': (context) => const LocationScreen(), // Route for LocationScreen
        '/my_listings': (context) => const MyListingsScreen(), // Route for MyListingsScreen
        '/booking': (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          if (args is String) {
            return BookingPage(itemId: args);
          }
          return Scaffold(
            appBar: AppBar(title: const Text('Error')),
            body: const Center(child: Text('Invalid Item ID for Booking')),
          );
        },
        '/rental_requests': (context) => const RentalRequestsScreen(), // Route for RentalRequestsScreen
        '/renter_orders': (context) => const RenterOrdersScreen(), // NEW: Route for RenterOrdersScreen (renamed)
        '/chat_screen': (context) => const ChatScreen(), // NEW: Route for ChatScreen
      },
    );
  }
}
