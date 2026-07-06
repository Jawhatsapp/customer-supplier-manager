// lib/presentation/returns/approve_return_requests_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart'; // Import Provider
import '../../providers/auth_provider.dart'; // Import AuthProvider

// (نماذج البيانات تبقى كما هي)
class LoadedReturnItem {
  final int returnRequestItemId;
  final int orderItemId;
  final int productId;
  final String productName;
  final int returnedQuantity;
  final double originalUnitPrice;

  LoadedReturnItem({
    required this.returnRequestItemId, required this.orderItemId,
    required this.productId, required this.productName,
    required this.returnedQuantity, required this.originalUnitPrice,
  });
}

class ApproveReturnRequestsScreen extends StatefulWidget {
  final int storeId;
  const ApproveReturnRequestsScreen({Key? key, required this.storeId}) : super(key: key);

  @override
  State<ApproveReturnRequestsScreen> createState() => _ApproveReturnRequestsScreenState();
}

class _ApproveReturnRequestsScreenState extends State<ApproveReturnRequestsScreen> {
  final _supabase = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _requestsFuture;
  final Map<int, bool> _isLoadingMap = {};
  final TextEditingController _rejectionReasonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _requestsFuture = _fetchRequestsWithItems();
  }

  @override
  void dispose() {
    _rejectionReasonController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _fetchRequestsWithItems() async {
    try {
      final response = await _supabase
          .from('return_requests')
          .select(''' id, store_id, user_id, order_id, reason, image_url, status, created_at,
            profile:user_id(first_name, last_name),
            order:order_id(created_at),
            return_request_items ( id, order_item_id, quantity, order_item:order_item_id ( unit_price, product:products (id, product_name)))
          ''')
          .eq('store_id', widget.storeId)
          .eq('status', 'قيد المراجعة')
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print("Error fetching return requests with items: $e");
      if (mounted) _showMsg('خطأ في جلب طلبات المرتجع.', isError: true);
      return [];
    }
  }

  Future<void> _refreshData() async {
    setState(() { _isLoadingMap.clear(); _requestsFuture = _fetchRequestsWithItems(); });
  }

  void _setLoading(int requestId, bool loading) {
    if (!mounted) return;
    setState(() { _isLoadingMap[requestId] = loading; });
  }

  // --- دالة مساعدة لجلب متجر المستخدم (مهمة للقيد المرآة) ---
  Future<int?> _fetchUserStoreId(String userId) async {
    final supabase = Supabase.instance.client;
    try {
      final storeResponse = await supabase.from('stores').select('id').eq('owner_id', userId).maybeSingle();
      return storeResponse?['id'] as int?;
    } catch (e) {
      print("Error fetching user's store ID for mirroring: $e");
      return null;
    }
  }

  // --- دالة إنشاء القيود المالية (مشتركة) ---
  Future<void> _createFinancialEntry({
    required int storeId, int? orderId, required String paymentType,
    required String status, required String debtorId, required String creditorId,
    required double amount, required String noteSuffix, required String lineDescSuffix,
  }) async {
    try {
      final trxRes = await _supabase.from('financial_transactions').insert({
        'store_id': storeId, 'order_id': orderId, 'payment_type': paymentType, 'status': status, 'note': noteSuffix,
      }).select('id').single();
      final transactionId = trxRes['id'];
      final lines = [
        {'transaction_id': transactionId, 'user_id': debtorId, 'related_user_id': creditorId, 'type': 'عليه', 'amount': amount, 'description': '$lineDescSuffix (مدين)'},
        {'transaction_id': transactionId, 'user_id': creditorId, 'related_user_id': debtorId, 'type': 'له', 'amount': amount, 'description': '$lineDescSuffix (دائن)'},
      ];
      await _supabase.from('transaction_lines').insert(lines);
    } catch(e) { throw Exception("خطأ في إنشاء القيد المالي: $e"); }
  }


  Future<void> _updateStockForReturnedItems(List<LoadedReturnItem> returnedItems, int requestId, SupabaseClient supabase) async {
    if (returnedItems.isEmpty) return;
    try {
      List<Map<String, dynamic>> stockMovementsData = [];
      for (var item in returnedItems) {
        await supabase.rpc('increment_product_stock', params: {'p_product_id': item.productId, 'p_quantity': item.returnedQuantity});
        stockMovementsData.add({'product_id': item.productId, 'delta': item.returnedQuantity, 'reason': 'مرتجع موافق عليه #$requestId'});
      }
      if (stockMovementsData.isNotEmpty) await supabase.from('stock_movements').insert(stockMovementsData);
    } catch (e) { throw Exception("خطأ أثناء تحديث مخزون المرتجع: $e"); }
  }

  Future<void> _sendNotification({ required String userId, required String title, required String message }) async {
    try { await _supabase.from('notifications').insert({'user_id': userId, 'title': title, 'message': message}); }
    catch (e) { print("Error sending notification to $userId: $e"); }
  }


  // --- تم تعديل دالة الموافقة بشكل كامل ---
  Future<void> _approveRequest(Map<String, dynamic> request) async {
    final requestId = request['id'] as int;
    if (_isLoadingMap[requestId] == true) return;
    _setLoading(requestId, true);

    final ownerId = context.read<AuthProvider>().currentUser?.id;
    if (ownerId == null) {
      _showMsg('خطأ: المستخدم الموافق غير مسجل.', isError: true);
      _setLoading(requestId, false);
      return;
    }

    final storeId = request['store_id'] as int;
    final requestorId = request['user_id'] as String;
    final originalOrderId = request['order_id'] as int?;

    // 1. استخراج البنود وحساب المبلغ
    final List<dynamic> rawItems = request['return_request_items'] ?? [];
    final List<LoadedReturnItem> requestedReturnItems = [];
    double calculatedAmountToReturn = 0.0;
    for (var rawItem in rawItems) {
      final itemMap = rawItem as Map<String, dynamic>;
      final orderItemData = itemMap['order_item'] as Map<String, dynamic>?;
      final productData = orderItemData?['product'] as Map<String, dynamic>?;
      final unitPrice = double.tryParse(orderItemData?['unit_price']?.toString() ?? '0.0') ?? 0.0;
      final requestedQty = itemMap['quantity'] as int? ?? 0;
      if (productData != null && requestedQty > 0 && orderItemData != null) {
        requestedReturnItems.add(LoadedReturnItem( returnRequestItemId: itemMap['id'] as int, orderItemId: itemMap['order_item_id'] as int, productId: productData['id'] as int, productName: productData['product_name'] ?? 'منتج غير معروف', returnedQuantity: requestedQty, originalUnitPrice: unitPrice,));
        calculatedAmountToReturn += (unitPrice * requestedQty);
      }
    }
    if (requestedReturnItems.isEmpty || calculatedAmountToReturn <= 0) {
      _showMsg('خطأ: لا توجد بنود صالحة أو قيمة المرتجع صفر.', isError: true);
      _setLoading(requestId, false);
      return;
    }

    try {
      // 2. تحديث طلب المرتجع
      await _supabase.from('return_requests').update({
        'status': 'موافق', 'approved_by': ownerId, 'approved_at': DateTime.now().toIso8601String(), 'amount': calculatedAmountToReturn,
      }).eq('id', requestId);

      // 3. إنشاء القيد المالي الأساسي (في دفتر البائع)
      // عند المرتجع، البائع يصبح مديناً للعميل
      await _createFinancialEntry(
          storeId: storeId,
          orderId: originalOrderId,
          paymentType: 'return',
          status: 'approved',
          debtorId: ownerId,      // البائع مدين
          creditorId: requestorId, // العميل دائن
          amount: calculatedAmountToReturn,
          noteSuffix: 'موافقة مرتجع #$requestId',
          lineDescSuffix: 'موافقة مرتجع #$requestId'
      );

      // 4. *** إنشاء القيد المرآة في دفتر العميل (إذا كان لديه متجر) ***
      final requestorStoreId = await _fetchUserStoreId(requestorId);
      if (requestorStoreId != null && requestorStoreId != storeId) {
        print("Creating mirrored return transaction for user $requestorId in their store $requestorStoreId");
        await _createFinancialEntry(
            storeId: requestorStoreId,
            orderId: originalOrderId,
            paymentType: 'return',
            status: 'approved',
            debtorId: ownerId,      // البائع مدين
            creditorId: requestorId, // العميل دائن
            amount: calculatedAmountToReturn,
            noteSuffix: 'مرآة: مرتجع إلى متجر #$storeId',
            lineDescSuffix: 'مرآة: مرتجع إلى متجر #$storeId'
        );
      }

      // 5. تحديث المخزون
      await _updateStockForReturnedItems(requestedReturnItems, requestId, _supabase);

      // 6. إرسال إشعار
      await _sendNotification(userId: requestorId, title: 'تم قبول طلب المرتجع', message: 'تمت الموافقة على طلب المرتجع رقم $requestId بمبلغ ${calculatedAmountToReturn.toStringAsFixed(2)} ر.ي.');

      if (!mounted) return;
      _showMsg('تمت الموافقة على الطلب بنجاح.', success: true);
      _refreshData();

    } catch (e) {
      print("Error during return approval: $e");
      if (mounted) _showMsg('خطأ فني أثناء الموافقة: $e', isError: true);
    } finally {
      _setLoading(requestId, false);
    }
  }


  // --- دالة رفض الطلب مع سبب الرفض ---
  Future<void> _rejectRequestWithReason(Map<String, dynamic> request, {String? rejectionReason}) async {
    final requestId = request['id'] as int;
    if (_isLoadingMap[requestId] == true) return;

    String? finalRejectionReason = rejectionReason;

    if (finalRejectionReason == null) {
      finalRejectionReason = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('رفض طلب المرتجع #$requestId'),
          content: TextField( controller: _rejectionReasonController, decoration: const InputDecoration(hintText: 'سبب الرفض (اختياري)'), maxLines: 2,),
          actions: [
            TextButton( onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
            TextButton( onPressed: () => Navigator.pop(context, _rejectionReasonController.text.trim()), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('تأكيد الرفض')),
          ],
        ),
      );
      if (finalRejectionReason == null) return;
      _rejectionReasonController.clear();
    }

    _setLoading(requestId, true);
    final currentUser = _supabase.auth.currentUser;
    final userId = request['user_id'] as String;

    try {
      await _supabase.from('return_requests').update({
        'status': 'مرفوض', 'rejected_by': currentUser?.id, 'rejected_at': DateTime.now().toIso8601String(),
        'rejection_reason': finalRejectionReason!.isNotEmpty ? finalRejectionReason : null,
      }).eq('id', requestId);

      await _supabase.from('notifications').insert({
        'user_id': userId, 'title': 'تم رفض طلب المرتجع',
        'message': 'نأسف، تم رفض طلب المرتجع رقم $requestId.' + (finalRejectionReason.isNotEmpty ? '\nالسبب: $finalRejectionReason' : ''),
        'related_entity_type': 'return_request', // <-- النوع
        'related_entity_id': requestId,
      });

      if (!mounted) return;
      _showMsg('تم رفض الطلب بنجاح.');
      _refreshData();
    } catch (e) {
      print("Error rejecting return: $e");
      if (mounted) _showMsg('خطأ أثناء الرفض: $e');
    } finally {
      _setLoading(requestId, false);
    }
  }

  // --- دالة عرض الرسائل ---
  // الكود الصحيح
  void _showMsg(String msg, {bool success = false, bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: Duration(seconds: (success || isError) ? 4 : 2),
        backgroundColor: isError
            ? Theme.of(context).colorScheme.error
            : (success ? Colors.green : null),
      ),
    );
  }

  // --- بناء الواجهة ---
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('مراجعة طلبات المرتجع'),
        actions: [
          IconButton( icon: const Icon(Icons.refresh), onPressed: _refreshData, tooltip: 'تحديث',)
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _requestsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) { return const Center(child: CircularProgressIndicator()); }
            if (snapshot.hasError) { return Center(child: Padding( padding: const EdgeInsets.all(16.0), child: Text('خطأ في تحميل البيانات: ${snapshot.error}', textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.error)),)); }
            final reqs = snapshot.data ?? [];
            if (reqs.isEmpty) { return const Center(child: Text('لا توجد طلبات مرتجع قيد المراجعة حالياً.')); }
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: reqs.length,
              itemBuilder: (context, index) {
                final r = reqs[index];
                final requestId = r['id'] as int;
                final isLoading = _isLoadingMap[requestId] ?? false;
                final profile = r['profile'];
                final buyerName = profile == null ? '?' : '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'.trim();
                final reason = r['reason'] ?? '-';
                final createdAt = DateTime.tryParse(r['created_at'] ?? '')?.toLocal();
                // ** استخدم تنسيق يدوي بسيط هنا أيضاً **
                final dateStr = createdAt != null ? '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}' : '?';
                final originalOrderId = r['order_id'];
                final imageUrl = r['image_url'];
                final List<dynamic> rawItems = r['return_request_items'] ?? [];
                final List<LoadedReturnItem> returnedItems = [];
                double cardCalculatedAmount = 0;
                for (var rawItem in rawItems) { /* ... استخراج البنود وحساب المبلغ للبطاقة ... */
                  final itemMap = rawItem as Map<String, dynamic>;
                  final orderItemData = itemMap['order_item'] as Map<String, dynamic>?;
                  final productData = orderItemData?['product'] as Map<String, dynamic>?;
                  final unitPrice = double.tryParse(orderItemData?['unit_price']?.toString() ?? '0.0') ?? 0.0;
                  final returnedQty = itemMap['quantity'] as int? ?? 0;
                  if (productData != null && returnedQty > 0) {
                    returnedItems.add(LoadedReturnItem( returnRequestItemId: itemMap['id'] as int, orderItemId: itemMap['order_item_id'] as int, productId: productData['id'] as int, productName: productData['product_name'] ?? 'منتج غير معروف', returnedQuantity: returnedQty, originalUnitPrice: unitPrice,));
                    cardCalculatedAmount += (unitPrice * returnedQty);
                  }
                }
                return Card(
                  margin: const EdgeInsets.only(bottom: 16), elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded( child: Text( 'طلب مرتجع #$requestId', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),)),
                        if (isLoading) const SizedBox( width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                        else Row( mainAxisSize: MainAxisSize.min, children: [
                          IconButton( padding: EdgeInsets.zero, constraints: const BoxConstraints(), icon: const Icon(Icons.check_circle_outline, color: Colors.green, size: 28), tooltip: 'موافقة', onPressed: () => _approveRequest(r),),
                          const SizedBox(width: 8),
                          IconButton( padding: EdgeInsets.zero, constraints: const BoxConstraints(), icon: const Icon(Icons.highlight_off, color: Colors.red, size: 28), tooltip: 'رفض', onPressed: () => _rejectRequestWithReason(r),), // No reason passed here
                        ],),
                      ],),
                      const Divider(height: 16),
                      _buildDetailRow('مقدم الطلب:', buyerName),
                      if (originalOrderId != null) _buildDetailRow('الطلب الأصلي:', '#$originalOrderId'),
                      _buildDetailRow('تاريخ الطلب:', dateStr),
                      if (returnedItems.isNotEmpty) ...[
                        Padding( padding: const EdgeInsets.only(top: 5.0, bottom: 2.0), child: Text('البنود المطلوبة للإرجاع:', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),),
                        Padding( padding: const EdgeInsets.only(right: 8.0), child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: returnedItems.map((item) => Text('- ${item.productName} (الكمية: ${item.returnedQuantity})', style: theme.textTheme.bodyMedium)).toList(),),),
                        _buildDetailRow('المبلغ المحسوب:', '${cardCalculatedAmount.toStringAsFixed(2)} ر.ي'),
                      ] else const Text('لم يتم العثور على تفاصيل البنود لهذا المرتجع.', style: TextStyle(color: Colors.orange)),
                      _buildDetailRow('السبب:', reason),
                      if (imageUrl != null && imageUrl.isNotEmpty) _buildImageViewer(imageUrl),
                    ],),),);},);},),),);
  }

  // --- الدوال المساعدة (_buildDetailRow, _buildImageViewer) ---
  Widget _buildDetailRow(String label, String value) {
    final theme = Theme.of(context);
    return Padding( padding: const EdgeInsets.symmetric(vertical: 3.0), child: Row( crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: theme.textTheme.labelLarge?.copyWith( color: theme.colorScheme.onSurfaceVariant)), const SizedBox(width: 8),
      Expanded( child: Text( value.isEmpty ? '-' : value, style: theme.textTheme.bodyMedium, ),),],),);
  }
  Widget _buildImageViewer(String imageUrl) {
    final theme = Theme.of(context);
    return Padding( padding: const EdgeInsets.only(top: 8.0), child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('الصورة المرفقة:', style: theme.textTheme.labelLarge), const SizedBox(height: 4),
      InkWell(
        onTap: () => showDialog( context: context, builder: (_) => Dialog( child: InteractiveViewer( panEnabled: false, minScale: 0.5, maxScale: 4,
          child: Image.network( imageUrl, fit: BoxFit.contain,
            loadingBuilder: (ctx, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator()),
            errorBuilder: (c, e, s) => const Center(child: Text("خطأ تحميل الصورة")),),),),),
        child: ClipRRect( borderRadius: BorderRadius.circular(8), child: Image.network( imageUrl, height: 150, width: double.infinity, fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) => progress == null ? child : Container( height: 150, color: Colors.grey[200], child: const Center(child: CircularProgressIndicator())),
          errorBuilder: (context, error, stackTrace) => Container( height: 150, color: Colors.grey[200], child: const Center( child: Icon(Icons.broken_image_outlined, color: Colors.grey)),),),),),
    ],),);
  }
} // نهاية الكلاس

/* --- كود SQL لإنشاء دالة RPC للتحقق من الكمية (نفذه في Supabase) ---
 CREATE OR REPLACE FUNCTION public.get_total_approved_return_quantity (
    p_order_item_id bigint,
    p_exclude_request_id bigint default null -- لتمرير معرف الطلب الحالي واستبعاده
 )
 RETURNS integer -- تأكد من أن النوع المرجع هو integer
 LANGUAGE sql
 STABLE -- Important: Indicates the function doesn't modify the database
 AS $$
    SELECT COALESCE(SUM(rri.quantity), 0)::integer -- Cast to integer
    FROM public.return_request_items rri
    JOIN public.return_requests rr ON rri.return_request_id = rr.id
    WHERE rri.order_item_id = p_order_item_id
      AND rr.status = 'موافق' -- Match the exact status string used in your app
      AND (p_exclude_request_id IS NULL OR rr.id != p_exclude_request_id);
 $$;

 -- Grant permission to call the function (using the correct signature)
 GRANT EXECUTE ON FUNCTION public.get_total_approved_return_quantity(bigint, bigint) TO authenticated;
 -- GRANT EXECUTE ON FUNCTION public.get_total_approved_return_quantity(bigint) TO authenticated; -- This line is likely not needed if default is null

 */