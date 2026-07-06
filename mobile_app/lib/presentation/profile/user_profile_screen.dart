// lib/presentation/profile/user_profile_screen.dart
import 'dart:io'; // <-- استيراد للملفات

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Provider;
import '../../providers/auth_provider.dart'; // تأكد من المسار الصحيح
import 'package:image_picker/image_picker.dart'; // <-- استيراد image_picker
import 'package:path/path.dart' as p; // <-- استيراد path
class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({Key? key}) : super(key: key);

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false; // للعمليات العامة (حفظ الحقول النصية)
  bool _isUploading = false; // لحالة رفع الصورة

  // Controllers للمعلومات القابلة للتعديل
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();

  // متغيرات لعرض المعلومات غير القابلة للتعديل
  String _email = '';
  String _role = '';
  String? _currentAvatarUrl; // <-- لتخزين رابط الصورة الحالي
  File? _imageFile; // <-- لتخزين الصورة المختارة محلياً
  final ImagePicker _picker = ImagePicker(); // <-- تهيئة ImagePicker



  @override
  void initState() {
    super.initState();
    // تحميل بيانات الملف الشخصي الحالية عند بدء الشاشة
    _loadUserProfile();
  }

  void _loadUserProfile() {
    // استخدام listen: false لأننا فقط نقرأ القيمة الأولية
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final profile = authProvider.userProfile;
    final user = authProvider.currentUser;

    if (profile != null) {
      _firstNameController.text = profile.firstName;
      _lastNameController.text = profile.lastName;
      _phoneController.text = profile.phone ?? '';
      _addressController.text = profile.address ?? '';
      _role = profile.role; // الدور لا يتم تعديله من هنا عادةً
      _currentAvatarUrl = profile.avatarUrl; // <-- تحميل رابط الصورة

    }
    if (user != null) {
      _email = user.email ?? 'لا يوجد بريد إلكتروني';
    }
    // إعادة رسم الواجهة بعد تحميل البيانات
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    // التخلص من الـ Controllers عند إغلاق الشاشة
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  // --- اختيار صورة ---
  Future<void> _pickImage() async {
    if (_isUploading) return; // منع الاختيار أثناء الرفع
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery, // أو ImageSource.camera
        imageQuality: 80, // ضغط الصورة قليلاً
        maxWidth: 800,   // تحديد أبعاد قصوى (اختياري)
      );
      if (pickedFile != null && mounted) {
        setState(() {
          _imageFile = File(pickedFile.path); // عرض الصورة المختارة مؤقتًا
        });
        // --- رفع الصورة مباشرة بعد الاختيار ---
        await _uploadAndSaveAvatar();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في اختيار الصورة: $e')),
        );
      }
    }
  }

  // --- رفع الصورة وتحديث الملف الشخصي ---
  Future<void> _uploadAndSaveAvatar() async {
    if (_imageFile == null) return; // لا يوجد صورة لرفعها
    if (_isUploading) return; // منع الرفع المتعدد

    setState(() => _isUploading = true); // بدء حالة رفع الصورة

    final authProvider = context.read<AuthProvider>();
    final userId = authProvider.currentUser?.id;

    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('خطأ: لم يتم العثور على المستخدم.')),
      );
      setState(() => _isUploading = false);
      return;
    }

    try {
      // 1. تحديد اسم ومسار فريد للصورة في Storage
      final fileExtension = p.extension(_imageFile!.path); // .png, .jpg, etc.
      final fileName = 'avatar$fileExtension'; // اسم ملف ثابت للمستخدم
      final filePath = '$userId/$fileName'; // المسار داخل الـ Bucket

      // 2. رفع الصورة (مع خيار upsert للكتابة فوق القديمة)
      await Supabase.instance.client.storage.from('avatars').upload(
        filePath,
        _imageFile!,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
      );

      // 3. الحصول على الرابط العام للصورة المرفوعة
      //    ملاحظة: يجب أن يكون الرابط ثابتاً لأن اسم الملف ثابت
      //    نستخدم timestamp فقط لتجنب مشاكل التخزين المؤقت للمتصفح/التطبيق (cache busting)
      final imageUrlResponse = Supabase.instance.client.storage
          .from('avatars')
          .getPublicUrl(filePath);
      // إضافة timestamp لمنع التخزين المؤقت (اختياري لكن مفيد)
      final publicUrl = '$imageUrlResponse?t=${DateTime.now().millisecondsSinceEpoch}';


      // 4. تحديث حقل avatar_url في جدول profiles
      await Supabase.instance.client
          .from('profiles')
          .update({'avatar_url': publicUrl}) // <-- تحديث الرابط فقط
          .eq('id', userId);

      // 5. تحديث الحالة في AuthProvider لعكس التغيير فوراً في أماكن أخرى (مثل Drawer)
      await authProvider.refreshUserProfile();

      // 6. تحديث الحالة المحلية وعرض رسالة نجاح
      if (mounted) {
        setState(() {
          _currentAvatarUrl = publicUrl; // تحديث الرابط المعروض
          _imageFile = null; // مسح الصورة المحلية المؤقتة
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم تحديث الصورة بنجاح!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل رفع الصورة أو تحديث الملف: $e')),
        );
      }
      print("Avatar Upload/Save Error: $e");
    } finally {
      // 7. إيقاف حالة الرفع دائماً
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }


  // --- دالة حفظ التعديلات ---
  // --- دالة حفظ التعديلات (الحقول النصية فقط) ---
  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) { return; }
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    final authProvider = context.read<AuthProvider>();
    final userId = authProvider.currentUser?.id;
    if (userId == null) { /* ... التعامل مع الخطأ ... */
      setState(() => _isLoading = false); return;
    }

    try {
      final updates = { /* ... نفس بيانات التحديث النصية ... */
        'first_name': _firstNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'phone': _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        'address': _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
        // لا نحدث avatar_url هنا، يتم تحديثه منفصلاً
      };
      await Supabase.instance.client.from('profiles').update(updates).eq('id', userId);
      await authProvider.refreshUserProfile();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ تم تحديث البيانات بنجاح!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) { /* ... معالجة الأخطاء ... */
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في حفظ البيانات: $e')),
        );
      }
    } finally {
      if (mounted) { setState(() => _isLoading = false); }
    }
  }

  // Helper لترجمة الدور للعربية (من AppDrawer)
  String _getArabicRoleName(String role) {
    switch (role) {
      case 'client': return 'عميل';
      case 'retailer': return 'تاجر تجزئة';
      case 'supplier': return 'مورد';
      default: return 'غير معروف';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('الملف الشخصي'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- عرض الصورة وزر التعديل ---
              Center(
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundColor: theme.colorScheme.surfaceVariant,
                      // عرض الصورة المحلية المؤقتة إذا وجدت، وإلا الصورة الحالية من الرابط
                      backgroundImage: _imageFile != null
                          ? FileImage(_imageFile!) as ImageProvider
                          : (_currentAvatarUrl != null && _currentAvatarUrl!.isNotEmpty
                          ? NetworkImage(_currentAvatarUrl!)
                          : null),
                      child: (_imageFile == null && (_currentAvatarUrl == null || _currentAvatarUrl!.isEmpty))
                          ? Icon(Icons.person, size: 60, color: theme.colorScheme.onSurfaceVariant)
                          : null,
                    ),
                    // زر تعديل الصورة مع مؤشر تحميل
                    Material(
                      color: theme.colorScheme.primary,
                      shape: const CircleBorder(),
                      elevation: 2,
                      child: InkWell(
                        onTap: _isUploading ? null : _pickImage, // تعطيل أثناء الرفع
                        customBorder: const CircleBorder(),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: _isUploading
                              ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                              : const Icon(Icons.camera_alt, size: 20, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // --- حقول قابلة للتعديل ---
              // ... (TextFormFields للأسماء والهاتف والعنوان كما هي) ...
              TextFormField(
                controller: _firstNameController,
                decoration: const InputDecoration(
                  labelText: 'الاسم الأول',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'الاسم الأول مطلوب';
                  }
                  return null;
                },
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _lastNameController,
                decoration: const InputDecoration(
                  labelText: 'الاسم الأخير',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'الاسم الأخير مطلوب';
                  }
                  return null;
                },
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'رقم الهاتف (اختياري)',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                // يمكنك إضافة validator لرقم الهاتف إذا أردت
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'العنوان (اختياري)',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
                maxLines: 2, // السماح بأكثر من سطر للعنوان
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              // --- حقول غير قابلة للتعديل ---
              ListTile(
                leading: const Icon(Icons.email_outlined, color: Colors.grey),
                title: const Text('البريد الإلكتروني', style: TextStyle(color: Colors.grey)),
                subtitle: Text(_email, style: theme.textTheme.bodyLarge),
              ),
              ListTile(
                leading: const Icon(Icons.badge_outlined, color: Colors.grey),
                title: const Text('الدور', style: TextStyle(color: Colors.grey)),
                subtitle: Text(_getArabicRoleName(_role), style: theme.textTheme.bodyLarge),
              ),
              const SizedBox(height: 32),

              // --- زر حفظ البيانات النصية ---
              ElevatedButton.icon(
                onPressed: _isLoading || _isUploading ? null : _saveProfile, // تعطيل أثناء أي تحميل
                icon: _isLoading
                    ? Container( /* ... مؤشر التحميل ... */
                  width: 20,
                  height: 20,
                  padding: const EdgeInsets.all(2.0),
                  child: const CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                )
                    : const Icon(Icons.save_outlined),
                label: Text(_isLoading ? 'جاري الحفظ...' : 'حفظ البيانات'), // تغيير النص
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14)
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}