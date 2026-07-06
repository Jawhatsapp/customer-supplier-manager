// lib/presentation/management/store_settings_screen.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Provider;

// --- استيرادات جديدة ومعدلة ---
import '../../data/models/store_model.dart';
import '../../data/repositories/store_repository.dart';
import '../../models/store_payment_method_model.dart';
import '../../providers/auth_provider.dart';
import '../currencies/currency_management_screen.dart';
import 'add_edit_payment_method_dialog.dart';

class StoreSettingsScreen extends StatefulWidget {
  const StoreSettingsScreen({Key? key}) : super(key: key);

  @override
  State<StoreSettingsScreen> createState() => _StoreSettingsScreenState();
}

class _StoreSettingsScreenState extends State<StoreSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  // --- المستودعات والبروفايدرز ---
  late final StoreRepository _storeRepository;
  late final AuthProvider _authProvider;

  // Controllers
  final _storeNameController = TextEditingController();
  final _addressController = TextEditingController();

  // Loading States
  bool _isLoadingData = true;
  bool _isSaving = false;
  String? _fetchStoreError;

  // Store Data
  StoreModel? _store;

  // Payment Methods State
  Future<List<StorePaymentMethod>>? _paymentMethodsFuture;

  // Image State
  File? _logoFile;
  File? _bannerFile;

  @override
  void initState() {
    super.initState();
    _storeRepository = StoreRepository();
    _authProvider = Provider.of<AuthProvider>(context, listen: false);

    _loadInitialData();
  }

  @override
  void dispose() {
    _storeNameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  // --- دوال جلب البيانات ---
  Future<void> _loadInitialData() async {
    if (!_authProvider.isLoggedIn || _authProvider.storeId == null) {
      if (mounted) {
        setState(() {
          _isLoadingData = false;
          _fetchStoreError = "لا يمكن الوصول لبيانات المتجر. يرجى تسجيل الدخول كمالك متجر.";
        });
      }
      return;
    }

    if (mounted) setState(() { _isLoadingData = true; _fetchStoreError = null; });

    try {
      final storeData = await _storeRepository.getStoreById(_authProvider.storeId!);
      if (!mounted) return;

      setState(() {
        _store = storeData;
        _storeNameController.text = storeData.storeName;
        _addressController.text = storeData.address ?? '';
        _paymentMethodsFuture = _fetchStorePaymentMethods();
      });

    } catch (e) {
      if (mounted) setState(() { _fetchStoreError = e.toString(); });
    } finally {
      if (mounted) setState(() => _isLoadingData = false);
    }
  }

  Future<List<StorePaymentMethod>> _fetchStorePaymentMethods() async {
    if (_authProvider.currentUser?.id == null || !mounted) return [];
    try {
      final response = await Supabase.instance.client
          .from('store_payment_methods')
          .select()
          .eq('owner_id', _authProvider.currentUser!.id)
          .order('created_at');
      return (response as List).map((data) => StorePaymentMethod.fromJson(data)).toList();
    } catch (e) {
      print("Error fetching payment methods: $e");
      if (mounted) _showMsg("خطأ: $e", isError: true);
      return [];
    }
  }

  // --- دوال العمليات ---
  Future<void> _pickImage(ImageSource source, {required bool isLogo}) async {
    if (_isSaving) return;
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: isLogo ? 85 : 75,
        maxWidth: isLogo ? 600 : 1200,
      );
      if (pickedFile != null && mounted) {
        setState(() {
          if (isLogo) { _logoFile = File(pickedFile.path); }
          else { _bannerFile = File(pickedFile.path); }
        });
      }
    } catch (e) {
      if(mounted) _showMsg("خطأ اختيار الصورة: $e", isError: true);
    }
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate() || _store == null) return;
    if (_isSaving) return;

    setState(() => _isSaving = true);

    String? newLogoUrl = _store!.logoUrl;
    String? newBannerUrl = _store!.bannerUrl;

    try {
      if (_logoFile != null) {
        newLogoUrl = await _storeRepository.uploadStoreImage(
            file: _logoFile!,
            storeId: _store!.id,
            imageType: 'logo',
            bucketName: 'store-logos'
        );
      }
      if (_bannerFile != null) {
        newBannerUrl = await _storeRepository.uploadStoreImage(
            file: _bannerFile!,
            storeId: _store!.id,
            imageType: 'banner',
            bucketName: 'store-logos'
        );
      }

      final Map<String, dynamic> updates = {
        'store_name': _storeNameController.text.trim(),
        'address': _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
        'logo_url': newLogoUrl,
        'banner_url': newBannerUrl,
      };

      await _storeRepository.updateStoreDetails(storeId: _store!.id, updates: updates);

      if (!mounted) return;

      setState(() {
        _store = StoreModel(
          id: _store!.id,
          ownerId: _store!.ownerId,
          storeType: _store!.storeType,
          createdAt: _store!.createdAt,
          storeName: updates['store_name'],
          address: updates['address'],
          logoUrl: newLogoUrl,
          bannerUrl: newBannerUrl,
        );
        _logoFile = null;
        _bannerFile = null;
      });

      _showMsg('تم حفظ بيانات المتجر بنجاح', success: true);

    } catch (e) {
      if (mounted) _showMsg(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showMsg(String msg, {bool isError = false, bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Theme.of(context).colorScheme.error : (success ? Colors.green : null),
    ));
  }

  void _showAddEditPaymentMethodDialog({StorePaymentMethod? method}) {
    if (_store == null || _authProvider.currentUser == null) {
      _showMsg("خطأ: بيانات المتجر أو المالك غير مكتملة.", isError: true);
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AddEditPaymentMethodDialog(
          storeId: _store!.id,
          storeType: _store!.storeType,
          ownerId: _authProvider.currentUser!.id,
          existingMethod: method,
          onSaved: () {
            setState(() { _paymentMethodsFuture = _fetchStorePaymentMethods(); });
          },
        );
      },
    );
  }

  Future<void> _togglePaymentMethodStatus(StorePaymentMethod method) async {
    if (!mounted) return;
    final newStatus = !method.isActive;
    try {
      await Supabase.instance.client.from('store_payment_methods').update({'is_active': newStatus}).eq('id', method.id);
      if (!mounted) return;
      setState(() { _paymentMethodsFuture = _fetchStorePaymentMethods(); });
      _showMsg(newStatus ? 'تم تفعيل طريقة الدفع' : 'تم إلغاء تفعيل طريقة الدفع');
    } catch (e) {
      print("Error toggling status: $e");
      if (mounted) _showMsg("خطأ: $e", isError: true);
    }
  }

  Future<void> _deletePaymentMethod(StorePaymentMethod method) async {
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف "${method.institutionName} - ${method.accountNumber}"؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('نعم، حذف', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await Supabase.instance.client.from('store_payment_methods').delete().eq('id', method.id);
      if (!mounted) return;
      _showMsg('تم حذف طريقة الدفع بنجاح.');
      setState(() { _paymentMethodsFuture = _fetchStorePaymentMethods(); });
    } catch (e) {
      print("Error deleting method: $e");
      if (mounted) _showMsg("خطأ: $e", isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إعدادات المتجر')),
      body: _isLoadingData
          ? const Center(child: CircularProgressIndicator())
          : _fetchStoreError != null
          ? _buildErrorWidget(_fetchStoreError!)
          : _store == null
          ? _buildErrorWidget('لم يتم العثور على بيانات المتجر.')
          : _buildSettingsForm(),
    );
  }

  Widget _buildErrorWidget(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadInitialData, child: const Text('إعادة المحاولة'))
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsForm() {
    final theme = Theme.of(context);
    final currentLogoUrl = _store?.logoUrl;
    final currentBannerUrl = _store?.bannerUrl;

    return RefreshIndicator(
      onRefresh: _loadInitialData,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // --- قسم الصور ---
          _buildSettingsSectionHeader(context, "صور المتجر"),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    Text("الشعار (Logo)", style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: theme.colorScheme.surfaceVariant,
                          backgroundImage: _logoFile != null ? FileImage(_logoFile!) as ImageProvider : (currentLogoUrl != null && currentLogoUrl.isNotEmpty) ? NetworkImage(currentLogoUrl) : null,
                          child: (_logoFile == null && (currentLogoUrl == null || currentLogoUrl.isEmpty)) ? Icon(Icons.store, size: 40, color: theme.colorScheme.onSurfaceVariant) : null,
                        ),
                        Positioned(right: -5, bottom: -5, child: _buildEditImageButton(isLogo: true)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    Text("البانر (Banner)", style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Stack(
                        fit: StackFit.expand,
                        alignment: Alignment.bottomRight,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                              image: DecorationImage(
                                fit: BoxFit.cover,
                                image: _bannerFile != null ? FileImage(_bannerFile!) as ImageProvider : (currentBannerUrl != null && currentBannerUrl.isNotEmpty) ? NetworkImage(currentBannerUrl) : const AssetImage('assets/logo.png'), // Add a placeholder asset
                              ),
                            ),
                            child: (_bannerFile == null && (currentBannerUrl == null || currentBannerUrl.isEmpty)) ? Icon(Icons.image_outlined, size: 40, color: theme.colorScheme.onSurfaceVariant) : null,
                          ),
                          Positioned(right: 4, bottom: 4, child: _buildEditImageButton(isLogo: false)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // --- قسم المعلومات الأساسية ---
          const Divider(height: 30, thickness: 1),
          _buildSettingsSectionHeader(context, "المعلومات الأساسية"),
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                TextFormField(enabled: !_isSaving, controller: _storeNameController, decoration: const InputDecoration(labelText: 'اسم المتجر', prefixIcon: Icon(Icons.storefront_outlined)), validator: (v) => (v == null || v.trim().isEmpty) ? 'اسم المتجر مطلوب' : null),
                const SizedBox(height: 16),
                TextFormField(enabled: !_isSaving, controller: _addressController, decoration: const InputDecoration(labelText: 'العنوان', prefixIcon: Icon(Icons.location_on_outlined)), maxLines: 2),
                const SizedBox(height: 24),
              ],
            ),
          ),
          Center(
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveChanges,
              icon: _isSaving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_outlined),
              label: Text(_isSaving ? 'جاري الحفظ...' : 'حفظ كل التعديلات'),
              style: ElevatedButton.styleFrom(minimumSize: const Size(200, 45), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
            ),
          ),

          const Divider(height: 40, thickness: 1),

          // --- قسم إدارة العملات ---
          _buildSettingsSectionHeader(context, "إدارة العملات"),
          ListTile(
            subtitle: const Text('إضافة أو تعديل العملات المدعومة وأسعار الصرف.'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 18),
            onTap: _isSaving ? null : () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => CurrencyManagementScreen(storeId: _store!.id)),
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 30, thickness: 1),

          // --- قسم إدارة طرق الدفع ---
          _buildSettingsSectionHeader(context, "طرق الدفع الخاصة بالمتجر"),
          const Text("إدارة الحسابات التي يمكن للعملاء التحويل إليها.", style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 16),
          FutureBuilder<List<StorePaymentMethod>>(
            future: _paymentMethodsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator()));
              }
              if (snapshot.hasError) {
                return Center(child: Text('خطأ: ${snapshot.error}', style: TextStyle(color: theme.colorScheme.error)));
              }
              final methods = snapshot.data ?? [];
              if (methods.isEmpty) {
                return const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 16.0), child: Text('لم تقم بإضافة أي طرق دفع بعد.')));
              }
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: methods.length,
                itemBuilder: (ctx, index) {
                  final method = methods[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    elevation: 1.5,
                    child: ListTile(
                      title: Text(method.institutionName, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text("اسم الحساب: ${method.accountName}"),
                        Text("الرقم: ${method.accountNumber}"),
                        if (method.details != null && method.details!.isNotEmpty) Text("تفاصيل: ${method.details!}"),
                      ]),
                      trailing: Wrap(
                        spacing: 0,
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          Switch(value: method.isActive, onChanged: _isSaving ? null : (value) => _togglePaymentMethodStatus(method), activeColor: theme.colorScheme.primary, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
                          IconButton(icon: const Icon(Icons.edit_outlined, size: 20), tooltip: 'تعديل', onPressed: _isSaving ? null : () => _showAddEditPaymentMethodDialog(method: method), padding: const EdgeInsets.symmetric(horizontal: 6), constraints: const BoxConstraints()),
                          IconButton(icon: Icon(Icons.delete_outline, color: theme.colorScheme.error, size: 20), tooltip: 'حذف', onPressed: _isSaving ? null : () => _deletePaymentMethod(method), padding: const EdgeInsets.symmetric(horizontal: 6), constraints: const BoxConstraints()),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 16),
          Center(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add_card),
              label: const Text('إضافة طريقة دفع جديدة'),
              onPressed: _isSaving ? null : () => _showAddEditPaymentMethodDialog(),
              style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.secondary, minimumSize: const Size(200, 40), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildEditImageButton({required bool isLogo}) {
    return Material(
      color: Theme.of(context).colorScheme.primary,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        onTap: _isSaving ? null : () => _pickImage(ImageSource.gallery, isLogo: isLogo),
        customBorder: const CircleBorder(),
        child: const Padding(
          padding: EdgeInsets.all(6.0),
          child: Icon(Icons.edit, size: 18, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildSettingsSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}