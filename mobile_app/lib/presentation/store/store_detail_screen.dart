import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/product.dart';
import 'product_detail_screen.dart';
import 'add_edit_product_screen.dart';

class StoreDetailScreen extends StatefulWidget {
  final String storeId;   // أو int
  final String userRole;  // 'client' | 'retailer' | 'supplier'

  const StoreDetailScreen({
    Key? key,
    required this.storeId,
    required this.userRole,
  }) : super(key: key);

  @override
  State<StoreDetailScreen> createState() => _StoreDetailScreenState();
}

class _StoreDetailScreenState extends State<StoreDetailScreen> {
  Map<String, dynamic>? _storeData;
  late Future<List<Product>> _productsFuture;
  bool _isLoadingStoreInfo = true;

  @override
  void initState() {
    super.initState();
    // جلب معلومات المتجر
    _fetchStoreData();
    // جلب المنتجات
    _productsFuture = _fetchStoreProducts();
  }

  /// جلب معلومات المتجر من جدول (retailer_stores أو supplier_stores) عبر الصيغة الأحدث
  Future<void> _fetchStoreData() async {
    try {
      final data = await Supabase.instance.client
          .from('retailer_stores')           // عدّل الاسم إذا كان مختلفًا
          .select()
          .eq('id', widget.storeId)
          .maybeSingle();

      // في حال لم يوجد سجل مطابق
      if (data == null) {
        setState(() {
          _storeData = null;
          _isLoadingStoreInfo = false;
        });
        return;
      }
      // إن وُجد
      setState(() {
        _storeData = data as Map<String, dynamic>;
        _isLoadingStoreInfo = false;
      });
    } catch (error) {
      // في حال وجود خطأ، يمكنك طباعته أو التعامل معه
      debugPrint('Error fetching store info: $error');
      setState(() {
        _storeData = null;
        _isLoadingStoreInfo = false;
      });
    }
  }

  /// جلب قائمة المنتجات دون استخدام .execute()
  Future<List<Product>> _fetchStoreProducts() async {
    try {
      final data = await Supabase.instance.client
          .from('products')
          .select()                        // يمكن تحديد الأعمدة بدل * إن أحببت
          .eq('store_id', widget.storeId);

      // إذا كانت النتيجة فارغة أو null
      if (data == null) {
        return [];
      }

      // data يفترض أن يكون List<dynamic> لعدة صفوف
      final List<dynamic> dataList = data as List<dynamic>;
      return dataList.map((json) => Product.fromMap(json)).toList();
    } catch (error) {
      // رمي الخطأ ليتم التعامل معه في FutureBuilder
      throw Exception('Error fetching products: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // 1) شريط علوي من نوع SliverAppBar مع صورة خلفية (بانر للمتجر)
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(_storeData?['store_name'] ?? '...'),
              background: _storeData?['banner_url'] != null
                  ? Image.network(
                _storeData!['banner_url'],
                fit: BoxFit.cover,
              )
                  : Container(color: Colors.blueGrey),
            ),
          ),
          // 2) عرض بعض معلومات المتجر في الأعلى - اختياري
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: _isLoadingStoreInfo
                  ? const Center(child: CircularProgressIndicator())
                  : _storeData == null
                  ? const Center(child: Text('لا توجد بيانات للمتجر.'))
                  : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _storeData!['store_name'] ?? '',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _storeData!['address'] ?? 'لا يوجد عنوان',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  // أي معلومات أخرى حول المتجر
                ],
              ),
            ),
          ),
          // 3) قسم عرض المنتجات
          SliverFillRemaining(
            child: FutureBuilder<List<Product>>(
              future: _productsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Center(
                    child: Text('حدث خطأ في تحميل المنتجات: ${snapshot.error}'),
                  );
                } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('لا توجد منتجات.'));
                } else {
                  final products = snapshot.data!;
                  // هنا يمكن عرض المنتجات في Grid أو List
                  return GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2, // عدد الأعمدة
                      childAspectRatio: 0.7,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    padding: const EdgeInsets.all(16),
                    itemCount: products.length,
                    itemBuilder: (ctx, index) {
                      final product = products[index];
                      return GestureDetector(
                        onTap: () {
                          // إذا العميل: شاشة التفاصيل أو أضف للسلة
                          // إذا صاحب المتجر: ممكن تحرير المنتج
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  ProductDetailScreen(product: product,
                                    ),
                            ),
                          );
                        },
                        child: Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: product.imageUrl != null
                                    ? ClipRRect(
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(16),
                                    topRight: Radius.circular(16),
                                  ),
                                  child: Image.network(
                                    product.imageUrl!,
                                    fit: BoxFit.cover,
                                  ),
                                )
                                    : Container(
                                  decoration: BoxDecoration(
                                    color: Colors.grey[300],
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(16),
                                      topRight: Radius.circular(16),
                                    ),
                                  ),
                                  child: const Icon(Icons.image, size: 50),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  product.productName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Text(
                                  '\$${product.price}',
                                  style: TextStyle(color: colorScheme.primary),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                }
              },
            ),
          ),
        ],
      ),
      // 4) زر إضافة منتج يظهر فقط إن كان المستخدم هو صاحب المتجر (retailer أو supplier)
      floatingActionButton:
      (widget.userRole == 'retailer' || widget.userRole == 'supplier')
          ? FloatingActionButton(
        onPressed: () async {
          // الانتقال لشاشة إضافة منتج
          final storeIdInt = int.tryParse(widget.storeId) ?? 0;
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AddEditProductScreen(storeId: storeIdInt),
            ),
          );
          // بعد العودة، أعد التحميل
          setState(() {
            _productsFuture = _fetchStoreProducts();
          });
        },
        child: const Icon(Icons.add),
      )
          : null,
    );
  }
}
