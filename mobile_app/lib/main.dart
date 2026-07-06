// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Provider;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Providers
import 'providers/auth_provider.dart';
import 'presentation/cart/cart_provider.dart'; // تأكد من وجود هذا الملف

// Screens
import 'presentation/onboarding/onboarding_screen.dart';
import 'presentation/auth/login_screen.dart';
import 'presentation/auth/signup_screen.dart';
import 'presentation/home/customer_home_screen.dart'; // تأكد من وجود هذا الملف
import 'presentation/home/retailer_home_screen.dart'; // تأكد من وجود هذا الملف
import 'presentation/home/supplier_home_screen.dart'; // تأكد من وجود هذا الملف
import 'presentation/splash_screen.dart';
import 'presentation/auth/pending_approval_screen.dart';
import 'presentation/auth/verify_email_screen.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL'] ?? '',
    anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
  );
  await initializeDateFormatting('ar');
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => CartProvider()), // تأكد من وجود هذا البروفايدر
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // --- تعريف الثيم (ThemeData) ---
    final ThemeData myAppTheme = ThemeData(
        fontFamily: 'Tajawal',
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00579B), primary: const Color(0xFF00579B),
          secondary: const Color(0xFF00A9E0), surface: Colors.white,
          background: Colors.grey[100]!, error: Colors.redAccent[700]!,
          onPrimary: Colors.white, onSecondary: Colors.white, onSurface: Colors.black87,
          onBackground: Colors.black87, onError: Colors.white, brightness: Brightness.light,
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(fontSize: 32.0, fontWeight: FontWeight.bold, color: Color(0xFF00579B), fontFamily: 'Tajawal'),
          titleLarge: TextStyle(fontSize: 22.0, fontWeight: FontWeight.w600, fontFamily: 'Tajawal'),
          headlineSmall: TextStyle(fontSize: 24.0, fontWeight: FontWeight.w600, fontFamily: 'Tajawal'),
          titleMedium: TextStyle(fontSize: 16.0, fontWeight: FontWeight.w500, fontFamily: 'Tajawal'),
          bodyLarge: TextStyle(fontSize: 16.0, fontFamily: 'Tajawal'),
          bodyMedium: TextStyle(fontSize: 14.0, fontFamily: 'Tajawal'),
          bodySmall: TextStyle(fontSize: 12.0, fontFamily: 'Tajawal'),
          labelLarge: TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold, fontFamily: 'Tajawal'),
          labelMedium: TextStyle(fontSize: 14.0, fontWeight: FontWeight.w500, fontFamily: 'Tajawal'),
          titleSmall: TextStyle(fontSize: 14.0, fontWeight: FontWeight.w500, fontFamily: 'Tajawal'),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00579B), foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Tajawal'),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF00579B),
            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, fontFamily: 'Tajawal'),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0), borderSide: BorderSide(color: Colors.grey[400]!)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0), borderSide: BorderSide(color: Colors.grey[400]!)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0), borderSide: const BorderSide(color: Color(0xFF00579B), width: 1.5)),
            labelStyle: TextStyle(color: Colors.grey[700], fontFamily: 'Tajawal'),
            hintStyle: TextStyle(color: Colors.grey[500], fontFamily: 'Tajawal'),
            filled: true, fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
            errorStyle: TextStyle(color: Colors.redAccent[700]!)
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF00579B), foregroundColor: Colors.white,
          elevation: 1, centerTitle: true,
          titleTextStyle: TextStyle(fontSize: 20.0, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Tajawal'),
        ),
        cardTheme: CardTheme(
          elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
          margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 10.0), color: Colors.white,
        ),
        scaffoldBackgroundColor: Colors.grey[100],
        progressIndicatorTheme: const ProgressIndicatorThemeData( color: Color(0xFF00579B)),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        )
    );
    // --- نهاية الثيم ---

    return MaterialApp(
      title: 'إدارة الحسابات',
      debugShowCheckedModeBanner: false,
      theme: myAppTheme,
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      initialRoute: '/initial',
      routes: {
        '/initial': (context) => const InitialScreen(),
        '/login': (context) => const LoginScreen(),
        '/signup': (context) => const SignupScreen(),
        '/customer_home': (context) => const CustomerHomeScreen(),
        '/retailer_home': (context) => const RetailerHomeScreen(),
        '/supplier_home': (context) => const SupplierHomeScreen(),
        '/pending_approval': (context) => const PendingApprovalScreen(),
        '/verify_email': (context) => const VerifyEmailScreen(),
        // '/reset_password': (context) => const ResetPasswordScreen(),
      },
    );
  }
}

// --- ويدجت شاشة التحقق الأولية ---
class InitialScreen extends StatelessWidget {
  const InitialScreen({Key? key}) : super(key: key);

  Future<bool> _checkOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('hasSeenOnboarding') ?? false;
    } catch (e) {
      print("Error checking onboarding status: $e");
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    // **** طباعة للتشخيص ****
    print(">>>> InitialScreen: Build method called. Auth Initialized: ${auth.isInitialized}");

    if (!auth.isInitialized) {
      // **** طباعة للتشخيص ****
      print(">>>> InitialScreen: Auth not initialized, showing Consumer for Splash/OnboardingCheck.");
      return Consumer<AuthProvider>(
          builder: (context, authConsumer, _) {
            // **** طباعة للتشخيص ****
            print(">>>> InitialScreen Consumer (Pre-Init): isLoading=${authConsumer.isLoading}, isInitialized=${authConsumer.isInitialized}");
            return authConsumer.isInitialized
                ? _buildOnboardingCheck(context)
                : const SplashScreen(message: "جاري تهيئة التطبيق...");
          }
      );
    }
    // **** طباعة للتشخيص ****
    print(">>>> InitialScreen: Auth initialized, building OnboardingCheck.");
    return _buildOnboardingCheck(context);
  }

  Widget _buildOnboardingCheck(BuildContext context) {
    // **** طباعة للتشخيص ****
    print(">>>> InitialScreen: _buildOnboardingCheck called.");
    return FutureBuilder<bool>(
      future: _checkOnboarding(),
      builder: (context, onboardingSnapshot) {
        if (onboardingSnapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreen(message: "جاري التحقق من الإعدادات...");
        }

        if (onboardingSnapshot.data == false) {
          return const OnboardingScreen();
        }

        return Consumer<AuthProvider>(
          builder: (context, auth, _) {
            // **** طباعة للتشخيص ****
            print(">>>> InitialScreen Consumer (Post-Onboarding): isLoading=${auth.isLoading}, isLoggedIn=${auth.isLoggedIn}, isEmailConfirmed=${auth.isEmailConfirmed}, role=${auth.userRole}, approved=${auth.isUserApproved}, profile=${auth.userProfile?.id}, error=${auth.errorMessage}");

            if (auth.isLoading) {
              // **** طباعة للتشخيص ****
              print(">>>> InitialScreen Consumer: Auth isLoading=true, showing Splash.");
              return const SplashScreen(message: "جاري تحميل بيانات المستخدم...");
            }

            // **** طباعة للتشخيص ****
            print(">>>> InitialScreen Consumer: Auth isLoading=false, calling _getAppropriateScreenBasedOnAuth.");
            return _getAppropriateScreenBasedOnAuth(context, auth);
          },
        );
      },
    );
  }

  // دالة مساعدة لتحديد الشاشة بناءً على حالة المصادقة
  Widget _getAppropriateScreenBasedOnAuth(BuildContext context, AuthProvider auth) {
    // **** طباعة للتشخيص ****
    print(">>>> _getAppropriateScreenBasedOnAuth: Evaluating state -> isLoggedIn=${auth.isLoggedIn}, isEmailConfirmed=${auth.isEmailConfirmed}, isUserApproved=${auth.isUserApproved}, profile=${auth.userProfile?.id}, error=${auth.errorMessage}");

    // الحالة 1: مسجل الدخول
    if (auth.isLoggedIn) {
      // 1a: خطأ في تحميل الملف الشخصي (بعد انتهاء التحميل)
      if (auth.errorMessage != null && auth.userProfile == null && !auth.isLoading) {
        // **** طباعة للتشخيص ****
        print(">>>> _getAppropriateScreenBasedOnAuth: Rendering ErrorLoadingScreen.");
        return ErrorLoadingScreen(
          errorMessage: auth.errorMessage!,
          onLogout: () => context.read<AuthProvider>().signOut(),
          onRetry: () => context.read<AuthProvider>().refreshUserProfile(),
        );
      }
      // 1b: البريد الإلكتروني غير مؤكد
      else if (!auth.isEmailConfirmed) {
        // **** طباعة للتشخيص ****
        print(">>>> _getAppropriateScreenBasedOnAuth: Rendering VerifyEmailScreen.");
        return const VerifyEmailScreen();
      }
      // 1c: تم تسجيل الدخول والبريد مؤكد، والملف الشخصي تم تحميله
      else if (auth.userProfile != null) {
        bool isBusiness = ['retailer', 'supplier'].contains(auth.userRole);
        // 1c.1: تاجر/مورد ينتظر الموافقة
        if (isBusiness && !auth.isUserApproved) {
          // **** طباعة للتشخيص ****
          print(">>>> _getAppropriateScreenBasedOnAuth: Rendering PendingApprovalScreen.");
          return const PendingApprovalScreen();
        }
        // 1c.2: عميل (مؤكد) أو تاجر/مورد موافق عليه (ومؤكد)
        else {
          // **** طباعة للتشخيص ****
          print(">>>> _getAppropriateScreenBasedOnAuth: Rendering Home Screen for role: ${auth.userRole}.");
          switch (auth.userRole) {
            case 'client': return const CustomerHomeScreen();
            case 'retailer': return const RetailerHomeScreen();
            case 'supplier': return const SupplierHomeScreen();
            default:
            // **** طباعة للتشخيص ****
              print(">>>> _getAppropriateScreenBasedOnAuth: Unknown role '${auth.userRole}', logging out.");
              WidgetsBinding.instance.addPostFrameCallback((_) {
                context.read<AuthProvider>().signOut();
              });
              return const SplashScreen(message: "دور المستخدم غير صالح، جاري تسجيل الخروج...");
          }
        }
      }
      // 1d: حالة انتقالية/غير متوقعة: مسجل، مؤكد، لكن الملف لم يحمل بعد (أو لا يزال التحميل قيد التشغيل)
      else {
        // If still loading, the Consumer check above handles the SplashScreen.
        // This else handles the unexpected state: logged in, confirmed, but profile is null *and* not loading.
        // **** طباعة للتشخيص ****
        print(">>>> _getAppropriateScreenBasedOnAuth: Logged in, Confirmed, but profile is null and not loading. Logging out.");
        WidgetsBinding.instance.addPostFrameCallback((_) {
          context.read<AuthProvider>().signOut();
        });
        return const SplashScreen(message: "خطأ في حالة الحساب، جاري تسجيل الخروج...");
      }
    }
    // الحالة 2: غير مسجل الدخول
    else {
      // **** طباعة للتشخيص ****
      print(">>>> _getAppropriateScreenBasedOnAuth: Not logged in. Rendering LoginScreen.");
      return const LoginScreen();
    }
  }
}

// --- شاشة الخطأ أثناء تحميل الملف الشخصي ---
class ErrorLoadingScreen extends StatelessWidget {
  final String errorMessage;
  final VoidCallback onLogout;
  final VoidCallback onRetry;

  const ErrorLoadingScreen({
    Key? key,
    required this.errorMessage,
    required this.onLogout,
    required this.onRetry,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(25.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.cloud_off_rounded, color: Theme.of(context).colorScheme.error, size: 70),
                const SizedBox(height: 25),
                Text('حدث خطأ', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
                const Text(
                  "تعذر تحميل بيانات حسابك. يرجى التحقق من اتصالك بالإنترنت أو المحاولة لاحقاً.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.black54, height: 1.4),
                ),
                const SizedBox(height: 10),
                Text(
                  "التفاصيل: $errorMessage",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.error, height: 1.3),
                ),
                const SizedBox(height: 40),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('إعادة المحاولة'),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.primary,
                          side: BorderSide(color: Theme.of(context).colorScheme.primary),
                          padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 12)
                      ),
                    ),
                    const SizedBox(width: 15),
                    ElevatedButton.icon(
                      onPressed: onLogout,
                      icon: const Icon(Icons.logout),
                      label: const Text('تسجيل الخروج'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.error.withOpacity(0.8),
                          foregroundColor: Theme.of(context).colorScheme.onError,
                          padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 12)
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- بقية الملفات (OnboardingScreen, CartProvider, HomeScreen variants, SplashScreen, PendingApprovalScreen, VerifyEmailScreen, LoginScreen) لم تتغير في هذا الرد ---