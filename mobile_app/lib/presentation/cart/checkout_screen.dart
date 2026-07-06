// lib/presentation/cart/checkout_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/product.dart'; // تأكد من المسار الصحيح
import 'cart_provider.dart';
import 'cash_payment_upload_screen.dart'; // <-- شاشة رفع الإيصال الجديدة
// استورد شاشات أخرى إذا لزم الأمر

class CheckoutScreen extends StatefulWidget {
  final int storeId;

  const CheckoutScreen({
    Key? key,
    required this.storeId,
  }) : super(key: key);

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _noteController = TextEditingController();
  bool _isLoading = false;
  // تأكد أن 'عند الاستلام' أو 'آجل' هو خيار افتراضي منطقي
  String _selectedPaymentType = 'عند الاستلام';
  // أضف الحالة الجديدة لقائمة الحالات في قاعدة البيانات إذا لم تكن موجودة
  // مثال: ALTER TYPE public.your_order_status_enum ADD VALUE 'pending_payment';
  // مثال: ALTER TYPE public.your_order_status_enum ADD VALUE 'payment_submitted';
  final List<String> _paymentTypes = ['نقدًا', 'عند الاستلام', 'آجل'];

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  // --- Handler الرئيسي لتحديد مسار العملية ---
  Future<void> _handleCheckout(CartProvider cartProvider) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يجب تسجيل الدخول أولاً')),
        );
      }
      return;
    }

    // منع الضغط المتكرر
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      if (_selectedPaymentType == 'نقدًا') {
        await _createPendingCashOrderAndNavigate(cartProvider, user.id);
      } else {
        await _submitDirectOrder(cartProvider, user.id);
      }
    } catch (e) {
      debugPrint('Checkout Handling Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ غير متوقع: $e')),
        );
      }
    } finally {
      // تأكد من إيقاف التحميل فقط إذا كان الـ widget ما زال موجوداً
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }


  // --- دالة إنشاء الطلب وتوجيه للدفع النقدي ---
  Future<void> _createPendingCashOrderAndNavigate(CartProvider cartProvider, String userId) async {
    try {
      final total = cartProvider.totalPrice;

      // 1. إنشاء الطلب بحالة 'بانتظار الدفع'
      final orderResponse = await Supabase.instance.client.from('orders').insert({
        'user_id': userId,
        'store_id': widget.storeId,
        'total_price': total,
        'note': _noteController.text.trim(),
        'status': 'pending_payment', // <-- حالة جديدة للطلب
        'payment_type': 'نقدًا',
        'is_approved': false, // غير موافق عليه بعد
      }).select().single();

      final orderId = orderResponse['id'];

      // 2. إضافة بنود الطلب (Order Items)
      final orderItems = cartProvider.items.entries.map((entry) {
        final product = entry.key;
        final qty = entry.value;
        return {
          'order_id': orderId,
          'product_id': product.id,
          'quantity': qty,
          'unit_price': product.price,
        };
      }).toList();
      await Supabase.instance.client.from('order_items').insert(orderItems);

      // 3. تفريغ السلة بعد نجاح إنشاء الطلب
      cartProvider.clearCart();

      // 4. الانتقال لشاشة رفع الإيصال
      if (mounted) {
        Navigator.pushReplacement( // استبدال الشاشة الحالية
          context,
          MaterialPageRoute(
            builder: (_) => CashPaymentUploadScreen(
              orderId: orderId,
              storeId: widget.storeId,
              totalAmount: total,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Cash Order Creation Error: $e');
      // لا نوقف التحميل هنا لأنه سيتم في finally الخارجية
      rethrow; // أعد رمي الخطأ ليتم التقاطه في _handleCheckout
    }
  }

  // --- دالة إرسال الطلبات المباشرة (عند الاستلام، آجل) ---
  Future<void> _submitDirectOrder(CartProvider cartProvider, String userId) async {
    try {
      final total = cartProvider.totalPrice;
      final isDeferred = _selectedPaymentType == 'آجل';

      // 1. إنشاء الطلب بالحالة المناسبة (تم الطلب أو قيد الموافقة)
      final orderResponse = await Supabase.instance.client.from('orders').insert({
        'user_id': userId,
        'store_id': widget.storeId,
        'total_price': total,
        'note': _noteController.text.trim(),
        'status': isDeferred ? 'قيد الموافقة' : 'تم الطلب',
        'payment_type': _selectedPaymentType,
        'is_approved': !isDeferred, // الموافقة الفورية لغير الآجل
      }).select().single();

      final orderId = orderResponse['id'];

      // 2. إضافة بنود الطلب
      final orderItems = cartProvider.items.entries.map((entry) {
        // ... (نفس منطق الـ mapping)
        return {
          'order_id': orderId,
          'product_id': entry.key.id,
          'quantity': entry.value,
          'unit_price': entry.key.price,
        };
      }).toList();
      await Supabase.instance.client.from('order_items').insert(orderItems);

      // 3. *** ملاحظة: لا يتم إنشاء قيد مالي هنا ***
      //    القيود المالية لـ COD أو آجل تتم عند تأكيد الاستلام أو الموافقة.

      // 4. تفريغ السلة
      cartProvider.clearCart();

      // 5. العودة وإظهار رسالة نجاح
      if (mounted) {
        Navigator.popUntil(context, (route) => route.isFirst); // العودة للشاشة الرئيسية مثلاً
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ تم إرسال الطلب بنجاح')),
        );
      }
    } catch (e) {
      debugPrint('Direct Order Submission Error: $e');
      // لا نوقف التحميل هنا لأنه سيتم في finally الخارجية
      rethrow; // أعد رمي الخطأ ليتم التقاطه في _handleCheckout
    }
  }


  @override
  Widget build(BuildContext context) {
    final cartProvider = context.watch<CartProvider>();
    final items = cartProvider.items;
    final theme = Theme.of(context);

    // ---- واجهة المستخدم ----
    return Scaffold(
      appBar: AppBar(
        title: const Text('تأكيد الطلب'),
      ),
      body: items.isEmpty
          ? Center(
        child: Text(
          'لا توجد عناصر في السلة للمتابعة.',
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
      )
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ... (عرض تفاصيل الطلب والإجمالي - لا تغيير هنا) ...
            Text('تفاصيل الطلب:', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    ...items.entries.map((entry) { /* ... ListTile لكل منتج ... */
                      final product = entry.key;
                      final qty = entry.value;
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                        title: Text(product.productName, style: theme.textTheme.bodyLarge),
                        subtitle: Text('${product.price.toStringAsFixed(2)} ر.ي × $qty', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        trailing: Text('${(product.price * qty).toStringAsFixed(2)} ر.ي', style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                      );
                    }),
                    const Divider(height: 16, thickness: 1),
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8.0),
                      title: Text('الإجمالي', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      trailing: Text('${cartProvider.totalPrice.toStringAsFixed(2)} ر.ي', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('اختر طريقة الدفع:', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            // --- Dropdown لاختيار طريقة الدفع ---
            DropdownButtonFormField<String>(
              value: _selectedPaymentType,
              items: _paymentTypes
                  .map((type) => DropdownMenuItem(value: type, child: Text(type)))
                  .toList(),
              // تحديث الحالة عند التغيير وإعادة بناء الواجهة
              onChanged: (val) => setState(() => _selectedPaymentType = val!),
              decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder() // Use theme's default border
              ),
            ),
            const SizedBox(height: 16),
            // --- حقل الملاحظات ---
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'ملاحظات إضافية (اختياري)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 24),
            // --- زر الإرسال ---
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                // تعطيل الزر أثناء التحميل
                onPressed: _isLoading ? null : () => _handleCheckout(cartProvider),
                icon: _isLoading
                    ? Container(
                  width: 24, height: 24, padding: const EdgeInsets.all(2.0),
                  child: CircularProgressIndicator(color: theme.colorScheme.onPrimary, strokeWidth: 3),
                )
                // تغيير الأيقونة حسب نوع الدفع
                    : Icon(_selectedPaymentType == 'نقدًا'
                    ? Icons.arrow_forward // سهم للمتابعة
                    : Icons.check_circle_outline), // علامة صح للإرسال
                label: Text(
                    _isLoading
                        ? 'جاري المعالجة...'
                    // تغيير النص حسب نوع الدفع
                        : (_selectedPaymentType == 'نقدًا'
                        ? 'متابعة لرفع الإيصال'
                        : 'إتمام وإرسال الطلب')
                ),
                style: ElevatedButton.styleFrom( // Optional: Add padding
                    padding: const EdgeInsets.symmetric(vertical: 12)
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}