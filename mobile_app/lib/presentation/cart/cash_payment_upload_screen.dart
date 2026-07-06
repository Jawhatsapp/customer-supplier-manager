// lib/presentation/cart/cash_payment_upload_screen.dart

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';

// --- استيراد النموذج الجديد ---
import '../../models/store_payment_method_model.dart';

// --- تم إزالة تعريف PaymentInstitution القديم ---

// --- الشاشة الفعلية ---
class CashPaymentUploadScreen extends StatefulWidget {
  final int orderId;
  final int storeId; // المتجر الذي يتم الدفع له
  final double totalAmount;

  const CashPaymentUploadScreen({
    Key? key,
    required this.orderId,
    required this.storeId,
    required this.totalAmount,
  }) : super(key: key);

  @override
  _CashPaymentUploadScreenState createState() => _CashPaymentUploadScreenState();
}

class _CashPaymentUploadScreenState extends State<CashPaymentUploadScreen> {
  // --- تحديث متغيرات الحالة ---
  StorePaymentMethod? _selectedMethod; // بدلاً من _selectedInstitution
  List<StorePaymentMethod> _paymentMethods = []; // بدلاً من _institutions
  bool _isLoadingMethods = true; // بدلاً من _isLoadingInstitutions
  // --------------------------
  bool _isUploading = false;
  File? _receiptImage;
  final _picker = ImagePicker();
  final _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchStorePaymentMethods(); // استدعاء الدالة الجديدة
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  // --- تعديل دالة جلب البيانات ---
  Future<void> _fetchStorePaymentMethods() async {
    if (!mounted) return;
    setState(() {
      _isLoadingMethods = true;
      _paymentMethods = []; // مسح القائمة القديمة
      _selectedMethod = null; // إلغاء التحديد السابق
    });

    try {
      final response = await Supabase.instance.client
          .from('store_payment_methods') // <-- اسم الجدول الجديد
          .select()
          .eq('store_id', widget.storeId) // <-- فلتر حسب المتجر
          .eq('is_active', true); // <-- فقط الطرق النشطة

      if (mounted) {
        setState(() {
          _paymentMethods = List<StorePaymentMethod>.from(
              response.map((data) => StorePaymentMethod.fromJson(data))
          );
        });
      }
    } catch (e) {
      debugPrint("Error fetching store payment methods for store ${widget.storeId}: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل بيانات الدفع للمتجر: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingMethods = false);
      }
    }
  }
  // --------------------------

  // --- اختيار صورة من المعرض أو الكاميرا (لا تغيير هنا) ---
  Future<void> _pickImage(ImageSource source) async {
    if (_isUploading) return;
    try {
      final pickedFile = await _picker.pickImage(source: source, imageQuality: 70);
      if (pickedFile != null && mounted) {
        setState(() { _receiptImage = File(pickedFile.path); });
      }
    } catch(e) {
      debugPrint("Image picking error: $e");
      if (mounted) { _showMsg('حدث خطأ أثناء اختيار الصورة.'); }
    }
  }

  // --- تعديل دالة رفع الإيصال واستخدام البيانات الجديدة ---
  Future<void> _uploadReceiptAndSubmitPayment() async {
    if (_receiptImage == null) { _showMsg('يرجى اختيار صورة الإيصال أولاً'); return; }
    // --- التحقق من _selectedMethod ---
    if (_selectedMethod == null) { _showMsg('يرجى اختيار طريقة الدفع'); return; }
    // ------------------------------
    if (_isUploading) return;
    setState(() => _isUploading = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception("User not logged in");

      // 1. رفع الصورة (لا تغيير هنا)
      final imageExtension = _receiptImage!.path.split('.').last.toLowerCase();
      final imageBytes = await _receiptImage!.readAsBytes();
      final imagePath = 'public/receipts/${widget.storeId}/${widget.orderId}-${DateTime.now().millisecondsSinceEpoch}.$imageExtension';
      await Supabase.instance.client.storage.from('receipts').uploadBinary(imagePath, imageBytes, fileOptions: FileOptions(cacheControl: '3600', upsert: false, contentType: 'image/$imageExtension'));
      final receiptPublicUrl = Supabase.instance.client.storage.from('receipts').getPublicUrl(imagePath);

      // 2. إنشاء سجل جديد في جدول `payments` (استخدام بيانات _selectedMethod)
      await Supabase.instance.client.from('payments').insert({
        'order_id': widget.orderId,
        'store_id': widget.storeId,
        // --- استخدام الحقول الصحيحة من _selectedMethod ---
        'bank_name': _selectedMethod!.institutionName, // <-- اسم المؤسسة
        'account_number': _selectedMethod!.accountNumber, // <-- رقم الحساب
        // ------------------------------------------
        'receipt_url': receiptPublicUrl,
        'note': _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
        'status': 'بانتظار الموافقة', // الحالة الافتراضية
      });

      // 3. تحديث حالة الطلب (لا تغيير هنا)
      await Supabase.instance.client
          .from('orders')
          .update({'status': 'payment_submitted'})
          .eq('id', widget.orderId);

      // 4. إظهار رسالة نجاح والعودة (لا تغيير هنا)
      if (mounted) {
        _showMsg('✅ تم رفع الإيصال، سيتم مراجعة دفعتك قريباً.', success: true);
        Navigator.popUntil(context, (route) => route.isFirst);
      }

    } catch (e) {
      debugPrint("Receipt Upload/Payment Submit Error: $e");
      if (mounted) {
        String errorMessage = 'حدث خطأ أثناء إرسال الدفع.';
        if (e is StorageException) { errorMessage = 'خطأ في رفع الصورة: ${e.message}'; }
        else if (e is PostgrestException) { errorMessage = 'خطأ في قاعدة البيانات: ${e.message}'; }
        _showMsg(errorMessage); // استخدام الدالة المساعدة
      }
    } finally {
      if (mounted) { setState(() => _isUploading = false); }
    }
  }
  // ----------------------------------------------------

  // --- دالة عرض الرسائل ---
  void _showMsg(String msg, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(msg),
          backgroundColor: success ? Colors.green : Theme.of(context).colorScheme.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('رفع إيصال دفع لطلب #${widget.orderId}'),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () { if (!_isUploading) { Navigator.of(context).pop(); } }
        ),
      ),
      body: _isLoadingMethods // <-- استخدام الحالة الجديدة
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // عرض المبلغ المطلوب (لا تغيير)
            Center( child: Text( 'المبلغ المطلوب للدفع: ${widget.totalAmount.toStringAsFixed(2)} ر.ي', style: theme.textTheme.titleLarge?.copyWith( color: theme.colorScheme.primary, fontWeight: FontWeight.bold), textAlign: TextAlign.center, ),),
            const SizedBox(height: 20),

            // --- 1. اختيار طريقة الدفع (تحديث لاستخدام StorePaymentMethod) ---
            Text('1. اختر الحساب البنكي أو طريقة الدفع للتحويل:', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<StorePaymentMethod>( // <-- النوع الجديد
              value: _selectedMethod, // <-- القيمة الجديدة
              hint: const Text('- اختر طريقة الدفع -'),
              isExpanded: true,
              items: _paymentMethods.isEmpty // <-- القائمة الجديدة
                  ? [ const DropdownMenuItem(enabled: false, child: Text('لا توجد طرق دفع متاحة لهذا المتجر')) ]
                  : _paymentMethods.map((method) { // <-- التكرار على القائمة الجديدة
                return DropdownMenuItem<StorePaymentMethod>( // <-- النوع الجديد
                  value: method, // <-- القيمة هي الكائن نفسه
                  child: Text(method.institutionName, overflow: TextOverflow.ellipsis), // <-- عرض اسم المؤسسة
                );
              }).toList(),
              onChanged: _isLoadingMethods || _paymentMethods.isEmpty
                  ? null
                  : (value) {
                if(mounted) setState(() => _selectedMethod = value ); // <-- تحديث الحالة الجديدة
              },
              decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12)
              ),
              validator: (value) => value == null ? 'يرجى اختيار طريقة الدفع' : null,
            ),
            const SizedBox(height: 16),
            // ------------------------------------------------------------

            // --- عرض تفاصيل الطريقة المختارة (تحديث لاستخدام _selectedMethod) ---
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              child: _selectedMethod == null
                  ? const SizedBox.shrink()
                  : Card(
                elevation: 2,
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('تفاصيل حساب: ${_selectedMethod!.institutionName}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const Divider(height: 10, thickness: 1),
                        SelectableText('اسم المستفيد: ${_selectedMethod!.accountName}'),
                        SelectableText('رقم الحساب/الآيبان: ${_selectedMethod!.accountNumber}'),
                        if (_selectedMethod!.details != null && _selectedMethod!.details!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text('ملاحظات إضافية: ${_selectedMethod!.details}'),
                          ),
                      ]
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // ---------------------------------------------------------------

            // 2. تعليمات التحويل (لا تغيير)
            Text('2. قم بتحويل المبلغ المطلوب باستخدام التفاصيل أعلاه.', style: theme.textTheme.titleMedium),
            const SizedBox(height: 20),

            // 3. رفع الإيصال (لا تغيير في منطق العرض والأزرار)
            Text('3. ارفع صورة واضحة لإيصال التحويل:', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (_receiptImage != null)
              Padding( padding: const EdgeInsets.symmetric(vertical: 10), child: Stack( alignment: Alignment.topLeft, children: [ Image.file( _receiptImage!, height: 200, width: double.infinity, fit: BoxFit.contain ), if (!_isUploading) IconButton( icon: const Icon(Icons.delete_outline, color: Colors.red, size: 28), tooltip: 'إزالة الصورة', onPressed: () => setState(() => _receiptImage = null), style: IconButton.styleFrom(backgroundColor: Colors.black54),) ],) )
            else
              Container( height: 150, decoration: BoxDecoration( color: theme.colorScheme.surfaceVariant.withOpacity(0.5), borderRadius: BorderRadius.circular(8), border: Border.all(color: theme.colorScheme.outline) ), child: Center( child: Text('لم يتم اختيار صورة الإيصال', style: theme.textTheme.bodyMedium) ), ),
            const SizedBox(height: 12),
            Row( mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              ElevatedButton.icon( icon: const Icon(Icons.photo_library_outlined), label: const Text('المعرض'), onPressed: _isUploading ? null : () => _pickImage(ImageSource.gallery), style: ElevatedButton.styleFrom(minimumSize: const Size(140, 40)) ),
              ElevatedButton.icon( icon: const Icon(Icons.camera_alt_outlined), label: const Text('الكاميرا'), onPressed: _isUploading ? null : () => _pickImage(ImageSource.camera), style: ElevatedButton.styleFrom(minimumSize: const Size(140, 40)) ),
            ],
            ),
            const SizedBox(height: 20),

            // 4. حقل الملاحظة أو المرجع (لا تغيير)
            Text('4. أدخل اسم المحول أو الرقم المرجعي (اختياري):', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField( controller: _noteController, decoration: const InputDecoration( hintText: 'مثال: حوالة أحمد محمد، أو رقم عملية البنك', border: OutlineInputBorder(), prefixIcon: Icon(Icons.notes), ), enabled: !_isUploading,),
            const SizedBox(height: 30),

            // --- زر التأكيد والرفع (تحديث التحقق من _selectedMethod) ---
            ElevatedButton.icon(
              onPressed: (_receiptImage == null || _selectedMethod == null || _isUploading) // <-- التحقق من _selectedMethod
                  ? null
                  : _uploadReceiptAndSubmitPayment,
              icon: _isUploading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                  : const Icon(Icons.cloud_upload_outlined),
              label: Padding( padding: const EdgeInsets.symmetric(vertical: 14.0), child: Text(_isUploading ? 'جاري الإرسال...' : 'تأكيد رفع الإيصال'),),
              style: ElevatedButton.styleFrom( textStyle: theme.textTheme.titleMedium,),
            ),
            // -----------------------------------------------------
          ],
        ),
      ),
    );
  }
}