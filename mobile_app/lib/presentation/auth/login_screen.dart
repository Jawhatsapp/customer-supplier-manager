// lib/presentation/auth/login_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _loginFormKey = GlobalKey<FormState>();
  final TextEditingController emailLoginController = TextEditingController();
  final TextEditingController passwordLoginController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isLoggingIn = false; // حالة تحميل محلية للزر

  @override
  void dispose() {
    emailLoginController.dispose();
    passwordLoginController.dispose();
    super.dispose();
  }

  // --- دالة تسجيل الدخول ---
  Future<void> _login() async {
    if (_isLoggingIn) return;
    FocusScope.of(context).unfocus();
    if (!_loginFormKey.currentState!.validate()) return;

    setState(() => _isLoggingIn = true);

    final authProvider = context.read<AuthProvider>();
    // مسح أي خطأ سابق قبل محاولة تسجيل الدخول
    authProvider.clearErrorMessage();
    authProvider.clearInfoMessage();

    final bool success = await authProvider.signIn(
      emailLoginController.text.trim(),
      passwordLoginController.text.trim(),
    );

    // إيقاف التحميل المحلي للزر بعد اكتمال العملية
    // التحقق من mounted مهم جداً
    if (mounted) {
      setState(() => _isLoggingIn = false);

      // إذا فشلت المصادقة (بسبب خطأ مثل كلمة المرور أو عدم تأكيد البريد)
      if (!success) {
        // قراءة رسالة الخطأ المحدثة من المزود
        final errorMsg = context.read<AuthProvider>().errorMessage;

        if (errorMsg != null) {
          // استخدام WidgetsBinding لضمان عرض SnackBar بعد اكتمال البناء
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(errorMsg), // عرض الخطأ المحدد (مثل "يرجى تأكيد بريدك")
                  backgroundColor: Theme.of(context).colorScheme.error,
                  duration: const Duration(seconds: 5), // مدة أطول قليلاً
                  behavior: SnackBarBehavior.floating,
                  action: errorMsg.contains('تأكيد بريدك') // إضافة زر إعادة الإرسال إذا كان الخطأ متعلقًا بالتأكيد
                      ? SnackBarAction(
                    label: 'إعادة الإرسال',
                    textColor: Colors.white,
                    onPressed: () => _resendConfirmationEmail(context, emailLoginController.text.trim()),
                  )
                      : null,
                ),
              );
              // لا تمسح الخطأ هنا، اتركه في المزود حتى المحاولة التالية أو الانتقال
            }
          });
        }
      }
      // لا يوجد else هنا. إذا كان success == true، فإن onAuthStateChange في AuthProvider
      // سيتولى تحديث الحالة، و InitialScreen سيتولى التوجيه.
    }
  }


  // --- دالة إعادة إرسال بريد التأكيد ---
  Future<void> _resendConfirmationEmail(BuildContext context, String email) async {
    if (email.isEmpty) return;
    print("LoginScreen: Resending confirmation email to $email");
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('جاري إرسال بريد التأكيد...'), duration: Duration(seconds: 2), behavior: SnackBarBehavior.floating)
    );
    try {
      await Supabase.instance.client.auth.resend(
          type: OtpType.signup, // أو OtpType.email_change إذا كان مناسباً
          email: email
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال بريد التأكيد مجدداً. تحقق من بريدك.'), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating),
        );
      }
    } on AuthException catch (e) {
      print("LoginScreen: Error resending confirmation - ${e.message}");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في إعادة الإرسال: ${e.message}'), backgroundColor: Theme.of(context).colorScheme.error, behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      print("LoginScreen: Generic error resending confirmation - $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('حدث خطأ غير متوقع أثناء إعادة الإرسال.'), backgroundColor: Theme.of(context).colorScheme.error, behavior: SnackBarBehavior.floating),
        );
      }
    }
  }


  // --- دالة عرض حوار نسيت كلمة المرور (تبقى كما هي) ---
  void _showForgotPasswordDialog(BuildContext context) {
    final TextEditingController resetEmailController = TextEditingController();
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    bool isDialogSending = false; // حالة تحميل خاصة بالحوار

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              title: const Text('إعادة تعيين كلمة المرور'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('أدخل بريدك الإلكتروني المسجل وسيتم إرسال رابط لإعادة التعيين.'),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: resetEmailController,
                      enabled: !isDialogSending,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'البريد الإلكتروني', prefixIcon: Icon(Icons.email_outlined)),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return 'البريد مطلوب';
                        if (!RegExp(r'^.+@.+\..+$').hasMatch(value.trim())) return 'بريد غير صالح';
                        return null;
                      },
                      textDirection: TextDirection.ltr, // ضمان اتجاه النص لليسار لخانة الايميل
                      textAlign: TextAlign.right, // محاذاة النص لليمين داخل الخانة
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: isDialogSending ? null : () => Navigator.pop(ctx),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  onPressed: isDialogSending ? null : () async {
                    if (formKey.currentState!.validate()) {
                      setDialogState(() => isDialogSending = true);
                      String? dialogErrorMessage;
                      try {
                        print("Requesting password reset for ${resetEmailController.text.trim()}");
                        await Supabase.instance.client.auth.resetPasswordForEmail(
                          resetEmailController.text.trim(),
                          // redirectTo: 'YOUR_APP_REDIRECT_URL', // Consider adding deep linking later
                        );
                        print("Password reset email request sent.");
                      } on AuthException catch (e) {
                        dialogErrorMessage = e.message;
                        print("AuthException on reset: $e");
                      } catch (e) {
                        dialogErrorMessage = 'حدث خطأ غير متوقع.';
                        print("Generic Exception on reset: $e");
                      }

                      if (!ctx.mounted) return;

                      setDialogState(() => isDialogSending = false);
                      Navigator.pop(ctx);

                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          if (dialogErrorMessage == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('تم إرسال رابط إعادة التعيين إلى بريدك.'),
                                backgroundColor: Colors.green,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('خطأ: $dialogErrorMessage'),
                                backgroundColor: Theme.of(context).colorScheme.error,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        }
                      });
                    }
                  },
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20)),
                  child: isDialogSending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('إرسال'),
                ),
              ],
            );
          },
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _loginFormKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon( Icons.storefront_outlined, size: 85, color: theme.colorScheme.primary),
                  const SizedBox(height: 24),
                  Text('مرحباً بعودتك! ', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('سجّل الدخول للمتابعة', textAlign: TextAlign.center, style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 35),

                  TextFormField(
                    controller: emailLoginController,
                    enabled: !_isLoggingIn,
                    decoration: const InputDecoration(labelText: 'البريد الإلكتروني', prefixIcon: Icon(Icons.email_outlined)),
                    keyboardType: TextInputType.emailAddress,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.right,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return 'يرجى إدخال البريد الإلكتروني';
                      if (!RegExp(r'^.+@.+\..+$').hasMatch(value.trim())) return 'بريد غير صالح';
                      return null;
                    },
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: passwordLoginController,
                    enabled: !_isLoggingIn,
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_isPasswordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        onPressed: _isLoggingIn ? null : () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                      ),
                    ),
                    obscureText: !_isPasswordVisible,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.right,
                    validator: (value) => (value == null || value.isEmpty) ? 'يرجى إدخال كلمة المرور' : null,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) { if (!_isLoggingIn) { _login(); } },
                  ),
                  const SizedBox(height: 25),

                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoggingIn ? null : _login,
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: _isLoggingIn
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                          : const Text('تسجيل الدخول', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: _isLoggingIn ? null : () => _showForgotPasswordDialog(context),
                        child: const Text('نسيت كلمة المرور؟'),
                      ),
                      TextButton(
                        onPressed: _isLoggingIn ? null : () => Navigator.pushNamed(context, '/signup'),
                        child: const Text('إنشاء حساب جديد', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
