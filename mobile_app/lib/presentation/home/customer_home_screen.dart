// lib/presentation/home/customer_home_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
// لا حاجة لـ 'package:supabase_flutter/supabase_flutter.dart' هنا الآن
import '../../data/models/store_model.dart';         // <-- استيراد المودل
import '../../data/repositories/store_repository.dart'; // <-- استيراد المستودع
import '../store/store_tab_screen.dart';
import '../widgets/app_drawer.dart';

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({Key? key}) : super(key: key);

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  // --- متغيرات الحالة المعدلة ---
  late final StoreRepository _storeRepository;
  late Future<List<StoreModel>> _retailerStoresFuture; // <-- النوع الآن StoreModel

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  String _searchTerm = '';

  @override
  void initState() {
    super.initState();
    _storeRepository = StoreRepository(); // تهيئة المستودع
    _retailerStoresFuture = _fetchRetailerStores(); // استدعاء الدالة الجديدة
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // --- تم تعديل هذه الدالة لاستخدام المستودع ---
  Future<List<StoreModel>> _fetchRetailerStores({String? searchTerm}) async {
    try {
      // استدعاء الدالة من المستودع مباشرة
      return await _storeRepository.getStores(
        storeType: 'retailer',
        searchTerm: searchTerm,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString())));
      }
      return []; // إرجاع قائمة فارغة عند الخطأ
    }
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      final currentSearchTerm = _searchController.text.trim();
      if (mounted && _searchTerm != currentSearchTerm) {
        setState(() {
          _searchTerm = currentSearchTerm;
          _retailerStoresFuture = _fetchRetailerStores(searchTerm: _searchTerm);
        });
      }
    });
  }

  Future<void> _refreshStores() async {
    if (!mounted) return;
    setState(() {
      _retailerStoresFuture = _fetchRetailerStores(searchTerm: _searchTerm);
    });
  }

  // --- تم تعديل هذه الدالة لتقبل StoreModel ---
  Widget _buildStoreListTile(StoreModel store, ThemeData theme) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: CircleAvatar(
          radius: 28,
          backgroundImage: (store.logoUrl != null && store.logoUrl!.isNotEmpty) ? NetworkImage(store.logoUrl!) : null,
          backgroundColor: (store.logoUrl != null && store.logoUrl!.isNotEmpty) ? Colors.transparent : theme.colorScheme.secondaryContainer.withOpacity(0.3),
          child: (store.logoUrl == null || store.logoUrl!.isEmpty) ? Icon(Icons.storefront, color: theme.colorScheme.secondary, size: 28) : null,
        ),
        title: Text(store.storeName, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(store.address ?? 'لا يوجد عنوان', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => StoreTabScreen(storeId: store.id, storeType: store.storeType)),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
        dense: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('متاجر التجزئة'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث المتاجر',
            onPressed: _refreshStores,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'ابحث باسم المتجر أو العنوان...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchTerm.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  tooltip: 'مسح البحث',
                  onPressed: () {
                    _searchController.clear();
                    // _onSearchChanged(); // سيتم استدعاؤه تلقائياً بواسطة المستمع
                  },
                )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(25.0)),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshStores,
              child: FutureBuilder<List<StoreModel>>( // <-- النوع الآن StoreModel
                future: _retailerStoresFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator(color: theme.colorScheme.primary));
                  } else if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('حدث خطأ: ${snapshot.error}', textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.error)),
                            const SizedBox(height: 10),
                            ElevatedButton.icon(icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة'), onPressed: _refreshStores),
                          ],
                        ),
                      ),
                    );
                  }

                  final stores = snapshot.data ?? [];
                  if (stores.isEmpty) {
                    final emptyMessage = _searchTerm.isNotEmpty
                        ? 'لا توجد متاجر تطابق بحثك "${_searchTerm}".'
                        : 'لا توجد متاجر تجزئة متاحة حالياً.';
                    return LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Container(
                          height: constraints.maxHeight,
                          alignment: Alignment.center,
                          child: Text(emptyMessage, style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey[600]), textAlign: TextAlign.center),
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                    itemCount: stores.length,
                    itemBuilder: (context, index) {
                      final store = stores[index];
                      return _buildStoreListTile(store, theme);
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}