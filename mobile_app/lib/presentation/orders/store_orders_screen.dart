// lib/presentation/store/store_orders_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../orders/order_detail_screen.dart';

class StoreOrdersScreen extends StatefulWidget {
  final int storeId;

  const StoreOrdersScreen({Key? key, required this.storeId}) : super(key: key);

  @override
  State<StoreOrdersScreen> createState() => _StoreOrdersScreenState();
}

class _StoreOrdersScreenState extends State<StoreOrdersScreen> {
  late Future<List<Map<String, dynamic>>> _ordersFuture;

  @override
  void initState() {
    super.initState();
    _ordersFuture = _fetchStoreOrders();
  }

  Future<List<Map<String, dynamic>>> _fetchStoreOrders() async {
    final result = await Supabase.instance.client.rpc('get_store_orders', params: {
      'store_id_param': widget.storeId,
    });
    return List<Map<String, dynamic>>.from(result);
  }

  Future<void> _refreshOrders() async {
    setState(() {
      _ordersFuture = _fetchStoreOrders();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('طلبات المتجر')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _ordersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('حدث خطأ: ${snapshot.error}'));
          }

          final orders = snapshot.data ?? [];
          if (orders.isEmpty) {
            return const Center(child: Text('لا توجد طلبات حالياً.'));
          }

          return RefreshIndicator(
            onRefresh: _refreshOrders,
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: orders.length,
              itemBuilder: (context, index) {
                final order = orders[index];
                final orderId = order['id'];
                final customerName = order['full_name'] ?? 'بدون اسم';
                final totalPrice = order['total_price'] ?? 0;
                final status = order['status'] ?? 'غير محدد';
                final createdAt = order['created_at']?.toString().split('T').first ?? '';

                return Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 3,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text('طلب رقم: $orderId'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('العميل: $customerName'),
                        Text('المبلغ: $totalPrice ر.ي'),
                        Text('الحالة: $status'),
                        Text('تاريخ الإنشاء: $createdAt'),
                      ],
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => OrderDetailScreen(orderId: orderId),
                        ),
                      );

                      // إذا تمت الموافقة على الطلب أو حدث تعديل، أعد التحديث
                      if (result == true) {
                        _refreshOrders();
                      }
                    },
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
