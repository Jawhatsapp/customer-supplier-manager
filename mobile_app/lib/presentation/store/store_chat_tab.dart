// lib/presentation/store/store_chat_tab.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// تبويب الدردشة داخل المتجر:
/// - العميل: يفتح محادثته مع المتجر مباشرة.
/// - صاحب المتجر: يرى قائمة العملاء الذين راسلوه ويفتح أي محادثة.
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
        // أحدث رسالة لكل عميل (القائمة مرتبة من الأحدث)
        final latest = <String, Map<String, dynamic>>{};
        for (final m in snap.data!) {
          latest.putIfAbsent(m['customer_id'] as String, () => m);
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
            return ListTile(
              leading: CircleAvatar(
                child: Text(name.substring(0, 1)),
              ),
              title: Text(name),
              subtitle: Text(
                (msg['body'] ?? '') as String,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                _hhmm(msg['created_at']),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: Text(name)),
                      body: ChatThread(
                          storeId: widget.storeId, customerId: cid),
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
// شاشة المحادثة (رسائل لحظية)
// ---------------------------------------------------------------------
class ChatThread extends StatefulWidget {
  final int storeId;
  final String customerId;
  const ChatThread({Key? key, required this.storeId, required this.customerId})
      : super(key: key);

  @override
  State<ChatThread> createState() => _ChatThreadState();
}

class _ChatThreadState extends State<ChatThread> {
  final _client = Supabase.instance.client;
  final _ctrl = TextEditingController();
  late final Stream<List<Map<String, dynamic>>> _stream;
  bool _sending = false;

  String get _me => _client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _stream = _client
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .eq('customer_id', widget.customerId)
        .order('created_at', ascending: false);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر إرسال الرسالة، حاول مرة أخرى.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
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
              // رسائل هذا المتجر فقط، الأحدث أولاً (القائمة معكوسة لتبقى على آخر رسالة)
              final msgs = snap.data!
                  .where((m) => m['store_id'] == widget.storeId)
                  .toList();
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
                  return Align(
                    alignment: mine
                        ? AlignmentDirectional.centerStart
                        : AlignmentDirectional.centerEnd,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75),
                      decoration: BoxDecoration(
                        color: mine
                            ? theme.colorScheme.primary
                            : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (m['body'] ?? '') as String,
                            style: TextStyle(
                                color: mine ? Colors.white : Colors.black87,
                                fontSize: 15),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _hhmm(m['created_at']),
                            style: TextStyle(
                                fontSize: 10,
                                color:
                                    mine ? Colors.white70 : Colors.black45),
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
        Material(
          elevation: 8,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Row(
                children: [
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
                  const SizedBox(width: 6),
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

String _hhmm(dynamic iso) {
  if (iso == null) return '';
  final d = DateTime.tryParse(iso.toString())?.toLocal();
  if (d == null) return '';
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
