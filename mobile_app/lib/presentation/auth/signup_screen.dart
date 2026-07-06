// lib/presentation/auth/signup_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart'; // تأكد من المسار الصحيح

// --- Enum ودوال مساعدة للأدوار ---
enum UserRole { supplier, retailer, client }

String userRoleToString(UserRole role) {
  switch (role) {
    case UserRole.supplier: return 'supplier';
    case UserRole.retailer: return 'retailer';
    case UserRole.client: return 'client';
  }
}

String userRoleToDisplayString(UserRole role) {
  switch (role) {
    case UserRole.supplier: return 'مورد';
    case UserRole.retailer: return 'تاجر تجزئة';
    case UserRole.client: return 'عميل';
  }
}
// --- نهاية Enum والمساعدات ---


class SignupScreen extends StatefulWidget {
  const SignupScreen({Key? key}) : super(key: key);

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController firstNameController = TextEditingController();
  final TextEditingController lastNameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();
  final TextEditingController addressController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  UserRole _selectedRole = UserRole.client;
  bool _isSigningUp = false; // حالة تحميل محلية للزر

  @override
  void dispose() {
    firstNameController.dispose(); lastNameController.dispose(); phoneController.dispose();
    emailController.dispose(); passwordController.dispose(); confirmPasswordController.dispose();
    addressController.dispose();
    super.dispose();
  }

  // --- دالة إنشاء الحساب (مُعدّلة لمعالجة فشل التحقق المحلي) ---
  Future<void> _signUp() async {
    if (_isSigningUp) return; // منع الضغط المتكرر
    FocusScope.of(context).unfocus(); // إخفاء لوحة المفاتيح

    // الخطوة 1: التحقق من صحة النموذج المحلي
    // سيؤدي استدعاء validate() إلى إظهار رسائل الخطأ في الحقول غير الصالحة
    final isFormValid = _formKey.currentState?.validate() ?? false;

    if (!isFormValid) {
      // إذا لم يكن النموذج صالحًا:
      // لا حاجة لـ SnackBar إضافي عادةً، حيث تظهر الأخطاء في الحقول.
      print("SignupScreen: Form validation failed.");
      // تأكد من إيقاف أي حالة تحميل قد تكون بدأت عن طريق الخطأ
      if (_isSigningUp) {
        setState(() => _isSigningUp = false);
      }
      // إيقاف التنفيذ هنا
      return;
    }

    // الخطوة 2: إذا كان النموذج صالحًا، ابدأ عملية التسجيل الفعلية
    setState(() => _isSigningUp = true); // بدء التحميل المحلي

    final authProvider = context.read<AuthProvider>();
    // مسح الرسائل السابقة من المحاولة السابقة (إن وجدت)
    authProvider.clearErrorMessage();
    authProvider.clearInfoMessage();

    // الخطوة 3: استدعاء API التسجيل
    print("SignupScreen: Form valid, calling authProvider.signUp...");
    final String? resultMessage = await authProvider.signUp(
      email: emailController.text.trim(),
      password: passwordController.text.trim(),
      firstName: firstNameController.text.trim(),
      lastName: lastNameController.text.trim(),
      phone: phoneController.text.trim(),
      address: addressController.text.trim(),
      role: userRoleToString(_selectedRole),
    );
    print("SignupScreen: authProvider.signUp completed. Result: $resultMessage");

    // الخطوة 4: التعامل مع النتيجة وإيقاف التحميل
    // التحقق من mounted مهم جداً بعد استدعاء async
    if (mounted) {
      setState(() => _isSigningUp = false); // إيقاف التحميل المحلي دائمًا

      if (resultMessage != null) {
        final bool isError = resultMessage.startsWith('خطأ') || resultMessage.contains('مسجل بالفعل');
        final bool isInfoSuccess = !isError;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(resultMessage),
            backgroundColor: isError
                ? Theme.of(context).colorScheme.error
                : Colors.green[700],
            duration: Duration(seconds: isInfoSuccess ? 8 : 5),
            behavior: SnackBarBehavior.floating,
          ),
        );

        if (isInfoSuccess) {
          print("SignupScreen: Signup successful/info. Navigating to LoginScreen.");
          // استخدام Future.delayed لضمان اكتمال بناء الـ SnackBar قبل الانتقال
          Future.delayed(const Duration(milliseconds: 150), () {
            if (mounted) {
              Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
            }
          });
        } else {
          print("SignupScreen: Signup resulted in an error message.");
        }
      } else {
        // حالة غير متوقعة (لا يوجد رسالة)
        print("SignupScreen: Signup resulted in null message (unexpected).");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar( content: const Text('حدث خطأ غير متوقع أثناء التسجيل.'), backgroundColor: Theme.of(context).colorScheme.error, behavior: SnackBarBehavior.floating),
        );
      }
    } else {
      print("SignupScreen: Widget unmounted after signUp call.");
    }
  }


  // --- ودجت اختيار الدور ---
  Widget _buildRoleRadio(UserRole role, ThemeData theme) {
    final bool isSelected = (_selectedRole == role);
    return GestureDetector(
      onTap: _isSigningUp ? null : () => setState(() => _selectedRole = role),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary.withOpacity(0.15) : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(30),
          border: Border.all( color: isSelected ? theme.colorScheme.primary : theme.dividerColor, width: isSelected ? 1.5 : 1.0,),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Radio<UserRole>(
              value: role,
              groupValue: _selectedRole,
              onChanged: _isSigningUp ? null : (UserRole? value) {
                if (value != null) { setState(() => _selectedRole = value); }
              },
              activeColor: theme.colorScheme.primary,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            ),
            Text(userRoleToDisplayString(role), style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface
            )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('إنشاء حساب جديد'),
        leading: Navigator.canPop(context) ? IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: _isSigningUp ? null : () => Navigator.pop(context),
          tooltip: 'رجوع',
        ) : null,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24.0, 16.0, 24.0, 24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('املأ البيانات التالية للانضمام إلينا', textAlign: TextAlign.center, style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.secondary, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 24),

                  TextFormField(controller: firstNameController, enabled: !_isSigningUp, decoration: const InputDecoration(labelText: 'الاسم الأول *', prefixIcon: Icon(Icons.person_outline)), validator: (v) => v==null || v.trim().isEmpty ? 'مطلوب' : null, textInputAction: TextInputAction.next,),
                  const SizedBox(height: 12),
                  TextFormField(controller: lastNameController, enabled: !_isSigningUp, decoration: const InputDecoration(labelText: 'الاسم الأخير *', prefixIcon: Icon(Icons.person_outline)), validator: (v) => v==null || v.trim().isEmpty ? 'مطلوب' : null, textInputAction: TextInputAction.next,),
                  const SizedBox(height: 12),
                  TextFormField(controller: phoneController, enabled: !_isSigningUp, decoration: const InputDecoration(labelText: 'رقم الهاتف *', prefixIcon: Icon(Icons.phone_outlined)), keyboardType: TextInputType.phone, validator: (v) => v==null || v.trim().isEmpty ? 'مطلوب' : null, textInputAction: TextInputAction.next,),
                  const SizedBox(height: 12),
                  TextFormField(controller: emailController, enabled: !_isSigningUp, decoration: const InputDecoration(labelText: 'البريد الإلكتروني *', prefixIcon: Icon(Icons.email_outlined)), keyboardType: TextInputType.emailAddress, textDirection: TextDirection.ltr, textAlign: TextAlign.right, validator: (v) { if (v==null || v.trim().isEmpty) return 'مطلوب'; if (!RegExp(r'^.+@.+\..+$').hasMatch(v)) return 'بريد غير صالح'; return null; }, textInputAction: TextInputAction.next,),
                  const SizedBox(height: 12),
                  TextFormField(controller: passwordController, enabled: !_isSigningUp, decoration: InputDecoration(labelText: 'كلمة المرور *', prefixIcon: const Icon(Icons.lock_outline), suffixIcon: IconButton(icon: Icon(_isPasswordVisible ? Icons.visibility_off : Icons.visibility), onPressed: ()=>setState(()=>_isPasswordVisible=!_isPasswordVisible))), obscureText: !_isPasswordVisible, textDirection: TextDirection.ltr, textAlign: TextAlign.right, validator: (v) { if (v==null || v.isEmpty) return 'مطلوب'; if (v.length < 6) return '6 حروف على الأقل'; return null; }, textInputAction: TextInputAction.next,),
                  const SizedBox(height: 12),
                  TextFormField(controller: confirmPasswordController, enabled: !_isSigningUp, decoration: InputDecoration(labelText: 'تأكيد كلمة المرور *', prefixIcon: const Icon(Icons.lock_outline), suffixIcon: IconButton(icon: Icon(_isConfirmPasswordVisible ? Icons.visibility_off : Icons.visibility), onPressed: ()=>setState(()=>_isConfirmPasswordVisible=!_isConfirmPasswordVisible))), obscureText: !_isConfirmPasswordVisible, textDirection: TextDirection.ltr, textAlign: TextAlign.right, validator: (v) { if (v==null || v.isEmpty) return 'مطلوب'; if (v != passwordController.text) return 'غير متطابقة'; return null; }, textInputAction: TextInputAction.next,),
                  const SizedBox(height: 12),
                  TextFormField(controller: addressController, enabled: !_isSigningUp, decoration: const InputDecoration(labelText: 'العنوان (اختياري)', prefixIcon: Icon(Icons.location_on_outlined)), maxLines: 2, textInputAction: TextInputAction.done, onFieldSubmitted: (_) => _signUp()),
                  const SizedBox(height: 24),

                  Text('اختر نوع الحساب:', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8.0, runSpacing: 8.0, alignment: WrapAlignment.center,
                    children: [
                      _buildRoleRadio(UserRole.client, theme),
                      _buildRoleRadio(UserRole.retailer, theme),
                      _buildRoleRadio(UserRole.supplier, theme),
                    ],
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isSigningUp ? null : _signUp,
                      style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                      child: _isSigningUp
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                          : const Text('إنشاء الحساب', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text( 'لديك حساب بالفعل؟', style: theme.textTheme.bodyMedium),
                      TextButton(
                        onPressed: _isSigningUp ? null : () {
                          if (Navigator.canPop(context)) { Navigator.pop(context); }
                          else { Navigator.pushReplacementNamed(context, '/login'); }
                        },
                        child: const Text('تسجيل الدخول', style: TextStyle(fontWeight: FontWeight.bold)),
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