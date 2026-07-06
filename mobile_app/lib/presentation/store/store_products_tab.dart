// lib/presentation/store/store_products_tab.dart

import 'dart:async'; // <-- استيراد للـ Timer (للـ Debounce)
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Provider;
import '../../../models/product.dart';
import 'add_edit_product_screen.dart';
import 'product_detail_screen.dart';

class StoreProductsTab extends StatefulWidget {
  final int storeId;
  final bool isOwner;

  const StoreProductsTab({
    Key? key,
    required this.storeId,
    required this.isOwner,
  }) : super(key: key);

  @override
  // Note: Changed state class name slightly for clarity if needed elsewhere
  State<StoreProductsTab> createState() => StoreProductsTabState();
}

// Renamed State class for potential external access via GlobalKey
class StoreProductsTabState extends State<StoreProductsTab>
    with SingleTickerProviderStateMixin {

  // --- متغيرات الحالة الجديدة ---
  int? _selectedCategoryId;
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce; // مؤقت لتأخير البحث
  String _searchTerm = ''; // لتخزين مصطلح البحث الحالي

  // --- متغيرات الحالة السابقة ---
  bool _isClient = false; // سنبقيها لتحديد سلوك النقر/المفضلة
  String? _currentUserId;

  late Future<List<Map<String, dynamic>>> _categoriesFuture;
  late Future<List<Product>> _productsFuture;

  // --- متغيرات الأنيميشن (كما هي) ---
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _determineUserRole();
    _categoriesFuture = _fetchCategories();
    _productsFuture = _fetchProducts(); // الجلب الأولي بدون فلتر

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300), // تقليل مدة الأنيميشن قليلاً
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeInOut); // تغيير المنحنى

    // --- إضافة مستمع لحقل البحث للـ Debounce ---
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged); // إزالة المستمع
    _searchController.dispose();
    _debounce?.cancel(); // إلغاء المؤقت عند الخروج
    _animController.dispose();
    super.dispose();
  }

  // --- دوال جلب البيانات (مع تعديل _fetchProducts) ---
  Future<void> _determineUserRole() async {
    // ... (الكود كما هو من الإصدار السابق)
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      _currentUserId = user.id;
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();
      if (profile != null && mounted) { // التحقق من mounted قبل setState
        setState(() {
          _isClient = (profile['role'] == 'client');
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchCategories() async {
    // ... (الكود كما هو من الإصدار السابق)
    final cats = await Supabase.instance.client
        .from('categories')
        .select('id, category_name')
        .eq('store_id', widget.storeId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(cats);
  }

  // --- تعديل دالة جلب المنتجات لتقبل الفلاتر ---
  Future<List<Product>> _fetchProducts({int? categoryId, String? searchTerm}) async {
    print("Fetching products with Category: $categoryId, Search: $searchTerm"); // للتصحيح
    try {
      var query = Supabase.instance.client
          .from('products')
          .select()
          .eq('store_id', widget.storeId);

      // تطبيق فلتر التصنيف
      if (categoryId != null) {
        query = query.eq('category_id', categoryId);
      }

      // تطبيق فلتر البحث (في اسم المنتج والوصف)
      if (searchTerm != null && searchTerm.trim().isNotEmpty) {
        // استخدام or للبحث في أكثر من حقل
        // استخدام ilike للبحث غير الحساس لحالة الأحرف
        // % يعني أي تسلسل من الحروف
        final searchPattern = '%${searchTerm.trim()}%';
        query = query.or(
            'product_name.ilike.$searchPattern,product_description.ilike.$searchPattern'
        );
      }

      if (categoryId != null) {
        query = query.eq('category_id', categoryId); // لا يزال PostgrestFilterBuilder
      }

      final res = await query;
      final List<dynamic> list = (res is List) ? res : [];
      // بدء الأنيميشن عند اكتمال الجلب
      if (mounted) {
        _animController.forward(from: 0.0);
      }
      return list.map((json) => Product.fromMap(json)).toList();
    } catch (e) {
      print("Error fetching products: $e");
      // يمكنك إظهار خطأ للمستخدم هنا إذا أردت
      if(mounted){
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في جلب المنتجات: $e')),
        );
      }
      return []; // إرجاع قائمة فارغة عند الخطأ
    }
  }

  // --- دوال التعامل مع الواجهة ---
  void _onCategorySelected(int? catId) {
    setState(() {
      _selectedCategoryId = catId;
      // إعادة تحميل المنتجات مع التصنيف المختار ومصطلح البحث الحالي
      _productsFuture = _fetchProducts(categoryId: _selectedCategoryId, searchTerm: _searchTerm);
    });
  }

  // --- دالة البحث مع Debounce ---
  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel(); // إلغاء المؤقت السابق إذا كان نشطًا
    _debounce = Timer(const Duration(milliseconds: 500), () { // انتظار 500 ملي ثانية بعد توقف الكتابة
      if (mounted && _searchTerm != _searchController.text.trim()) { // تحقق إذا تغير النص فعلاً
        setState(() {
          _searchTerm = _searchController.text.trim();
          // إعادة تحميل المنتجات مع التصنيف المختار ومصطلح البحث الجديد
          _productsFuture = _fetchProducts(categoryId: _selectedCategoryId, searchTerm: _searchTerm);
        });
      }
    });
  }

  // --- دوال إضافة/تعديل/حذف المنتج (كما هي من الإصدار السابق) ---
  Future<void> openAddProductScreen(BuildContext context) async {
    if (!widget.isOwner) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddEditProductScreen(storeId: widget.storeId),
      ),
    );
    if (result == true && mounted) { // التحقق من mounted
      setState(() {
        _productsFuture = _fetchProducts(categoryId: _selectedCategoryId, searchTerm: _searchTerm); // تحديث مع الفلاتر الحالية
      });
    }
  }

  Future<void> _editProduct(Product product) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddEditProductScreen(storeId: widget.storeId, product: product),
      ),
    );
    if (result == true && mounted) { // التحقق من mounted
      setState(() {
        _productsFuture = _fetchProducts(categoryId: _selectedCategoryId, searchTerm: _searchTerm); // تحديث مع الفلاتر الحالية
      });
    }
  }

  Future<void> _deleteProduct(Product product) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل تريد حذف المنتج "${product.productName}"؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red), // لون زر الحذف
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('نعم، حذف')
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await Supabase.instance.client
          .from('products')
          .delete()
          .eq('id', product.id);

      // محاولة حذف الصورة من Storage (اختياري لكن جيد)
      if (product.imageUrl != null && product.imageUrl!.isNotEmpty) {
        try {
          // استخراج اسم الملف من الرابط
          final uri = Uri.parse(product.imageUrl!);
          // المسار عادة يكون بعد اسم الـ bucket، قد تحتاج لتعديل حسب هيكلك
          final filePath = uri.pathSegments.sublist(uri.pathSegments.indexOf('product-images') + 1).join('/');
          print("Attempting to delete storage object: $filePath");
          await Supabase.instance.client.storage
              .from('product-images') // اسم الـ bucket
              .remove([filePath]);
          print("Storage object deleted successfully.");
        } catch (storageError) {
          print("Could not delete storage object: $storageError. Maybe already deleted or permissions issue.");
          // لا توقف العملية كلها بسبب فشل حذف الصورة، فقط سجل الخطأ
        }
      }

      if (mounted) { // التحقق من mounted
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف المنتج بنجاح'), backgroundColor: Colors.green),
        );
        setState(() {
          _productsFuture = _fetchProducts(categoryId: _selectedCategoryId, searchTerm: _searchTerm); // تحديث مع الفلاتر الحالية
        });
      }
    } catch (e) {
      if (mounted) { // التحقق من mounted
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الحذف: $e')),
        );
      }
      print("Error deleting product: $e");
    }
  }

  // --- بناء واجهة المستخدم ---
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context); // الحصول على الثيم

    return Scaffold(
      // زر الإضافة يبقى كما هو
      floatingActionButton: widget.isOwner
          ? FloatingActionButton(
        onPressed: () => openAddProductScreen(context),
        tooltip: 'إضافة منتج جديد', // إضافة تلميح
        child: const Icon(Icons.add),
      )
          : null,
      body: Column(
        children: [
          // --- شريط البحث ---
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'ابحث عن منتج...',
                prefixIcon: const Icon(Icons.search),
                // إضافة زر لمسح البحث
                suffixIcon: _searchTerm.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    // _onSearchChanged(); // استدعاء يدوي لتحديث النتائج فوراً
                    // أو الاعتماد على المستمع ليعمل بعد المسح
                  },
                )
                    : null,
                isDense: true, // جعل الحقل أصغر قليلاً
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), // تعديل padding
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25.0), // حدود دائرية
                  borderSide: BorderSide(color: Colors.grey[400]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25.0),
                  borderSide: BorderSide(color: Colors.grey[400]!),
                ),
                focusedBorder: OutlineInputBorder( // حدود عند التركيز
                  borderRadius: BorderRadius.circular(25.0),
                  borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
                ),
              ),
            ),
          ),

          // --- شريط التصنيفات ---
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _categoriesFuture,
            builder: (ctx, snapCats) {
              if (snapCats.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                  child: Center(child: SizedBox(height: 36, child: LinearProgressIndicator())), // استخدام LinearProgressIndicator
                );
              }
              // لا تعرض رسالة خطأ هنا إذا فشل جلب التصنيفات، فقط لا تعرض الشريط
              // if (snapCats.hasError) { ... }
              final cats = snapCats.data ?? [];
              // لا تعرض الشريط إذا لم تكن هناك تصنيفات
              if (cats.isEmpty) {
                return const SizedBox.shrink(); // عنصر فارغ لا يأخذ مساحة
              }
              return Container(
                height: 45, // ارتفاع ثابت للشريط
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: cats.length + 1, // +1 لزر "الكل"
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        // زر "الكل"
                        return Padding(
                          padding: const EdgeInsets.only(left: 8.0), // مسافة لليسار
                          child: ChoiceChip(
                            label: const Text('الكل'),
                            selected: _selectedCategoryId == null,
                            onSelected: (_) => _onCategorySelected(null),
                            visualDensity: VisualDensity.compact, // جعل الشريحة أصغر
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                        );
                      } else {
                        final cat = cats[index - 1];
                        final catId   = cat['id'] as int;
                        final catName = cat['category_name'] as String;
                        final isSelected = (_selectedCategoryId == catId);
                        return Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: ChoiceChip(
                            label: Text(catName),
                            selected: isSelected,
                            onSelected: (_) => _onCategorySelected(catId),
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                        );
                      }
                    }
                ),
              );
            },
          ),

          const Divider(height: 1, thickness: 0.5), // فاصل أنحف

          // --- قائمة المنتجات ---
          Expanded(
            child: FutureBuilder<List<Product>>(
              future: _productsFuture,
              builder: (ctx, snapProds) {
                if (snapProds.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapProds.hasError) {
                  return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          'خطأ في تحميل المنتجات: ${snapProds.error}',
                          style: TextStyle(color: theme.colorScheme.error),
                          textAlign: TextAlign.center,
                        ),
                      )
                  );
                }
                final products = snapProds.data ?? [];
                if (products.isEmpty) {
                  return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          _searchTerm.isNotEmpty || _selectedCategoryId != null
                              ? 'لا توجد منتجات تطابق بحثك أو الفلتر الحالي.'
                              : 'لا توجد منتجات في هذا المتجر حالياً.',
                          style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
                          textAlign: TextAlign.center,
                        ),
                      )
                  );
                }

                // استخدام الأنيميشن عند عرض القائمة
                return FadeTransition(
                  opacity: _fadeAnim,
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 80), // زيادة padding السفلي لتجنب FAB
                    itemCount: products.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 2, // عدد أعمدة متجاوب
                      crossAxisSpacing: 10, // تعديل المسافات
                      mainAxisSpacing: 10, // تعديل المسافات
                      childAspectRatio: 0.75, // تعديل نسبة العرض للارتفاع
                    ),
                    itemBuilder: (context, index) {
                      final product = products[index];
                      return _buildProductCard(product); // استخدام الدالة السابقة
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- دالة بناء كارت المنتج (كما هي مع تعديل بسيط) ---
  Widget _buildProductCard(Product product) {
    final theme = Theme.of(context); // الحصول على الثيم
    return InkWell( // استخدام InkWell لتأثير النقر
      onTap: () {
        Navigator.push(
          context,
          // استخدام PageRouteBuilder لتأثير fade
          PageRouteBuilder(
            pageBuilder: (_, animation, __) => FadeTransition(
              opacity: animation,
              child: ProductDetailScreen(
                product: product,
                isOwner: widget.isOwner,
                isClient: _isClient,
              ),
            ),
            transitionDuration: const Duration(milliseconds: 300), // مدة التأثير
          ),
        );
      },
      onLongPress: widget.isOwner
          ? () => _showEditDeleteMenu(product) // استدعاء دالة قائمة التعديل/الحذف
          : null,
      borderRadius: BorderRadius.circular(12), // لجعل تأثير النقر مستديرًا
      child: Card(
        elevation: 2, // تقليل الظل قليلاً
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias, // لقص الصورة بشكل صحيح
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3, // إعطاء مساحة أكبر للصورة
              child: Stack(
                fit: StackFit.expand, // لجعل الصورة تملأ المساحة
                children: [
                  (product.imageUrl != null && product.imageUrl!.isNotEmpty)
                      ? Image.network(
                    product.imageUrl!,
                    fit: BoxFit.cover,
                    // إضافة مؤشر تحميل للصورة
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Center(child: CircularProgressIndicator(value: progress.expectedTotalBytes != null ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes! : null));
                    },
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: Colors.grey[200],
                      child: Icon(Icons.broken_image_outlined, color: Colors.grey[400], size: 40),
                    ),
                  )
                      : Container( // Placeholder محسن
                    color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                    child: Icon(Icons.image_not_supported_outlined, color: theme.colorScheme.onSurfaceVariant, size: 40),
                  ),
                  // يمكنك إعادة تفعيل زر المفضلة هنا إذا أردت
                  Positioned(
                    top: 6,
                    right: 6,
                    child: _FavoriteIcon(product), // استدعاء ودجت المفضلة
                  ),
                ],
              ),
            ),
            // تفاصيل المنتج
            Expanded(
              flex: 2, // مساحة أقل للتفاصيل النصية
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween, // توزيع المساحة
                  children: [
                    Text(
                      product.productName,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600), // استخدام titleSmall
                      maxLines: 2, // السماح بسطرين للاسم
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${product.price.toStringAsFixed(2)} ر.ي',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    // عرض المخزون (اختياري)
                    Text(
                      'المخزون: ${product.stock}',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- دالة إظهار قائمة التعديل/الحذف ---
  void _showEditDeleteMenu(Product product) {
    // يمكنك استخدام showModalBottomSheet أو showMenu
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder( // جعل الحواف العلوية دائرية
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Wrap( // استخدام Wrap لعرض الخيارات
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('تعديل المنتج'),
            onTap: () {
              Navigator.pop(ctx); // إغلاق الـ BottomSheet
              _editProduct(product);
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
            title: Text('حذف المنتج', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            onTap: () {
              Navigator.pop(ctx); // إغلاق الـ BottomSheet
              _deleteProduct(product);
            },
          ),
          const Divider(height: 1),
          ListTile( // إضافة خيار الإلغاء
            leading: const Icon(Icons.cancel_outlined),
            title: const Text('إلغاء'),
            onTap: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }


  // --- ودجت أيقونة المفضلة (كما هي أو مع تحسينات الحالة) ---
  Widget _FavoriteIcon(Product product) {
    // Logic to check if the product is favorited by the current user
    // This might involve checking a list in a provider or a quick query
    // For simplicity, we'll assume a function `isFavorite(productId)` exists
    // bool isCurrentlyFavorite = isFavorite(product.id); // Replace with actual check

    // --- تحسين: استخدام FutureBuilder للتحقق من المفضلة عند بناء الأيقونة ---
    final user = Supabase.instance.client.auth.currentUser;

    // لا تعرض الأيقونة إذا لم يكن المستخدم مسجلًا أو إذا كان هو المالك
    if (user == null || widget.isOwner) {
      return const SizedBox.shrink(); // لا تظهر أيقونة المفضلة للمالك أو غير المسجل
    }

    return FutureBuilder<bool>(
      // جلب حالة المفضلة للمنتج الحالي
        future: _checkIfFavorite(product.id),
        initialData: false, // القيمة الافتراضية
        builder: (context, snapshot) {
          final bool isFav = snapshot.data ?? false;
          // أيقونة صغيرة قابلة للنقر
          return Material( // استخدام Material لتأثير splash
            color: Colors.black.withOpacity(0.4), // خلفية شبه شفافة
            shape: const CircleBorder(),
            child: InkWell(
              onTap: () => _toggleFavorite(product), // استدعاء دالة التبديل
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(5.0), // padding حول الأيقونة
                child: Icon(
                  isFav ? Icons.favorite : Icons.favorite_border, // تغيير الأيقونة بناءً على الحالة
                  color: isFav ? Colors.redAccent : Colors.white, // تغيير اللون
                  size: 18, // حجم الأيقونة
                ),
              ),
            ),
          );
        }
    );
  }

  // --- دالة التحقق من المفضلة للمنتج المحدد ---
  Future<bool> _checkIfFavorite(int productId) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return false;
    try {
      final response = await Supabase.instance.client
          .from('favorites')
          .select('product_id') // فقط للتأكد من وجود السجل
          .eq('user_id', user.id)
          .eq('product_id', productId)
          .maybeSingle(); // استخدام maybeSingle لأنه إما موجود أو لا

      return response != null; // إذا كان غير null، فهو موجود في المفضلة
    } catch (e) {
      print("Error checking favorite status for product $productId: $e");
      return false; // افترض أنه ليس مفضلاً عند حدوث خطأ
    }
  }


  // --- دالة تبديل حالة المفضلة (كما هي مع تعديل بسيط) ---
  Future<void> _toggleFavorite(Product product) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('الرجاء تسجيل الدخول لإضافة للمفضلة')));
      return;
    }

    // إعادة التحقق من الحالة الحالية قبل التبديل (أكثر أمانًا)
    final isCurrentlyFavorite = await _checkIfFavorite(product.id);

    try {
      if (isCurrentlyFavorite) {
        // حذف
        await Supabase.instance.client
            .from('favorites')
            .delete()
            .eq('user_id', user.id)
            .eq('product_id', product.id);
        if(mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تمت الإزالة من المفضلة'), duration: Duration(seconds: 1)),
          );
        }
      } else {
        // إضافة
        await Supabase.instance.client.from('favorites').insert({
          'user_id': user.id,
          'product_id': product.id,
        });
        if(mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تمت الإضافة إلى المفضلة'), duration: Duration(seconds: 1)),
          );
        }
      }
      // تحديث الواجهة لإظهار التغيير في الأيقونة فوراً
      setState(() {}); // إعادة بناء الودجت لإعادة استدعاء FutureBuilder للأيقونة
    } catch (e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحديث المفضلة: $e')),
        );
      }
      print("Error toggling favorite: $e");
    }
  }


} // نهاية _StoreProductsTabState