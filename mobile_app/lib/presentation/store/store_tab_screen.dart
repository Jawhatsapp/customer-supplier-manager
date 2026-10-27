// lib/presentation/store/store_tab_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:badges/badges.dart' as badges;
import 'package:supabase_flutter/supabase_flutter.dart' hide Provider;

// --- استيرادات جديدة ومعدلة ---
import '../../data/models/store_model.dart';         // <-- استيراد المودل
import '../../data/repositories/store_repository.dart'; // <-- استيراد المستودع
import '../../providers/auth_provider.dart';
import '../cart/cart_provider.dart';
// ... (باقي الاستيرادات كما هي)
import '../cart/cart_screen.dart';
import '../notifications/notification_screen.dart';
import 'store_products_tab.dart';
import '../management/store_settings_screen.dart';
import '../widgets/app_drawer.dart';
import 'store_favorites_tab.dart';
import '../orders/store_orders_screen.dart';
import 'store_chat_tab.dart';


class StoreTabScreen extends StatefulWidget {
  final int storeId;
  final String storeType;

  const StoreTabScreen({
    Key? key,
    required this.storeId,
    required this.storeType,
  }) : super(key: key);

  @override
  State<StoreTabScreen> createState() => _StoreTabScreenState();
}

class _StoreTabScreenState extends State<StoreTabScreen> {
  // --- متغيرات الحالة المبسطة ---
  late final StoreRepository _storeRepository;
  Future<StoreModel>? _storeFuture; // <-- الآن هو Future لكائن StoreModel

  int _selectedIndex = 0;
  bool _isOwner = false;

  final GlobalKey<StoreProductsTabState> _productsTabKey = GlobalKey<StoreProductsTabState>();
  late List<Widget> _tabs;

  @override
  void initState() {
    super.initState();
    _storeRepository = StoreRepository(); // تهيئة المستودع
    _fetchStoreDataAndOwnerStatus();      // استدعاء الدالة الجديدة

    // تهيئة التابات بقيم افتراضية، سيتم تحديثها بعد جلب البيانات
    _tabs = [
      StoreProductsTab(
        key: _productsTabKey,
        storeId: widget.storeId,
        isOwner: _isOwner,
      ),
      const FavoritesScreen(),
      StoreOrdersScreen(storeId: widget.storeId),
      StoreChatTab(storeId: widget.storeId),
    ];
  }

  // --- دالة جلب البيانات باستخدام المستودع ---
  void _fetchStoreDataAndOwnerStatus() {
    if (!mounted) return;

    // استدعاء دالة المستودع لجلب بيانات المتجر
    final future = _storeRepository.getStoreById(widget.storeId);

    // التحقق من حالة المالك بعد جلب البيانات بنجاح
    future.then((store) {
      if (!mounted) return;
      final currentUser = Supabase.instance.client.auth.currentUser;
      final isOwnerNow = (currentUser != null && store.ownerId == currentUser.id);

      setState(() {
        _isOwner = isOwnerNow;
        // تحديث تاب المنتجات بالحالة الصحيحة للمالك
        _tabs[0] = StoreProductsTab(
          key: _productsTabKey,
          storeId: widget.storeId,
          isOwner: _isOwner,
        );
      });
    }).catchError((error) {
      // معالجة الخطأ هنا إذا فشلت عملية الجلب
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString()))
      );
    });

    // تحديث حالة الواجهة لتعرض مؤشر التحميل بناءً على الـ Future الجديد
    setState(() {
      _storeFuture = future;
    });
  }

  // ... (باقي الدوال _onItemTapped, _buildFloatingActionButton, _fetchUnreadNotificationsCount تبقى كما هي)
  void _onItemTapped(int index) {
    if (!mounted) return;
    setState(() { _selectedIndex = index; });
  }

  Widget? _buildFloatingActionButton() {
    if (_selectedIndex == 0 && _isOwner) {
      return FloatingActionButton(
        onPressed: () => _productsTabKey.currentState?.openAddProductScreen(context),
        tooltip: 'إضافة منتج جديد',
        child: const Icon(Icons.add),
      );
    }
    return null;
  }

  Future<int> _fetchUnreadNotificationsCount() async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return 0;
    try {
      final result = await Supabase.instance.client
          .from('notifications')
          .select('id', const FetchOptions(count: CountOption.exact))
          .eq('user_id', currentUser.id)
          .eq('is_read', false);
      return result.count ?? 0;
    } catch(e) {
      print("Error fetching notification count: $e");
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StoreModel>(
      future: _storeFuture,
      builder: (context, snapshot) {
        // --- بناء الواجهة بناءً على حالة الـ Future ---

        // 1. حالة التحميل
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        // 2. حالة الخطأ
        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('خطأ')),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(snapshot.error?.toString() ?? 'لم يتم العثور على المتجر.'),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: _fetchStoreDataAndOwnerStatus,
                    child: const Text('إعادة المحاولة'),
                  )
                ],
              ),
            ),
          );
        }

        // 3. حالة النجاح
        final store = snapshot.data!;

        // الآن يمكننا بناء الواجهة الكاملة باستخدام `store`
        return _buildScaffold(context, store);
      },
    );
  }

  // --- دالة مساعدة لبناء الواجهة الرئيسية لتجنب التكرار ---
  Widget _buildScaffold(BuildContext context, StoreModel store) {
    final theme = Theme.of(context);

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (store.logoUrl != null && store.logoUrl!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.white,
                  backgroundImage: NetworkImage(store.logoUrl!),
                ),
              ),
            Flexible(
                child: Text(
                  store.storeName,
                  overflow: TextOverflow.ellipsis,
                )
            ),
          ],
        ),
        centerTitle: false,
        actions: [
          if (_isOwner)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'إعدادات المتجر',
              onPressed: () {
                final auth = context.read<AuthProvider>();
                if (auth.storeId == widget.storeId) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const StoreSettingsScreen()));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('جاري مزامنة بيانات المتجر، يرجى المحاولة بعد لحظات.')));
                }
              },
            ),

          Consumer<CartProvider>(
            builder: (ctx, cartProvider, _) => badges.Badge(
              position: badges.BadgePosition.topEnd(top: 0, end: 3),
              showBadge: cartProvider.totalCount > 0,
              badgeContent: Text(cartProvider.totalCount.toString(), style: const TextStyle(color: Colors.white, fontSize: 10)),
              child: IconButton(
                icon: const Icon(Icons.shopping_cart_outlined),
                tooltip: 'سلة المشتريات',
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartScreen())),
              ),
            ),
          ),

          FutureBuilder<int>(
            future: _fetchUnreadNotificationsCount(),
            builder: (ctx, snap) => badges.Badge(
              position: badges.BadgePosition.topEnd(top: 0, end: 3),
              showBadge: (snap.data ?? 0) > 0,
              badgeContent: Text((snap.data ?? 0).toString(), style: const TextStyle(color: Colors.white, fontSize: 10)),
              child: IconButton(
                icon: const Icon(Icons.notifications_outlined),
                tooltip: 'الإشعارات',
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationScreen()));
                  if (mounted) setState(() {});
                },
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _tabs,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: theme.colorScheme.primary,
        unselectedItemColor: Colors.grey[600],
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.store_outlined), label: 'المنتجات'),
          BottomNavigationBarItem(icon: Icon(Icons.favorite_border), label: 'المفضلة'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long_outlined), label: 'الطلبات'),
          BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline), label: 'الدردشة'),
        ],
      ),
      floatingActionButton: _buildFloatingActionButton(),
    );
  }
}
