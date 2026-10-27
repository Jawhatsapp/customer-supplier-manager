// lib/presentation/widgets/support_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class _ChangeLogEntry {
  final String version;
  final String? date;
  final List<String> items;
  const _ChangeLogEntry(this.version, this.date, this.items);
}

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  // ====== عدّل هذه القيم متى شئت ======
  static const String appName = 'تطبيق إدارة حسابات العملاء والموردين';
  static const String appVersion = '1.1.0';
  static const String developerAlias = 'JA-MOD';
  static const String developerName = 'جلال الدين الاهدل';
  static const String email = 'jalaladdin15000@gmail.com';
  static const String phoneDisplay = '+967 717 622 071';
  static const String whatsappNumber = '967717622071';
  static const String channelUrl = ''; // ضع رابط قناتك هنا ليظهر زرها (اتركه فارغاً لإخفائه)

  // سجل التغييرات: أضف إصداراً جديداً في أول القائمة عند كل تحديث
  static const List<_ChangeLogEntry> changelog = [
    _ChangeLogEntry('1.1.0', '2026-10-27', [
      'إضافة قسم الدعم والمعلومات.',
      'إضافة سجل التغييرات ومعلومات المطوّر.',
    ]),
    _ChangeLogEntry('1.0.0', null, [
      'الإصدار الأول: المتاجر والمنتجات والطلبات.',
      'دفتر الحسابات والتقارير المالية وتقارير المبيعات.',
      'المرتجعات والعمليات اليدوية والإشعارات.',
      'أدوار: عميل، تاجر تجزئة، مورد، مع موافقة الإدارة.',
    ]),
  ];

  Future<void> _open(BuildContext context, Uri uri, String fallbackCopy) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return;
    } catch (_) {}
    await Clipboard.setData(ClipboardData(text: fallbackCopy));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر فتح التطبيق، تم نسخ البيانات')),
      );
    }
  }

  Future<void> _copy(BuildContext context, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم النسخ')),
      );
    }
  }

  Widget _contactTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
    required String copyValue,
  }) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      subtitle: Text(value, textDirection: TextDirection.ltr, textAlign: TextAlign.start),
      trailing: IconButton(
        icon: const Icon(Icons.copy, size: 20),
        tooltip: 'نسخ',
        onPressed: () => _copy(context, copyValue),
      ),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(title: const Text('الدعم والمعلومات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // بطاقة التطبيق
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.storefront_outlined, size: 48, color: primary),
                  const SizedBox(height: 12),
                  Text(appName,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text('الإصدار $appVersion', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // بطاقة التواصل
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text('تواصل معنا',
                      style: theme.textTheme.titleSmall?.copyWith(color: primary, fontWeight: FontWeight.bold)),
                ),
                _contactTile(
                  context: context,
                  icon: Icons.email_outlined,
                  title: 'البريد الإلكتروني',
                  value: email,
                  copyValue: email,
                  onTap: () => _open(context, Uri.parse('mailto:$email'), email),
                ),
                _contactTile(
                  context: context,
                  icon: Icons.chat_outlined,
                  title: 'واتساب',
                  value: phoneDisplay,
                  copyValue: '+$whatsappNumber',
                  onTap: () => _open(context, Uri.parse('https://wa.me/$whatsappNumber'), '+$whatsappNumber'),
                ),
                if (channelUrl.isNotEmpty)
                  _contactTile(
                    context: context,
                    icon: Icons.campaign_outlined,
                    title: 'القناة',
                    value: channelUrl,
                    copyValue: channelUrl,
                    onTap: () => _open(context, Uri.parse(channelUrl), channelUrl),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // بطاقة سجل التغييرات
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('سجل التغييرات',
                      style: theme.textTheme.titleSmall?.copyWith(color: primary, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  for (final entry in changelog) ...[
                    const SizedBox(height: 8),
                    Text(
                      entry.date == null ? 'الإصدار ${entry.version}' : 'الإصدار ${entry.version}  •  ${entry.date}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    for (final item in entry.items)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('•  '),
                            Expanded(child: Text(item)),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // التذييل
          Center(
            child: Column(
              children: [
                Text('تم التطوير بواسطة', style: theme.textTheme.bodySmall),
                const SizedBox(height: 2),
                Text(developerName,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                Text(developerAlias, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
