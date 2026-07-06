import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AccountLedgerScreen extends StatefulWidget {
  const AccountLedgerScreen({Key? key}) : super(key: key);

  @override
  State<AccountLedgerScreen> createState() => _AccountLedgerScreenState();
}

class _AccountLedgerScreenState extends State<AccountLedgerScreen> {
  late Future<List<Map<String, dynamic>>> _linesFuture;

  @override
  void initState() {
    super.initState();
    _linesFuture = _fetchLines();
  }

  Future<List<Map<String, dynamic>>> _fetchLines() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return [];

    // نجلب البنود التي تعود لهذا المستخدم
    final response = await Supabase.instance.client
        .from('transaction_lines')
        .select('''
          *,
          transaction:financial_transactions(order_id, store_id, payment_type, status, note, created_at),
          user:profiles!transaction_lines_user_id_fkey(first_name, last_name)
        ''') // لو أنشأت علاقة FK
        .eq('user_id', user.id)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  double _calculateTotal(List<Map<String, dynamic>> lines) {
    double total = 0;
    for (var l in lines) {
      final type = l['type'];
      final amount = double.tryParse(l['amount'].toString()) ?? 0;
      total += (type == 'له') ? amount : -amount;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context); // Get theme
    final creditColor = Colors.green.shade700;
    final debitColor = theme.colorScheme.error;

    return Scaffold(
      appBar: AppBar(
        // Uses theme styles
        title: const Text('دفتر الحسابات العام'), // More specific title
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _linesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            // Use themed indicator
            return Center(
                child: CircularProgressIndicator(
                    color: theme.colorScheme.primary));
          }
          if (snapshot.hasError) {
            // Use themed error message
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'خطأ في تحميل الدفتر: ${snapshot.error}',
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: theme.colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final lines = snapshot.data ?? [];
          final totalBalance = _calculateTotal(lines);

          // Determine balance color for the total
          final Color totalBalanceColor =
              totalBalance >= 0 ? creditColor : debitColor;

          return Column(
            children: [
              // Total Balance Header
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: theme.colorScheme.surfaceVariant
                    .withOpacity(0.3), // Subtle background
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'الرصيد الإجمالي:',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${totalBalance.toStringAsFixed(2)} ر.ي',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: totalBalanceColor,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 0), // Divider below total
              // Ledger Entries List
              Expanded(
                child: lines.isEmpty
                    ? Center(
                        // Themed empty state
                        child: Text(
                          'لا توجد قيود في الدفتر.',
                          style: theme.textTheme.titleMedium,
                        ),
                      )
                    : ListView.separated(
                        // Use separated for dividers
                        padding: const EdgeInsets.symmetric(
                            vertical: 8.0), // Padding for the list
                        itemCount: lines.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 0, indent: 16, endIndent: 16),
                        itemBuilder: (context, index) {
                          final line = lines[index];
                          final type = line['type'] as String? ?? '?';
                          final amount = double.tryParse(
                                  line['amount']?.toString() ?? '0') ??
                              0.0;
                          final transaction =
                              line['transaction'] as Map<String, dynamic>? ??
                                  {};
                          final orderId = transaction['order_id'];
                          final storeId = transaction['store_id'];
                          final createdAtStr = line['created_at'] as String? ??
                              transaction['created_at'] as String? ??
                              '';
                          final dateTime =
                              DateTime.tryParse(createdAtStr)?.toLocal();
                          final dateDisplay = dateTime != null
                              ? '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}'
                              : createdAtStr.split('T').first;
                          final note = line['description'] as String? ??
                              transaction['note'] as String? ??
                              ''; // Prefer line description
                          final payType =
                              transaction['payment_type'] as String? ?? '';

                          final typeColor = type == 'له'
                              ? creditColor
                              : (type == 'عليه'
                                  ? debitColor
                                  : theme.colorScheme.onSurface);

                          // Use themed ListTile inside a Card (optional, can remove Card if list dividers are enough)
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            title: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  type,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: typeColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${amount.toStringAsFixed(2)} ر.ي',
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: typeColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (note.isNotEmpty)
                                    Text('الوصف: $note',
                                        style: theme.textTheme.bodySmall),
                                  if (orderId != null)
                                    Text('مرتبط بطلب رقم: $orderId',
                                        style: theme.textTheme.bodySmall),
                                  if (storeId != null)
                                    Text('المتجر: $storeId',
                                        style: theme.textTheme.bodySmall),
                                  if (payType.isNotEmpty)
                                    Text('نوع الدفع: $payType',
                                        style: theme.textTheme.bodySmall),
                                  Text('التاريخ: $dateDisplay',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                              color: theme.colorScheme
                                                  .onSurfaceVariant)),
                                ],
                              ),
                            ),
                            // isThreeLine: true, // Adjust if needed based on content
                          );
                        },
                      ),
              )
            ],
          );
        },
      ),
    );
  }
}
