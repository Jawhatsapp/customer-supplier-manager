// lib/presentation/management/add_edit_payment_method_dialog.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/store_payment_method_model.dart'; // استيراد النموذج

class AddEditPaymentMethodDialog extends StatefulWidget {
  final int storeId;
  final String storeType;
  final String ownerId;
  final StorePaymentMethod? existingMethod; // إذا كان null، يعني إضافة جديدة
  final VoidCallback onSaved; // Callback للتحديث بعد الحفظ

  const AddEditPaymentMethodDialog({
    Key? key,
    required this.storeId,
    required this.storeType,
    required this.ownerId,
    this.existingMethod,
    required this.onSaved,
  }) : super(key: key);

  @override
  State<AddEditPaymentMethodDialog> createState() => _AddEditPaymentMethodDialogState();
}

class _AddEditPaymentMethodDialogState extends State<AddEditPaymentMethodDialog> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;
  bool _isLoading = false;

  // Controllers
  final _institutionNameCtrl = TextEditingController();
  final _accountNameCtrl = TextEditingController();
  final _accountNumberCtrl = TextEditingController();
  final _detailsCtrl = TextEditingController();
  bool _isActive = true; // القيمة الافتراضية عند الإضافة

  bool get _isEditMode => widget.existingMethod != null;

  @override
  void initState() {
    super.initState();
    if (_isEditMode) {
      // تعبئة الحقول بالبيانات الحالية للتعديل
      _institutionNameCtrl.text = widget.existingMethod!.institutionName;
      _accountNameCtrl.text = widget.existingMethod!.accountName;
      _accountNumberCtrl.text = widget.existingMethod!.accountNumber;
      _detailsCtrl.text = widget.existingMethod!.details ?? '';
      _isActive = widget.existingMethod!.isActive;
    }
  }

  @override
  void dispose() {
    _institutionNameCtrl.dispose();
    _accountNameCtrl.dispose();
    _accountNumberCtrl.dispose();
    _detailsCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isLoading) return;

    setState(() => _isLoading = true);

    final data = {
      'store_id': widget.storeId,
      'store_type': widget.storeType,
      'owner_id': widget.ownerId,
      'institution_name': _institutionNameCtrl.text.trim(),
      'account_name': _accountNameCtrl.text.trim(),
      'account_number': _accountNumberCtrl.text.trim(),
      'details': _detailsCtrl.text.trim().isEmpty ? null : _detailsCtrl.text.trim(),
      'is_active': _isActive,
    };

    try {
      if (_isEditMode) {
        // تعديل
        await _supabase
            .from('store_payment_methods')
            .update(data)
            .eq('id', widget.existingMethod!.id);
      } else {
        // إضافة جديدة
        await _supabase.from('store_payment_methods').insert(data);
      }

      if (!mounted) return;
      widget.onSaved(); // استدعاء Callback لتحديث القائمة في الشاشة السابقة
      Navigator.pop(context); // إغلاق الحوار
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isEditMode ? 'تم تحديث طريقة الدفع' : 'تمت إضافة طريقة الدفع'), backgroundColor: Colors.green),
      );

    } catch (e) {
      print("Error saving payment method: $e");
      if (!mounted) return;
      String errorMessage = 'خطأ في حفظ طريقة الدفع.';
      if (e is PostgrestException && e.code == '23505' && e.details != null && e.details!.contains('store_payment_methods_store_acc_unique')) {
        errorMessage = 'هذا الحساب مضاف مسبقاً لهذا المتجر.';
      } else if (e is PostgrestException) {
        errorMessage = 'خطأ قاعدة بيانات (${e.code}): ${e.message}';
      } else {
        errorMessage = 'خطأ غير متوقع: $e';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage), backgroundColor: Theme.of(context).colorScheme.error),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditMode ? 'تعديل طريقة الدفع' : 'إضافة طريقة دفع جديدة'),
      // جعل المحتوى قابلاً للتمرير
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min, // لجعل الحوار يأخذ أقل ارتفاع ممكن
            children: [
              TextFormField(
                controller: _institutionNameCtrl,
                decoration: const InputDecoration(labelText: 'اسم البنك/المؤسسة*'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'الحقل مطلوب' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _accountNameCtrl,
                decoration: const InputDecoration(labelText: 'اسم صاحب الحساب*'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'الحقل مطلوب' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _accountNumberCtrl,
                decoration: const InputDecoration(labelText: 'رقم الحساب/IBAN/رقم الجوال*'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'الحقل مطلوب' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _detailsCtrl,
                decoration: const InputDecoration(labelText: 'تفاصيل إضافية (اختياري)'),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              // مفتاح التفعيل
              SwitchListTile(
                title: const Text('تفعيل طريقة الدفع؟'),
                value: _isActive,
                onChanged: (value) => setState(() => _isActive = value),
                dense: true,
                contentPadding: EdgeInsets.zero, // إزالة padding الافتراضي
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _save,
          child: _isLoading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_isEditMode ? 'حفظ التعديلات' : 'إضافة'),
        ),
      ],
    );
  }
}