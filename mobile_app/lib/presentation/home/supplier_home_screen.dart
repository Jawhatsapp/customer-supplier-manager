// lib/presentation/home/supplier_home_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// لا حاجة لـ supabase_flutter هنا
import '../../data/models/store_model.dart';         // <-- استيراد
import '../../data/repositories/store_repository.dart'; // <-- استيراد
import '../store/store_tab_screen.dart';
import '../widgets/app_drawer.dart';
import '../../providers/auth_provider.dart';

class SupplierHomeScreen extends StatefulWidget {
  const SupplierHomeScreen({Key? key}) : super(key: key);

  @override
  State<SupplierHomeScreen> createState() => _SupplierHomeScreenState();
}

class _SupplierHomeScreenState extends State<SupplierHomeScreen> {
  // --- متغيرات الحالة المعدلة ---
  late final StoreRepository _storeRepository;
  Future<List<StoreModel>>? _retailerStoresFuture;
  Future<List<StoreModel>>? _otherSupplierStoresFuture;

  String? _currentUserId;
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  String _searchTerm = '';

  @override
  void initState() {
    super.initState();
    _storeRepository = StoreRepository(); // تهيئة
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadStores();
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _loadStores() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _currentUserId = authProvider.currentUser?.id;
    if (!mounted) return;

    if (_currentUserId != null) {
      setState(() {
        _retailerStoresFuture = _storeRepository.getStores(
          storeType: 'retailer',
          searchTerm: _searchTerm,
        );
        _otherSupplierStoresFuture = _storeRepository.getStores(
          storeType: 'supplier',
          searchTerm: _searchTerm,
          excludeOwnerId: _currentUserId, // استبعاد المتجر الخاص بالمستخدم الحالي
        );
      });
    } else {
      setState(() {
        _retailerStoresFuture = Future.value([]);
        _otherSupplierStoresFuture = Future.value([]);
      });
    }
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      final currentSearchTerm = _searchController.text.trim();
      if (mounted && _searchTerm != currentSearchTerm) {
        setState(() {
          _searchTerm = currentSearchTerm;
          _loadStores(); // إعادة الجلب بالبحث الجديد
        });
      }
    });
  }

  Future<void> _refreshAllStores() async {
    _loadStores();
  }

  void _navigateToStore(int storeId, String storeType) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => StoreTabScreen(storeId: storeId, storeType: storeType)));
  }

  // ودجات بناء الواجهة (تستخدم الآن StoreModel)
  Widget _buildStoreSection({required String title, required Future<List<StoreModel>>? future, bool horizontal = false}) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
          child: Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        ),
        FutureBuilder<List<StoreModel>>(
          future: future,
          builder: (context, snapshot) {
            if (future == null || snapshot.connectionState == ConnectionState.waiting) {
              return SizedBox(height: horizontal ? 180 : 120, child: Center(child: CircularProgressIndicator(color: theme.colorScheme.primary)));
            }
            if (snapshot.hasError) {
              return Padding(padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0), child: Center(child: Text('خطأ تحميل المتاجر: ${snapshot.error}')));
            }
            final stores = snapshot.data ?? [];
            if (stores.isEmpty) {
              final emptyMessage = _searchTerm.isNotEmpty ? 'لا توجد متاجر تطابق بحثك "${_searchTerm}" في هذا القسم.' : 'لا توجد متاجر متاحة حالياً في هذا القسم.';
              return Padding(padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0), child: Center(child: Text(emptyMessage, style: theme.textTheme.bodyMedium)));
            }
            if (horizontal) {
              return SizedBox(height: 180, child: ListView.builder(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12.0), itemCount: stores.length, itemBuilder: (context, index) => Padding(padding: const EdgeInsets.only(right: 8.0), child: _buildStoreCard(stores[index], theme))));
            } else {
              return ListView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.symmetric(horizontal: 4.0), itemCount: stores.length, itemBuilder: (context, index) => _buildStoreListTile(stores[index], theme));
            }
          },
        ),
      ],
    );
  }

  Widget _buildStoreCard(StoreModel store, ThemeData theme) {
    return SizedBox(width: 240, child: Card(clipBehavior: Clip.antiAlias, elevation: 3, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), child: InkWell(onTap: () => _navigateToStore(store.id, store.storeType), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(height: 95, width: double.infinity, child: store.bannerUrl != null && store.bannerUrl!.isNotEmpty ? Image.network(store.bannerUrl!, fit: BoxFit.cover, loadingBuilder: (ctx, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2)), errorBuilder: (ctx, err, st) => _buildLogoOrPlaceholder(store, theme, isBannerFailed: true)) : _buildLogoOrPlaceholder(store, theme)), Padding(padding: const EdgeInsets.all(10.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(store.storeName, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis), const SizedBox(height: 4), Text(store.address ?? 'لا يوجد عنوان', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis)]))]))));
  }

  Widget _buildStoreListTile(StoreModel store, ThemeData theme) {
    return Card(margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), child: ListTile(leading: CircleAvatar(radius: 28, backgroundImage: (store.logoUrl != null && store.logoUrl!.isNotEmpty) ? NetworkImage(store.logoUrl!) : null, backgroundColor: (store.logoUrl != null && store.logoUrl!.isNotEmpty) ? Colors.transparent : (store.storeType == 'supplier' ? theme.primaryColor.withOpacity(0.1) : theme.colorScheme.secondary.withOpacity(0.1)), child: (store.logoUrl == null || store.logoUrl!.isEmpty) ? Icon(store.storeType == 'supplier' ? Icons.store : Icons.storefront, color: store.storeType == 'supplier' ? theme.primaryColor : theme.colorScheme.secondary, size: 28) : null), title: Text(store.storeName, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)), subtitle: Text(store.address ?? 'لا يوجد عنوان', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis), trailing: Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant), onTap: () => _navigateToStore(store.id, store.storeType), contentPadding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0), dense: false));
  }

  Widget _buildLogoOrPlaceholder(StoreModel store, ThemeData theme, {bool isBannerFailed = false}) {
    if (store.logoUrl != null && store.logoUrl!.isNotEmpty) { return Image.network(store.logoUrl!, fit: BoxFit.contain, errorBuilder: (ctx, err, st) => _buildPlaceholderIcon(store.storeType, theme), loadingBuilder: (ctx, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2))); } else { return _buildPlaceholderIcon(store.storeType, theme); }
  }

  Widget _buildPlaceholderIcon(String storeType, ThemeData theme) {
    return Container(color: theme.colorScheme.surfaceVariant.withOpacity(0.3), child: Center(child: Icon(storeType == 'supplier' ? Icons.store_mall_directory_outlined : Icons.storefront_outlined, size: 45, color: storeType == 'supplier' ? theme.primaryColor.withOpacity(0.7) : theme.colorScheme.secondary.withOpacity(0.7))));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('الصفحة الرئيسية للمورد'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'تحديث القوائم', onPressed: _refreshAllStores),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'ابحث عن متجر...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchTerm.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, size: 20), tooltip: 'مسح البحث', onPressed: () { _searchController.clear(); }) : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(25.0)),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshAllStores,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  _buildStoreSection(title: 'متاجر التجزئة', future: _retailerStoresFuture, horizontal: true),
                  const SizedBox(height: 16),
                  _buildStoreSection(title: 'موردين آخرين', future: _otherSupplierStoresFuture, horizontal: false),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
