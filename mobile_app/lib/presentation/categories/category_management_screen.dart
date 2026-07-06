import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CategoryManagementScreen extends StatefulWidget {
  final int storeId;
  const CategoryManagementScreen({Key? key, required this.storeId}) : super(key: key);

  @override
  State<CategoryManagementScreen> createState() => _CategoryManagementScreenState();
}

class _CategoryManagementScreenState extends State<CategoryManagementScreen> {
  late Future<List<Map<String, dynamic>>> _categoriesFuture;

  @override
  void initState() {
    super.initState();
    _categoriesFuture = _fetchCategories();
  }

  Future<List<Map<String, dynamic>>> _fetchCategories() async {
    final res = await Supabase.instance.client
        .from('categories')
        .select()
        .eq('store_id', widget.storeId)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> _refresh() async {
    setState(() {
      _categoriesFuture = _fetchCategories();
    });
  }

  /// فتح نافذة إضافة/تعديل
  Future<void> _addOrEditCategory({Map<String, dynamic>? category}) async {
    final isEdit = category != null;
    final nameCtrl = TextEditingController(text: category?['category_name'] ?? '');
    final descCtrl = TextEditingController(text: category?['description'] ?? '');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'تعديل تصنيف' : 'إضافة تصنيف'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'اسم التصنيف'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: 'وصف التصنيف (اختياري)'),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              final newName = nameCtrl.text.trim();
              final newDesc = descCtrl.text.trim();
              if (newName.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('أدخل اسم التصنيف')),
                );
                return;
              }
              try {
                if (!isEdit) {
                  // إضافة
                  await Supabase.instance.client.from('categories').insert({
                    'store_id': widget.storeId,
                    'category_name': newName,
                    if (newDesc.isNotEmpty) 'description': newDesc,
                  });
                } else {
                  // تعديل
                  await Supabase.instance.client
                      .from('categories')
                      .update({
                    'category_name': newName,
                    if (newDesc.isNotEmpty) 'description': newDesc,
                  })
                      .eq('id', category!['id']);
                }
                Navigator.pop(ctx, true);
                _refresh();
              } catch (e) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('خطأ: $e')),
                );
              }
            },
            child: Text(isEdit ? 'حفظ' : 'إضافة'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteCategory(int categoryId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل تريد حذف هذا التصنيف؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('نعم')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      // بالاعتماد على ON DELETE SET NULL في قاعدة البيانات
      await Supabase.instance.client
          .from('categories')
          .delete()
          .eq('id', categoryId);

      _refresh();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ عند الحذف: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة التصنيفات'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          )
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _categoriesFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('خطأ: ${snap.error}'));
          }
          final cats = snap.data ?? [];
          if (cats.isEmpty) {
            return const Center(child: Text('لا توجد تصنيفات حالياً.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            itemCount: cats.length,
            itemBuilder: (ctx, i) {
              final cat = cats[i];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: ListTile(
                  title: Text(cat['category_name'] ?? 'بدون اسم'),
                  subtitle: Text(cat['description'] ?? ''),
                  trailing: PopupMenuButton<String>(
                    onSelected: (val) {
                      if (val == 'edit') {
                        _addOrEditCategory(category: cat);
                      } else if (val == 'delete') {
                        _deleteCategory(cat['id'] as int);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('تعديل')),
                      PopupMenuItem(value: 'delete', child: Text('حذف')),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addOrEditCategory(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
