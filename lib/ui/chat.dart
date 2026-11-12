// The conversation view, after Soloza's notes messages
// (`modules/notes/ui/note_messages.dart`): flat tiles, an author line that
// shows only when the speaker changes or seven minutes pass, and text that
// selects across messages as one document.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/db.dart';
import '../engine/voice.dart';
import '../terra/smooth_scroll.dart';
import 'ui.dart';
import 'voice_bar.dart';

class ChatMessage {
  ChatMessage(this.author, this.text, this.at, {this.mine = false, this.meta});
  final String author, text;
  final DateTime at;
  final bool mine;

  /// A quiet line under the message, such as how long the answer took.
  final String? meta;

  static ChatMessage of(Json j, {required String them}) => ChatMessage(
    j['role'] == 'user' ? 'You' : them,
    j['text'] as String,
    DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
    mine: j['role'] == 'user',
    meta: j['meta'] as String?,
  );
}

/// Whether [m] starts a new group, as chat apps group (Soloza's rule).
bool startsMessageGroup(ChatMessage? prev, ChatMessage m) =>
    prev == null ||
    prev.author != m.author ||
    m.at.difference(prev.at) > const Duration(minutes: 7);

String _clock(DateTime t) {
  final l = t.toLocal();
  final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
  return '$h:${l.minute.toString().padLeft(2, '0')} ${l.hour < 12 ? 'AM' : 'PM'}';
}

class ChatList extends StatefulWidget {
  const ChatList({
    super.key,
    required this.messages,
    this.typing,
    this.empty,
    this.maxWidth = 760,
  });
  final List<ChatMessage> messages;

  /// Who is composing a reply, if anyone.
  final String? typing;
  final Widget? empty;
  final double maxWidth;

  @override
  State<ChatList> createState() => _ChatListState();
}

class _ChatListState extends State<ChatList> {
  final _scroll = SmoothScrollController();

  @override
  void didUpdateWidget(ChatList old) {
    super.didUpdateWidget(old);
    if (old.messages.length != widget.messages.length ||
        old.typing != widget.typing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final msgs = widget.messages;
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    if (msgs.isEmpty && widget.typing == null) {
      return Center(child: widget.empty ?? const SizedBox.shrink());
    }
    return MiddleScroll(
      controller: _scroll,
      child: SelectionArea(
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(28, 8, 28, 16),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: widget.maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, m) in msgs.indexed) ...[
                  SizedBox(
                    height: startsMessageGroup(i == 0 ? null : msgs[i - 1], m)
                        ? 14
                        : 4,
                  ),
                  if (startsMessageGroup(i == 0 ? null : msgs[i - 1], m))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: m.author,
                              style: t.bodyMedium
                                  ?.copyWith(color: m.mine ? p.text : p.ink)
                                  .weight(600),
                            ),
                            TextSpan(
                              text: '   ${_clock(m.at)}',
                              style: t.bodySmall?.copyWith(color: p.textFaint),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Text(m.text, style: readStyle(context)),
                  if (m.meta != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        m.meta!,
                        style: t.bodySmall?.copyWith(color: p.textFaint),
                      ),
                    ),
                ],
                if (widget.typing != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text(
                      '${widget.typing} is thinking…',
                      style: t.bodyMedium?.copyWith(
                        color: p.textFaint,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }
}

/// Enter sends, Shift+Enter makes a new line.
class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.onSend,
    this.enabled = true,
    this.hint = 'Type your answer',
    this.onFirstKey,
    this.leading,
    this.onVoice,
  });
  final ValueChanged<String> onSend;
  final bool enabled;
  final String hint;

  /// Called when the learner starts typing an answer (to start a timer).
  final VoidCallback? onFirstKey;

  /// Shown left of the field, such as a timer.
  final Widget? leading;

  /// Given a spoken answer's timing; when set, the composer offers to record.
  final ValueChanged<VoiceResult>? onVoice;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _text = TextEditingController();
  bool _started = false;
  late final _focus = FocusNode(
    onKeyEvent: (node, e) {
      if (e is KeyDownEvent &&
          e.logicalKey == LogicalKeyboardKey.enter &&
          !HardwareKeyboard.instance.isShiftPressed) {
        _send();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
  );

  void _send() {
    final t = _text.text.trim();
    if (t.isEmpty || !widget.enabled) return;
    _text.clear();
    _started = false;
    widget.onSend(t);
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 10, 28, 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.onVoice != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: VoiceBar(
                    enabled: widget.enabled,
                    onText: (text) => setState(() => _text.text = text),
                    onDone: (r) {
                      widget.onFirstKey?.call();
                      widget.onVoice!(r);
                    },
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (widget.leading != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 12, bottom: 7),
                      child: widget.leading,
                    ),
                  Expanded(
                    child: TextField(
                      key: const Key('composer'),
                      controller: _text,
                      focusNode: _focus,
                      autofocus: true,
                      minLines: 1,
                      maxLines: 10,
                      // Never disabled: a disabled field drops the keyboard
                      // focus, and the learner would have to click back in
                      // after every reply. Only sending waits.
                      style: readStyle(context),
                      onChanged: (v) {
                        if (!_started && v.trim().isNotEmpty) {
                          _started = true;
                          widget.onFirstKey?.call();
                        }
                      },
                      decoration: writeField(
                        '${widget.hint}. Enter sends, Shift+Enter starts a new line.',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  JBtn(
                    'Send',
                    primary: true,
                    height: 34,
                    onTap: widget.enabled ? _send : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
