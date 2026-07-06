// lib/presentation/notifications/notification_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago; // مكتبة لعرض الوقت بشكل أفضل

import '../orders/order_detail_screen.dart';
import '../returns/approve_return_requests_screen.dart';
import '../manual_operations/approve_manual_operations_screen.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({Key? key}) : super(key: key);

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final _supabase = Supabase.instance.client;
  final List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  String? _errorMessage;
  StreamSubscription<List<Map<String, dynamic>>>? _notificationSubscription;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    // تهيئة اللغة العربية لـ timeago (ضعها مرة واحدة في main.dart أفضل)
    // timeago.setLocaleMessages('ar', timeago.ArMessages());
    _currentUserId = _supabase.auth.currentUser?.id;
    if (_currentUserId != null) {
      _initialFetchAndSubscribe();
    } else {
      if (mounted) {
        setState(() { _isLoading = false; _errorMessage = "يرجى تسجيل الدخول لعرض الإشعارات."; });
      }
    }
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initialFetchAndSubscribe() async {
    if (!mounted) return;
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final initialData = await _supabase.from('notifications').select().eq('user_id', _currentUserId!).order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _notifications.clear();
        _notifications.addAll(List<Map<String, dynamic>>.from(initialData));
        _isLoading = false;
      });
      _subscribeToNewNotifications();
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _errorMessage = "خطأ تحميل الإشعارات: $e"; });
    }
  }

  void _subscribeToNewNotifications() {
    _notificationSubscription?.cancel();
    _notificationSubscription = _supabase
        .from('notifications')
        .stream(primaryKey: ['id']).eq('user_id', _currentUserId!)
        .order('created_at', ascending: false)
        .listen(
            (List<Map<String, dynamic>> data) {
          if (!mounted) return;
          print("Realtime: Received ${data.length} notifications.");
          setState(() {
            // استخدام Map لدمج البيانات بكفاءة والحفاظ على الترتيب
            final Map<int, Map<String, dynamic>> combined = {};
            // إضافة البيانات الجديدة/المحدثة
            for (var item in data) { combined[item['id']] = item; }
            // إضافة البيانات القديمة غير الموجودة في التحديث
            for (var oldItem in _notifications) { combined.putIfAbsent(oldItem['id'], () => oldItem); }
            // تحويل الـ Map إلى قائمة مرتبة
            _notifications.clear();
            _notifications.addAll(combined.values.toList());
            _notifications.sort((a, b) => DateTime.parse(b['created_at']).compareTo(DateTime.parse(a['created_at'])));
          });
        },
        onError: (error) { print("Stream Error: $error"); },
        cancelOnError: false
    );
    print("Subscribed to notifications for $_currentUserId");
  }

  Future<void> _markAsRead(int notificationId, int index) async {
    if (!mounted || _notifications[index]['is_read'] == true) return;
    final originalState = _notifications[index]['is_read']; // حفظ الحالة الأصلية
    setState(() { _notifications[index]['is_read'] = true; });
    try {
      await _supabase.from('notifications').update({'is_read': true}).eq('id', notificationId);
    } catch (e) {
      if (mounted) {
        setState(() { _notifications[index]['is_read'] = originalState; }); // إعادة الحالة عند الفشل
        _showMsg("خطأ تحديث حالة الإشعار.", isError: true);
      }
    }
  }

  Future<void> _deleteNotification(int notificationId, int index) async {
    if (!mounted) return;
    final removedItem = _notifications.removeAt(index);
    setState(() {}); // تحديث فوري للواجهة
    try {
      await _supabase.from('notifications').delete().eq('id', notificationId);
    } catch (e) {
      if (mounted) {
        setState(() { _notifications.insert(index, removedItem); }); // إعادة العنصر عند الفشل
        _showMsg("خطأ حذف الإشعار.", isError: true);
      }
    }
  }

  // --- عرض تفاصيل الإشعار في Dialog ---
  void _showNotificationDetailsDialog(Map<String, dynamic> notification, int index) {
    // وضع علامة مقروء عند فتح التفاصيل
    if (notification['is_read'] == false) {
      _markAsRead(notification['id'] as int, index);
    }

    final String title = notification['title'] ?? 'تفاصيل الإشعار';
    final String message = notification['message'] ?? 'لا يوجد محتوى.';
    final DateTime createdAt = DateTime.tryParse(notification['created_at'] ?? '')?.toLocal() ?? DateTime.now();
    final bool canNavigate = notification['related_entity_type'] != null && notification['related_entity_id'] != null;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView( // للسماح بالتمرير إذا كان المحتوى طويلاً
          child: ListBody( // لعرض المحتوى بشكل منظم
            children: <Widget>[
              Text(message),
              const SizedBox(height: 10),
              Text(
                'تم الاستلام: ${_formatDateTime(createdAt)} (${timeago.format(createdAt, locale: 'ar')})', // عرض الوقت الدقيق والنسبي
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          // زر الانتقال (يظهر فقط إذا كان الانتقال ممكنًا)
          if (canNavigate)
            TextButton(
              child: const Text('الانتقال إلى التفاصيل'),
              onPressed: () {
                Navigator.of(context).pop(); // أغلق الحوار أولاً
                _navigateToDetails(notification); // ثم انتقل
              },
            ),
          TextButton(
            child: const Text('إغلاق'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }


  // --- الانتقال للتفاصيل (تُستدعى من الحوار) ---
  void _navigateToDetails(Map<String, dynamic> notification) {
    final String? entityType = notification['related_entity_type'];
    final int? entityId = notification['related_entity_id'] as int?;
    final int? storeId = notification['store_id'] as int?;

    // التحقق مرة أخرى (احتياطي)
    if (entityType == null || entityId == null) return;

    Widget? destination;
    try {
      switch (entityType) {
        case 'order': destination = OrderDetailScreen(orderId: entityId); break;
        case 'return_request': if (storeId != null) { destination = ApproveReturnRequestsScreen(storeId: storeId); } else { _showMsg("خطأ: Store ID مفقود للمرتجع."); } break;
        case 'manual_operation': destination = const ApproveManualOperationsScreen(); break;
        default: _showMsg("نوع إشعار غير مدعوم للانتقال: $entityType");
      }
    } catch(e) { /* ... handle error ... */ }

    if (destination != null && mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => destination!));
    }
  }

  void _showMsg(String msg, {bool isError = false}) { /* ... same ... */ if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar( SnackBar( content: Text(msg), backgroundColor: isError ? Theme.of(context).colorScheme.error : Colors.green,),); }

  // --- تنسيق التاريخ والوقت ---
  String _formatDateTime(DateTime dt) {
    // يمكنك استخدام intl إذا أضفت الاعتمادية وهيأتها
    // return DateFormat('yyyy/MM/dd hh:mm a', 'ar').format(dt);
    return '${dt.year}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}'; // تنسيق بسيط
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('الإشعارات')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_errorMessage!, style: TextStyle(color: theme.colorScheme.error), textAlign: TextAlign.center)))
          : _notifications.isEmpty
          ? Center( child: Text('لا توجد إشعارات حالياً.', style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey[600])))
          : RefreshIndicator(
        onRefresh: _initialFetchAndSubscribe,
        child: ListView.separated( // استخدام separated لإضافة فواصل
          padding: const EdgeInsets.all(10),
          itemCount: _notifications.length,
          separatorBuilder: (context, index) => Divider(height: 1, thickness: 0.5, indent: 60, endIndent: 10), // فاصل أنيق
          itemBuilder: (context, index) {
            final notif = _notifications[index];
            final bool isRead = notif['is_read'] ?? false;
            final String title = notif['title'] ?? 'بدون عنوان';
            final String message = notif['message'] ?? '';
            final DateTime createdAt = DateTime.tryParse(notif['created_at'] ?? '')?.toLocal() ?? DateTime.now();
            // استخدام timeago لعرض الوقت النسبي بشكل أفضل
            final String timeAgo = timeago.format(createdAt, locale: 'ar', allowFromNow: true);

            IconData leadingIcon = Icons.notifications_none_outlined; // أيقونة افتراضية
            if (notif['related_entity_type'] == 'order') leadingIcon = Icons.receipt_long_outlined;
            if (notif['related_entity_type'] == 'return_request') leadingIcon = Icons.undo_outlined;
            if (notif['related_entity_type'] == 'manual_operation') leadingIcon = Icons.edit_note_outlined;

            return Dismissible(
              key: ValueKey(notif['id']),
              direction: DismissDirection.endToStart,
              onDismissed: (direction) => _deleteNotification(notif['id'] as int, index),
              background: Container( color: Colors.red.shade100, padding: const EdgeInsets.only(right: 20.0), alignment: Alignment.centerRight, child: Icon(Icons.delete_outline, color: Colors.red.shade700),),
              child: ListTile(
                // تحسين التمييز البصري لـ isRead
                tileColor: isRead ? null : theme.colorScheme.primary.withOpacity(0.05),
                leading: CircleAvatar(
                  radius: 22,
                  backgroundColor: isRead ? Colors.grey.shade300 : theme.colorScheme.primary.withOpacity(0.8),
                  child: Icon(leadingIcon, size: 20, color: isRead ? Colors.grey.shade700 : Colors.white),
                ),
                title: Text( title, style: TextStyle(fontWeight: isRead ? FontWeight.normal : FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis,),
                subtitle: Text( message, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: isRead ? Colors.grey[600] : theme.textTheme.bodySmall?.color),),
                trailing: Text(timeAgo, style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
                onTap: () => _showNotificationDetailsDialog(notif, index), // فتح الحوار عند النقر
                contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              ),
            );
          },
        ),
      ),
    );
  }
}