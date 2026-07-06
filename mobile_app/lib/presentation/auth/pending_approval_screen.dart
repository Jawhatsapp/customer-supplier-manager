// lib/presentation/auth/pending_approval_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../splash_screen.dart'; // استيراد شاشة الانتظار

class PendingApprovalScreen extends StatefulWidget {
  const PendingApprovalScreen({Key? key}) : super(key: key);

  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen> {

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        print("PendingApprovalScreen - Rebuilding. isLoggedIn: ${authProvider.isLoggedIn}, isUserApproved: ${authProvider.isUserApproved}");

        // --- الانتقال التلقائي عند الموافقة ---
        // نتحقق أولاً إذا كان المستخدم مسجلاً وموافق عليه (والبريد مؤكد ضمناً لأنه وصل لهذه الشاشة)
        if (authProvider.isLoggedIn && authProvider.isUserApproved) {
          print("PendingApprovalScreen: User approved! Scheduling navigation back to /initial.");
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // Check state again and ensure widget is still mounted and is the current route
            if (mounted && ModalRoute.of(context)?.isCurrent == true) {
              final currentAuth = context.read<AuthProvider>();
              if(currentAuth.isLoggedIn && currentAuth.isUserApproved) {
                print("PendingApprovalScreen: Navigating now to /initial for re-evaluation.");
                Navigator.pushNamedAndRemoveUntil(context, '/initial', (route) => false);
              } else {
                print("PendingApprovalScreen: Navigation skipped (state changed again before nav).");
              }
            } else {
              print("PendingApprovalScreen: Navigation skipped (not mounted or not current screen).");
            }
          });
          return const SplashScreen(message: "تمت الموافقة! جاري التوجيه...");
        }
        // -------------------------------------

        // عرض المحتوى العادي إذا لم تتم الموافقة بعد
        return Scaffold(
          appBar: AppBar(
            title: const Text("انتظار الموافقة"),
            automaticallyImplyLeading: false,
            actions: [
              // زر تسجيل الخروج يظهر فقط إذا كان المستخدم مسجلاً
              if (authProvider.isLoggedIn)
                IconButton(
                    icon: const Icon(Icons.logout),
                    tooltip: 'تسجيل الخروج',
                    onPressed: () async {
                      await context.read<AuthProvider>().signOut();
                    }
                )
            ],
          ),
          body: child, // Use the pre-built child
        );
      },
      // المحتوى الثابت للشاشة
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(25.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.hourglass_empty_rounded, size: 70, color: Colors.orange.shade800),
              const SizedBox(height: 25),
              // Consumer just for the role text
              Consumer<AuthProvider>(
                builder: (context, auth, _) => Text(
                  auth.userRole != null
                      ? 'تم استلام طلب تسجيلك كـ"${auth.getArabicRoleName(auth.userRole)}".'
                      : 'جاري تحميل بيانات الدور...',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 15),
              const Text(
                'حسابك قيد المراجعة حاليًا من قبل الإدارة.\nسيتم إعلامك وتوجيهك تلقائيًا فور الموافقة.\n\n(تأكد من أنك قمت بتأكيد بريدك الإلكتروني أيضاً إذا طُلب منك ذلك).',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.black54, height: 1.5),
              ),
              const SizedBox(height: 40),
              // Manual refresh button
              TextButton.icon(
                icon: const Icon(Icons.refresh, size: 20),
                label: const Text("التحقق من حالة الموافقة"),
                onPressed: () => context.read<AuthProvider>().refreshUserProfile(),
              )
            ],
          ),
        ),
      ),
    );
  }
}