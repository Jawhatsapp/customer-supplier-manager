// lib/presentation/reports/external_account_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/external_account_models.dart';
// استيراد واجهة إضافة المعاملة (سيتم إنشاؤها لاحقاً)
import 'add_external_transaction_dialog.dart';

class ExternalAccountDetailScreen extends StatefulWidget {
  final int externalAccountId;
  final int storeId;

  const ExternalAccountDetailScreen({
    Key? key,
    required this.externalAccountId,
    required this.storeId,
  }) : super(key: key);

  @override
  State<ExternalAccountDetailScreen> createState() =>
      _ExternalAccountDetailScreenState();
}

class _ExternalAccountDetailScreenState
    extends State<ExternalAccountDetailScreen> {
  late Future<ExternalAccount?> _accountDetailsFuture;
  late Future<List<ExternalAccountTransaction>> _transactionsFuture;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    _accountDetailsFuture = _fetchAccountDetails();
    _transactionsFuture = _fetchTransactions();
  }

  Future<ExternalAccount?> _fetchAccountDetails() async {
    try {
      final response = await Supabase.instance.client
          .from('external_accounts')
          .select()
          .eq('id', widget.externalAccountId)
          .eq('store_id', widget.storeId) // تأكيد أنه لنفس المتجر
          .maybeSingle(); // استخدام maybeSingle لأنه يجب أن يكون هناك حساب واحد أو لا شيء

      if (response != null) {
        return ExternalAccount.fromJson(response);
      }
      return null;
    } catch (e) {
      print("Error fetching external account details: $e");
      // يمكنك عرض خطأ للمستخدم
      return null;
    }
  }

  Future<List<ExternalAccountTransaction>> _fetchTransactions() async {
    try {
      final response = await Supabase.instance.client
          .from('external_account_transactions')
          .select()
          .eq('external_account_id', widget.externalAccountId)
          .order('transaction_date', ascending: false); // عرض الأحدث أولاً

      return (response as List)
          .map((data) => ExternalAccountTransaction.fromJson(data))
          .toList();
    } catch (e) {
      print("Error fetching external account transactions: $e");
      return [];
    }
  }

  Future<void> _refreshData() async {
    setState(() {
      _loadData();
    });
    // إرجاع true للإشارة إلى الشاشة السابقة بحدوث تغيير
    if(Navigator.canPop(context)) {
      // لا تغلق الشاشة هنا، فقط أرسل إشارة عند الإغلاق اليدوي
      // Navigator.pop(context, true);
    }
  }


  // --- دالة لفتح نافذة إضافة معاملة ---
  void _showAddTransactionDialog(ExternalAccount account) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AddExternalTransactionDialog(
          externalAccountId: widget.externalAccountId,
          storeId: widget.storeId,
          accountName: account.fullName,
          onTransactionAdded: _refreshData, // تحديث عند الإضافة
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: FutureBuilder<ExternalAccount?>(
          future: _accountDetailsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Text('تحميل...');
            }
            if (snapshot.hasData && snapshot.data != null) {
              return Text('كشف حساب: ${snapshot.data!.fullName}');
            }
            return const Text('تفاصيل الحساب');
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshData,
            tooltip: 'تحديث',
          )
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: FutureBuilder<List<dynamic>>( // استخدم Future.wait لتحميل الاثنين معاً
          future: Future.wait([_accountDetailsFuture, _transactionsFuture]),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
              return Center(child: Text('خطأ في تحميل البيانات: ${snapshot.error ?? "بيانات غير متوفرة"}'));
            }

            final accountDetails = snapshot.data![0] as ExternalAccount?;
            final transactions = snapshot.data![1] as List<ExternalAccountTransaction>;

            if (accountDetails == null) {
              return const Center(child: Text('لم يتم العثور على الحساب.'));
            }

            // حساب الملخص
            double totalCredit = 0;
            double totalDebit = 0;
            for (var trx in transactions) {
              if (trx.type == 'له') totalCredit += trx.amount;
              if (trx.type == 'عليه') totalDebit += trx.amount;
            }
            final balance = totalCredit - totalDebit;

            final headerStyle = theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurfaceVariant);
            final cellStyle = theme.textTheme.bodyMedium;
            final amountStyle = theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace');
            final creditColor = Colors.green.shade700;
            final debitColor = theme.colorScheme.error;

            return Column(
              children: [
                // --- عرض تفاصيل الحساب ---
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Card(
                    elevation: 0,
                    color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('الاسم: ${accountDetails.fullName}', style: theme.textTheme.titleMedium),
                          if (accountDetails.phone != null) Text('الهاتف: ${accountDetails.phone}'),
                          if (accountDetails.address != null) Text('العنوان: ${accountDetails.address}'),
                          Text('النوع: ${accountDetails.accountType}'), // يمكنك تحويل النوع لنص مقروء
                          if (accountDetails.details != null) Text('تفاصيل: ${accountDetails.details}'),
                        ],
                      ),
                    ),
                  ),
                ),
                // --- رأس جدول المعاملات ---
                Container(
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(flex: 2, child: Text('التاريخ', style: headerStyle)),
                      Expanded(flex: 1, child: Text('النوع', style: headerStyle)),
                      Expanded(flex: 2, child: Text('المبلغ', style: headerStyle, textAlign: TextAlign.end)),
                      Expanded(flex: 3, child: Text('الوصف', style: headerStyle)),
                    ],
                  ),
                ),
                // --- قائمة المعاملات ---
                Expanded(
                  child: transactions.isEmpty
                      ? Center(
                    child: Text(
                      'لا توجد معاملات مسجلة لهذا الحساب.',
                      style: theme.textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                  )
                      : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 80.0), // لتجنب FAB والملخص
                    itemCount: transactions.length,
                    separatorBuilder: (context, index) => const Divider(height: 0, thickness: 0.5),
                    itemBuilder: (ctx, i) {
                      final trx = transactions[i];
                      final date = trx.transactionDate.toLocal();
                      final dateDisplay = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                      final typeColor = trx.type == 'له' ? creditColor : debitColor;

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 2, child: Text(dateDisplay, style: cellStyle?.copyWith(fontSize: 13))),
                            Expanded(flex: 1, child: Text(trx.type, style: cellStyle?.copyWith(color: typeColor, fontWeight: FontWeight.bold))),
                            Expanded(flex: 2, child: Text(trx.amount.toStringAsFixed(2), style: amountStyle, textAlign: TextAlign.end)),
                            Expanded(flex: 3, child: Text(trx.description ?? '-', style: cellStyle?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                // --- قسم الملخص ---
                Container(
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    border: Border(top: BorderSide(color: theme.dividerColor)),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: DefaultTextStyle(
                    style: theme.textTheme.bodyLarge ?? const TextStyle(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('الإجمالي له:'),
                            Text('${totalCredit.toStringAsFixed(2)} ر.ي', style: TextStyle(color: creditColor, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('الإجمالي عليه:'),
                            Text('${totalDebit.toStringAsFixed(2)} ر.ي', style: TextStyle(color: debitColor, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const Divider(height: 16, thickness: 1),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('الرصيد الحالي:', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                            Text(
                              '${balance.toStringAsFixed(2)} ر.ي',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: balance >= 0 ? creditColor : debitColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                )
              ],
            );
          },
        ),
      ),
      // --- زر إضافة معاملة ---
      floatingActionButton: FutureBuilder<ExternalAccount?>(
          future: _accountDetailsFuture, // نعتمد على تحميل تفاصيل الحساب أولاً
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data != null) {
              return FloatingActionButton.extended(
                onPressed: () => _showAddTransactionDialog(snapshot.data!),
                icon: const Icon(Icons.add),
                label: const Text('إضافة معاملة'),
              );
            }
            return const SizedBox.shrink(); // لا تظهر الزر حتى يتم تحميل تفاصيل الحساب
          }
      ),
      // تأكد من إضافة WillPopScope إذا أردت إرسال إشارة عند الضغط على زر الرجوع
      // بناءً على ما إذا كان _refreshData قد تم استدعاؤه (تحتاج متغير حالة إضافي لتتبع ذلك)
    );
  }
}