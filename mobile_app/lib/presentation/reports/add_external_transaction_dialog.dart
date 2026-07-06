// lib/presentation/reports/add_external_transaction_dialog.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// يمكنك استخدام package مثل intl لتحسين تنسيق التاريخ
// import 'package:intl/intl.dart';

class AddExternalTransactionDialog extends StatefulWidget {
  final int externalAccountId;
  final int storeId;
  final String accountName;
  final Function() onTransactionAdded; // Callback للتحديث

  const AddExternalTransactionDialog({
    Key? key,
    required this.externalAccountId,
    required this.storeId,
    required this.accountName,
    required this.onTransactionAdded,
  }) : super(key: key);

  @override
  State<AddExternalTransactionDialog> createState() =>
      _AddExternalTransactionDialogState();
}

class _AddExternalTransactionDialogState
    extends State<AddExternalTransactionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  String? _selectedType; // 'له' or 'عليه'
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;

  Future<void> _saveTransaction() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_selectedType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى تحديد نوع المعاملة (له/عليه)')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final currentUser = Supabase.instance.client.auth.currentUser;
    final amount = double.tryParse(_amountController.text.trim());

    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('المبلغ يجب أن يكون رقمًا أكبر من صفر')),
      );
      setState(() => _isLoading = false);
      return;
    }

    try {
      await Supabase.instance.client.from('external_account_transactions').insert({
        'external_account_id': widget.externalAccountId,
        'store_id': widget.storeId,
        'type': _selectedType!,
        'amount': amount,
        'description': _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
        'transaction_date': _selectedDate.toUtc().toIso8601String(), // حفظ بتنسيق UTC
        'created_by': currentUser?.id,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تمت إضافة المعاملة بنجاح')),
        );
        widget.onTransactionAdded(); // استدعاء callback
        Navigator.of(context).pop(); // إغلاق الدايالوج
      }

    } catch (e) {
      print("Error saving external transaction: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في حفظ المعاملة: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // دالة لاختيار التاريخ
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000), // حدد نطاق التاريخ المناسب
      lastDate: DateTime.now().add(const Duration(days: 365)), // السماح بتواريخ مستقبلية قليلاً؟
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // تنسيق التاريخ للعرض
    // final displayDateFormat = DateFormat('yyyy-MM-dd');

    return AlertDialog(
      title: Text('إضافة معاملة لـ ${widget.accountName}'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                DropdownButtonFormField<String>(
                  value: _selectedType,
                  hint: const Text('نوع المعاملة *'),
                  items: const [
                    DropdownMenuItem(value: 'له', child: Text('له (هو دائن / استلمت منه)')),
                    DropdownMenuItem(value: 'عليه', child: Text('عليه (هو مدين / دفعت له)')),
                  ],
                  onChanged: (newValue) {
                    setState(() {
                      _selectedType = newValue;
                    });
                  },
                  validator: (value) => value == null ? 'النوع مطلوب' : null,
                ),
                TextFormField(
                  controller: _amountController,
                  decoration: const InputDecoration(
                    labelText: 'المبلغ *',
                    suffixText: 'ر.ي',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'المبلغ مطلوب';
                    }
                    final pVal = double.tryParse(value);
                    if (pVal == null || pVal <= 0) {
                      return 'أدخل مبلغاً صحيحاً أكبر من صفر';
                    }
                    return null;
                  },
                ),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(labelText: 'الوصف / ملاحظة'),
                  maxLines: 2,
                ),
                const SizedBox(height: 15),
                Text('تاريخ المعاملة:', style: theme.textTheme.labelMedium),
                TextButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 18),
                  // label: Text(displayDateFormat.format(_selectedDate)),
                  label: Text('${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}'), // تنسيق بسيط
                  onPressed: () => _selectDate(context),
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
          onPressed: _isLoading ? null : _saveTransaction,
          child: _isLoading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('حفظ المعاملة'),
        ),
      ],
    );
  }
}