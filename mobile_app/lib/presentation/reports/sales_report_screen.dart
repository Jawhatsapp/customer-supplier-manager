// lib/presentation/reports/sales_report_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Provider;
import '../../providers/auth_provider.dart'; // لجلب storeId إذا لم يُمرر
import 'package:intl/intl.dart'; // لتنسيق الأرقام والتواريخ

class SalesReportScreen extends StatefulWidget {
  final int? storeId; // يمكن تمريره أو جلبه من AuthProvider

  const SalesReportScreen({Key? key, this.storeId}) : super(key: key);

  @override
  State<SalesReportScreen> createState() => _SalesReportScreenState();
}

class _SalesReportScreenState extends State<SalesReportScreen> {
  final _supabase = Supabase.instance.client;

  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1); // بداية الشهر الحالي
  DateTime _endDate = DateTime.now(); // اليوم الحالي

  int? _currentStoreId;
  Future<Map<String, dynamic>?>? _reportFuture; // لتخزين نتيجة RPC

  @override
  void initState() {
    super.initState();
    _currentStoreId = widget.storeId ?? Provider.of<AuthProvider>(context, listen: false).storeId;
    if (_currentStoreId != null) {
      _fetchReportData(); // الجلب الأولي
    }
  }

  // دالة جلب بيانات التقرير باستخدام RPC
  void _fetchReportData() {
    if (_currentStoreId == null) {
      print("Store ID is null, cannot fetch report.");
      // عرض خطأ للمستخدم أو التعامل معه
      setState(() {
        _reportFuture = Future.value(null); // تعيين قيمة افتراضية للـ FutureBuilder
      });
      return;
    }
    if (!mounted) return;

    // تحديث Future لبدء FutureBuilder من جديد
    setState(() {
      _reportFuture = _supabase.rpc(
        'get_store_sales_report', // اسم الدالة التي أنشأناها
        params: {
          'p_store_id': _currentStoreId,
          // إرسال التواريخ بتنسيق ISO 8601 (Supabase يفهمها)
          // تأكد من أن start_date يمثل بداية اليوم و end_date يمثل نهاية اليوم
          'p_start_date': DateFormat('yyyy-MM-dd').format(_startDate), // بداية اليوم
          'p_end_date': DateFormat('yyyy-MM-dd').format(_endDate),     // نهاية اليوم (الدالة SQL تتعامل مع النطاق بشكل صحيح)
        },
      ).then((response) {
        // RPC يرجع عادة قائمة، حتى لو كانت تحتوي على صف واحد
        if (response is List && response.isNotEmpty) {
          print("Report RPC Response: ${response.first}");
          return response.first as Map<String, dynamic>;
        } else if (response is Map) {
          // احتياطي إذا أرجعت الدالة كائنًا واحدًا مباشرة
          print("Report RPC Response (Map): $response");
          return response as Map<String, dynamic>;
        }
        print("Report RPC Response: Unexpected format or empty list - $response");
        return null; // إرجاع null إذا كانت البيانات غير متوقعة أو فارغة
      }).catchError((error) {
        print("Error calling RPC get_store_sales_report: $error");
        if (mounted) {
          _showMsg("خطأ في جلب بيانات التقرير: ${error is PostgrestException ? error.message : error}", isError: true);
        }
        // رمي الخطأ مرة أخرى ليتم التقاطه بواسطة FutureBuilder
        throw error;
      });
    });
  }

  // دالة اختيار نطاق التاريخ
  Future<void> _selectDateRange(BuildContext context) async {
    final initialRange = DateTimeRange(start: _startDate, end: _endDate);
    final newRange = await showDateRangePicker(
      context: context,
      initialDateRange: initialRange,
      firstDate: DateTime(2020), // تاريخ بداية معقول
      lastDate: DateTime.now().add(const Duration(days: 1)), // السماح باختيار اليوم الحالي
      // يمكنك إضافة locale هنا للغة العربية
      // locale: const Locale('ar'),
      builder: (context, child) { // لتطبيق الثيم على منتقي التاريخ
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: Theme.of(context).colorScheme.primary, // لون التأكيد
              onPrimary: Colors.white, // لون النص على التأكيد
            ),
          ),
          child: child!,
        );
      },
    );

    if (newRange != null && newRange != initialRange && mounted) {
      setState(() {
        _startDate = newRange.start;
        _endDate = newRange.end;
      });
      _fetchReportData(); // إعادة جلب البيانات بالنطاق الجديد
    }
  }

  // دالة عرض الرسائل
  void _showMsg(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar( content: Text(msg), backgroundColor: isError ? Theme.of(context).colorScheme.error : Colors.green,),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // تنسيق العملة
    final currencyFormat = NumberFormat.currency(locale: 'ar', symbol: 'ر.ي');
    // تنسيق التاريخ للعرض
    final displayDateFormat = DateFormat('yyyy/MM/dd');

    return Scaffold(
      appBar: AppBar(
        title: const Text('تقرير المبيعات'),
      ),
      body: _currentStoreId == null
          ? const Center(child: Text('لم يتم تحديد المتجر لهذا التقرير.'))
          : Column(
        children: [
          // --- قسم اختيار التاريخ ---
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('النطاق الزمني:', style: theme.textTheme.labelMedium),
                        Text(
                          '${displayDateFormat.format(_startDate)} - ${displayDateFormat.format(_endDate)}',
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: Icon(Icons.calendar_month_outlined, color: theme.colorScheme.primary),
                      tooltip: 'تغيير نطاق التاريخ',
                      onPressed: () => _selectDateRange(context),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // --- قسم عرض نتائج التقرير ---
          Expanded(
            child: FutureBuilder<Map<String, dynamic>?>(
              future: _reportFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  // يتم عرض الخطأ عبر _showMsg، هنا نعرض رسالة عامة
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        'حدث خطأ أثناء تحميل التقرير. حاول مرة أخرى.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData || snapshot.data == null) {
                  return const Center(
                    child: Text('لا توجد بيانات مبيعات للفترة المحددة.'),
                  );
                }

                final reportData = snapshot.data!;
                // استخدام ?. و ?? للوصول الآمن للقيم
                final double totalSales = (reportData['total_sales'] as num?)?.toDouble() ?? 0.0;
                final int orderCount = (reportData['order_count'] as int?) ?? 0;

                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      _buildReportCard(
                        context: context,
                        title: 'إجمالي المبيعات',
                        value: currencyFormat.format(totalSales), // تنسيق العملة
                        icon: Icons.attach_money,
                        color: Colors.green.shade700,
                      ),
                      const SizedBox(height: 16),
                      _buildReportCard(
                        context: context,
                        title: 'عدد الطلبات المكتملة',
                        value: orderCount.toString(),
                        icon: Icons.shopping_cart_checkout,
                        color: theme.colorScheme.secondary,
                      ),
                      // يمكنك إضافة المزيد من الكروت هنا لاحقاً (متوسط قيمة الطلب مثلاً)
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ودجت مساعد لعرض كارت التقرير
  Widget _buildReportCard({
    required BuildContext context,
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0),
        child: Row(
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: color),
                    overflow: TextOverflow.ellipsis, // لمنع تجاوز النص
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

}