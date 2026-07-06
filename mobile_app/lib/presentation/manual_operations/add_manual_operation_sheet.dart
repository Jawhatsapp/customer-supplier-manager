// lib/presentation/manual_operations/add_manual_operation_sheet.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddManualOperationSheet extends StatefulWidget {
  final int storeId; // المتجر الذي سترتبط به العملية
  final String counterpartyId; // معرف الطرف الآخر الذي ستُرسل له العملية

  const AddManualOperationSheet({
    Key? key,
    required this.storeId,
    required this.counterpartyId,
  }) : super(key: key);

  @override
  State<AddManualOperationSheet> createState() =>
      _AddManualOperationSheetState();
}

class _AddManualOperationSheetState extends State<AddManualOperationSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _direction = 'له'; // القيمة الافتراضية
  bool _loading = false;

  Future<void> _submitOperation() async {
    if (!_formKey.currentState!.validate()) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('خطأ: يجب تسجيل الدخول أولاً')));
      return;
    }
    // التحقق مرة أخرى من عدم إرسال طلب للنفس
    if (user.id == widget.counterpartyId) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا يمكن إرسال طلب عملية لنفسك.')));
      return;
    }

    setState(() => _loading = true);

    try {
      final amount = double.parse(_amountCtrl.text.trim());
      final desc = _descCtrl.text.trim();

      // إنشاء طلب العملية اليدوية في الجدول بالحالة 'pending'
      final response = await Supabase.instance.client
          .from('manual_operations')
          .insert({
        'store_id': widget.storeId,
        'initiator_id': user.id, // المستخدم الحالي هو المبادر
        'counterparty_id': widget.counterpartyId, // الطرف الآخر
        'operation_type': 'يدوي', // نوع العملية
        'direction': _direction, // الاتجاه الذي اختاره المبادر ('له' أو 'عليه')
        'amount': amount,
        'description': desc.isEmpty ? null : desc, // الوصف اختياري
        'status': 'pending', // الحالة الأولية هي معلق للموافقة
        'created_by': user.id, // معرف من أنشأ السجل (قد يكون مفيداً)
      }).select('id').single(); // جلب معرف العملية التي تم إنشاؤها

      final createdOpId = response['id'];
      if (createdOpId == null) {
        throw Exception('فشل في إنشاء طلب العملية اليدوية.');
      }

      // جلب بيانات المبادر لإضافتها في رسالة الإشعار
      final profileResponse = await Supabase.instance.client
          .from('profiles')
          .select('first_name, last_name, role')
          .eq('id', user.id)
          .maybeSingle();

      String senderName = profileResponse?['first_name'] ?? user.email ?? 'مستخدم';
      String senderRole = profileResponse?['role'] ?? 'مستخدم'; // افتراض دور إذا لم يوجد

      final notificationMessage =
          'لديك طلب عملية يدوية (${_direction == 'له' ? 'هو مدين لك' : 'أنت مدين له'}) بقيمة $amount ر.ي من $senderName ($senderRole). المتجر: ${widget.storeId}.';

      // إرسال إشعار للطرف الآخر
      await Supabase.instance.client.from('notifications').insert({
        'user_id': widget.counterpartyId, // إرسال الإشعار للموافق المحتمل
        'title': 'طلب عملية مالية يدوية جديدة',
        'message': notificationMessage,
        // يمكنك إضافة حقول أخرى مثل type أو related_id إذا أردت
      });

      if (!mounted) return;
      Navigator.pop(context, true); // أغلق الشاشة وأرجع true للإشارة إلى النجاح المحتمل

      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال طلب العملية بنجاح للموافقة.')));

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ عند إرسال الطلب: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        // إضافة padding لتجنب لوحة المفاتيح
        padding: EdgeInsets.only(
          bottom: mq.viewInsets.bottom + 20,
          left: 16,
          right: 16,
          top: 20,
        ),
        child: SingleChildScrollView( // للسماح بالتمرير إذا كان المحتوى طويلاً
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min, // لجعل الـ BottomSheet يأخذ أقل ارتفاع ممكن
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'إضافة عملية مالية يدوية',
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                DropdownButtonFormField<String>(
                  value: _direction,
                  decoration: const InputDecoration(
                    labelText: 'اتجاه العملية بالنسبة لك',
                    prefixIcon: Icon(Icons.compare_arrows_outlined),
                    border: OutlineInputBorder(), // إضافة حدود
                  ),
                  items: const [
                    // !!! تحسين مقترح: اجعل هذه النصوص أوضح للمستخدم !!!
                    DropdownMenuItem(
                      value: 'له',
                      child: Text('له ( مدين)'),
                    ),
                    DropdownMenuItem(
                      value: 'عليه',
                      child: Text('عليه (دائن)'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _direction = val);
                  },
                  validator: (value) =>
                  value == null ? 'يرجى تحديد اتجاه العملية' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'المبلغ',
                    prefixIcon: Icon(Icons.monetization_on_outlined),
                    suffixText: 'ر.ي',
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) {
                    if (val == null || val.isEmpty) return 'يرجى إدخال المبلغ';
                    final parsed = double.tryParse(val);
                    if (parsed == null || parsed <= 0) {
                      return 'المبلغ يجب أن يكون رقماً أكبر من صفر';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'الوصف / ملاحظة (اختياري)',
                    prefixIcon: Icon(Icons.description_outlined),
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2, // تحديد عدد أسطر مناسب
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 24),
                // !!! تحسين مقترح: أضف رسالة تأكيد قبل استدعاء _submitOperation !!!
                // مثال باستخدام showDialog:
                /*
                 onPressed: _loading ? null : () {
                   if (_formKey.currentState!.validate()) {
                     showDialog(
                       context: context,
                       builder: (ctx) => AlertDialog(
                         title: Text('تأكيد العملية'),
                         content: Text('سيتم إرسال طلب لتسجيل عملية (${_direction == 'له' ? 'هو مدين لك' : 'أنت مدين له'}) بمبلغ ${_amountCtrl.text} ر.ي. هل أنت متأكد؟'),
                         actions: [
                           TextButton(onPressed: () => Navigator.pop(ctx), child: Text('إلغاء')),
                           ElevatedButton(onPressed: (){ Navigator.pop(ctx); _submitOperation(); }, child: Text('تأكيد وإرسال')),
                         ],
                       )
                     );
                   }
                 },
                 */
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                  icon: _loading
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white, // لون مناسب للزر
                    ),
                  )
                      : const Icon(Icons.send_outlined),
                  label: Text(
                      _loading ? 'جاري الإرسال...' : 'إرسال طلب العملية للموافقة'),
                  onPressed: _loading ? null : _submitOperation,
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }
}