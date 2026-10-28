// lib/presentation/store/store_chat_tab.dart
import 'package:badges/badges.dart' as badges;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// يخبر الدردشة هل تبويبها ظاهر الآن (حتى لا تُعلَّم الرسائل كمقروءة وهي مخفية)
final ValueNotifier<bool> chatTabVisible = ValueNotifier<bool>(false);

bool _isUnread(Map<String, dynamic> m, String me) =>
    m['sender_id'] != me && m['read_at'] == null && m['deleted'] != true;

String _hhmm(dynamic iso) {
  if (iso == null) return '';
  final d = DateTime.tryParse(iso.toString())?.toLocal();
  if (d == null) return '';
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------
// أيقونة التبويب مع عدّاد الرسائل غير المقروءة
// ---------------------------------------------------------------------
class ChatTabIcon extends StatefulWidget {
  final int storeId;
  const ChatTabIcon({Key? key, required this.storeId}) : super(key: key);

  @override
  State<ChatTabIcon> createState() => _ChatTabIconState();
}

class _ChatTabIconState extends State<ChatTabIcon> {
  Stream<List<Map<String, dynamic>>>? _stream;

  @override
  void initState() {
    super.initState();
    if (Supabase.instance.client.auth.currentUser != null) {
      _stream = Supabase.instance.client
          .from('chat_messages')
          .stream(primaryKey: ['id'])
          .eq('store_id', widget.storeId)
          .order('created_at', ascending: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = Supabase.instance.client.auth.currentUser?.id;
    if (_stream == null || me == null) {
      return const Icon(Icons.chat_bubble_outline);
    }
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snap) {
        final n = (snap.data ?? const <Map<String, dynamic>>[])
            .where((m) => _isUnread(m, me))
            .length;
        return badges.Badge(
          position: badges.BadgePosition.topEnd(top: -8, end: -8),
          showBadge: n > 0,
          badgeContent: Text(
            n > 99 ? '99+' : '$n',
            style: const TextStyle(color: Colors.white, fontSize: 10),
          ),
          child: const Icon(Icons.chat_bubble_outline),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------
// تبويب الدردشة داخل المتجر
// ---------------------------------------------------------------------
class StoreChatTab extends StatefulWidget {
  final int storeId;
  const StoreChatTab({Key? key, required this.storeId}) : super(key: key);

  @override
  State<StoreChatTab> createState() => _StoreChatTabState();
}

class _StoreChatTabState extends State<StoreChatTab> {
  late final Future<String?> _ownerFuture;

  @override
  void initState() {
    super.initState();
    _ownerFuture = _loadOwner();
  }

  @override
  void dispose() {
    chatTabVisible.value = false;
    super.dispose();
  }

  Future<String?> _loadOwner() async {
    final row = await Supabase.instance.client
        .from('stores')
        .select('owner_id')
        .eq('id', widget.storeId)
        .maybeSingle();
    if (row == null) return null;
    return (row as Map)['owner_id'] as String?;
  }

  @override
  Widget build(BuildContext context) {
    final me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null) {
      return const Center(child: Text('سجّل الدخول لاستخدام الدردشة'));
    }
    return FutureBuilder<String?>(
      future: _ownerFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError || snap.data == null) {
          return const Center(child: Text('تعذر تحميل الدردشة'));
        }
        if (snap.data == me) {
          return _OwnerConversations(storeId: widget.storeId);
        }
        return ChatThread(storeId: widget.storeId, customerId: me);
      },
    );
  }
}

// ---------------------------------------------------------------------
// قائمة المحادثات (لصاحب المتجر)
// ---------------------------------------------------------------------
class _OwnerConversations extends StatefulWidget {
  final int storeId;
  const _OwnerConversations({Key? key, required this.storeId}) : super(key: key);

  @override
  State<_OwnerConversations> createState() => _OwnerConversationsState();
}

class _OwnerConversationsState extends State<_OwnerConversations> {
  final _client = Supabase.instance.client;
  late final Stream<List<Map<String, dynamic>>> _stream;
  final Map<String, String> _names = {};
  final Set<String> _requested = {};

  String get _me => _client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _stream = _client
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .eq('store_id', widget.storeId)
        .order('created_at', ascending: false);
  }

  void _ensureNames(List<String> ids) {
    final missing = ids.where((i) => !_requested.contains(i)).toList();
    if (missing.isEmpty) return;
    _requested.addAll(missing);
    _client
        .from('profiles')
        .select('id, first_name, last_name')
        .in_('id', missing)
        .then((rows) {
      if (!mounted) return;
      setState(() {
        for (final r in (rows as List)) {
          final m = r as Map;
          _names[m['id'] as String] =
              '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim();
        }
      });
    }).catchError((_) {});
  }

  String _preview(Map<String, dynamic> m) {
    if (m['deleted'] == true) return 'تم حذف الرسالة';
    final body = (m['body'] ?? '') as String;
    if (body.isEmpty && m['image_url'] != null) return '📷 صورة';
    return body;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return const Center(child: Text('تعذر تحميل المحادثات'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final latest = <String, Map<String, dynamic>>{};
        final unread = <String, int>{};
        for (final m in snap.data!) {
          final cid = m['customer_id'] as String;
          latest.putIfAbsent(cid, () => m);
          if (_isUnread(m, _me)) unread[cid] = (unread[cid] ?? 0) + 1;
        }
        if (latest.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'لا توجد محادثات بعد.\nستظهر هنا رسائل العملاء عندما يراسلون متجرك.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final ids = latest.keys.toList();
        _ensureNames(ids);
        return ListView.separated(
          itemCount: ids.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final cid = ids[i];
            final msg = latest[cid]!;
            final name = (_names[cid] ?? '').isEmpty ? 'عميل' : _names[cid]!;
            final n = unread[cid] ?? 0;
            return ListTile(
              leading: CircleAvatar(child: Text(name.substring(0, 1))),
              title: Text(
                name,
                style: TextStyle(
                    fontWeight: n > 0 ? FontWeight.bold : FontWeight.normal),
              ),
              subtitle: Text(
                _preview(msg),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontWeight: n > 0 ? FontWeight.w600 : FontWeight.normal),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _hhmm(msg['created_at']),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  if (n > 0)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        n > 99 ? '99+' : '$n',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                ],
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: Text(name)),
                      body: ChatThread(
                        storeId: widget.storeId,
                        customerId: cid,
                        alwaysActive: true,
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------
// شاشة المحادثة
// ---------------------------------------------------------------------
class ChatThread extends StatefulWidget {
  final int storeId;
  final String customerId;
  final bool alwaysActive;
  const ChatThread({
    Key? key,
    required this.storeId,
    required this.customerId,
    this.alwaysActive = false,
  }) : super(key: key);

  @override
  State<ChatThread> createState() => _ChatThreadState();
}

class _ChatThreadState extends State<ChatThread> {
  final _client = Supabase.instance.client;
  final _ctrl = TextEditingController();
  late final Stream<List<Map<String, dynamic>>> _stream;
  final Set<int> _marked = {};
  List<Map<String, dynamic>> _latest = [];
  bool _sending = false;

  String get _me => _client.auth.currentUser!.id;
  bool get _active => widget.alwaysActive || chatTabVisible.value;

  @override
  void initState() {
    super.initState();
    _stream = _client
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .eq('customer_id', widget.customerId)
        .order('created_at', ascending: false);
    chatTabVisible.addListener(_maybeMarkRead);
  }

  @override
  void dispose() {
    chatTabVisible.removeListener(_maybeMarkRead);
    _ctrl.dispose();
    super.dispose();
  }

  // تعليم رسائل الطرف الآخر كمقروءة (فقط والمحادثة ظاهرة أمامك)
  void _maybeMarkRead() {
    if (!mounted || !_active) return;
    final ids = <int>[];
    for (final m in _latest) {
      final id = (m['id'] as num).toInt();
      if (_isUnread(m, _me) && !_marked.contains(id)) ids.add(id);
    }
    if (ids.isEmpty) return;
    _marked.addAll(ids);
    _client
        .from('chat_messages')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .in_('id', ids)
        .then((_) {})
        .catchError((_) {
      _marked.removeAll(ids);
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _client.from('chat_messages').insert({
        'store_id': widget.storeId,
        'customer_id': widget.customerId,
        'sender_id': _me,
        'body': text,
      });
      _ctrl.clear();
    } catch (e) {
      _toast('تعذر إرسال الرسالة، حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendImage() async {
    if (_sending) return;
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 1280,
      );
      if (picked == null) return;
      setState(() => _sending = true);
      final bytes = await picked.readAsBytes();
      final path =
          '${widget.storeId}/${widget.customerId}/${DateTime.now().millisecondsSinceEpoch}.jpg';
      await _client.storage.from('chat-images').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
          );
      final url = _client.storage.from('chat-images').getPublicUrl(path);
      await _client.from('chat_messages').insert({
        'store_id': widget.storeId,
        'customer_id': widget.customerId,
        'sender_id': _me,
        'body': '',
        'image_url': url,
      });
    } catch (e) {
      _toast('تعذر إرسال الصورة، حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _confirmDelete(Map<String, dynamic> m) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.delete_outline, color: Colors.red),
          title: const Text('حذف الرسالة'),
          onTap: () async {
            Navigator.pop(ctx);
            try {
              await _client
                  .from('chat_messages')
                  .update({'deleted': true}).eq('id', m['id']);
            } catch (e) {
              _toast('تعذر حذف الرسالة.');
            }
          },
        ),
      ),
    );
  }

  void _openImage(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: InteractiveViewer(child: Image.network(url)),
      ),
    );
  }

  Widget _content(Map<String, dynamic> m, bool mine) {
    final textColor = mine ? Colors.white : Colors.black87;
    if (m['deleted'] == true) {
      return Text(
        '🚫 تم حذف هذه الرسالة',
        style: TextStyle(
            color: textColor.withAlpha(180),
            fontStyle: FontStyle.italic,
            fontSize: 14),
      );
    }
    final String img = (m['image_url'] as String?) ?? '';
    final bool hasImg = img.isNotEmpty;
    final body = (m['body'] ?? '') as String;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasImg)
          GestureDetector(
            onTap: () => _openImage(img),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                img,
                width: 220,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(
                  width: 220,
                  height: 80,
                  child: Center(child: Icon(Icons.broken_image)),
                ),
              ),
            ),
          ),
        if (body.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: hasImg ? 6 : 0),
            child: Text(body, style: TextStyle(color: textColor, fontSize: 15)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _stream,
            builder: (context, snap) {
              if (snap.hasError) {
                return const Center(child: Text('تعذر تحميل الرسائل'));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final msgs = snap.data!
                  .where((m) => m['store_id'] == widget.storeId)
                  .toList();
              _latest = msgs;
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => _maybeMarkRead());
              if (msgs.isEmpty) {
                return const Center(child: Text('ابدأ المحادثة بإرسال رسالة 👋'));
              }
              return ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(12),
                itemCount: msgs.length,
                itemBuilder: (context, i) {
                  final m = msgs[i];
                  final mine = m['sender_id'] == _me;
                  final deleted = m['deleted'] == true;
                  final read = m['read_at'] != null;
                  return Align(
                    alignment: mine
                        ? AlignmentDirectional.centerStart
                        : AlignmentDirectional.centerEnd,
                    child: GestureDetector(
                      onLongPress:
                          (mine && !deleted) ? () => _confirmDelete(m) : null,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        constraints: BoxConstraints(
                            maxWidth:
                                MediaQuery.of(context).size.width * 0.75),
                        decoration: BoxDecoration(
                          color: mine
                              ? theme.colorScheme.primary
                              : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _content(m, mine),
                            const SizedBox(height: 2),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _hhmm(m['created_at']),
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: mine
                                          ? Colors.white70
                                          : Colors.black45),
                                ),
                                if (mine && !deleted)
                                  Text(
                                    read ? '  ✓✓' : '  ✓',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: read
                                            ? Colors.lightBlueAccent
                                            : Colors.white70),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        Material(
          elevation: 8,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _sending ? null : _sendImage,
                    icon: Icon(Icons.image_outlined,
                        color: theme.colorScheme.primary),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 2000,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: 'اكتب رسالة...',
                        counterText: '',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(Icons.send, color: theme.colorScheme.primary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
