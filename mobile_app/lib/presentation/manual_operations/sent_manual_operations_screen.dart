import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SentManualOperationsScreen extends StatefulWidget {
  final int storeId; // معرف المتجر
  const SentManualOperationsScreen({Key? key, required this.storeId}) : super(key: key);

  @override
  State<SentManualOperationsScreen> createState() => _SentManualOperationsScreenState();
}

class _SentManualOperationsScreenState extends State<SentManualOperationsScreen> {
  late Future<List<Map<String, dynamic>>> _sentOpsFuture;

  // حفظ الحالة المختارة للفلترة. قيمنا الأساسية: all, pending, approved, rejected
  String _selectedStatus = 'all';

  // دالة لمطابقة الحالة الإنجليزية بعرض عربي
  String _mapStatusToArabic(String? status) {
    switch (status) {
      case 'pending':
        return 'معلقة';
      case 'approved':
        return 'موافقة';
      case 'rejected':
        return 'مرفوضة';
      default:
        return 'غير معروف';
    }
  }

  // دالة مساعدة لترجمة نوع العملية (مثال افتراضي)
  String _mapOperationTypeToArabic(String? opType) {
    switch (opType) {
      case 'credit':
        return 'إيداع';
      case 'debit':
        return 'سحب';
      default:
        return opType ?? 'غير محدد';
    }
  }

  // تنسيق الوقت
  String _formatDateTime(String? dateTimeStr) {
    if (dateTimeStr == null || dateTimeStr.isEmpty) return 'غير معروف';
    try {
      final dateTime = DateTime.parse(dateTimeStr).toLocal();
      return DateFormat('yyyy-MM-dd HH:mm').format(dateTime);
    } catch (_) {
      return dateTimeStr.split('T').first;
    }
  }

  @override
  void initState() {
    super.initState();
    _sentOpsFuture = _fetchSentOps();
  }

  Future<List<Map<String, dynamic>>> _fetchSentOps() async {
    final supabase = Supabase.instance.client;
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return [];

    final response = await supabase
        .from('manual_operations')
        .select()
        .eq('store_id', widget.storeId)
        .eq('initiator_id', currentUser.id)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // خريطة الحالات المسموحة مع عناوينها بالعربية
    // المفتاح هو القيمة الفعلية في الجدول، والقيمة النص العربي للعرض
    // 'all' تعني "لا توجد فلترة"
    final Map<String, String> statusFilters = {
      'all': 'الكل',
      'pending': 'معلقة',
      'approved': 'موافقة',
      'rejected': 'مرفوضة',
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('العمليات المرسلة'),
      ),
      body: Column(
        children: [
          // شريط الفلترة (الحالات)
          _buildFilterChips(statusFilters),

          // Expanded لعرض القائمة في المساحة المتبقية
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _sentOpsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'حدث خطأ أثناء تحميل العمليات: ${snapshot.error}',
                      style: TextStyle(color: theme.colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                final allOps = snapshot.data ?? [];
                if (allOps.isEmpty) {
                  return const Center(child: Text('لا توجد عمليات مرسلة حالياً.'));
                }

                // تطبيق الفلترة
                final visibleOps = (_selectedStatus == 'all')
                    ? allOps
                    : allOps.where((op) => op['status'] == _selectedStatus).toList();

                if (visibleOps.isEmpty) {
                  return Center(
                    child: Text(
                      'لا توجد عمليات بالحالة "${statusFilters[_selectedStatus]}"',
                      style: theme.textTheme.bodyMedium,
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: visibleOps.length,
                  padding: const EdgeInsets.all(12),
                  itemBuilder: (context, index) {
                    final op = visibleOps[index];
                    final opType   = _mapOperationTypeToArabic(op['operation_type'] as String?);
                    final status   = _mapStatusToArabic(op['status'] as String?);
                    final amount   = op['amount'] ?? 0;
                    final createdAt = _formatDateTime(op['created_at']?.toString());
                    final desc = (op['description'] ?? '') as String;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // صف العنوان مع الحالة
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'نوع العملية: $opType',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                // الحالة بعنصر مميز
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: (status == 'معلقة')
                                        ? Colors.orange.shade100
                                        : (status == 'موافقة')
                                        ? Colors.green.shade100
                                        : (status == 'مرفوضة')
                                        ? Colors.red.shade100
                                        : Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    status,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: (status == 'معلقة')
                                          ? Colors.orange.shade800
                                          : (status == 'موافقة')
                                          ? Colors.green.shade800
                                          : (status == 'مرفوضة')
                                          ? Colors.red.shade800
                                          : Colors.grey.shade800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // المبلغ
                            Text(
                              'المبلغ: $amount ر.ي',
                              style: theme.textTheme.bodyMedium,
                            ),
                            // الوصف
                            if (desc.trim().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text(
                                  'الوصف: $desc',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            const SizedBox(height: 6),
                            // التاريخ
                            Text(
                              'تاريخ الإنشاء: $createdAt',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ودجت لبناء مجموعة من الـ ChoiceChip للفلترة
  Widget _buildFilterChips(Map<String, String> statusMap) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: statusMap.keys.map((key) {
          final label = statusMap[key] ?? key;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ChoiceChip(
              label: Text(label),
              selected: _selectedStatus == key,
              onSelected: (bool selected) {
                setState(() {
                  _selectedStatus = key;
                });
              },
            ),
          );
        }).toList(),
      ),
    );
  }
}
