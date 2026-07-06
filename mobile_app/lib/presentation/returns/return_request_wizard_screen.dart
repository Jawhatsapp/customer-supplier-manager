// lib/presentation/returns/return_request_screen_simple.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

// نموذج مساعد لعناصر الطلب المعروضة (لا تغيير)
class DisplayOrderItemSimple {
  final int orderItemId;
  final int productId;
  final String productName;
  final int originalQuantity;
  final double unitPrice;
  final TextEditingController quantityController = TextEditingController(text: '0');
  int get returnQuantity => int.tryParse(quantityController.text) ?? 0;

  DisplayOrderItemSimple({
    required this.orderItemId,
    required this.productId,
    required this.productName,
    required this.originalQuantity,
    required this.unitPrice,
  });

  void dispose() {
    quantityController.dispose();
  }
}

// نموذج مساعد لعرض المتاجر في القائمة المنسدلة (لا تغيير)
class StoreSelectionItem {
  final int id;
  final String name;
  final String type;

  StoreSelectionItem({required this.id, required this.name, required this.type});

  String get displayName => '$name (${type == 'supplier' ? 'مورد' : 'تاجر'})';
}


class ReturnRequestScreenSimple extends StatefulWidget {
  final String currentUserId;
  const ReturnRequestScreenSimple({Key? key, required this.currentUserId}) : super(key: key);

  @override
  State<ReturnRequestScreenSimple> createState() => _ReturnRequestScreenSimpleState();
}

class _ReturnRequestScreenSimpleState extends State<ReturnRequestScreenSimple> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;

  StoreSelectionItem? _selectedStore;
  int? _selectedOrderId;

  List<StoreSelectionItem> _allStores = [];
  String? _storeFetchError;
  bool _isFetchingStores = true;

  Future<List<Map<String, dynamic>>>? _ordersFuture;
  List<DisplayOrderItemSimple> _displayItems = [];
  bool _isFetchingItems = false;
  String? _itemFetchError;

  final TextEditingController _reasonCtrl = TextEditingController();
  final TextEditingController _amountCtrl = TextEditingController(text: '0.00');
  File? _selectedImage;
  String? _uploadedImageUrl;
  bool _isUploadingImage = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _fetchAllStores();
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    _amountCtrl.dispose();
    _disposeItemControllers();
    super.dispose();
  }

  void _disposeItemControllers() {
    for (var item in _displayItems) { item.dispose(); }
  }

  Future<void> _fetchAllStores() async {
    if (!mounted) return;
    setState(() { _isFetchingStores = true; _storeFetchError = null; _allStores = []; });
    try {
      final response = await _supabase
          .from('stores')
          .select('id, store_name, store_type');

      final List<StoreSelectionItem> combinedStores =
      List<Map<String, dynamic>>.from(response).map(
              (s) => StoreSelectionItem(
              id: s['id'],
              name: s['store_name'] ?? 'متجر غير مسمى',
              type: s['store_type'] ?? 'unknown'
          )
      ).toList();

      combinedStores.sort((a, b) => a.name.compareTo(b.name));

      if (!mounted) return;
      setState(() { _allStores = combinedStores; });

    } catch (e) {
      print("Error fetching all stores: $e");
      if (!mounted) return;
      setState(() { _storeFetchError = "خطأ في جلب قائمة المتاجر."; });
      if (mounted) _showMsg(_storeFetchError!, isError: true);
    } finally {
      if (mounted) setState(() => _isFetchingStores = false);
    }
  }

  void _onStoreChanged(StoreSelectionItem? selectedStore) {
    if (!mounted) return;
    setState(() {
      _selectedStore = selectedStore;
      _selectedOrderId = null;
      _disposeItemControllers();
      _displayItems = [];
      _amountCtrl.text = '0.00';
      _itemFetchError = null;
      if (_selectedStore != null) {
        _ordersFuture = _fetchUserOrdersInternal(_selectedStore!.id);
      } else {
        _ordersFuture = null;
      }
    });
  }

  Future<List<Map<String, dynamic>>> _fetchUserOrdersInternal(int storeId) async {
    try {
      final response = await _supabase
          .from('orders')
          .select('id, created_at, total_price')
          .eq('store_id', storeId)
          .eq('user_id', widget.currentUserId)
          .in_('status', ['تمت الموافقة', 'تم الدفع', 'مكتمل']) // حالات يمكن الإرجاع منها
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print("Error fetching orders for store $storeId: $e");
      if (mounted) _showMsg("خطأ في جلب الطلبات للمتجر المحدد: $e", isError: true);
      throw Exception("خطأ في جلب الطلبات.");
    }
  }

  void _onOrderChanged(int? selectedOrderId) {
    if (!mounted) return;
    setState(() {
      _selectedOrderId = selectedOrderId;
      _disposeItemControllers();
      _displayItems = [];
      _amountCtrl.text = '0.00';
      _itemFetchError = null;
      if (_selectedOrderId != null) {
        _fetchAndPrepareOrderItems();
      }
    });
  }

  Future<void> _fetchAndPrepareOrderItems() async {
    if (_selectedOrderId == null || !mounted) return;
    setState(() { _isFetchingItems = true; _itemFetchError = null; });
    try {
      final response = await _supabase
          .from('order_items')
          .select('id, product_id, quantity, unit_price, product:products(product_name)')
          .eq('order_id', _selectedOrderId!);
      final itemsData = List<Map<String, dynamic>>.from(response);

      if (!mounted) return;
      setState(() {
        _displayItems = itemsData.map((item) {
          final productData = item['product'] as Map<String, dynamic>?;
          return DisplayOrderItemSimple(
            orderItemId: item['id'] as int,
            productId: item['product_id'] as int,
            productName: productData?['product_name'] ?? 'منتج غير معروف (${item['product_id']})',
            originalQuantity: item['quantity'] as int,
            unitPrice: double.tryParse(item['unit_price'].toString()) ?? 0.0,
          );
        }).toList();
      });
    } catch (e) {
      print("Error fetching order items: $e");
      if (!mounted) return;
      setState(() { _itemFetchError = "خطأ في جلب بنود الطلب."; });
      if (mounted) _showMsg(_itemFetchError!, isError: true);
    } finally {
      if (mounted) setState(() => _isFetchingItems = false);
    }
  }

  void _updateReturnAmount() {
    double total = 0.0;
    for (var item in _displayItems) {
      total += item.unitPrice * item.returnQuantity;
    }
    if (mounted) {
      setState(() { _amountCtrl.text = total.toStringAsFixed(2); });
    }
  }

  void _handleQuantityChange(DisplayOrderItemSimple item, String value) {
    final qty = int.tryParse(value) ?? 0;
    int newQty = qty;
    if (qty < 0) {
      newQty = 0;
    } else if (qty > item.originalQuantity) {
      newQty = item.originalQuantity;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showMsg('الكمية المتاحة ${item.originalQuantity} فقط');
      });
    }

    if (newQty.toString() != item.quantityController.text) {
      item.quantityController.text = newQty.toString();
      item.quantityController.selection = TextSelection.fromPosition(TextPosition(offset: item.quantityController.text.length));
    }
    _updateReturnAmount();
  }

  Future<void> _pickAndUploadImage() async {
    if (_isUploadingImage || !mounted) return;
    final picker = ImagePicker();
    XFile? pickedFile;
    try { pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 75); }
    catch (e) { print("Image picker error: $e"); if (mounted) _showMsg("خطأ أثناء اختيار الصورة: $e", isError: true); return; }
    if (pickedFile == null || !mounted) return;
    setState(() { _selectedImage = File(pickedFile!.path); _isUploadingImage = true; _uploadedImageUrl = null; });
    try {
      final fileBytes = await _selectedImage!.readAsBytes();
      final fileExtension = p.extension(pickedFile.path);
      final fileName = 'return_${widget.currentUserId}_${DateTime.now().millisecondsSinceEpoch}$fileExtension';
      final filePath = '${widget.currentUserId}/$fileName';
      await _supabase.storage.from('return-images').uploadBinary(filePath, fileBytes, fileOptions: const FileOptions(cacheControl: '3600', upsert: false));
      final publicUrl = _supabase.storage.from('return-images').getPublicUrl(filePath);
      if (mounted) { setState(() { _uploadedImageUrl = publicUrl; }); }
    } catch (e) {
      print("Image upload error: $e");
      if (mounted) _showMsg('فشل رفع الصورة: $e', isError: true);
      if (mounted) { setState(() { _selectedImage = null; _uploadedImageUrl = null; }); }
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  void _removeImage() {
    if (!mounted) return;
    setState(() { _selectedImage = null; _uploadedImageUrl = null; });
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedStore == null || _selectedOrderId == null) {
      _showMsg('يرجى التأكد من اختيار المتجر والطلب.', isError: true); return;
    }
    if (!_displayItems.any((item) => item.returnQuantity > 0)) {
      _showMsg('يرجى تحديد كمية الإرجاع لمنتج واحد على الأقل.', isError: true); return;
    }

    if (!mounted) return;
    setState(() => _isSubmitting = true);

    try {
      final calculatedAmount = double.tryParse(_amountCtrl.text) ?? 0.0;
      final response = await _supabase.from('return_requests').insert({
        'store_id': _selectedStore!.id, 'order_id': _selectedOrderId, 'user_id': widget.currentUserId,
        'amount': calculatedAmount > 0 ? calculatedAmount : null, 'reason': _reasonCtrl.text.trim().isEmpty ? null : _reasonCtrl.text.trim(),
        'image_url': _uploadedImageUrl, 'status': 'قيد المراجعة', 'created_at': DateTime.now().toIso8601String(),
      }).select('id').single();
      final returnRequestId = response['id'] as int?;
      if (returnRequestId == null) throw Exception('فشل في إنشاء طلب المرتجع الرئيسي.');

      final List<Map<String, dynamic>> itemsToInsert = _displayItems.where((item) => item.returnQuantity > 0)
          .map((item) => { 'return_request_id': returnRequestId, 'order_item_id': item.orderItemId, 'quantity': item.returnQuantity, }).toList();
      if (itemsToInsert.isEmpty) { await _supabase.from('return_requests').delete().eq('id', returnRequestId); throw Exception('لم يتم تحديد أي بنود للإرجاع.'); }
      await _supabase.from('return_request_items').insert(itemsToInsert);

      if (!mounted) return;
      _showMsg('تم إرسال طلب المرتجع بنجاح', success: true);
      Navigator.pop(context, true);

    } catch (e) {
      print("Error submitting return request: $e");
      if (mounted) _showMsg('خطأ في إرسال الطلب: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showMsg(String msg, {bool success = false, bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar( content: Text(msg), duration: Duration(seconds: success ? 2 : 3), backgroundColor: success ? Colors.green : (isError ? Theme.of(context).colorScheme.error : null)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLoading = _isFetchingStores || _isUploadingImage || _isSubmitting;

    return Scaffold(
      appBar: AppBar(
        title: const Text('طلب مرتجع جديد'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. اختيار المتجر
              DropdownButtonFormField<StoreSelectionItem>(
                value: _selectedStore,
                hint: const Text('اختر المتجر (تاجر أو مورد)'),
                isExpanded: true,
                items: _isFetchingStores
                    ? [const DropdownMenuItem(enabled: false, child: Center(child: SizedBox(width:20, height: 20, child: CircularProgressIndicator(strokeWidth: 2,))))]
                    : _allStores.map((store) => DropdownMenuItem<StoreSelectionItem>(
                  value: store,
                  child: Text(store.displayName),
                )).toList(),
                onChanged: isLoading ? null : _onStoreChanged,
                validator: (value) => value == null ? 'يرجى اختيار المتجر' : null,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: 'المتجر*',
                  errorText: _storeFetchError,
                ),
              ),
              const SizedBox(height: 16),

              // 2. اختيار الطلب
              if (_selectedStore != null && _storeFetchError == null)
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _ordersFuture,
                  builder: (context, snapshot) {
                    Widget content;
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      content = const Center(child: CircularProgressIndicator());
                    } else if (snapshot.hasError) {
                      content = Center(child: Text("خطأ: ${snapshot.error}", style: TextStyle(color: theme.colorScheme.error)));
                    } else {
                      final orders = snapshot.data ?? [];
                      if (orders.isEmpty) {
                        content = const Text('لا توجد طلبات مكتملة متاحة للإرجاع من هذا المتجر.');
                      } else {
                        content = DropdownButtonFormField<int>(
                          value: _selectedOrderId,
                          hint: const Text('اختر الطلب المراد إرجاعه'),
                          isExpanded: true,
                          items: orders.map((order) {
                            final orderId = order['id'] as int;
                            final date = DateTime.tryParse(order['created_at'] ?? '')?.toLocal();
                            final dateStr = date != null ? '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}' : '?';
                            final price = double.tryParse(order['total_price']?.toString() ?? '0')?.toStringAsFixed(2) ?? '0.00';
                            return DropdownMenuItem<int>(value: orderId, child: Text('طلب #$orderId ($dateStr) - $price ر.ي', overflow: TextOverflow.ellipsis));
                          }).toList(),
                          onChanged: isLoading ? null : _onOrderChanged,
                          validator: (value) => value == null ? 'يرجى اختيار الطلب' : null,
                          decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'الطلب*'),
                        );
                      }
                    }
                    return AnimatedSize(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 16.0),
                        child: content,
                      ),
                    );
                  },
                ),

              // 3. قائمة البنود
              if (_selectedOrderId != null)
                Padding(
                  padding: const EdgeInsets.only(top: 20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('حدد كميات المنتجات المراد إرجاعها:', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      if (_isFetchingItems)
                        const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator()))
                      else if (_itemFetchError != null)
                        Center(child: Text(_itemFetchError!, style: TextStyle(color: theme.colorScheme.error)))
                      else if (_displayItems.isEmpty)
                          const Text('لا توجد بنود في هذا الطلب.')
                        else
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _displayItems.length,
                            itemBuilder: (context, index) {
                              final item = _displayItems[index];
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column( crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(item.productName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                            Text('الكمية الأصلية: ${item.originalQuantity} | السعر: ${item.unitPrice.toStringAsFixed(2)}', style: theme.textTheme.bodySmall),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      SizedBox(
                                        width: 85,
                                        child: TextFormField(
                                          controller: item.quantityController,
                                          textAlign: TextAlign.center,
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                          decoration: const InputDecoration(
                                              labelText: 'للإرجاع',
                                              border: OutlineInputBorder(),
                                              isDense: true,
                                              contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 4)
                                          ),
                                          onChanged: (value) => _handleQuantityChange(item, value),
                                          validator: (value) {
                                            final qty = int.tryParse(value ?? '');
                                            if (qty == null) return '!';
                                            if (qty < 0) return '<0!';
                                            if (qty > item.originalQuantity) return '> متاح!';
                                            return null;
                                          },
                                        ),
                                      )
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                      const SizedBox(height: 16),
                      // 4. المبلغ المحسوب
                      TextField(
                        controller: _amountCtrl,
                        readOnly: true,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          labelText: 'المبلغ الإجمالي المتوقع للمرتجع',
                          suffixText: 'ر.ي',
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          border: const OutlineInputBorder(),
                        ),
                        style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                      ),
                    ],
                  ),
                ),

              // 5. حقل السبب
              Padding(
                padding: const EdgeInsets.only(top: 24.0),
                child: TextFormField(
                  controller: _reasonCtrl,
                  decoration: const InputDecoration(
                    labelText: 'سبب الإرجاع (اختياري)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.note_alt_outlined),
                  ),
                  maxLines: 3,
                ),
              ),
              const SizedBox(height: 16),

              // 6. رفع الصورة
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('إرفاق صورة (اختياري):', style: theme.textTheme.titleSmall),
                  if (_selectedImage != null && !_isUploadingImage)
                    IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: _removeImage, tooltip: 'إزالة الصورة'),
                ],
              ),
              const SizedBox(height: 8),
              if (_isUploadingImage)
                const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator()))
              else if (_selectedImage != null)
                Center(child: Image.file(_selectedImage!, height: 150, fit: BoxFit.contain))
              else
                Container(
                  height: 100, width: double.infinity, alignment: Alignment.center,
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)),
                  child: const Text('لم يتم اختيار صورة'),
                ),
              const SizedBox(height: 8),
              if (!_isUploadingImage)
                Center(
                  child: TextButton.icon(
                    icon: const Icon(Icons.attach_file),
                    label: Text(_selectedImage == null ? 'اختيار ورفع صورة' : 'تغيير الصورة'),
                    onPressed: _pickAndUploadImage,
                  ),
                ),

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),

              // 7. زر الإرسال
              ElevatedButton.icon(
                icon: _isSubmitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.send_outlined),
                label: Text(_isSubmitting ? 'جاري الإرسال...' : 'إرسال طلب المرتجع'),
                onPressed: isLoading ? null : _submitRequest,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}