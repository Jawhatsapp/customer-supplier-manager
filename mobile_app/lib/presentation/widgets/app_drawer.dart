// lib/presentation/widgets/app_drawer.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Provider; // إخفاء Provider من Supabase

// Import Providers and Screens (تأكد من صحة المسارات)
import '../../providers/auth_provider.dart';
import '../auth/login_screen.dart';
import '../home/customer_home_screen.dart';
import '../home/retailer_home_screen.dart';
import '../home/supplier_home_screen.dart';
import '../profile/user_profile_screen.dart';
import '../cart/cart_screen.dart';
import '../orders/my_orders_screen.dart';
import '../accounts/account_ledger_screen.dart';
import '../reports/financial_report_screen.dart';
import '../returns/return_request_wizard_screen.dart'; // أو Simple
import '../notifications/notification_screen.dart'; // <-- إضافة شاشة الإشعارات

// Screens for Business Users
import '../store/store_tab_screen.dart';
import '../management/store_settings_screen.dart';
import '../categories/category_management_screen.dart';
import '../currencies/currency_management_screen.dart';
import '../orders/approve_pending_orders_screen.dart';
import '../returns/approve_return_requests_screen.dart';
import '../manual_operations/approve_manual_operations_screen.dart';
import '../manual_operations/sent_manual_operations_screen.dart';
import '../reports/sales_report_screen.dart';


class AppDrawer extends StatelessWidget {
  const AppDrawer({Key? key}) : super(key: key);

  // --- Helper Functions (كما هي من قبل) ---
  Widget _buildDrawerItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool enabled = true,
    bool dense = true, // جعلها dense بشكل افتراضي
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: enabled ? colorScheme.primary : Colors.grey[400], size: 22),
      title: Text(title, style: TextStyle(fontSize: 14, color: enabled ? colorScheme.onSurface : Colors.grey)), // تصغير الخط قليلاً
      onTap: enabled ? () { Navigator.pop(context); onTap(); } : null,
      enabled: enabled,
      dense: dense,
      visualDensity: VisualDensity.compact, // تقليل المسافات الرأسية
    );
  }

  String _getArabicRoleName(String? role) { /* ... نفس الكود ... */
    switch (role) { case 'client': return 'عميل'; case 'retailer': return 'تاجر تجزئة'; case 'supplier': return 'مورد'; default: return 'غير معروف'; }
  }
  // ------------------------------------

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final theme = Theme.of(context);

    final user = authProvider.currentUser;
    final profile = authProvider.userProfile;
    final role = authProvider.userRole;
    final storeId = authProvider.storeId;
    final bool isBusinessUser = (role == 'retailer' || role == 'supplier');
    final bool hasStoreId = storeId != null;

    // --- بناء أيقونة الصورة الرمزية مع التحميل والخطأ ---
    Widget buildAvatar() {
      final avatarUrl = profile?.avatarUrl;
      final firstNameInitial = profile?.firstName.isNotEmpty == true ? profile!.firstName[0].toUpperCase() : '?';

      if (avatarUrl != null && avatarUrl.isNotEmpty) {
        return CircleAvatar(
          radius: 30, // حجم مناسب للـ Header
          backgroundColor: Colors.white70, // لون خلفية احتياطي
          backgroundImage: NetworkImage(avatarUrl),
          onBackgroundImageError: (exception, stackTrace) {
            print("Error loading avatar in Drawer: $exception");
          },
        );
      } else {
        return CircleAvatar(
          radius: 30,
          backgroundColor: Colors.white70,
          child: Text(
            firstNameInitial,
            style: TextStyle(fontSize: 26, color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
          ),
        );
      }
    }
    // -----------------------------------------------------

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // --- Drawer Header (محسّن) ---
          UserAccountsDrawerHeader(
            accountName: Text(
              profile?.fullName ?? (user != null ? 'جاري التحميل...' : 'الرجاء تسجيل الدخول'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            accountEmail: Text(user?.email ?? ''),
            currentAccountPicture: buildAvatar(), // استخدام الدالة المساعدة
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              // يمكنك إضافة صورة خلفية هنا إذا أردت
              // image: DecorationImage(image: AssetImage("assets/drawer_bg.png"), fit: BoxFit.cover)
            ),
            otherAccountsPictures: [
              if (role != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Chip(
                    label: Text(
                      _getArabicRoleName(role),
                      style: TextStyle(color: theme.colorScheme.primary, fontSize: 11),
                    ),
                    backgroundColor: Colors.white.withOpacity(0.85), // زيادة الشفافية قليلاً
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    visualDensity: VisualDensity.compact,
                  ),
                )
            ],
            margin: EdgeInsets.zero,
          ),

          // --- قسم عام (للجميع) ---
          _buildDrawerItem( context: context, icon: Icons.home_outlined, title: 'الرئيسية', enabled: user != null,
            onTap: () {
              Widget destination;
              if (role == 'client') destination = const CustomerHomeScreen();
              else if (role == 'retailer') destination = const RetailerHomeScreen();
              else if (role == 'supplier') destination = const SupplierHomeScreen();
              else destination = const LoginScreen();
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => destination));
            },
          ),
          _buildDrawerItem( context: context, icon: Icons.person_outline, title: 'الملف الشخصي', enabled: user != null,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserProfileScreen())),
          ),
          _buildDrawerItem( context: context, icon: Icons.notifications_outlined, title: 'الإشعارات', enabled: user != null,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationScreen())),
          ),
          _buildDrawerItem( context: context, icon: Icons.shopping_cart_outlined, title: 'سلة المشتريات', enabled: user != null,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartScreen())),
          ),
          _buildDrawerItem( context: context, icon: Icons.list_alt_outlined, title: 'طلباتي', enabled: user != null,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyOrdersScreen())),
          ),
          _buildDrawerItem( context: context, icon: Icons.account_balance_wallet_outlined, title: 'دفتر الحسابات العام', enabled: user != null,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountLedgerScreen())),
          ),
          // --- طلب المرتجع (يظهر للكل تقريباً) ---
          if (role == 'client' || role == 'retailer' || role == 'supplier') // أو حسب منطق عملك
            _buildDrawerItem( context: context, icon: Icons.undo_outlined, title: 'طلب مرتجع جديد', enabled: user != null,
              onTap: () { if (user != null) { Navigator.push( context, MaterialPageRoute( builder: (_) => ReturnRequestScreenSimple(currentUserId: user.id), ), ); } },
            ),

          // --- أقسام المستخدمين التجاريين (تجار وموردين) ---
          if (isBusinessUser) ...[
            const Divider(thickness: 0.6, height: 16),
            // --- قسم إدارة المتجر ---
            ExpansionTile(
              leading: const Icon(Icons.store_mall_directory_outlined, size: 22),
              title: Text('إدارة المتجر', style: TextStyle(fontSize: 14, color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
              tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              childrenPadding: const EdgeInsets.only(right: 20, bottom: 8), // Padding داخلي
              initiallyExpanded: hasStoreId, // فتح القائمة تلقائيًا إذا كان لديه متجر
              children: <Widget>[
                _buildDrawerItem( context: context, icon: Icons.visibility_outlined, title: 'عرض المتجر', enabled: hasStoreId,
                  onTap: () => Navigator.push( context, MaterialPageRoute( builder: (_) => StoreTabScreen(storeId: storeId!, storeType: role!), ), ),
                ),
                _buildDrawerItem( context: context, icon: Icons.settings_outlined, title: 'إعدادات المتجر', enabled: hasStoreId,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StoreSettingsScreen())),
                ),
                _buildDrawerItem( context: context, icon: Icons.category_outlined, title: 'إدارة التصنيفات', enabled: hasStoreId,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CategoryManagementScreen(storeId: storeId!))),
                ),
                _buildDrawerItem( context: context, icon: Icons.currency_exchange_outlined, title: 'إدارة العملات', enabled: hasStoreId,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CurrencyManagementScreen(storeId: storeId!))),
                ),
              ],
            ),

            // --- قسم العمليات والموافقات ---
            ExpansionTile(
              leading: const Icon(Icons.checklist_rtl_outlined, size: 22),
              title: Text('الموافقات والعمليات', style: TextStyle(fontSize: 14, color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
              tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              childrenPadding: const EdgeInsets.only(right: 20, bottom: 8),
              children: <Widget>[
                _buildDrawerItem( context: context, icon: Icons.price_check_outlined, title: 'مراجعة المدفوعات/الطلبات', enabled: hasStoreId,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ApprovePendingOrdersScreen(storeId: storeId!))),
                ),
                _buildDrawerItem( context: context, icon: Icons.assignment_return_outlined, title: 'مراجعة طلبات المرتجع', enabled: hasStoreId,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ApproveReturnRequestsScreen(storeId: storeId!))),
                ),
                _buildDrawerItem( context: context, icon: Icons.sync_alt_outlined, title: 'مراجعة العمليات اليدوية', enabled: user != null, // متاح للكل من يصله إشعار
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ApproveManualOperationsScreen())),
                ),
                _buildDrawerItem( context: context, icon: Icons.outbox_outlined, title: 'عملياتي اليدوية المرسلة', enabled: hasStoreId,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SentManualOperationsScreen(storeId: storeId!))),
                ),
              ],
            ),

            // --- قسم التقارير ---
            ExpansionTile(
              leading: const Icon(Icons.analytics_outlined, size: 22),
              title: Text('التقارير', style: TextStyle(fontSize: 14, color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
              tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              childrenPadding: const EdgeInsets.only(right: 20, bottom: 8),
              children: <Widget>[
                _buildDrawerItem( context: context, icon: Icons.account_balance_outlined, title: 'تقرير الحسابات المالية', enabled: hasStoreId,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FinancialAccountsReportScreen(storeId: storeId!))),
                ),
                _buildDrawerItem( context: context, icon: Icons.bar_chart_outlined, title: 'تقرير المبيعات', enabled: hasStoreId,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SalesReportScreen(storeId: storeId!))),
                ),
              ],
            ),
            // --- رابط المتاجر الأخرى (بقي منفصلاً) ---
            // _buildDrawerItem( context: context, icon: Icons.group_work_outlined, title: 'عرض المتاجر الأخرى', enabled: user != null,
            //   onTap: () { ... navigate based on role ... } // يمكنك إبقاؤه أو دمجه
            // ),
          ],

          // --- Logout ---
          const Divider(thickness: 0.6, height: 16),
          _buildDrawerItem( context: context, icon: Icons.logout, title: 'تسجيل الخروج', enabled: user != null,
            onTap: () async { await context.read<AuthProvider>().signOut(); },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}