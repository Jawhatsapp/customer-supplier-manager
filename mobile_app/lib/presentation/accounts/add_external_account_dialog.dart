// lib/presentation/accounts/add_external_account_dialog.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddExternalAccountDialog extends StatefulWidget {
  final int storeId;
  final Function() onAccountAdded; // Callback to refresh the list

  const AddExternalAccountDialog({
    Key? key,
    required this.storeId,
    required this.onAccountAdded,
  }) : super(key: key);

  @override
  State<AddExternalAccountDialog> createState() => _AddExternalAccountDialogState();
}

class _AddExternalAccountDialogState extends State<AddExternalAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _detailsController = TextEditingController();
  String? _selectedAccountType;
  bool _isLoading = false;

  final List<String> _accountTypes = [
    'external_client',
    'external_supplier',
    'employee',
    'expense',
    'other_revenue',
    'other',
  ];

  // تحويل النوع إلى نص مقروء (يمكن تحسينه باستخدام Map أو Enum)
  String _getAccountTypeDisplay(String type) {
    switch (type) {
      case 'external_client': return 'عميل خارجي';
      case 'external_supplier': return 'مورد خارجي';
      case 'employee': return 'موظف';
      case 'expense': return 'مصروفات';
      case 'other_revenue': return 'إيرادات أخرى';
      case 'other': return 'أخرى';
      default: return type;
    }
  }

  Future<void> _saveAccount() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_selectedAccountType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار نوع الحساب')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final currentUser = Supabase.instance.client.auth.currentUser;

    try {
      await Supabase.instance.client.from('external_accounts').insert({
        'store_id': widget.storeId,
        'first_name': _firstNameController.text.trim(),
        'last_name': _lastNameController.text.trim().isEmpty ? null : _lastNameController.text.trim(),
        'phone': _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        'address': _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
        'account_type': _selectedAccountType!,
        'details': _detailsController.text.trim().isEmpty ? null : _detailsController.text.trim(),
        'created_by': currentUser?.id, // تأكد من أن المستخدم مسجل الدخول
        'is_active': true,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إضافة الحساب بنجاح')),
        );
        widget.onAccountAdded(); // استدعاء الـ callback لتحديث القائمة
        Navigator.of(context).pop(); // إغلاق الدايالوج
      }
    } on PostgrestException catch (e) {
      print("Error saving external account: ${e.message}");
      String userMessage = 'حدث خطأ أثناء حفظ الحساب.';
      if (e.code == '23505') { // Unique violation
        if (e.message.contains('external_accounts_phone_key')) {
          userMessage = 'رقم الهاتف هذا مستخدم بالفعل لحساب آخر.';
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userMessage)),
        );
      }
    }
    catch (e) {
      print("Error saving external account: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ غير متوقع: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إضافة حساب خارجي جديد'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Directionality( // Ensure RTL layout
            textDirection: TextDirection.rtl,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextFormField(
                  controller: _firstNameController,
                  decoration: const InputDecoration(labelText: 'الاسم الأول *'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'الاسم الأول مطلوب';
                    }
                    return null;
                  },
                ),
                TextFormField(
                  controller: _lastNameController,
                  decoration: const InputDecoration(labelText: 'الاسم الأخير'),
                ),
                DropdownButtonFormField<String>(
                  value: _selectedAccountType,
                  hint: const Text('اختر نوع الحساب *'),
                  items: _accountTypes.map((String type) {
                    return DropdownMenuItem<String>(
                      value: type,
                      child: Text(_getAccountTypeDisplay(type)),
                    );
                  }).toList(),
                  onChanged: (newValue) {
                    setState(() {
                      _selectedAccountType = newValue;
                    });
                  },
                  validator: (value) => value == null ? 'نوع الحساب مطلوب' : null,
                ),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(labelText: 'رقم الهاتف'),
                  keyboardType: TextInputType.phone,
                ),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(labelText: 'العنوان'),
                ),
                TextFormField(
                  controller: _detailsController,
                  decoration: const InputDecoration(labelText: 'تفاصيل إضافية'),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('إلغاء'),
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _saveAccount,
          child: _isLoading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('حفظ'),
        ),
      ],
    );
  }
}