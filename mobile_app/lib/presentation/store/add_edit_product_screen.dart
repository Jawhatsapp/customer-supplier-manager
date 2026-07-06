// lib/presentation/store/add_edit_product_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/product.dart';

class AddEditProductScreen extends StatefulWidget {
  final int storeId;
  final Product? product; // إذا != null => تعديل، وإلا إضافة جديد

  const AddEditProductScreen({
    Key? key,
    required this.storeId,
    this.product,
  }) : super(key: key);

  @override
  State<AddEditProductScreen> createState() => _AddEditProductScreenState();
}

class _AddEditProductScreenState extends State<AddEditProductScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl  = TextEditingController();
  final _descCtrl  = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();

  File? _imageFile;
  String? _oldImageUrl;
  bool _isLoading = false;

  // ---- جديد: حقل التصنيف
  int? _selectedCategoryId;
  late Future<List<Map<String, dynamic>>> _categoriesFuture;

  @override
  void initState() {
    super.initState();

    // إذا شاشة تعديل، نعبي القيم
    if (widget.product != null) {
      _nameCtrl.text  = widget.product!.productName;
      _descCtrl.text  = widget.product!.product_description;
      _priceCtrl.text = widget.product!.price.toString();
      _stockCtrl.text = widget.product!.stock.toString();
      _oldImageUrl    = widget.product!.imageUrl;
      _selectedCategoryId = widget.product!.categoryId; // ← تعبئة التصنيف
    }

    // تحميل التصنيفات للمتجر
    _categoriesFuture = _fetchCategories();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _fetchCategories() async {
    final cats = await Supabase.instance.client
        .from('categories')
        .select('id, category_name')
        .eq('store_id', widget.storeId)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(cats);
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _imageFile = File(picked.path);
      });
    }
  }

  Future<String?> _uploadImage(File file) async {
    try {
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}${p.extension(file.path)}';

      await Supabase.instance.client.storage
          .from('product-images')
          .upload(fileName, file, fileOptions: const FileOptions(upsert: true));

      final publicUrl = Supabase.instance.client.storage
          .from('product-images')
          .getPublicUrl(fileName);

      return publicUrl;
    } catch (e) {
      debugPrint('Upload error: $e');
      return null;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    // 1) رفع الصورة إن وُجدت
    String? imageUrl = _oldImageUrl; // في حالة عدم تغيير الصورة
    if (_imageFile != null) {
      final uploadedUrl = await _uploadImage(_imageFile!);
      if (uploadedUrl == null) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشل رفع الصورة')),
        );
        return;
      }
      imageUrl = uploadedUrl;
    }

    try {
      // 2) تجهيز الداتا
      final priceVal = double.tryParse(_priceCtrl.text.trim());
      final stockVal = int.tryParse(_stockCtrl.text.trim());
      if (priceVal == null || stockVal == null) {
        throw Exception('السعر أو الكمية غير صالحين');
      }

      final productData = {
        'store_id': widget.storeId,
        'product_name': _nameCtrl.text.trim(),
        'product_description': _descCtrl.text.trim(),
        'price': priceVal,
        'stock': stockVal,
        'image_url': imageUrl,
        'category_id': _selectedCategoryId,
      };

      //  تنفيذ insert أو update
      final supabase = Supabase.instance.client;
      if (widget.product == null) {
        await supabase.from('products').insert(productData);
      } else {
        await supabase
            .from('products')
            .update(productData)
            .eq('id', widget.product!.id);
      }

      if (!mounted) return;
      Navigator.pop(context, true); // رجوع مع علامة نجاح
    } catch (e) {
      debugPrint('Save product error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ أثناء حفظ المنتج: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = (widget.product != null);

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'تعديل منتج' : 'إضافة منتج'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'اسم المنتج'),
                validator: (val) =>
                val == null || val.isEmpty ? 'حقل إجباري' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(labelText: 'وصف المنتج'),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _priceCtrl,
                decoration: const InputDecoration(labelText: 'السعر'),
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _stockCtrl,
                decoration: const InputDecoration(labelText: 'الكمية المتوفرة'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              // Dropdown لاختيار التصنيف
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _categoriesFuture,
                builder: (ctx, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Text('خطأ في جلب التصنيفات: ${snap.error}');
                  }
                  final cats = snap.data ?? [];
                  if (cats.isEmpty) {
                    return const Text('لا توجد تصنيفات لهذا المتجر');
                  }
                  return DropdownButtonFormField<int>(
                    value: _selectedCategoryId,
                    items: cats.map((cat) {
                      final catId   = cat['id'] as int;
                      final catName = cat['category_name'] as String;
                      return DropdownMenuItem<int>(
                        value: catId,
                        child: Text(catName),
                      );
                    }).toList(),
                    decoration: const InputDecoration(labelText: 'التصنيف'),
                    onChanged: (val) {
                      setState(() {
                        _selectedCategoryId = val;
                      });
                    },
                  );
                },
              ),
              const SizedBox(height: 16),
              // الصورة
              if (_imageFile != null)
                Image.file(_imageFile!, height: 120)
              else if (_oldImageUrl != null && _oldImageUrl!.isNotEmpty)
                Image.network(_oldImageUrl!, height: 120)
              else
                Container(
                  height: 120,
                  color: Colors.grey[300],
                  child: const Center(child: Text('لا توجد صورة')),
                ),
              TextButton(
                onPressed: _pickImage,
                child: const Text('اختيار صورة'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isLoading ? null : _save,
                child: Text(_isLoading
                    ? 'جاري الحفظ ...'
                    : (isEdit ? 'حفظ التعديلات' : 'إضافة المنتج')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
