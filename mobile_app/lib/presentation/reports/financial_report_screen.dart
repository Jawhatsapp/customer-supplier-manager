// lib/presentation/reports/financial_accounts_report_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Provider;
// We are not using `groupBy` anymore, so the import can be removed if not used elsewhere.
// import 'package:collection/collection.dart';

import '../../models/external_account_models.dart';
import '../accounts/add_external_account_dialog.dart';
import 'external_account_detail_screen.dart';
import '../accounts/account_details_screen.dart';

class FinancialAccountsReportScreen extends StatefulWidget {
  final int storeId;
  const FinancialAccountsReportScreen({Key? key, required this.storeId}) : super(key: key);
  @override
  State<FinancialAccountsReportScreen> createState() => _FinancialAccountsReportScreenState();
}

class _FinancialAccountsReportScreenState extends State<FinancialAccountsReportScreen> {
  late Future<List<AccountSummaryItem>> _summariesFuture;
  final TextEditingController _searchController = TextEditingController();
  String _searchTerm = '';
  String _filterType = 'all';

  @override
  void initState() {
    super.initState();
    _summariesFuture = _fetchAccountSummaries();
    _searchController.addListener(() {
      if (mounted && _searchTerm != _searchController.text.trim()) {
        setState(() {
          _searchTerm = _searchController.text.trim();
          _summariesFuture = _fetchAccountSummaries();
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<AccountSummaryItem>> _fetchAccountSummaries() async {
    List<AccountSummaryItem> combinedSummaries = [];
    try {
      if (_filterType == 'all' || _filterType == 'registered') {
        final registeredSummaries = await _fetchRegisteredUserSummaries();
        combinedSummaries.addAll(registeredSummaries);
      }
      if (_filterType == 'all' || _filterType == 'external') {
        final externalSummaries = await _fetchExternalAccountSummaries();
        combinedSummaries.addAll(externalSummaries);
      }

      if (_searchTerm.isNotEmpty) {
        combinedSummaries = combinedSummaries.where((item) => item.name.toLowerCase().contains(_searchTerm.toLowerCase())).toList();
      }

      combinedSummaries.sort((a, b) => a.balance.compareTo(b.balance));
      return combinedSummaries;
    } catch (e) {
      print("Error fetching combined account summaries: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: ${e.toString()}')));
      return [];
    }
  }

  // --- الدالة النهائية التي تعالج المشكلة ---
  Future<List<AccountSummaryItem>> _fetchRegisteredUserSummaries() async {
    final supabase = Supabase.instance.client;
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return [];

    try {
      // 1. جلب كل القيود التي تخص المستخدم الحالي في هذا المتجر
      final response = await supabase
          .from('transaction_lines')
          .select('*, transaction:financial_transactions!inner(store_id, status)')
          .filter('transaction.store_id', 'eq', widget.storeId)
          .filter('transaction.status', 'eq', 'approved')
          .or('user_id.eq.${currentUser.id},related_user_id.eq.${currentUser.id}');

      final allLines = List<Map<String, dynamic>>.from(response);

      if (allLines.isEmpty) {
        print("_fetchRegisteredUserSummaries: No lines fetched for user ${currentUser.id} in store ${widget.storeId}");
        return [];
      }

      // 2. جمع كل معرفات المستخدمين الفريدة (الأطراف الأخرى)
      final counterpartyIds = allLines.map((line) {
        final userId = line['user_id']?.toString();
        final relatedUserId = line['related_user_id']?.toString();
        return userId == currentUser.id.toString() ? relatedUserId : userId;
      }).where((id) => id != null && id != currentUser.id.toString()).toSet();

      if (counterpartyIds.isEmpty) return [];

      // 3. جلب الملفات الشخصية للأطراف الأخرى دفعة واحدة
      final profilesResponse = await supabase
          .from('profiles')
          .select('id, first_name, last_name')
          .in_('id', counterpartyIds.toList());

      final profilesMap = {for (var p in profilesResponse) p['id'] as String: p};

      // 4. تجميع القيود وحساب الملخصات باستخدام Map يدويًا
      final Map<String, AccountSummaryItem> summariesMap = {};

      for (var line in allLines) {
        final counterpartyId = (line['user_id'] == currentUser.id ? line['related_user_id'] : line['user_id'])?.toString();
        if (counterpartyId == null || !counterpartyIds.contains(counterpartyId)) continue;

        // إذا لم يتم إنشاء ملخص لهذا الطرف، قم بإنشائه
        summariesMap.putIfAbsent(counterpartyId, () {
          final profile = profilesMap[counterpartyId];
          String name = 'مستخدم (${counterpartyId.substring(0, 6)})';
          if (profile != null) {
            name = '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'.trim();
          }
          return AccountSummaryItem(
              isExternal: false, id: counterpartyId, name: name,
              totalCredit: 0, totalDebit: 0, lastTransactionDate: null
          );
        });

        // تحديث أرصدة الملخص الموجود
        final summary = summariesMap[counterpartyId]!;
        final amount = (line['amount'] as num).toDouble();
        final txDate = DateTime.tryParse(line['created_at']);

        double currentCredit = summary.totalCredit;
        double currentDebit = summary.totalDebit;
        DateTime? lastDate = summary.lastTransactionDate;

        if (line['user_id'] == currentUser.id) {
          if (line['type'] == 'له') currentCredit += amount;
          if (line['type'] == 'عليه') currentDebit += amount;
        } else {
          if (line['type'] == 'له') currentDebit += amount;
          if (line['type'] == 'عليه') currentCredit += amount;
        }

        if (txDate != null && (lastDate == null || txDate.isAfter(lastDate))) {
          lastDate = txDate;
        }

        // إعادة تعيين الكائن في الخريطة بالقيم الجديدة
        summariesMap[counterpartyId] = AccountSummaryItem(
            isExternal: summary.isExternal, id: summary.id, name: summary.name,
            totalCredit: currentCredit, totalDebit: currentDebit, lastTransactionDate: lastDate
        );
      }

      return summariesMap.values.toList();

    } catch (e) {
      print("Error in _fetchRegisteredUserSummaries: $e");
      throw e;
    }
  }

  Future<List<AccountSummaryItem>> _fetchExternalAccountSummaries() async {
    final supabase = Supabase.instance.client;
    try {
      final response = await supabase.rpc(
        'get_external_account_summaries_for_store',
        params: {'p_store_id': widget.storeId},
      );
      final List<Map<String, dynamic>> summariesData = List<Map<String, dynamic>>.from(response);
      return summariesData.map((data) => AccountSummaryItem(
        isExternal: true,
        id: (data['account_id'] as int).toString(),
        name: data['account_name'] ?? 'حساب خارجي',
        totalCredit: (data['total_credit'] as num? ?? 0).toDouble(),
        totalDebit: (data['total_debit'] as num? ?? 0).toDouble(),
        lastTransactionDate: DateTime.tryParse(data['last_transaction_date'] ?? ''),
      )).toList();
    } catch (e) {
      print("Error fetching external account summaries: $e");
      return [];
    }
  }

  Future<void> _refreshData() async {
    if (!mounted) return;
    setState(() { _summariesFuture = _fetchAccountSummaries(); });
  }

  void _showAddAccountDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) => AddExternalAccountDialog(storeId: widget.storeId, onAccountAdded: _refreshData),
    );
  }

  void _navigateToDetails(AccountSummaryItem summary) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) {
          if (summary.isExternal) {
            return ExternalAccountDetailScreen(externalAccountId: int.parse(summary.id), storeId: widget.storeId);
          } else {
            return AccountDetailScreen(userId: summary.id, userName: summary.name, storeId: widget.storeId);
          }
        },
      ),
    );
    _refreshData();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('الحسابات المالية للمتجر ${widget.storeId}'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refreshData, tooltip: 'تحديث')
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(child: TextField(controller: _searchController, decoration: InputDecoration(hintText: 'ابحث بالاسم...', prefixIcon: const Icon(Icons.search, size: 20), isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(25.0))))),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  icon: Icon(Icons.filter_list, color: theme.colorScheme.primary),
                  tooltip: 'تصفية حسب النوع',
                  onSelected: (String result) {
                    if (_filterType != result) {
                      setState(() { _filterType = result; _summariesFuture = _fetchAccountSummaries(); });
                    }
                  },
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(value: 'all', child: Text('الكل', style: TextStyle(fontWeight: _filterType == 'all' ? FontWeight.bold : FontWeight.normal))),
                    PopupMenuItem<String>(value: 'registered', child: Text('مسجلين', style: TextStyle(fontWeight: _filterType == 'registered' ? FontWeight.bold : FontWeight.normal))),
                    PopupMenuItem<String>(value: 'external', child: Text('خارجيين', style: TextStyle(fontWeight: _filterType == 'external' ? FontWeight.bold : FontWeight.normal))),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshData,
              child: FutureBuilder<List<AccountSummaryItem>>(
                future: _summariesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                  if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(16.0), child: Text('خطأ في تحميل الحسابات: ${snapshot.error}', textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.error))));
                  final data = snapshot.data ?? [];
                  if (data.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(16.0), child: Text(_searchTerm.isNotEmpty || _filterType != 'all' ? 'لا توجد حسابات تطابق البحث أو الفلتر.' : 'لا توجد حسابات لعرضها لهذا المتجر.', style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey[600]), textAlign: TextAlign.center)));
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 80),
                    itemCount: data.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final summary = data[index];
                      final balance = summary.balance;
                      final balanceColor = balance > 0.01 ? Colors.green.shade700 : (balance < -0.01 ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant);
                      final lastDateStr = summary.lastTransactionDate != null ? '${summary.lastTransactionDate!.toLocal().year}-${summary.lastTransactionDate!.toLocal().month.toString().padLeft(2, '0')}-${summary.lastTransactionDate!.toLocal().day.toString().padLeft(2, '0')}' : 'لا يوجد';
                      return Card(
                        margin: EdgeInsets.zero,
                        elevation: 1.5,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 14.0),
                          leading: CircleAvatar(radius: 22, backgroundColor: summary.isExternal ? theme.colorScheme.secondaryContainer.withOpacity(0.6) : theme.colorScheme.primaryContainer.withOpacity(0.6), child: Icon(summary.isExternal ? Icons.business_center_outlined : Icons.person_pin_circle_outlined, color: summary.isExternal ? theme.colorScheme.onSecondaryContainer : theme.colorScheme.onPrimaryContainer, size: 20)),
                          title: Text(summary.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                          subtitle: Text('آخر عملية: $lastDateStr', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[700])),
                          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [Text(balance.toStringAsFixed(2), style: TextStyle(color: balanceColor, fontWeight: FontWeight.bold, fontSize: 14)), const Text('ر.ي', style: TextStyle(fontSize: 10, color: Colors.grey))]),
                          onTap: () => _navigateToDetails(summary),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          dense: true,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: _showAddAccountDialog, icon: const Icon(Icons.add_business_outlined), label: const Text('إضافة حساب خارجي')),
    );
  }
}