import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/gemini_service.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';

class AiCoachChatScreen extends StatefulWidget {
  const AiCoachChatScreen({super.key});

  @override
  State<AiCoachChatScreen> createState() => _AiCoachChatScreenState();
}

class _ChatMessage {
  final String text;
  final bool isUser;
  final DateTime time;

  _ChatMessage({required this.text, required this.isUser, DateTime? time})
      : time = time ?? DateTime.now();
}

class _AiCoachChatScreenState extends State<AiCoachChatScreen>
    with TickerProviderStateMixin {
  final _gemini = GeminiService();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _messages = <_ChatMessage>[];
  bool _isLoading = false;
  bool _needsApiKey = false;
  final _apiKeyController = TextEditingController();

  Map<String, dynamic> _playerStats = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _initialize() async {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      _playerStats = args;
    }

    // Load user-overridden API key (only if they explicitly changed it)
    final prefs = await SharedPreferences.getInstance();
    final savedKey = prefs.getString('gemini_api_key') ?? '';
    // Clear any stale/exhausted keys from previous sessions
    const oldKeys = [
      'AIzaSyDK68zqMDRnOTCH7LZLSlvo8ov-oWuBy5k',
    ];
    if (savedKey.isNotEmpty && !oldKeys.contains(savedKey)) {
      _gemini.setApiKey(savedKey);
    } else if (savedKey.isNotEmpty && oldKeys.contains(savedKey)) {
      // Remove stale key
      await prefs.remove('gemini_api_key');
    }

    if (!_gemini.isConfigured) {
      setState(() => _needsApiKey = true);
      return;
    }

    _startChat();
  }

  void _startChat() {
    _gemini.startSession(playerStats: _playerStats);
    setState(() {
      _needsApiKey = false;
      _isLoading = true;
    });

    // Send initial greeting
    _gemini.sendMessage('Hello! I just finished my match analysis. Can you review my stats and help me improve?').then((response) {
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(text: response, isUser: false));
        _isLoading = false;
      });
      _scrollToBottom();
    });
  }

  Future<void> _saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', key.trim());
    _gemini.setApiKey(key.trim());
    if (_gemini.isConfigured) {
      _startChat();
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isLoading) return;

    _controller.clear();
    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true));
      _isLoading = true;
    });
    _scrollToBottom();

    final response = await _gemini.sendMessage(text);
    if (!mounted) return;

    setState(() {
      _messages.add(_ChatMessage(text: response, isUser: false));
      _isLoading = false;
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.tx(context)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF1D63FF), Color(0xFF00E676)],
                ),
              ),
              child: const Icon(Icons.sports_soccer, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Performance Coach',
                  style: TextStyle(
                    color: AppColors.tx(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                Text(
                  _isLoading ? 'Typing...' : 'Online',
                  style: TextStyle(
                    color: _isLoading ? AppColors.warning : AppColors.success,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.key, color: AppColors.txMuted(context), size: 20),
            onPressed: _showApiKeyDialog,
            tooltip: 'Change API Key',
          ),
        ],
      ),
      body: Column(
        children: [
          // Stats summary bar
          if (_playerStats.isNotEmpty) _buildStatsSummary(),

          // Messages area
          Expanded(
            child: _needsApiKey ? _buildApiKeyPrompt() : _buildMessageList(),
          ),

          // Input bar
          if (!_needsApiKey) _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildStatsSummary() {
    final ovr = _playerStats['ovr'] ?? '?';
    final pac = _playerStats['pac'] ?? '?';
    final sho = _playerStats['sho'] ?? '?';
    final pas = _playerStats['pas'] ?? '?';
    final dri = _playerStats['dri'] ?? '?';
    final def = _playerStats['def'] ?? '?';
    final phy = _playerStats['phy'] ?? '?';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'OVR $ovr',
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _miniStat('PAC', pac),
                  _miniStat('SHO', sho),
                  _miniStat('PAS', pas),
                  _miniStat('DRI', dri),
                  _miniStat('DEF', def),
                  _miniStat('PHY', phy),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, dynamic value) {
    final v = value is int ? value : 0;
    final color = v >= 80
        ? AppColors.success
        : v >= 60
            ? AppColors.warning
            : AppColors.danger;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('$value', style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _buildApiKeyPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: GlassCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1D63FF), Color(0xFF00E676)],
                  ),
                ),
                child: const Icon(Icons.smart_toy, color: Colors.white, size: 32),
              ),
              const SizedBox(height: 16),
              Text(
                'AI Coach Setup',
                style: TextStyle(
                  color: AppColors.tx(context),
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your free Gemini API key to start chatting with your AI performance coach.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.txMuted(context), fontSize: 13),
              ),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () {},
                child: const Text(
                  'Get free API key at aistudio.google.com',
                  style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _apiKeyController,
                style: TextStyle(color: AppColors.tx(context), fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Paste your Gemini API key here...',
                  hintStyle: TextStyle(color: AppColors.txMuted(context)),
                  filled: true,
                  fillColor: AppColors.surf2(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.bdr(context)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.bdr(context)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primary, width: 2),
                  ),
                  prefixIcon: Icon(Icons.key, color: AppColors.txMuted(context), size: 20),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    final key = _apiKeyController.text.trim();
                    if (key.isNotEmpty) {
                      _saveApiKey(key);
                    }
                  },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  child: const Text('Start Coaching Session'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _messages.length + (_isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length && _isLoading) {
          return _buildTypingIndicator();
        }
        return _buildMessageBubble(_messages[index]);
      },
    );
  }

  Widget _buildMessageBubble(_ChatMessage msg) {
    final isUser = msg.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: EdgeInsets.only(
          top: 4,
          bottom: 4,
          left: isUser ? 40 : 0,
          right: isUser ? 0 : 40,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isUser) ...[
              Container(
                width: 28,
                height: 28,
                margin: const EdgeInsets.only(right: 6, bottom: 2),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFF1D63FF), Color(0xFF00E676)],
                  ),
                ),
                child: const Icon(Icons.sports_soccer, color: Colors.white, size: 14),
              ),
            ],
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isUser
                      ? AppColors.primary
                      : AppColors.surface.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isUser ? 16 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 16),
                  ),
                  border: isUser
                      ? null
                      : Border.all(color: AppColors.border.withValues(alpha: 0.5)),
                  boxShadow: [
                    BoxShadow(
                      color: (isUser ? AppColors.primary : Colors.black)
                          .withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: SelectableText(
                  msg.text,
                  style: TextStyle(
                    color: isUser ? Colors.white : AppColors.text,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(left: 34, top: 4, bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dot(0),
            const SizedBox(width: 4),
            _dot(1),
            const SizedBox(width: 4),
            _dot(2),
          ],
        ),
      ),
    );
  }

  Widget _dot(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.3, end: 1.0),
      duration: Duration(milliseconds: 600 + index * 200),
      builder: (context, value, child) {
        return AnimatedOpacity(
          opacity: _isLoading ? value : 0.3,
          duration: const Duration(milliseconds: 300),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: 0.8),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.95),
        border: Border(top: BorderSide(color: AppColors.border.withValues(alpha: 0.5))),
      ),
      child: Row(
        children: [
          // Quick suggestions
          IconButton(
            icon: const Icon(Icons.lightbulb_outline, color: AppColors.warning, size: 22),
            onPressed: _showSuggestions,
            tooltip: 'Suggestions',
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              style: TextStyle(color: AppColors.tx(context), fontSize: 14),
              maxLines: 3,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
              decoration: InputDecoration(
                hintText: 'Ask your AI coach...',
                hintStyle: TextStyle(color: AppColors.txMuted(context)),
                filled: true,
                fillColor: AppColors.surf2(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF1D63FF), Color(0xFF00B0FF)],
              ),
            ),
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white, size: 20),
              onPressed: _isLoading ? null : _sendMessage,
            ),
          ),
        ],
      ),
    );
  }

  void _showSuggestions() {
    final suggestions = [
      'How can I improve my weakest stat?',
      'Give me a weekly training plan',
      'What exercises improve my pace?',
      'Compare my stats to a pro player',
      'How can I improve my shooting?',
      'What should I focus on for my position?',
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Quick Questions',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: suggestions.map((s) {
                  return ActionChip(
                    label: Text(s, style: const TextStyle(fontSize: 12)),
                    backgroundColor: AppColors.surface2,
                    side: BorderSide(color: AppColors.border.withValues(alpha: 0.5)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _controller.text = s;
                      _sendMessage();
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showApiKeyDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        final keyCtrl = TextEditingController();
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Gemini API Key', style: TextStyle(color: AppColors.text)),
          content: TextField(
            controller: keyCtrl,
            style: const TextStyle(color: AppColors.text, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Paste new API key...',
              hintStyle: const TextStyle(color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.surface2,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final key = keyCtrl.text.trim();
                if (key.isNotEmpty) {
                  _saveApiKey(key);
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Save & Restart'),
            ),
          ],
        );
      },
    );
  }
}
