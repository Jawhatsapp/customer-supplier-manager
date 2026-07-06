import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// دالة إنشاء PDF لكشف الحساب
Future<File?> generateAccountStatementPdf({
  required String accountName,
  required List<Map<String, dynamic>> linesData,
  required double totalCredit,
  required double totalDebit,
  required double balance,
  String? storeName,
}) async {
  final pdf = pw.Document();

  // تحميل الخطوط
  final fontData = await rootBundle.load("assets/fonts/Tajawal-Regular.ttf");
  final boldFontData = await rootBundle.load("assets/fonts/Tajawal-Bold.ttf");
  final ttf = pw.Font.ttf(fontData);
  final boldTtf = pw.Font.ttf(boldFontData);

  // تحميل شعار المتجر (اختياري)
  Uint8List? logoBytes;
  try {
    final logoData = await rootBundle.load('assets/logo.png');
    logoBytes = logoData.buffer.asUint8List();
  } catch (_) {
    logoBytes = null;
  }

  // إنشاء الصفحة
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      textDirection: pw.TextDirection.rtl,
      theme: pw.ThemeData.withFont(base: ttf, bold: boldTtf),
      margin: const pw.EdgeInsets.all(30),
      header: (context) => _buildHeader(accountName, storeName, logoBytes),
      footer: _buildFooter,
      build: (context) => [
        _buildTable(linesData),
        pw.SizedBox(height: 16),
        _buildSummary(totalCredit, totalDebit, balance),
        pw.SizedBox(height: 32),
        _buildSignature(),
      ],
    ),
  );

  try {
    final outputDir = await getTemporaryDirectory();
    final outputFile = File("${outputDir.path}/كشف_${accountName.replaceAll(' ', '_')}.pdf");
    await outputFile.writeAsBytes(await pdf.save());
    return outputFile;
  } catch (e) {
    print("خطأ في حفظ الملف: $e");
    return null;
  }
}

// --- Header مع الشعار واسم الحساب ---
pw.Widget _buildHeader(String name, String? storeName, Uint8List? logo) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      if (logo != null)
        pw.Container(
          alignment: pw.Alignment.centerLeft,
          margin: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Image(pw.MemoryImage(logo), width: 60),
        ),
      if (storeName != null)
        pw.Text(storeName, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
      pw.Text("كشف حساب: $name", style: pw.TextStyle(fontSize: 16)),
      pw.Text("تاريخ الطباعة: ${DateFormat('yyyy-MM-dd – HH:mm').format(DateTime.now())}", style: const pw.TextStyle(fontSize: 10)),
      pw.SizedBox(height: 10),
    ],
  );
}

// --- جدول البيانات ---
pw.Widget _buildTable(List<Map<String, dynamic>> lines) {
  final headers = ['التاريخ', 'الوصف', 'له', 'عليه', 'الرصيد'];
  double runningBalance = 0;

  final data = lines.map<List<String>>((line) {
    final type = line['type'] ?? '';
    final amount = (line['amount'] as num?)?.toDouble() ?? 0.0;
    final description = line['combinedDesc'] ?? '-';
    final dateStr = line['dateDisplay'] ?? '';
    final formattedDate = dateStr;

    String credit = '', debit = '';
    if (type == 'له') {
      credit = amount.toStringAsFixed(2);
      runningBalance += amount;
    } else if (type == 'عليه') {
      debit = amount.toStringAsFixed(2);
      runningBalance -= amount;
    }

    return [
      formattedDate,
      description,
      credit,
      debit,
      runningBalance.toStringAsFixed(2),
    ];
  }).toList();

  return pw.Table.fromTextArray(
    headers: headers,
    data: data,
    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
    cellStyle: const pw.TextStyle(fontSize: 9),
    border: pw.TableBorder.all(color: PdfColors.grey600),
    cellAlignment: pw.Alignment.centerRight,
    columnWidths: {
      0: const pw.FixedColumnWidth(60),
      1: const pw.FlexColumnWidth(3),
      2: const pw.FixedColumnWidth(45),
      3: const pw.FixedColumnWidth(45),
      4: const pw.FixedColumnWidth(55),
    },
  );
}

// --- ملخص الحساب ---
pw.Widget _buildSummary(double credit, double debit, double balance) {
  return pw.Container(
    alignment: pw.Alignment.centerLeft,
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('الإجمالي له: ${credit.toStringAsFixed(2)} ر.ي'),
        pw.Text('الإجمالي عليه: ${debit.toStringAsFixed(2)} ر.ي'),
        pw.Divider(),
        pw.Text('الرصيد النهائي: ${balance.toStringAsFixed(2)} ر.ي', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      ],
    ),
  );
}

// --- التوقيع ---
pw.Widget _buildSignature() {
  return pw.Align(
    alignment: pw.Alignment.centerLeft,
    child: pw.Text('توقيع المدير: ________________', style: const pw.TextStyle(fontSize: 12)),
  );
}

// --- فوتر الصفحة ---
pw.Widget _buildFooter(pw.Context context) {
  return pw.Container(
    alignment: pw.Alignment.center,
    margin: const pw.EdgeInsets.only(top: 10),
    child: pw.Text(
      'صفحة ${context.pageNumber} من ${context.pagesCount}',
      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey),
    ),
  );
}
