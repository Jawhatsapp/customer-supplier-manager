// lib/presentation/manual_operations/manual_operation_notification_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManualOperationNotificationDetailScreen extends StatefulWidget {
  final int operationId;
  final int storeId;

  const ManualOperationNotificationDetailScreen({
    Key? key,
    required this.operationId,
    required this.storeId,
  }) : super(key: key);

  @override
  _ManualOperationNotificationDetailScreenState createState() =>
      _ManualOperationNotificationDetailScreenState();
}

class _ManualOperationNotificationDetailScreenState
    extends State<ManualOperationNotificationDetailScreen> {
  late Future<Map<String, dynamic>?> _operationFuture;

  @override
  void initState() {
    super.initState();
    _operationFuture = _fetchOperation();
  }

  Future<Map<String, dynamic>?> _fetchOperation() async {
    final response = await Supabase.instance.client
        .from('manual_operations')
        .select()
        .eq('id', widget.operationId)
        .maybeSingle();
    return response;
  }

  Future<void> _approveOperation(Map<String, dynamic> op) async {
    final supabase = Supabase.instance.client;
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return;

    final opId = op['id'];
    final initiatorId = op['initiator_id'];
    final storeId = op['store_id'];
    final amount = double.tryParse(op['amount'].toString()) ?? 0;
    final operationType = op['operation_type'] as String;
    final direction = op['direction'] as String? ?? '';
    final desc = op['description'] as String? ?? '';

    try {
      // إنشاء معاملة مالية
      final trxResponse = await supabase.from('financial_transactions').insert({
        'store_id': storeId,
        'payment_type': 'manual',
        'status': 'approved',
        'note': desc.isEmpty ? 'عملية مالية يدوية' : desc,
      }).select().single();
      final trxId = trxResponse['id'];

      // تحديد اتجاه القيد
      String initiatorLine = 'عليه';
      String counterLine = 'له';
      if (operationType == 'يدوي') {
        if (direction == 'له') {
          initiatorLine = 'له';
          counterLine = 'عليه';
        } else {
          initiatorLine = 'عليه';
          counterLine = 'له';
        }
      }

      // تسجيل قيود مزدوجة
      await supabase.from('transaction_lines').insert([
        {
          'transaction_id': trxId,
          'user_id': initiatorId,
          'related_user_id': currentUser.id,
          'type': initiatorLine,
          'amount': amount,
          'description': desc.isEmpty ? 'عملية يدوية تمت الموافقة عليها' : desc,
        },
        {
          'transaction_id': trxId,
          'user_id': currentUser.id,
          'related_user_id': initiatorId,
          'type': counterLine,
          'amount': amount,
          'description': desc.isEmpty ? 'عملية يدوية تمت الموافقة عليها' : desc,
        }
      ]);

      // تحديث حالة العملية
      await supabase
          .from('manual_operations')
          .update({'status': 'approved'})
          .eq('id', opId);

      // إشعار الطرف الآخر
      await supabase.from('notifications').insert({
        'user_id': initiatorId,
        'title': 'تمت الموافقة على عمليتك',
        'message': 'تمت الموافقة على عملية مالية بقيمة $amount ر.ي.',
      });

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تمت الموافقة على العملية')));
        Navigator.pop(context, true);
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
  }

  Future<void> _rejectOperation(Map<String, dynamic> op) async {
    final supabase = Supabase.instance.client;
    final initiatorId = op['initiator_id'];
    try {
      await supabase
          .from('manual_operations')
          .update({'status': 'rejected'})
          .eq('id', op['id']);
      await supabase.from('notifications').insert({
        'user_id': initiatorId,
        'title': 'تم رفض العملية',
        'message': 'تم رفض العملية المالية التي أرسلتها',
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تم رفض العملية')));
      Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'بإنتظار الموافقة';
      case 'approved':
        return 'مقبولة';
      case 'rejected':
        return 'مرفوضة';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تفاصيل العملية اليدوية'),
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _operationFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return const Center(child: Text('خطأ في جلب تفاصيل العملية'));
          }
          final op = snapshot.data!;
          final amount = op['amount'];
          final operationType = op['operation_type'] as String;
          final direction = op['direction'] as String? ?? '';
          final desc = op['description'] as String? ?? '';
          final status = op['status'] as String;
          final createdAt = op['created_at']?.toString().split('T').first ?? '';
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('نوع العملية: $operationType',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (operationType == 'يدوي')
                  Text('الاتجاه: $direction', style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 8),
                Text('المبلغ: $amount ر.ي', style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 8),
                Text('الوصف: $desc', style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 8),
                Text('الحالة: ${_getStatusText(status)}',
                    style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 8),
                Text('تاريخ الإنشاء: $createdAt',
                    style: const TextStyle(fontSize: 16)),
                const Spacer(),
                if (status == 'pending')
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: () => _approveOperation(op),
                        child: const Text('موافقة'),
                      ),
                      ElevatedButton(
                        onPressed: () => _rejectOperation(op),
                        child: const Text('رفض'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red),
                      ),
                    ],
                  )
                else
                  Center(
                    child: Text(
                      'العملية ${_getStatusText(status)}',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  )
              ],
            ),
          );
        },
      ),
    );
  }
}
