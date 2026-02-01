import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'pages/splash_screen.dart';
import 'pages/auth_gate.dart';
import 'pages/login_phone_page.dart';
import 'pages/verify_otp_page.dart';
import 'pages/create_profile_page.dart';
import 'pages/main_shell.dart';
import 'pages/explore_page.dart';
import 'pages/listing_flow_gate_page.dart';
import 'pages/sell_create_auction_page.dart';
import 'pages/seller_my_auctions_page.dart';
import 'pages/auction_detail_page.dart';
import 'pages/admin_panel_page.dart';
import 'pages/wallet_page.dart';
import 'pages/kyc_page.dart';
import 'pages/my_won_auctions_page.dart';
import 'services/payment_service.dart';
import 'services/admin_settings_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Stripe publishable key: 1) Firestore adminSettings/main.stripePublishableKey, 2) dart-define
  try {
    final key = await AdminSettingsService().getStripePublishableKey();
    if (key != null && key.isNotEmpty) {
      PaymentService.setPublishableKey(key);
    }
  } catch (_) {}
  const envKey = String.fromEnvironment(
    'STRIPE_PUBLISHABLE_KEY',
    defaultValue: '',
  );
  if (envKey.isNotEmpty && envKey != 'pk_test_YOUR_PUBLISHABLE_KEY') {
    PaymentService.setPublishableKey(envKey);
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/authGate': (context) => const AuthGate(),
        '/login': (context) => const LoginPhonePage(),
        '/verifyOtp': (context) => const VerifyOtpPage(
              verificationId: '',
              phoneNumber: '',
            ),
        '/createProfile': (context) => const CreateProfilePage(),
        '/home': (context) => const MainShell(),
        '/explore': (context) => const ExplorePage(),
        '/sellCreateAuction': (context) => const ListingFlowGatePage(),
        '/sellerMyAuctions': (context) => const SellerMyAuctionsPage(),
        '/adminPanel': (context) {
          // Route protection - AdminPanelPage will check admin status internally
          return const AdminPanelPage();
        },
        '/wallet': (context) => const WalletPage(),
        '/kyc': (context) => const KycPage(),
        '/myWins': (context) => const MyWonAuctionsPage(),
      },
      onGenerateRoute: (settings) {
        final name = settings.name;
        if (name == null) return null;

        final uri = Uri.parse(name);

        // Option B: /auctionDetail?auctionId=...
        if (uri.path == '/auctionDetail') {
          final fromQuery = uri.queryParameters['auctionId'];
          final fromArgs = settings.arguments is String ? settings.arguments as String : null;
          final auctionId = fromQuery ?? fromArgs;

          if (auctionId != null && auctionId.isNotEmpty) {
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => AuctionDetailPage(auctionId: auctionId),
            );
          }

          return MaterialPageRoute(
            settings: settings,
            builder: (_) => const Scaffold(
              body: Center(child: Text('Invalid auction ID')),
            ),
          );
        }

        // Option A-compatible: /auctionDetail/<id>
        if (uri.pathSegments.length == 2 && uri.pathSegments.first == 'auctionDetail') {
          final auctionId = uri.pathSegments[1];
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => AuctionDetailPage(auctionId: auctionId),
          );
        }

        return null;
      },
    );
  }
}