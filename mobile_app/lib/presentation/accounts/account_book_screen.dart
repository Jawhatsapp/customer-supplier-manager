import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Provider;
import 'package:provider/provider.dart';

import '../manual_operations/approve_manual_operations_screen.dart';
import 'account_details_screen.dart';
import '../../providers/auth_provider.dart';

class AccountsBookScreen extends StatefulWidget {
  // أصبح storeId مطلوباً دائماً للوصول لهذه الشاشة
  final int storeId;
  const AccountsBookScreen({Key? key, required this.storeId}) : super(key: key);

  @override
  State<AccountsBookScreen> createState() => _AccountsBookScreenState();
}

class _AccountsBookScreenState extends State<AccountsBookScreen> {
  // جعلها nullable لتمثيل حالة التحميل الأولية أو الخطأ
  Future<List<Map<String, dynamic>>>? _accountsFuture;
  Future<int>? _pendingOpsCount;
  String _storeName = 'المتجر'; // اسم افتراضي

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
    });
  }

  // تحميل البيانات الأولية أو عند تغيير التبعيات (مثل تسجيل الدخول)
  void _loadInitialData() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentUser != null) {
      // استخدام setState هنا لتعيين الـ Futures وتحديث الواجهة
      setState(() {
        _accountsFuture = _fetchAccountsSummary(widget.storeId); // تم تعديل الاستدعاء
        _pendingOpsCount = _fetchPendingCount(authProvider.currentUser!.id);
      });
      _fetchStoreName(); // جلب اسم المتجر
    } else {
      // إذا لم يكن المستخدم مسجلاً عند بدء الشاشة
      setState(() {
        _accountsFuture = Future.value([]);
        _pendingOpsCount = Future.value(0);
      });
    }
  }

  Future<void> _fetchStoreName() async {
    final sb = Supabase.instance.client;
    String fetchedName = 'متجرك'; // اسم افتراضي عند الفشل
    try {
      // الآن نستعلم من جدول واحد فقط
      final response = await sb
          .from('stores')
          .select('store_name')
          .eq('id', widget.storeId)
          .maybeSingle();

      if (response != null && response['store_name'] != null) {
        fetchedName = response['store_name'];
      }

      if (mounted) {
        setState(() => _storeName = fetchedName);
      }
    } catch (e) {
      print("Error fetching store name for ID ${widget.storeId}: $e");
      if (mounted) {
        setState(() => _storeName = 'متجر غير معروف');
      }
    }
  }

  Future<int> _fetchPendingCount(String currentUserId) async {
    final sb = Supabase.instance.client;
    try {
      final res = await sb
          .from('manual_operations')
          .select('id', const FetchOptions(count: CountOption.exact))
          .eq('counterparty_id', currentUserId)
          .eq('status', 'pending')
          .maybeSingle();
      return res?.count ?? 0;
    } catch (e) {
      print("Error fetching pending count for user $currentUserId: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('خطأ في جلب عدد العمليات المعلقة')),
        );
      }
      return 0;
    }
  }

  // --- تم تعديل هذه الدالة بالكامل ---
  Future<List<Map<String, dynamic>>> _fetchAccountsSummary(int storeId) async {
    final sb = Supabase.instance.client;
    try {
      // استدعاء دالة RPC الجديدة بدلاً من الـ View
      final response = await sb.rpc(
        'get_my_account_summary_for_store',
        params: {'p_store_id': storeId},
      );

      // RPC يرجع List<dynamic>, لذا نحتاج لتحويله
      return List<Map<String, dynamic>>.from(response);

    } catch (e) {
      print("Error fetching accounts summary via RPC: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في جلب ملخص الحسابات: ${e.toString()}')),
        );
      }
      throw Exception('خطأ في جلب ملخص الحسابات');
    }
  }

  // تحديث البيانات عند السحب للتحديث
  Future<void> _refreshAll() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentUser != null) {
      setState(() {
        _accountsFuture = _fetchAccountsSummary(widget.storeId);
        _pendingOpsCount = _fetchPendingCount(authProvider.currentUser!.id);
        _fetchStoreName();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_accountsFuture == null) {
      return Scaffold(
        appBar: AppBar(title: Text('دفتر الحسابات • $_storeName')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('دفتر الحسابات • $_storeName'),
          actions: [
            // بناء أيقونة العمليات المعلقة
            FutureBuilder<int>(
              future: _pendingOpsCount,
              builder: (_, snapshot) {
                final count = (snapshot.connectionState == ConnectionState.done && !snapshot.hasError)
                    ? snapshot.data ?? 0
                    : 0;
                return IconButton(
                  tooltip: 'عمليات يدوية معلّقة ($count)',
                  icon: Stack(
                    alignment: Alignment.topRight,
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.inbox_outlined),
                      if (count > 0)
                        Positioned(
                          right: -5,
                          top: -5,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.error,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1),
                            ),
                            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                            child: Text(
                              '$count',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                  onPressed: () async {
                    // الانتقال لشاشة العمليات المعلقة
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ApproveManualOperationsScreen()),
                    );
                    // إعادة تحميل العدد بعد العودة
                    setState(() {
                      final authProvider = Provider.of<AuthProvider>(context, listen: false);
                      if (authProvider.currentUser != null) {
                        _pendingOpsCount = _fetchPendingCount(authProvider.currentUser!.id);
                      }
                    });
                  },
                );
              },
            ),
            // زر التحديث
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث',
              onPressed: _refreshAll,
            )
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _refreshAll,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _accountsFuture!,
            builder: (_, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, color: theme.colorScheme.error, size: 48),
                        const SizedBox(height: 16),
                        const Text('حدث خطأ أثناء تحميل الحسابات.', textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        Text('${snapshot.error}', style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: const Text('إعادة المحاولة'),
                          onPressed: _refreshAll,
                        )
                      ],
                    ),
                  ),
                );
              }
              final accounts = snapshot.data ?? [];
              if (accounts.isEmpty) {
                return Center(
                  child: Text(
                    'لا توجد حسابات لعرضها.',
                    style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(12.0),
                itemCount: accounts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, index) {
                  final account = accounts[index];
                  // --- تم تعديل أسماء الحقول هنا لتطابق مخرجات دالة RPC ---
                  final credit = (account['total_credit'] as num? ?? 0).toDouble();
                  final debit = (account['total_debit'] as num? ?? 0).toDouble();
                  final balance = (account['balance'] as num? ?? 0).toDouble();
                  final balanceColor = balance > 0.01 ? Colors.green.shade700
                      : balance < -0.01 ? theme.colorScheme.error
                      : theme.colorScheme.outline;
                  final counterpartyId = account['counterparty_id'] as String?;
                  final fullName = account['counterparty_name'] as String? ?? 'مستخدم غير معروف';

                  return Card(
                    elevation: 1.5,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                      leading: CircleAvatar(
                        backgroundColor: balanceColor.withOpacity(0.1),
                        child: Text(
                          fullName.isNotEmpty ? fullName[0].toUpperCase() : '؟',
                          style: TextStyle(color: balanceColor, fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(fullName, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        'له: ${credit.toStringAsFixed(2)} • عليه: ${debit.toStringAsFixed(2)}',
                        style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[700]),
                      ),
                      trailing: Text(
                        balance.toStringAsFixed(2),
                        style: TextStyle(
                          color: balanceColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      onTap: counterpartyId != null
                          ? () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AccountDetailScreen(
                            userId: counterpartyId,
                            userName: fullName,
                            storeId: widget.storeId,
                          ),
                        ),
                      ).then((_) => _refreshAll())
                          : null,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}