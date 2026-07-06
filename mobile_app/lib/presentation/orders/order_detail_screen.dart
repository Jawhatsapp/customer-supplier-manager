// lib/presentation/orders/order_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OrderDetailScreen extends StatefulWidget {
  final int orderId;

  const OrderDetailScreen({Key? key, required this.orderId}) : super(key: key);

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late Future<Map<String, dynamic>?> _orderDataFuture;
  late Future<List<Map<String, dynamic>>> _orderItemsFuture;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    _orderDataFuture = _fetchOrderData();
    _orderItemsFuture = _fetchOrderItems();
  }

  /// ✅ جلب بيانات الطلب + بيانات العميل من جدول profiles يدويًا
  Future<Map<String, dynamic>?> _fetchOrderData() async {
    final order = await Supabase.instance.client
        .from('orders')
        .select('*')
        .eq('id', widget.orderId)
        .maybeSingle();

    if (order != null && order['user_id'] != null) {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('first_name, last_name')
          .eq('id', order['user_id'])
          .maybeSingle();

      order['profile'] = profile;
    }

    return order;
  }

  /// ✅ جلب تفاصيل المنتجات المطلوبة فقط دون صور
  Future<List<Map<String, dynamic>>> _fetchOrderItems() async {
    final result = await Supabase.instance.client
        .from('order_items')
        .select('quantity, unit_price, products(product_name)')
        .eq('order_id', widget.orderId);
    return List<Map<String, dynamic>>.from(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تفاصيل الطلب')),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _orderDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('❌ حدث خطأ أثناء تحميل الطلب:\n${snapshot.error}'));
          }

          if (snapshot.data == null) {
            return const Center(child: Text('❌ لم يتم العثور على بيانات الطلب.'));
          }

          final order = snapshot.data!;
          final profile = order['profile'];
          final userName =
              '${profile?['first_name'] ?? 'مستخدم'} ${profile?['last_name'] ?? ''}';

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                title: Text('رقم الطلب: ${order['id']}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('العميل: $userName'),
                    Text('طريقة الدفع: ${order['payment_type']}'),
                    Text('الحالة: ${order['status']}'),
                    Text('الإجمالي: ${order['total_price']} ر.ي'),
                    Text('تاريخ الإنشاء: ${order['created_at'].toString().split("T").first}'),
                  ],
                ),
              ),
              const Divider(),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
                child: Text(
                  'تفاصيل الأصناف المطلوبة:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _orderItemsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError || snapshot.data == null) {
                      return const Center(child: Text('❌ تعذر تحميل تفاصيل المنتجات.'));
                    }

                    final items = snapshot.data!;
                    if (items.isEmpty) {
                      return const Center(child: Text('لا توجد أصناف في هذا الطلب.'));
                    }

                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.all(12),
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('الصنف')),
                          DataColumn(label: Text('الكمية')),
                          DataColumn(label: Text('سعر الوحدة')),
                          DataColumn(label: Text('الإجمالي الفرعي')),
                        ],
                        rows: items.map((item) {
                          final name = item['products']['product_name'] ?? '-';
                          final qty = item['quantity'] ?? 0;
                          final price = double.tryParse(item['unit_price'].toString()) ?? 0.0;
                          final subtotal = price * qty;

                          return DataRow(cells: [
                            DataCell(Text(name)),
                            DataCell(Text(qty.toString())),
                            DataCell(Text('${price.toStringAsFixed(2)} ر.ي')),
                            DataCell(Text('${subtotal.toStringAsFixed(2)} ر.ي')),
                          ]);
                        }).toList(),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
