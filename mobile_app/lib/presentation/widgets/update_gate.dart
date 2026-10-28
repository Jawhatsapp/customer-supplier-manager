// lib/presentation/widgets/update_gate.dart
//
// نافذة «تحديث متوفر» داخل التطبيق (Shorebird).
// - عند فتح التطبيق (وعند الرجوع إليه) يتحقق إن كان هناك تصحيح (patch) جديد.
// - الرسالة ونوع التحديث (اختياري/إجباري) تأتي من جدول app_updates في Supabase (من لوحة الأدمن).
// - اختياري: «تحديث الآن» أو «لاحقاً». إجباري: «تحديث الآن» فقط ولا يمكن تجاوز النافذة.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String _kLastUpdateId = 'last_applied_update_id';
const String _kDefaultTitle = 'تحديث جديد متوفر';
const String _kDefaultMessage = 'يتوفر تحديث جديد للتطبيق فيه تحسينات وميزات جديدة.';

enum _PatchState { none, available, downloaded }

class _UpdateInfo {
  final int? id;
  final String title;
  final String message;
  final bool isMandatory;
  const _UpdateInfo({
    this.id,
    required this.title,
    required this.message,
    required this.isMandatory,
  });
}

/// يغلّف التطبيق كله ويعرض نافذة التحديث عند الحاجة.
class UpdateGate extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  const UpdateGate({super.key, required this.navigatorKey, required this.child});

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> with WidgetsBindingObserver {
  bool _busy = false; // فحص جارٍ أو نافذة مفتوحة
  bool _skipThisSession = false; // ضغط «لاحقاً» في هذه الجلسة

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // تأخير بسيط حتى تستقر الواجهة الأولى قبل الفحص
    Future<void>.delayed(const Duration(seconds: 2), _check);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  ShorebirdUpdater? _newUpdater() {
    try {
      final u = ShorebirdUpdater();
      return u.isAvailable ? u : null;
    } catch (e) {
      debugPrint('Shorebird unavailable: $e');
      return null;
    }
  }

  Future<_PatchState> _checkPatch(ShorebirdUpdater updater) async {
    try {
      final status = await updater.checkForUpdate();
      if (status == UpdateStatus.outdated) return _PatchState.available;
      if (status == UpdateStatus.restartRequired) return _PatchState.downloaded;
    } catch (e) {
      debugPrint('checkForUpdate failed: $e');
    }
    return _PatchState.none;
  }

  Future<_UpdateInfo?> _fetchInfo() async {
    try {
      final res = await Supabase.instance.client
          .from('app_updates')
          .select('id, title, message, is_mandatory')
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(1);
      final list = res as List<dynamic>;
      if (list.isEmpty) return null;
      final m = Map<String, dynamic>.from(list.first as Map);
      final id = m['id'];
      final title = (m['title'] ?? '').toString().trim();
      final message = (m['message'] ?? '').toString().trim();
      return _UpdateInfo(
        id: id is int ? id : int.tryParse('$id'),
        title: title.isEmpty ? _kDefaultTitle : title,
        message: message.isEmpty ? _kDefaultMessage : message,
        isMandatory: m['is_mandatory'] == true,
      );
    } catch (e) {
      debugPrint('fetch app_updates failed: $e');
      return null;
    }
  }

  Future<void> _check() async {
    if (_busy || _skipThisSession || !mounted) return;
    _busy = true;
    try {
      final updater = _newUpdater();
      if (updater == null) return; // نسخة تجريبية/غير مبنية بـ Shorebird
      final state = await _checkPatch(updater);
      if (state == _PatchState.none) return;

      var info = await _fetchInfo();

      // إذا كانت هذه الرسالة نفسها سبق أن طُبّقت، فهي قديمة: نعرض النص الافتراضي
      // (اختياري) حتى لا تظهر رسالة قديمة/إجبارية لتصحيح جديد لم تكتب له رسالة.
      if (info?.id != null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          if (prefs.getInt(_kLastUpdateId) == info!.id) info = null;
        } catch (_) {}
      }
      info ??= const _UpdateInfo(
        title: _kDefaultTitle,
        message: _kDefaultMessage,
        isMandatory: false,
      );

      final ctx = widget.navigatorKey.currentContext;
      if (ctx == null || !mounted) return;

      final later = await showDialog<bool>(
        context: ctx,
        barrierDismissible: false,
        builder: (_) => _UpdateDialog(
          info: info!,
          updater: updater,
          alreadyDownloaded: state == _PatchState.downloaded,
        ),
      );
      if (later == true) _skipThisSession = true;
    } catch (e) {
      debugPrint('update check error: $e');
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

enum _Phase { prompt, downloading, ready, error }

class _UpdateDialog extends StatefulWidget {
  final _UpdateInfo info;
  final ShorebirdUpdater updater;
  final bool alreadyDownloaded;

  const _UpdateDialog({
    required this.info,
    required this.updater,
    required this.alreadyDownloaded,
  });

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  late _Phase _phase = widget.alreadyDownloaded ? _Phase.ready : _Phase.prompt;
  String? _error;

  bool get _mandatory => widget.info.isMandatory;

  Future<void> _startUpdate() async {
    setState(() {
      _phase = _Phase.downloading;
      _error = null;
    });
    try {
      await widget.updater.update();
      if (widget.info.id != null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt(_kLastUpdateId, widget.info.id!);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() => _phase = _Phase.ready);
    } catch (e) {
      debugPrint('update failed: $e');
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = 'تعذر تنزيل التحديث. تأكد من اتصالك بالإنترنت وحاول مرة أخرى.';
      });
    }
  }

  Future<void> _closeApp() async {
    // التصحيح يُطبَّق عند الفتح التالي، فنغلق التطبيق تماماً ليفتحه المستخدم من جديد.
    await SystemNavigator.pop();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    String body;
    switch (_phase) {
      case _Phase.ready:
        body = 'تم تنزيل التحديث بنجاح. اغلق التطبيق ثم افتحه من جديد لتظهر التغييرات.';
        break;
      case _Phase.downloading:
        body = 'جاري تنزيل التحديث... يرجى الانتظار وعدم إغلاق التطبيق.';
        break;
      default:
        body = widget.info.message;
    }

    final actions = <Widget>[];
    switch (_phase) {
      case _Phase.prompt:
        if (!_mandatory) {
          actions.add(TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('لاحقاً'),
          ));
        }
        actions.add(ElevatedButton(onPressed: _startUpdate, child: const Text('تحديث الآن')));
        break;
      case _Phase.error:
        if (!_mandatory) {
          actions.add(TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('إغلاق'),
          ));
        }
        actions.add(ElevatedButton(onPressed: _startUpdate, child: const Text('إعادة المحاولة')));
        break;
      case _Phase.ready:
        actions.add(ElevatedButton(onPressed: _closeApp, child: const Text('إغلاق التطبيق وفتحه من جديد')));
        break;
      case _Phase.downloading:
        break;
    }

    return PopScope(
      canPop: false, // لا إغلاق بزر الرجوع؛ الخروج فقط عبر الأزرار
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.system_update_alt_rounded, color: primary),
            const SizedBox(width: 10),
            Expanded(child: Text(widget.info.title, style: const TextStyle(fontWeight: FontWeight.bold))),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(body, style: const TextStyle(height: 1.5)),
              if (_phase == _Phase.prompt && _mandatory) ...[
                const SizedBox(height: 12),
                Text(
                  'هذا التحديث إلزامي، ولا يمكن متابعة استخدام التطبيق قبل تثبيته.',
                  style: TextStyle(color: theme.colorScheme.error, fontSize: 13, height: 1.4),
                ),
              ],
              if (_phase == _Phase.downloading) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
              if (_phase == _Phase.error && _error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 13, height: 1.4)),
              ],
            ],
          ),
        ),
        actions: actions,
      ),
    );
  }
}
