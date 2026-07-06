import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddOperationSheet extends StatefulWidget {
  final int storeId;
  final String targetUserId; // المستخدم المقابل (المشتري)
  final VoidCallback onDone;

  const AddOperationSheet({
    Key? key,
    required this.storeId,
    required this.targetUserId,
    required this.onDone,
  }) : super(key: key);

  @override
  State<AddOperationSheet> createState() => _AddOperationSheetState();
}

class _AddOperationSheetState extends State<AddOperationSheet> {
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();

  // نوع العملية: سداد أو عملية يدوية
  String _operationType = 'سداد';
  // إذا عملية يدوية، ممكن user يُحدد اتجاه المبلغ (له/عليه)
  String _manualSide = 'له';

  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: mq.viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('إضافة عملية', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),

            // Dropdown لاختيار نوع العملية
            Row(
              children: [
                const Text('نوع العملية: '),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _operationType,
                  items: const [
                    DropdownMenuItem(value: 'سداد', child: Text('سداد')),
                    DropdownMenuItem(value: 'عملية يدوية', child: Text('عملية يدوية')),
                  ],
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() => _operationType = val);
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),

            // إذا اخترت عملية يدوية => يظهر اختيار 'له' أو 'عليه'
            if (_operationType == 'عملية يدوية')
              Row(
                children: [
                  const Text('كيف تؤثر على المستخدم؟'),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _manualSide,
                    items: const [
                      DropdownMenuItem(value: 'له', child: Text('له')),
                      DropdownMenuItem(value: 'عليه', child: Text('عليه')),
                    ],
                    onChanged: (val) {
                      if (val == null) return;
                      setState(() => _manualSide = val);
                    },
                  ),
                ],
              ),

            const SizedBox(height: 8),

            // حقل المبلغ
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'المبلغ',
                prefixIcon: Icon(Icons.monetization_on),
              ),
            ),
            const SizedBox(height: 8),

            // حقل الوصف
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'الوصف (اختياري)',
                prefixIcon: Icon(Icons.description),
              ),
            ),
            const SizedBox(height: 16),

            ElevatedButton.icon(
              icon: _isLoading
                  ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Icon(Icons.save),
              label: Text(_isLoading ? 'جاري الحفظ...' : 'حفظ'),
              onPressed: _isLoading ? null : _saveOperation,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveOperation() async {
    final amountText = _amountCtrl.text.trim();
    if (amountText.isEmpty) {
      _showMessage('يرجى إدخال مبلغ');
      return;
    }
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      _showMessage('المبلغ غير صالح');
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (_operationType == 'سداد') {
        await _insertPayment(amount);
      } else {
        await _insertManual(amount, _manualSide);
      }

      widget.onDone();
      Navigator.pop(context);
    } catch (e) {
      _showMessage('حدث خطأ: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  /// إدخال سداد (قيد مزدوج):
  /// - user_id=targetUser => 'عليه'
  /// - user_id=owner => 'له'
  Future<void> _insertPayment(double amount) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return;

    // 1) إنشاء financial_transactions
    final trxRes = await Supabase.instance.client
        .from('financial_transactions')
        .insert({
      'store_id': widget.storeId,
      'order_id': null,
      'payment_type': 'payment',
      'status': 'completed',
      'note': _descCtrl.text.isNotEmpty
          ? 'سداد: ${_descCtrl.text}'
          : 'سداد بدون ملاحظة',
    }).select().single();

    final transactionId = trxRes['id'];

    // 2) جلب المالك (يمكنك أيضًا سحبه من store_relations)
    final ownerId = await _fetchStoreOwnerId(widget.storeId);

    final lines = [
      {
        'transaction_id': transactionId,
        'user_id': widget.targetUserId,
        'related_user_id': ownerId,
        'type': 'عليه',
        'amount': amount,
        'description': 'سداد بقيمة $amount',
      },
      {
        'transaction_id': transactionId,
        'user_id': ownerId,
        'related_user_id': widget.targetUserId,
        'type': 'له',
        'amount': amount,
        'description': 'استلام سداد بقيمة $amount',
      },
    ];
    await Supabase.instance.client.from('transaction_lines').insert(lines);

    // 3) عمل نسخة مرآة إن كان المشتري يملك متجره:
    await _createMirrorIfNeeded(
      amount: amount,
      paymentType: 'payment',
      note: _descCtrl.text.isNotEmpty ? _descCtrl.text : 'سداد',
      mainTypeUser: 'عليه', // buyer
      mainTypeOwner: 'له',  // store owner
    );

    // 4) إرسال إشعار (إن كنت تحتاج)
    await Supabase.instance.client.from('notifications').insert({
      'user_id': widget.targetUserId,
      'title': 'عملية سداد',
      'message': 'تم تسجيل سداد بقيمة $amount عليك في المتجر',
    });
  }

  /// عملية يدوية:
  /// إذا اخترت side='له' => user_id=target='له', owner='عليه'
  /// إذا side='عليه' => user_id=target='عليه', owner='له'
  Future<void> _insertManual(double amount, String side) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return;

    final trxRes = await Supabase.instance.client
        .from('financial_transactions')
        .insert({
      'store_id': widget.storeId,
      'order_id': null,
      'payment_type': 'manual',
      'status': 'approved',
      'note': 'عملية يدوية: ${_descCtrl.text}',
    }).select().single();

    final transactionId = trxRes['id'];

    final ownerId = await _fetchStoreOwnerId(widget.storeId);
    final opposite = (side == 'له') ? 'عليه' : 'له';

    final lines = [
      {
        'transaction_id': transactionId,
        'user_id': widget.targetUserId,
        'related_user_id': ownerId,
        'type': side,
        'amount': amount,
        'description': _descCtrl.text.isNotEmpty ? _descCtrl.text : 'عملية يدوية',
      },
      {
        'transaction_id': transactionId,
        'user_id': ownerId,
        'related_user_id': widget.targetUserId,
        'type': opposite,
        'amount': amount,
        'description': _descCtrl.text.isNotEmpty
            ? 'مقابل: ${_descCtrl.text}'
            : 'مقابل العملية اليدوية',
      },
    ];
    await Supabase.instance.client
        .from('transaction_lines')
        .insert(lines);

    // نسخة مرآة
    await _createMirrorIfNeeded(
      amount: amount,
      paymentType: 'manual',
      note: _descCtrl.text.isNotEmpty ? _descCtrl.text : 'عملية يدوية',
      mainTypeUser: side,
      mainTypeOwner: opposite,
    );

    // إشعار
    await Supabase.instance.client.from('notifications').insert({
      'user_id': widget.targetUserId,
      'title': 'عملية مالية جديدة',
      'message': 'تم تسجيل عملية يدويّة: ${_descCtrl.text}, المبلغ: $amount',
    });
  }

  /// جلب المالك من أي طريقة تريد، هنا مثال بسيط
  /// ويمكنك تبديلها باستخدام store_relations أيضاً
  Future<String?> _fetchStoreOwnerId(int storeId) async {
    // إذا كان store_relations ينظم المالك:
    final rel = await Supabase.instance.client
        .from('store_relations')
        .select('user_id')
        .eq('store_id', storeId)
        .eq('role_in_store', 'owner')
        .maybeSingle();

    if (rel != null) {
      return rel['user_id'] as String?;
    }
    return null;
  }

  /// نسخ العملية إلى متجر المشتري (إن كان buyer عنده متجر)
  /// في حال targetUser == تاجر له متجره
  Future<void> _createMirrorIfNeeded({
    required double amount,
    required String paymentType,
    required String note,
    required String mainTypeUser,
    required String mainTypeOwner,
  }) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return;

    // ابحث عن متجر user = targetUser
    final ret = await Supabase.instance.client
        .from('store_relations')
        .select('store_id')
        .eq('user_id', widget.targetUserId)
        .eq('role_in_store', 'owner')
        .maybeSingle();

    final userStoreId = ret?['store_id'] as int?;
    if (userStoreId == null) return;          // لا يملك متجر
    if (userStoreId == widget.storeId) return; // نفس المتجر => لا داعي للمرآة

    // ننشئ المعاملة في متجر المشتري
    final mirrorTrx = await Supabase.instance.client
        .from('financial_transactions')
        .insert({
      'store_id': userStoreId,
      'order_id': null,
      'payment_type': paymentType,
      'status': 'approved',
      'note': 'مرآة: $note',
    }).select().single();

    final mirrorTrxId = mirrorTrx['id'];

    // نعكس الجهة:
    final mirrorUserSide = (mainTypeUser == 'له') ? 'عليه' : 'له';
    final mirrorOwnerSide = (mainTypeOwner == 'له') ? 'عليه' : 'له';

    final lines2 = [
      {
        'transaction_id': mirrorTrxId,
        'user_id': currentUser.id,
        'related_user_id': widget.targetUserId,
        'type': mirrorOwnerSide,
        'amount': amount,
        'description': 'مرآة: $note',
      },
      {
        'transaction_id': mirrorTrxId,
        'user_id': widget.targetUserId,
        'related_user_id': currentUser.id,
        'type': mirrorUserSide,
        'amount': amount,
        'description': 'مرآة: $note (مقابل)',
      },
    ];
    await Supabase.instance.client
        .from('transaction_lines')
        .insert(lines2);
  }
}
