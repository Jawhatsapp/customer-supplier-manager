// lib/presentation/manual_operations/approve_manual_operations_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ApproveManualOperationsScreen extends StatefulWidget {
  const ApproveManualOperationsScreen({Key? key}) : super(key: key);

  @override
  State<ApproveManualOperationsScreen> createState() =>
      _ApproveManualOperationsScreenState();
}

class _ApproveManualOperationsScreenState
    extends State<ApproveManualOperationsScreen> {
  late Future<List<Map<String, dynamic>>> _pendingOpsFuture;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _pendingOpsFuture = _fetchPendingOps();
  }

  Future<List<Map<String, dynamic>>> _fetchPendingOps() async {
    final supabase = Supabase.instance.client;
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return [];

    final response = await supabase
        .from('manual_operations')
        .select('''
          id,
          store_id,
          initiator_id,
          counterparty_id,
          direction,
          amount,
          description,
          created_at,
          initiator_profile:initiator_id(first_name,last_name)
        ''')
        .eq('counterparty_id', currentUser.id)
        .eq('status', 'pending')
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  // --- تم تعديل هذه الدالة ---
  Future<String?> _getStoreOwnerId(int storeId) async {
    final supabase = Supabase.instance.client;
    try {
      final response = await supabase
          .from('stores') // <-- اسم الجدول الجديد
          .select('owner_id') // <-- اسم الحقل الجديد
          .eq('id', storeId)
          .maybeSingle();

      if (response != null && response['owner_id'] != null) {
        return response['owner_id'] as String;
      }
      return null;
    } catch (e) {
      print("Error fetching store owner ID: $e");
      return null;
    }
  }
  // --- نهاية التعديل ---

  Future<int?> _fetchUserStoreId(String userId) async {
    final supabase = Supabase.instance.client;
    try {
      // بما أننا لا نعرف دور المستخدم، يمكننا البحث في جدول المتاجر مباشرة
      final storeResponse = await supabase
          .from('stores') // <-- اسم الجدول الجديد
          .select('id')
          .eq('owner_id', userId)
          .maybeSingle();

      return storeResponse?['id'] as int?;
    } catch (e) {
      print("Error fetching user's store ID: $e");
      return null;
    }
  }

  Future<void> _insertFinancialTransaction({
    required int storeId,
    required String debtorId,
    required String creditorId,
    required double amount,
    required int opId,
    required String noteSuffix,
  }) async {
    final supabase = Supabase.instance.client;
    final trx = await supabase
        .from('financial_transactions')
        .insert({
      'store_id': storeId,
      'payment_type': 'manual',
      'status': 'approved',
      'note': noteSuffix,
    }).select().single();
    final trxId = trx['id'];

    final lines = [
      { 'transaction_id': trxId, 'user_id': debtorId, 'related_user_id': creditorId, 'type': 'عليه', 'amount': amount, 'description': 'عملية يدوية #$opId (مدين)', },
      { 'transaction_id': trxId, 'user_id': creditorId, 'related_user_id': debtorId, 'type': 'له', 'amount': amount, 'description': 'عملية يدوية #$opId (دائن)', },
    ];
    await supabase.from('transaction_lines').insert(lines);
  }

  Future<void> _approveOperation(Map<String, dynamic> op) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    final supabase = Supabase.instance.client;
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) { setState(() => _isProcessing = false); return; }

    final opId = op['id'] as int;
    final storeId = op['store_id'] as int;
    final initiatorId = op['initiator_id'] as String;
    final amount = (op['amount'] as num).toDouble();
    final direction = op['direction'] as String;
    final desc = op['description'] ?? 'عملية يدوية رقم $opId';
    final bool initiatorIsCreditor = (direction == 'له');
    final creditorId = initiatorIsCreditor ? initiatorId : currentUser.id;
    final debtorId = initiatorIsCreditor ? currentUser.id : initiatorId;

    try {
      // ❶ المعاملة الأولى
      await _insertFinancialTransaction( storeId: storeId, creditorId: creditorId, debtorId: debtorId, amount: amount, opId: opId, noteSuffix: desc );

      // ❷ المعاملة الثانية (مرآة)
      final storeOwnerId = await _getStoreOwnerId(storeId);
      final otherUserId = (storeOwnerId == initiatorId) ? currentUser.id : initiatorId;
      final secondStoreId = await _fetchUserStoreId(otherUserId);
      if (secondStoreId != null && secondStoreId != storeId) {
        await _insertFinancialTransaction( storeId: secondStoreId, creditorId: creditorId, debtorId: debtorId, amount: amount, opId: opId, noteSuffix: '$desc (جانب الطرف الآخر)' );
      }

      // ❸ تحديث حالة العملية اليدوية
      await supabase.from('manual_operations').update({'status': 'approved'}).eq('id', opId);

      // ❹ إرسال إشعار للمبادر
      await supabase.from('notifications').insert({
        'user_id': initiatorId,
        'title': 'تمت الموافقة على عمليتك اليدوية',
        'message': 'تمت الموافقة على العملية اليدوية رقم #$opId بمبلغ ${amount.toStringAsFixed(2)} ر.ي التي أرسلتها.',
        'related_entity_type': 'manual_operation',
        'related_entity_id': opId,
        'store_id': storeId,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar( content: Text('تمت الموافقة وتسجيل القيود للطرفين بنجاح')));
        setState(() { _pendingOpsFuture = _fetchPendingOps(); });
      }
    } catch (e) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ أثناء الموافقة: $e'))); }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _rejectOperation(Map<String, dynamic> op) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    final supabase = Supabase.instance.client;
    final opId = op['id'] as int;
    final initiatorId = op['initiator_id'] as String;
    final storeId = op['store_id'] as int;

    try {
      await supabase.from('manual_operations').update({'status': 'rejected'}).eq('id', opId);

      await supabase.from('notifications').insert({
        'user_id': initiatorId,
        'title': 'تم رفض عمليتك اليدوية',
        'message': 'تم رفض العملية اليدوية رقم #$opId التي أرسلتها.',
        'related_entity_type': 'manual_operation',
        'related_entity_id': opId,
        'store_id': storeId,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم رفض العملية')));
        setState(() { _pendingOpsFuture = _fetchPendingOps(); });
      }
    } catch (e) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ في الرفض: $e'))); }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('عمليات يدوية للموافقة')),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {
            _pendingOpsFuture = _fetchPendingOps();
          });
        },
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _pendingOpsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline,
                          color: theme.colorScheme.error, size: 48),
                      const SizedBox(height: 10),
                      Text(
                        'حدث خطأ أثناء تحميل العمليات:\n${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.error),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('إعادة المحاولة'),
                        onPressed: () {
                          setState(() {
                            _pendingOpsFuture = _fetchPendingOps();
                          });
                        },
                      )
                    ],
                  ),
                ),
              );
            }

            final ops = snapshot.data ?? [];
            if (ops.isEmpty) {
              return const Center(child: Text('لا توجد عمليات معلقة حالياً.'));
            }

            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: ops.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final op = ops[i];
                final initiatorProfile = op['initiator_profile'];
                final initiatorName = (initiatorProfile != null)
                    ? '${initiatorProfile['first_name'] ?? ''} ${initiatorProfile['last_name'] ?? ''}'.trim()
                    : 'مستخدم';
                final direction = op['direction'] as String;
                final reqText = (direction == 'له')
                    ? 'يطلب تسجيل أنك مدين له بمبلغ:'
                    : 'يطلب تسجيل أنه مدين لك بمبلغ:';
                final amount = (op['amount'] as num).toDouble();
                final desc = op['description'] ?? '';

                final dateStr = op['created_at']?.toString().split('T').first ?? '';
                final timeStr = op['created_at']?.toString().split('T').last?.substring(0,5) ?? '';

                return Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'طلب من: $initiatorName',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '$dateStr  $timeStr',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(reqText, style: theme.textTheme.bodyMedium),
                        const SizedBox(height: 4),
                        Text(
                          '$amount ر.ي',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (desc.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('الوصف: $desc',
                              style: theme.textTheme.bodySmall),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (_isProcessing)
                              const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            else ...[
                              TextButton.icon(
                                onPressed: () => _approveOperation(op),
                                icon: const Icon(Icons.check_circle, color: Colors.green),
                                label: const Text('موافقة'),
                              ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                onPressed: () =>_rejectOperation(op),
                                icon: const Icon(Icons.cancel, color: Colors.red),
                                label: const Text('رفض'),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}