// lib/presentation/orders/approve_pending_orders_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Provider;
import '../../providers/auth_provider.dart';
import 'order_detail_screen.dart';

// نموذج مساعد للعرض
class PendingApprovalItem {
  final ApprovalItemType type;
  final int id;
  final int orderId;
  final String buyerName;
  final String? buyerUserId;
  final double totalAmount;
  final DateTime createdAt;
  final String initialStatus;
  final String? paymentNote;
  final String? bankName;
  final String? receiptUrl;
  final Map<String, dynamic> originalData;

  PendingApprovalItem({
    required this.type, required this.id, required this.orderId, required this.buyerName,
    this.buyerUserId, required this.totalAmount, required this.createdAt,
    required this.initialStatus, this.paymentNote, this.bankName, this.receiptUrl,
    required this.originalData,
  });
}

enum ApprovalItemType { deferredOrder, cashPayment }

// الشاشة الرئيسية
class ApprovePendingOrdersScreen extends StatefulWidget {
  final int storeId;
  const ApprovePendingOrdersScreen({Key? key, required this.storeId}) : super(key: key);

  @override
  State<ApprovePendingOrdersScreen> createState() => _ApprovePendingOrdersScreenState();
}

class _ApprovePendingOrdersScreenState extends State<ApprovePendingOrdersScreen> {
  String _currentFilter = 'الكل';
  late Future<List<PendingApprovalItem>> _pendingItemsFuture;
  int? _processingItemId;
  String? _ownerId;

  @override
  void initState() {
    super.initState();
    _ownerId = Provider.of<AuthProvider>(context, listen: false).currentUser?.id;
    _fetchPendingItems();
  }

  void _fetchPendingItems() {
    if (!mounted) return;
    if (_ownerId == null) {
      setState(() { _pendingItemsFuture = Future.value([]); });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('خطأ: لا يمكن تحديد مالك المتجر الحالي.')));
      });
      return;
    }
    setState(() {
      _pendingItemsFuture = _loadPendingItems(_currentFilter);
    });
  }

  Future<List<PendingApprovalItem>> _loadPendingItems(String filter) async {
    final supabase = Supabase.instance.client;
    List<PendingApprovalItem> combinedList = [];
    Set<String> userIdsToFetch = {};
    List<Map<String, dynamic>> rawOrders = [];
    List<Map<String, dynamic>> rawPayments = [];

    try {
      if (filter == 'الكل' || filter == 'آجل') {
        final deferredOrdersRes = await supabase.from('orders').select('id, user_id, total_price, created_at, status').eq('store_id', widget.storeId).eq('payment_type', 'آجل').eq('status', 'قيد الموافقة').order('created_at', ascending: true);
        rawOrders = List<Map<String, dynamic>>.from(deferredOrdersRes);
        for (var order in rawOrders) { if (order['user_id'] != null) userIdsToFetch.add(order['user_id'] as String); }
      }
      if (filter == 'الكل' || filter == 'نقدي') {
        final cashPaymentsRes = await supabase.from('payments').select('id, order_id, store_id, bank_name, account_number, receipt_url, note, status, created_at, order:orders(user_id, total_price)').eq('store_id', widget.storeId).eq('status', 'بانتظار الموافقة').order('created_at', ascending: true);
        rawPayments = List<Map<String, dynamic>>.from(cashPaymentsRes);
        for (var payment in rawPayments) { final orderData = payment['order']; if (orderData != null && orderData['user_id'] != null) userIdsToFetch.add(orderData['user_id'] as String); }
      }

      Map<String, Map<String, dynamic>> profilesMap = {};
      if (userIdsToFetch.isNotEmpty) {
        final profilesRes = await supabase.from('profiles').select('id, first_name, last_name, role').in_('id', userIdsToFetch.toList());
        for (var profile in List<Map<String, dynamic>>.from(profilesRes)) { profilesMap[profile['id'] as String] = profile; }
      }

      for (var order in rawOrders) {
        final userId = order['user_id'] as String?;
        final profileData = userId != null ? profilesMap[userId] : null;
        String buyerName = 'مستخدم';
        if (profileData != null) { final fname = profileData['first_name'] ?? ''; final lname = profileData['last_name'] ?? ''; buyerName = '$fname $lname'.trim(); if (buyerName.isEmpty) buyerName = 'مستخدم (${userId?.substring(0, 6)}...)'; }
        combinedList.add(PendingApprovalItem(type: ApprovalItemType.deferredOrder, id: order['id'], orderId: order['id'], buyerName: buyerName, buyerUserId: userId, totalAmount: double.tryParse(order['total_price'].toString()) ?? 0.0, createdAt: DateTime.tryParse(order['created_at']?.toString() ?? '') ?? DateTime.now(), initialStatus: order['status'] ?? 'قيد الموافقة', originalData: order,));
      }
      for (var payment in rawPayments) {
        final orderData = payment['order'];
        final userId = orderData?['user_id'] as String?;
        final profileData = userId != null ? profilesMap[userId] : null;
        String buyerName = 'مستخدم';
        if (profileData != null) { final fname = profileData['first_name'] ?? ''; final lname = profileData['last_name'] ?? ''; buyerName = '$fname $lname'.trim(); if (buyerName.isEmpty) buyerName = 'مستخدم (${userId?.substring(0, 6)}...)'; }
        combinedList.add(PendingApprovalItem(type: ApprovalItemType.cashPayment, id: payment['id'], orderId: payment['order_id'], buyerName: buyerName, buyerUserId: userId, totalAmount: double.tryParse(orderData?['total_price']?.toString() ?? '0.0') ?? 0.0, createdAt: DateTime.tryParse(payment['created_at']?.toString() ?? '') ?? DateTime.now(), initialStatus: payment['status'] ?? 'بانتظار الموافقة', paymentNote: payment['note'], bankName: payment['bank_name'], receiptUrl: payment['receipt_url'], originalData: payment,));
      }

      combinedList.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return combinedList;

    } catch (e) {
      print("Error loading pending items (Filter: $filter): $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ في تحميل البيانات: ${e.toString()}')));
      return [];
    }
  }

  Future<int?> _fetchUserStoreId(String userId) async {
    final supabase = Supabase.instance.client;
    try {
      final storeResponse = await supabase
          .from('stores')
          .select('id')
          .eq('owner_id', userId)
          .maybeSingle();
      return storeResponse?['id'] as int?;
    } catch (e) {
      print("Error fetching user's store ID for mirroring: $e");
      return null;
    }
  }

  Future<void> _createFinancialEntry({
    required int storeId, int? orderId, required String paymentType,
    required String status, required String debtorId, required String creditorId,
    required double amount, required String noteSuffix, required String lineDescSuffix,
  }) async {
    final supabase = Supabase.instance.client;
    try {
      final trxRes = await supabase.from('financial_transactions').insert({
        'store_id': storeId, 'order_id': orderId, 'payment_type': paymentType, 'status': status, 'note': noteSuffix,
      }).select('id').single();
      final transactionId = trxRes['id'];
      final lines = [
        { 'transaction_id': transactionId, 'user_id': debtorId, 'related_user_id': creditorId, 'type': 'عليه', 'amount': amount, 'description': '$lineDescSuffix (مدين)' },
        { 'transaction_id': transactionId, 'user_id': creditorId, 'related_user_id': debtorId, 'type': 'له', 'amount': amount, 'description': '$lineDescSuffix (دائن)' },
      ];
      await supabase.from('transaction_lines').insert(lines);
      print("Financial entry created successfully for trx ID: $transactionId in store $storeId");
    } catch(e) {
      print("Error creating financial entry in store $storeId: $e");
      throw Exception("خطأ في إنشاء القيد المالي: $e");
    }
  }

  Future<void> _updateStockForOrder(int orderId, SupabaseClient supabase) async {
    try {
      final orderItems = await supabase.from('order_items').select('product_id, quantity').eq('order_id', orderId);
      if (orderItems.isEmpty) return;
      List<Map<String, dynamic>> stockMovementsData = [];
      for (var item in orderItems) {
        final productId = item['product_id'] as int?;
        final quantity = item['quantity'] as int?;
        if (productId != null && quantity != null && quantity > 0) {
          await supabase.rpc('decrement_product_stock', params: {'p_product_id': productId, 'p_quantity': quantity});
          stockMovementsData.add({'product_id': productId, 'delta': -quantity, 'reason': 'بيع - طلب رقم #$orderId موافق عليه'});
        }
      }
      if (stockMovementsData.isNotEmpty) await supabase.from('stock_movements').insert(stockMovementsData);
    } catch (e) {
      print("Error updating stock for order $orderId: $e");
      throw Exception("خطأ أثناء تحديث المخزون: $e");
    }
  }

  Future<void> _sendNotification({ required String userId, required String title, required String message }) async {
    try { await Supabase.instance.client.from('notifications').insert({'user_id': userId, 'title': title, 'message': message}); }
    catch (e) { print("Error sending notification to $userId: $e"); }
  }

  Future<void> _approveItem(PendingApprovalItem item) async {
    if (_processingItemId == item.id || _ownerId == null) return;
    setState(() => _processingItemId = item.id);
    try {
      if (item.type == ApprovalItemType.cashPayment) {
        await _approveCashPayment(item);
      } else if (item.type == ApprovalItemType.deferredOrder) {
        await _approveDeferredOrder(item);
      }
      _showMsg('تمت الموافقة بنجاح.', success: true);
      _fetchPendingItems();
    } catch (e) {
      print("Approve Error (ID: ${item.id}, Type: ${item.type}): $e");
      _showMsg('خطأ أثناء الموافقة: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _processingItemId = null);
    }
  }

  Future<void> _rejectItem(PendingApprovalItem item) async {
    if (_processingItemId == item.id) return;
    final confirm = await showDialog<bool>(
      context: context, builder: (ctx) => AlertDialog(
      title: const Text('تأكيد الرفض'),
      content: const Text('هل أنت متأكد من رفض هذا الطلب/الدفعة؟'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        TextButton(style: TextButton.styleFrom(foregroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('نعم، رفض')),
      ],
    ),
    );
    if (confirm != true) return;

    setState(() => _processingItemId = item.id);
    try {
      if (item.type == ApprovalItemType.cashPayment) {
        await _rejectCashPayment(item);
      } else if (item.type == ApprovalItemType.deferredOrder) {
        await _rejectDeferredOrder(item);
      }
      _showMsg('تم الرفض بنجاح.');
      _fetchPendingItems();
    } catch (e) {
      print("Reject Error (ID: ${item.id}, Type: ${item.type}): $e");
      _showMsg('خطأ أثناء الرفض: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _processingItemId = null);
    }
  }

  Future<void> _approveCashPayment(PendingApprovalItem item) async {
    final supabase = Supabase.instance.client;
    if (item.buyerUserId == null || _ownerId == null) throw Exception("Buyer or Owner ID missing.");
    final buyerId = item.buyerUserId!;
    final ownerId = _ownerId!;

    await supabase.from('payments').update({'status': 'موافقة'}).eq('id', item.id);
    await supabase.from('orders').update({'status': 'تم الدفع', 'is_approved': true}).eq('id', item.orderId);

    // إنشاء القيد الأساسي
    await _createFinancialEntry(
        storeId: widget.storeId, orderId: item.orderId, paymentType: 'نقدًا', status: 'approved',
        debtorId: ownerId, creditorId: buyerId, amount: item.totalAmount,
        noteSuffix: 'دفعة نقدية للطلب #${item.orderId}', lineDescSuffix: 'دفعة نقدية للطلب #${item.orderId}'
    );

    // إنشاء قيد مرآة إذا كان المشتري لديه متجر
    final buyerStoreId = await _fetchUserStoreId(buyerId);
    if (buyerStoreId != null && buyerStoreId != widget.storeId) {
      await _createFinancialEntry(
          storeId: buyerStoreId, orderId: item.orderId, paymentType: 'نقدًا', status: 'approved',
          debtorId: ownerId, creditorId: buyerId, amount: item.totalAmount,
          noteSuffix: 'مرآة: دفعة نقدية إلى متجر #${widget.storeId}', lineDescSuffix: 'مرآة: دفعة نقدية إلى متجر #${widget.storeId}'
      );
    }

    await _updateStockForOrder(item.orderId, supabase);
    await _sendNotification(userId: buyerId, title: 'تمت الموافقة على دفعتك', message: 'تم قبول الإيصال وتأكيد الدفع للطلب رقم ${item.orderId}.');
  }

  Future<void> _rejectCashPayment(PendingApprovalItem item) async {
    final supabase = Supabase.instance.client;
    await supabase.from('payments').update({'status': 'مرفوضة'}).eq('id', item.id);
    await supabase.from('orders').update({'status': 'الدفع مرفوض'}).eq('id', item.orderId);
    if (item.buyerUserId != null) await _sendNotification(userId: item.buyerUserId!, title: 'تم رفض دفعتك', message: 'نأسف، تم رفض إيصال الدفع الذي أرسلته للطلب رقم ${item.orderId}.');
  }

  Future<void> _approveDeferredOrder(PendingApprovalItem item) async {
    final supabase = Supabase.instance.client;
    if (item.buyerUserId == null || _ownerId == null) throw Exception("Buyer or Owner ID missing.");
    final buyerId = item.buyerUserId!;
    final ownerId = _ownerId!;

    await supabase.from('orders').update({'status': 'تمت الموافقة', 'is_approved': true}).eq('id', item.id);

    // إنشاء القيد المالي الأساسي في متجر البائع
    await _createFinancialEntry(
        storeId: widget.storeId, orderId: item.id, paymentType: 'آجل', status: 'approved',
        debtorId: buyerId, creditorId: ownerId, amount: item.totalAmount,
        noteSuffix: 'طلب آجل موافق عليه #${item.id}', lineDescSuffix: 'طلب آجل موافق عليه #${item.id}'
    );

    // إنشاء القيد المرآة في متجر المشتري (إذا كان لديه متجر)
    final buyerStoreId = await _fetchUserStoreId(buyerId);
    if (buyerStoreId != null && buyerStoreId != widget.storeId) {
      print("Creating mirrored transaction for user $buyerId in their store $buyerStoreId");
      await _createFinancialEntry(
          storeId: buyerStoreId, orderId: item.id, paymentType: 'آجل', status: 'approved',
          debtorId: buyerId, creditorId: ownerId, amount: item.totalAmount,
          noteSuffix: 'مرآة: طلب آجل من متجر #${widget.storeId}', lineDescSuffix: 'مرآة: طلب آجل من متجر #${widget.storeId}'
      );
    }

    await _updateStockForOrder(item.id, supabase);
    await _sendNotification(userId: buyerId, title: 'تمت الموافقة على طلبك الآجل', message: 'تمت الموافقة على طلبك رقم ${item.orderId}.');
  }

  Future<void> _rejectDeferredOrder(PendingApprovalItem item) async {
    final supabase = Supabase.instance.client;
    await supabase.from('orders').update({'status': 'مرفوض', 'is_approved': false}).eq('id', item.id);
    if (item.buyerUserId != null) await _sendNotification(userId: item.buyerUserId!, title: 'تم رفض طلبك الآجل', message: 'نأسف، تم رفض طلبك الآجل رقم ${item.orderId}.');
  }

  void _showMsg(String msg, {bool success = false, bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: isError ? Colors.red : (success ? Colors.green : null)));
  }

  void _showReceiptDialog(BuildContext context, String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) { _showMsg('لا يوجد رابط إيصال لعرضه.'); return; }
    showDialog(context: context, builder: (_) => Dialog( child: Padding( padding: const EdgeInsets.all(8.0), child: InteractiveViewer( panEnabled: false, minScale: 0.5, maxScale: 4, child: Image.network(imageUrl, fit: BoxFit.contain, loadingBuilder: (context, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator()), errorBuilder: (context, error, stackTrace) => const Center(child: Text('خطأ في تحميل الإيصال', textAlign: TextAlign.center))),),),),);
  }

  Widget _buildActionButton(IconData icon, Color color, String tooltip, VoidCallback? onPressed) {
    return IconButton(icon: Icon(icon), color: onPressed == null ? Colors.grey : color, tooltip: tooltip, iconSize: 26, visualDensity: VisualDensity.compact, padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: onPressed);
  }

  String _formatDateTime(DateTime dt) {
    try {
      return DateFormat('yyyy/MM/dd hh:mm a', Localizations.localeOf(context).languageCode).format(dt.toLocal());
    } catch (_) {
      return DateFormat('yyyy/MM/dd hh:mm a', 'en_US').format(dt.toLocal());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('مراجعة الطلبات (${_currentFilter})'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_alt_outlined),
            tooltip: 'تصفية حسب النوع',
            onSelected: (String result) {
              if (_currentFilter != result) {
                setState(() { _currentFilter = result; _fetchPendingItems(); });
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(value: 'الكل', child: Text('الكل', style: TextStyle(fontWeight: _currentFilter == 'الكل' ? FontWeight.bold : FontWeight.normal))),
              PopupMenuItem<String>(value: 'نقدي', child: Text('نقدي (إيصال)', style: TextStyle(fontWeight: _currentFilter == 'نقدي' ? FontWeight.bold : FontWeight.normal))),
              PopupMenuItem<String>(value: 'آجل', child: Text('آجل', style: TextStyle(fontWeight: _currentFilter == 'آجل' ? FontWeight.bold : FontWeight.normal))),
            ],
          ),
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'تحديث القائمة', onPressed: _fetchPendingItems),
        ],
      ),
      body: FutureBuilder<List<PendingApprovalItem>>(
        future: _pendingItemsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(16.0), child: Text('حدث خطأ: ${snapshot.error}', textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.error))));

          final items = snapshot.data ?? [];
          if (items.isEmpty) return Center(child: Text('لا توجد طلبات "${_currentFilter}" قيد المراجعة حالياً.', style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey[600])));

          return RefreshIndicator(
            onRefresh: () async => _fetchPendingItems(),
            child: ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final isProcessing = (item.id == _processingItemId);
                final bool isCashPayment = item.type == ApprovalItemType.cashPayment;

                return Opacity(
                  opacity: isProcessing ? 0.5 : 1.0,
                  child: Card(
                    elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), margin: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      onTap: isProcessing ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: item.orderId))),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Chip( label: Text( isCashPayment ? 'دفعة نقدية' : 'طلب آجل', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)), backgroundColor: isCashPayment ? Colors.orange.shade700 : Colors.blue.shade700, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0), visualDensity: VisualDensity.compact),
                              const Spacer(),
                              if(isProcessing) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              else Row( mainAxisSize: MainAxisSize.min, children: [
                                _buildActionButton(Icons.check_circle_outline, Colors.green.shade600, 'موافقة', () => _approveItem(item)),
                                const SizedBox(width: 12),
                                _buildActionButton(Icons.highlight_off, Colors.red.shade600, 'رفض', () => _rejectItem(item)),
                              ],),
                            ],),
                            const SizedBox(height: 8),
                            Text('طلب رقم: ${item.orderId}', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                            Text('المشتري: ${item.buyerName}', style: theme.textTheme.bodyMedium),
                            Text('المبلغ: ${item.totalAmount.toStringAsFixed(2)} ر.ي', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                            if(isCashPayment && item.bankName != null) Text('البنك: ${item.bankName}', style: theme.textTheme.bodySmall),
                            if(isCashPayment && item.paymentNote != null && item.paymentNote!.isNotEmpty) Padding( padding: const EdgeInsets.only(top: 4.0), child: Text('ملاحظة الدفع: ${item.paymentNote}', style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic))),
                            Text('تاريخ الإنشاء: ${_formatDateTime(item.createdAt)}', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[700])),
                            if (isCashPayment) ...[
                              const Divider(height: 16, thickness: 0.8),
                              Align( alignment: AlignmentDirectional.centerEnd, child: TextButton.icon( icon: const Icon(Icons.receipt_long_outlined, size: 18), label: const Text('عرض الإيصال'), style: TextButton.styleFrom( padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), visualDensity: VisualDensity.compact), onPressed: isProcessing ? null : () => _showReceiptDialog(context, item.receiptUrl))),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}