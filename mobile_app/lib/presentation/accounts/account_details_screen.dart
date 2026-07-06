// lib/presentation/accounts/account_detail_screen.dart
import 'dart:convert';
import 'dart:io'; // لاستخدام File
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart'; // للوصول للمسار
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw; // لاستخدام مكتبة PDF
import 'package:printing/printing.dart'; // للمعاينة والمشاركة
import 'package:share_plus/share_plus.dart'; // لمشاركة الملفات الأخرى (مثل CSV)
import 'package:supabase_flutter/supabase_flutter.dart';
import '../manual_operations/add_manual_operation_sheet.dart';
import '../../utils/pdf_generator.dart'; // دالة إنشاء PDF

class AccountDetailScreen extends StatefulWidget {
    final String userId;
    final String userName;
    final int? storeId;

    const AccountDetailScreen({
        Key? key,
        required this.userId,
        required this.userName,
        this.storeId,
    }) : super(key: key);

    @override
    State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
    late Future<List<Map<String, dynamic>>> _linesFuture;
    String? _currentUserId;
    bool _isExporting = false; // حالة لتتبع عملية التصدير
    List<Map<String, dynamic>> _fetchedLines = [];

    @override
    void initState() {
        super.initState();
        _currentUserId = Supabase.instance.client.auth.currentUser?.id;
        _linesFuture = _fetchLines();
    }

    Future<List<Map<String, dynamic>>> _fetchLines() async {
        final supabase = Supabase.instance.client;
        final viewingUserId = widget.userId;
        // هذا الاستعلام يجلب بنود المعاملات المالية لـ user_id معين ويربطها بالمعاملة المالية الأصلية
        // ويتم فلترته حسب حالة المعاملة 'approved' واختيارياً حسب store_id
        var queryBuilder = supabase.from('transaction_lines').select(''' 
      id, created_at, type, amount, description, related_user_id, 
      transaction:financial_transactions!inner( id, store_id, payment_type, note, created_at, status ) 
    ''')
            .eq('user_id', viewingUserId)
            .eq('transaction.status', 'approved');
        if (widget.storeId != null) {
            queryBuilder = queryBuilder.eq('transaction.store_id', widget.storeId!);
        }
        try {
            final response = await queryBuilder.order('created_at', ascending: true);
            if (response is List) {
                _fetchedLines = List<Map<String, dynamic>>.from(response);
                return _fetchedLines;
            } else {
                // يجب أن تكون الاستجابة قائمة حتى لو كانت فارغة، أي تنسيق آخر هو خطأ غير متوقع
                throw Exception('تنسيق بيانات غير متوقع من قاعدة البيانات.');
            }
        } catch (e) {
            print("Error fetching transaction lines for user ${widget.userId} and store ${widget.storeId}: $e");
            // عرض خطأ للمستخدم فقط إذا كانت الشاشة لا تزال مثبتة
            if (mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('خطأ في جلب العمليات: ${e.toString()}')));
            }
            // إعادة رمي الخطأ للسماح لـ FutureBuilder بمعالجته (أو إرجاع قائمة فارغة مع رسالة خطأ)
            // هنا نختار إرجاع قائمة فارغة بعد عرض SnackBar
            return [];
        }
    }

    Future<void> _refreshData() async {
        // التحقق من mounted قبل setState آمن
        if (mounted) {
            setState(() {
                _linesFuture = _fetchLines(); // إعادة تعيين المستقبل
            });
            // Wait for the new future to complete before potentially finishing refresh indicator
            await _linesFuture;
        }
    }

    // دالة عرض ورقة العملية اليدوية
    void _showAddOperationSheet() {
        // هذه العملية تتطلب أن تكون مرتبطة بمتجر معين
        if (widget.storeId == null) {
            // يمكنك عرض رسالة خطأ هنا إذا لم يكن storeId متوفراً
            print("Attempted to add manual operation without storeId.");
            if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('لا يمكن إضافة عملية يدوية بدون تحديد المتجر.'))
                );
            }
            return;
        }

        showModalBottomSheet(
            context: context,
            isScrollControlled: true, // للسماح بتعديل الحجم عند ظهور لوحة المفاتيح
            builder: (context) => AddManualOperationSheet(
                storeId: widget.storeId!, // storeId مؤكد أنه غير null هنا
                counterpartyId: widget.userId, // userId للشخص الذي يتم عرض كشف حسابه
            ),
        ).then((value) {
            // أعد تحميل البيانات إذا تم إضافة عملية بنجاح (ورقة العمليات ترجع true)
            if (value == true) {
                _refreshData();
            }
        });
    }

    // دالة تصدير PDF
    Future<void> _exportToPdf() async {
        // لا تصدر إذا لا توجد بيانات أو جارٍ التصدير
        if (_fetchedLines.isEmpty || _isExporting) return;
        // تعيين حالة التصدير لإظهار مؤشر أو تعطيل الأزرار
        setState(() => _isExporting = true);

        try {
            double totalCredit = 0.0;
            double totalDebit = 0.0;
            // تجهيز بيانات الصفوف للـ PDF
            final List<Map<String, dynamic>> pdfLinesData = _fetchedLines.map((ln) {
                final type = ln['type'] as String?;
                // التعامل مع المبلغ كـ num أو String
                final amount = double.tryParse(ln['amount']?.toString() ?? '0') ?? 0.0;
                if (type == 'له') totalCredit += amount;
                if (type == 'عليه') totalDebit += amount;

                final transactionData = ln['transaction'] as Map<String, dynamic>?;
                // تفضيل تاريخ الـ transaction_line إن وجد، وإلا تاريخ الـ transaction الأصلية
                final dateStr = (ln['created_at'] as String?) ??
                    transactionData?['created_at'] as String? ??
                    ''; // Get string date

                final dateTime = DateTime.tryParse(dateStr)?.toLocal(); // Parse and convert to local time
                final dateDisplay = dateTime != null
                    ? '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}' // Format date
                    : dateStr.split('T').first; // Fallback if parsing fails

                final lineDesc = ln['description'] as String? ?? '';
                final trxNote = transactionData?['note'] as String? ?? '';
                // استخدام وصف السطر إذا كان موجوداً، وإلا استخدم ملاحظة المعاملة الأصلية
                final combinedDesc = (lineDesc.isNotEmpty ? lineDesc : trxNote).trim();

                return {
                    'dateDisplay': dateDisplay,
                    'combinedDesc': combinedDesc,
                    'type': type,
                    'amount': amount,
                };
            }).toList();

            final balance = totalCredit - totalDebit;

            // استدعاء دالة إنشاء PDF من ملف pdf_generator.dart
            // يمكنك تمرير storeName هنا أيضاً إذا أردت إظهاره في الـ PDF
            final pdfFile = await generateAccountStatementPdf(
                accountName: widget.userName,
                linesData: pdfLinesData,
                totalCredit: totalCredit,
                totalDebit: totalDebit,
                balance: balance,
                // storeName: 'اسم المتجر هنا', // يمكنك جلبه وتمريره
            );

            // عرض أو مشاركة الملف
            if (pdfFile != null && mounted) { // التحقق من mounted قبل استخدام context
                // عرض شاشة المعاينة باستخدام مكتبة Printing
                await Printing.layoutPdf(
                    onLayout: (PdfPageFormat format) async => pdfFile.readAsBytes(),
                    name: pdfFile.path.split('/').last, // اسم الملف في المعاينة
                );
            } else if (mounted) {
                _showMsg("فشل في إنشاء ملف PDF.", isError: true);
            }
        } catch (e) {
            print("Error exporting PDF: $e");
            if (mounted) _showMsg("حدث خطأ أثناء تصدير PDF: ${e.toString()}", isError: true);
        } finally {
            // إعادة تعيين حالة التصدير دائماً في finally
            if (mounted) setState(() => _isExporting = false);
        }
    }

    // دالة تصدير CSV
    Future<void> _exportToCsv() async {
        if (_fetchedLines.isEmpty || _isExporting) return;
        setState(() => _isExporting = true);

        try {
            List<List<dynamic>> rows = [];
            // إضافة الهيدر (تأكد من الترتيب الصحيح للأعمدة)
            rows.add(['التاريخ', 'الوصف', 'له', 'عليه', 'الرصيد']);
            double runningBalance = 0; // حساب الرصيد المتراكم

            for (var ln in _fetchedLines) {
                final transactionData = ln['transaction'] as Map<String, dynamic>?;
                final dateStr = (ln['created_at'] as String?) ??
                    transactionData?['created_at'] as String? ??
                    '';
                final dateTime = DateTime.tryParse(dateStr)?.toLocal();
                final dateDisplay = dateTime != null
                    ? '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}'
                    : dateStr.split('T').first; // Fallback if parsing fails

                final type = ln['type'] as String?;
                final amount = double.tryParse(ln['amount']?.toString() ?? '0') ?? 0.0;
                final lineDesc = ln['description'] as String? ?? '';
                final trxNote = transactionData?['note'] as String? ?? '';
                final combinedDesc = (lineDesc.isNotEmpty ? lineDesc : trxNote).trim();

                String creditVal = ''; // المبلغ الذي له
                String debitVal = ''; // المبلغ الذي عليه

                if (type == 'له') {
                    creditVal = amount.toStringAsFixed(2);
                    runningBalance += amount;
                } else if (type == 'عليه') {
                    debitVal = amount.toStringAsFixed(2);
                    runningBalance -= amount;
                }

                rows.add([dateDisplay, combinedDesc, creditVal, debitVal, runningBalance.toStringAsFixed(2)]);
            }

            // إضافة الملخص في نهاية الملف (اختياري)
            double totalCredit = 0.0, totalDebit = 0.0;
            // إعادة حساب المجاميع للتأكيد (يمكن استخدام القيم المحسوبة في حلقة الصفوف إذا كانت مضمونة الدقة)
            for (var l in _fetchedLines) {
                final type = l['type'] as String?;
                final amount = double.tryParse(l['amount']?.toString() ?? '0') ?? 0.0;
                if (type == 'له') { totalCredit += amount; }
                else if (type == 'عليه') { totalDebit += amount; }
            }
            final balance = totalCredit - totalDebit;

            rows.add([]); // سطر فارغ للفصل
            rows.add(['الإجمالي له:', '', totalCredit.toStringAsFixed(2), '', '']);
            rows.add(['الإجمالي عليه:', '', '', totalDebit.toStringAsFixed(2), '']);
            rows.add(['الرصيد النهائي:', '', '', '', balance.toStringAsFixed(2)]);


            // تحويل البيانات إلى CSV (مع التأكد من ترميز UTF-8 للعربية)
            String csvData = const ListToCsvConverter().convert(rows);

            // حفظ الملف مؤقتًا
            final directory = await getTemporaryDirectory();
            final path = '${directory.path}/kshf_7sab_${widget.userName.replaceAll(' ', '_').replaceAll(RegExp(r'[^\w\s]+'), '')}.csv'; // اسم ملف أنظف
            final file = File(path);
            await file.writeAsString(csvData, encoding: utf8); // استخدام utf8 للعربية

            // مشاركة الملف باستخدام share_plus
            if (mounted) { // التحقق من mounted قبل استخدام context
                final result = await Share.shareXFiles([XFile(path)], text: 'كشف حساب: ${widget.userName}');
                if (result.status == ShareResultStatus.success) {
                    print('CSV Shared successfully!');
                } else if (result.status == ShareResultStatus.dismissed) {
                    print('CSV Share dismissed.');
                } else { // failed
                    print('CSV Share failed: ${result.status}');
                    if (mounted) _showMsg("فشل مشاركة ملف CSV.", isError: true);
                }
            }
        } catch (e) {
            print("Error exporting CSV: $e");
            if (mounted) _showMsg("حدث خطأ أثناء تصدير CSV: ${e.toString()}", isError: true);
        } finally {
            if (mounted) setState(() => _isExporting = false);
        }
    }

    // دالة عرض الرسائل (SnackBar)
    void _showMsg(String msg, {bool isError = false}) {
        // التحقق من mounted قبل عرض SnackBar
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(msg),
                backgroundColor: isError ? Theme.of(context).colorScheme.error : Colors.green,
            ),
        );
    }

    @override
    Widget build(BuildContext context) {
        final theme = Theme.of(context);
        // تأكد من شرط ظهور زر العملية اليدوية بحسب المطلوب
        // الزر يجب أن يظهر فقط إذا كانت الشاشة تعرض كشف حساب مرتبط بمتجر (وليس الكشف العام)
        // والمالك لديه صلاحية إضافة عمليات يدوية لهذا الحساب (الشرط widget.storeId != null كافٍ حالياً)
        final bool canAddOperation = widget.storeId != null;

        return Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
                appBar: AppBar(
                    // عنوان الشاشة يعرض اسم المستخدم ونوع الكشف (إذا كان مرتبطاً بمتجر)
                    title: Text('كشف حساب: ${widget.userName}${widget.storeId != null ? ' (متجر ${widget.storeId})' : ''}'),
                    actions: [
                        // زر خيارات التصدير (PDF/CSV)
                        PopupMenuButton<String>(
                            icon: Icon(_isExporting ? Icons.hourglass_top : Icons.ios_share),
                            tooltip: 'تصدير الكشف',
                            enabled: !_isExporting, // تعطيل الأزرار أثناء التصدير
                            onSelected: (String result) {
                                if (result == 'pdf') {
                                    _exportToPdf();
                                } else if (result == 'csv') {
                                    _exportToCsv();
                                }
                            },
                            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                                const PopupMenuItem<String>(
                                    value: 'pdf',
                                    child: ListTile(
                                        leading: Icon(Icons.picture_as_pdf),
                                        title: Text('تصدير PDF'),
                                    ),
                                ),
                                const PopupMenuItem<String>(
                                    value: 'csv',
                                    child: ListTile(
                                        leading: Icon(Icons.table_chart),
                                        title: Text('تصدير Excel (CSV)'),
                                    ),
                                ),
                            ],
                        ),
                        // زر التحديث
                        IconButton(
                            icon: const Icon(Icons.refresh),
                            onPressed: _isExporting ? null : _refreshData, // تعطيل أثناء التصدير
                            tooltip: 'تحديث',
                        ),
                    ],
                ),
                body: RefreshIndicator(
                    onRefresh: _isExporting ? () async {} : _refreshData, // تعطيل السحب للتحديث أثناء التصدير
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                        future: _linesFuture, // المستقبل الذي يحمل بيانات العمليات
                        builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                                // عرض مؤشر التحميل أثناء جلب البيانات
                                return const Center(child: CircularProgressIndicator());
                            }
                            if (snapshot.hasError) {
                                // عرض رسالة خطأ واضحة في حالة الفشل
                                return Center(
                                    child: Padding(
                                        padding: const EdgeInsets.all(16.0),
                                        child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                                Icon(Icons.error_outline, color: theme.colorScheme.error, size: 48),
                                                const SizedBox(height: 16),
                                                Text('حدث خطأ أثناء تحميل كشف الحساب.', textAlign: TextAlign.center),
                                                const SizedBox(height: 8),
                                                Text('${snapshot.error}', style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                                                const SizedBox(height: 16),
                                                ElevatedButton.icon(
                                                    icon: const Icon(Icons.refresh),
                                                    label: const Text('إعادة المحاولة'),
                                                    onPressed: _isExporting ? null : _refreshData, // إعادة المحاولة
                                                )
                                            ],
                                        ),
                                    ),
                                );
                            }
                            // التعامل مع البيانات بنجاح
                            // حساب الملخص باستخدام البيانات المجلوبة بالفعل
                            double totalCredit = 0.0;
                            double totalDebit = 0.0;
                            for (var ln in _fetchedLines) { // استخدم _fetchedLines بدلاً من snapshot.data
                                final type = ln['type'] as String?;
                                final amount = double.tryParse(ln['amount']?.toString() ?? '0') ?? 0.0;
                                if (type == 'له') totalCredit += amount;
                                if (type == 'عليه') totalDebit += amount;
                            }
                            final balance = totalCredit - totalDebit;

                            // تعريف الأنماط والألوان للخلايا والعنوان
                            final headerStyle = theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurfaceVariant);
                            final cellStyle = theme.textTheme.bodyMedium;
                            final amountStyle = theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'); // خط أحادي المسافة للأرقام
                            final creditColor = Colors.green.shade700;
                            final debitColor = theme.colorScheme.error;

                            return Column(
                                children: [
                                    // رأس جدول المعاملات
                                    Container(
                                        color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        child: Row(
                                            children: [
                                                Expanded(flex: 2, child: Text('التاريخ', style: headerStyle)),
                                                Expanded(flex: 1, child: Text('النوع', style: headerStyle)),
                                                Expanded(flex: 2, child: Text('المبلغ', style: headerStyle, textAlign: TextAlign.end)),
                                                Expanded(flex: 3, child: Text('الوصف/ملاحظة', style: headerStyle)),
                                                // عرض عمود المتجر فقط في الكشف العام (حيث storeId == null)
                                                if (widget.storeId == null)
                                                    Expanded(flex: 1, child: Text('المتجر', style: headerStyle, textAlign: TextAlign.center)),
                                            ],
                                        ),
                                    ),
                                    // قائمة المعاملات
                                    Expanded(
                                        child: _fetchedLines.isEmpty // استخدام _fetchedLines
                                            ? Center(
                                            child: Padding(
                                                padding: const EdgeInsets.all(16.0),
                                                child: Text(
                                                    // رسالة مناسبة إذا كانت القائمة فارغة
                                                    widget.storeId != null
                                                        ? 'لا توجد عمليات لهذا الحساب في المتجر المحدد.'
                                                        : 'لا توجد عمليات مسجلة لهذا الحساب.',
                                                    style: theme.textTheme.titleMedium,
                                                    textAlign: TextAlign.center,
                                                ),
                                            ),
                                        )
                                            : ListView.separated(
                                            physics: const AlwaysScrollableScrollPhysics(), // لتمكين السحب للتحديث حتى لو القائمة قصيرة
                                            padding: const EdgeInsets.only(bottom: 80.0), // إضافة padding سفلي لتجنب تداخل الـ FAB والملخص
                                            itemCount: _fetchedLines.length,
                                            separatorBuilder: (context, index) => const Divider(height: 0, thickness: 0.5), // فاصل بين الصفوف
                                            itemBuilder: (ctx, i) {
                                                final ln = _fetchedLines[i];
                                                final transactionData = ln['transaction'] as Map<String, dynamic>?;
                                                // استخراج وتنسيق التاريخ
                                                final dateStr = (ln['created_at'] as String?) ?? transactionData?['created_at'] as String? ?? '';
                                                final dateTime = DateTime.tryParse(dateStr)?.toLocal();
                                                final dateDisplay = dateTime != null ? '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}' : dateStr.split('T').first;

                                                final type = ln['type'] ?? '?';
                                                final amount = double.tryParse(ln['amount']?.toString() ?? '0') ?? 0.0;
                                                final lineDesc = ln['description'] as String? ?? '';
                                                final trxNote = transactionData?['note'] as String? ?? '';
                                                final combinedDesc = (lineDesc.isNotEmpty ? lineDesc : trxNote).trim();
                                                final storeDisplayId = transactionData?['store_id']?.toString() ?? '-';
                                                final typeColor = type == 'له'
                                                    ? creditColor // لون أخضر للمبلغ الذي له
                                                    : (type == 'عليه' ? debitColor : theme.colorScheme.onSurface); // لون أحمر للمبلغ الذي عليه

                                                return Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                    child: Row(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                            Expanded(flex: 2, child: Text(dateDisplay, style: cellStyle?.copyWith(fontSize: 13))),
                                                            Expanded(flex: 1, child: Text(type, style: cellStyle?.copyWith(color: typeColor, fontWeight: FontWeight.bold))),
                                                            Expanded(flex: 2, child: Text(amount.toStringAsFixed(2), style: amountStyle, textAlign: TextAlign.end)),
                                                            Expanded(flex: 3, child: Text(combinedDesc, style: cellStyle?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
                                                            // عرض معرف المتجر فقط في الكشف العام
                                                            if (widget.storeId == null)
                                                                Expanded(flex: 1, child: Text(storeDisplayId, style: cellStyle, textAlign: TextAlign.center)),
                                                        ],
                                                    ),
                                                );
                                            },
                                        ),
                                    ),
                                    // قسم الملخص في الأسفل
                                    Container(
                                        decoration: BoxDecoration(
                                            color: theme.cardColor, // لون خلفية مناسب
                                            border: Border(top: BorderSide(color: theme.dividerColor)), // خط فاصل علوي
                                            boxShadow: [ // ظل خفيف لتمييزه عن القائمة
                                                BoxShadow(
                                                    color: Colors.black.withOpacity(0.05),
                                                    blurRadius: 4,
                                                    offset: const Offset(0, -2),
                                                ),
                                            ],
                                        ),
                                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                                        child: DefaultTextStyle( // تطبيق نمط نص افتراضي
                                            style: theme.textTheme.bodyLarge ?? const TextStyle(),
                                            child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.stretch, // جعل العناصر تأخذ كامل العرض
                                                children: [
                                                    Row(
                                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                        children: [
                                                            const Text('الإجمالي له:'),
                                                            Text('${totalCredit.toStringAsFixed(2)} ر.ي',
                                                                style: TextStyle(color: creditColor, fontWeight: FontWeight.bold)),
                                                        ],
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Row(
                                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                        children: [
                                                            const Text('الإجمالي عليه:'),
                                                            Text('${totalDebit.toStringAsFixed(2)} ر.ي',
                                                                style: TextStyle(color: debitColor, fontWeight: FontWeight.bold)),
                                                        ],
                                                    ),
                                                    const Divider(height: 16, thickness: 1), // خط فاصل
                                                    Row(
                                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                        children: [
                                                            Text('الرصيد الحالي:', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                                                            Text(
                                                                '${balance.toStringAsFixed(2)} ر.ي',
                                                                style: theme.textTheme.titleLarge?.copyWith(
                                                                    fontWeight: FontWeight.bold,
                                                                    color: balance >= 0 ? creditColor : debitColor, // لون الرصيد حسب القيمة
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

                // زر إضافة عملية يدوية (يظهر فقط إذا كان مرتبطاً بمتجر ويُسمح بإضافة عملية يدوية)
                floatingActionButton: canAddOperation
                    ? FloatingActionButton.extended(
                    onPressed: _isExporting ? null : _showAddOperationSheet, // تعطيل الزر أثناء التصدير
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة'), // تغيير النص قليلاً
                )
                    : null,
                // ★★★ تعديل مكان ظهور الـ FAB ★★★
                floatingActionButtonLocation: FloatingActionButtonLocation.startFloat, // يظهر في الأسفل جهة اليسار (start)
            ),
        );
    }
}