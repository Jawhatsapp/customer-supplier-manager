// lib/presentation/currencies/currency_management_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CurrencyManagementScreen extends StatefulWidget {
  final int storeId;

  const CurrencyManagementScreen({Key? key, required this.storeId}) : super(key: key);

  @override
  State<CurrencyManagementScreen> createState() => _CurrencyManagementScreenState();
}

class _CurrencyManagementScreenState extends State<CurrencyManagementScreen> {
  late Future<List<Map<String, dynamic>>> _currenciesFuture;

  @override
  void initState() {
    super.initState();
    _currenciesFuture = _fetchCurrencies();
  }

  Future<List<Map<String, dynamic>>> _fetchCurrencies() async {
    final res = await Supabase.instance.client
        .from('currencies')
        .select()
        .eq('store_id', widget.storeId)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> _refresh() async {
    setState(() {
      _currenciesFuture = _fetchCurrencies();
    });
  }

  Future<void> _addOrEditCurrency({Map<String, dynamic>? currency}) async {
    final isEdit = currency != null;
    final codeCtrl = TextEditingController(text: currency?['currency_code'] ?? '');
    final nameCtrl = TextEditingController(text: currency?['currency_name'] ?? '');
    final rateCtrl = TextEditingController(
      text: currency?['rate_to_base']?.toString() ?? '',
    );

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'تعديل عملة' : 'إضافة عملة'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: codeCtrl,
                decoration: const InputDecoration(labelText: 'رمز العملة (مثل SAR)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'اسم العملة (اختياري)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: rateCtrl,
                decoration: const InputDecoration(labelText: 'معدل التحويل إلى الأساسي'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              final code = codeCtrl.text.trim();
              final cname= nameCtrl.text.trim();
              final rate = double.tryParse(rateCtrl.text.trim()) ?? 1.0;
              if (code.isEmpty || rate <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('البيانات غير صالحة')),
                );
                return;
              }
              try {
                if (!isEdit) {
                  // إضافة
                  await Supabase.instance.client.from('currencies').insert({
                    'store_id': widget.storeId,
                    'currency_code': code,
                    'currency_name': cname.isEmpty ? null : cname,
                    'rate_to_base': rate,
                  });
                } else {
                  // تعديل
                  await Supabase.instance.client.from('currencies').update({
                    'currency_code': code,
                    'currency_name': cname.isEmpty ? null : cname,
                    'rate_to_base': rate,
                  }).eq('id', currency!['id']);
                }
                Navigator.pop(ctx, true);
                _refresh();
              } catch (e) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('خطأ: $e')),
                );
              }
            },
            child: Text(isEdit ? 'حفظ' : 'إضافة'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteCurrency(int currencyId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل تريد حذف هذه العملة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('نعم')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await Supabase.instance.client
          .from('currencies')
          .delete()
          .eq('id', currencyId);

      _refresh();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ عند الحذف: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة العملات'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _currenciesFuture,
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('خطأ: ${snap.error}'));
          }
          final rows = snap.data ?? [];
          if (rows.isEmpty) {
            return const Center(child: Text('لا توجد عملات.'));
          }
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (ctx, i) {
              final row = rows[i];
              final code = row['currency_code'] as String;
              final cname= row['currency_name'] as String? ?? '';
              final rate = row['rate_to_base']?.toString() ?? '';
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                child: ListTile(
                  title: Text('$code (${cname.isNotEmpty ? cname : code})'),
                  subtitle: Text('المعدل: $rate'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (val) {
                      if (val == 'edit') {
                        _addOrEditCurrency(currency: row);
                      } else if (val == 'delete') {
                        _deleteCurrency(row['id'] as int);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('تعديل')),
                      PopupMenuItem(value: 'delete', child: Text('حذف')),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addOrEditCurrency(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
