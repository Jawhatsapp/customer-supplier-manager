// lib/presentation/auth/verify_email_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/auth_provider.dart'; // Adjust path as needed

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({Key? key}) : super(key: key);

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _isSending = false;

  Future<void> _resendConfirmationEmail() async {
    if (_isSending) return;
    final authProvider = context.read<AuthProvider>();
    final email = authProvider.currentUser?.email;

    if (email == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('لم يتم العثور على البريد الإلكتروني للمستخدم.'), backgroundColor: Theme.of(context).colorScheme.error, behavior: SnackBarBehavior.floating),
      );
      return;
    }

    setState(() => _isSending = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري إعادة إرسال بريد التأكيد...'), duration: Duration(seconds: 2), behavior: SnackBarBehavior.floating),
    );

    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: email,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال بريد التأكيد مجدداً. تحقق من بريدك (بما في ذلك البريد المزعج).'), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating, duration: Duration(seconds: 5)),
        );
      }
    } on AuthException catch (e) {
      print("VerifyEmailScreen: Error resending confirmation - ${e.message}");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في إعادة الإرسال: ${e.message}'), backgroundColor: Theme.of(context).colorScheme.error, behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      print("VerifyEmailScreen: Generic error resending confirmation - $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('حدث خطأ غير متوقع أثناء إعادة الإرسال.'), backgroundColor: Theme.of(context).colorScheme.error, behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use Consumer to get email safely, even if provider updates
    final userEmail = context.select((AuthProvider auth) => auth.currentUser?.email);

    return Scaffold(
      appBar: AppBar(
        title: const Text("تأكيد البريد الإلكتروني"),
        automaticallyImplyLeading: false, // No back button
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'تسجيل الخروج',
            onPressed: () async {
              await context.read<AuthProvider>().signOut();
              // Navigator will be handled by InitialScreen listener
            },
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(25.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.mark_email_unread_outlined, size: 80, color: Theme.of(context).colorScheme.secondary),
              const SizedBox(height: 30),
              Text(
                'تحقق من بريدك الإلكتروني!',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 15),
              Text(
                'لقد أرسلنا رابط تأكيد إلى:\n${userEmail ?? 'بريدك الإلكتروني المسجل'}\n\nيرجى الضغط على الرابط لتفعيل حسابك وتسجيل الدخول مرة أخرى.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Colors.black54, height: 1.5),
              ),
              const SizedBox(height: 40),
              ElevatedButton.icon(
                onPressed: _isSending ? null : _resendConfirmationEmail,
                icon: _isSending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_outlined, size: 20),
                label: const Text("إعادة إرسال رابط التأكيد"),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                  // backgroundColor: Theme.of(context).colorScheme.secondary, // Optional secondary color
                ),
              ),
              const SizedBox(height: 15),
              TextButton(
                onPressed: () async {
                  await context.read<AuthProvider>().signOut();
                },
                child: const Text("تسجيل الخروج الآن"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}