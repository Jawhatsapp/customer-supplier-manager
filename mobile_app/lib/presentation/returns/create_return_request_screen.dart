// lib/presentation/returns/create_return_request_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CreateReturnRequestScreen extends StatefulWidget {
  final int storeId;
  final String userId;

  const CreateReturnRequestScreen({
    Key? key,
    required this.storeId,
    required this.userId,
  }) : super(key: key);

  @override
  State<CreateReturnRequestScreen> createState() =>
      _CreateReturnRequestScreenState();
}

class _CreateReturnRequestScreenState extends State<CreateReturnRequestScreen> {
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _reasonCtrl = TextEditingController();
  bool _isLoading = false;

  Future<void> _submitReturnRequest() async {
    final amountText = _amountCtrl.text.trim();
    final reason = _reasonCtrl.text.trim();

    if (amountText.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('أدخل المبلغ')));
      return;
    }
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('مبلغ غير صالح')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      await Supabase.instance.client
          .from('return_requests')
          .insert({
        'store_id': widget.storeId,
        'user_id': widget.userId,
        'amount': amount,
        'reason': reason,
        'status': 'قيد المراجعة',
        'created_at': DateTime.now().toIso8601String(),
      });

      Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('خطأ: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('طلب مرتجع')),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'المبلغ المطلوب إرجاعه',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reasonCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'سبب الإرجاع',
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isLoading ? null : _submitReturnRequest,
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('إرسال الطلب'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
