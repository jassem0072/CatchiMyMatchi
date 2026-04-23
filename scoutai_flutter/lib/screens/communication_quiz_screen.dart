import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'dart:math';

import '../app/scoutai_app.dart';
import '../services/auth_api.dart';
import '../services/auth_storage.dart';
import '../services/gemini_service.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';

class CommunicationQuizScreen extends StatefulWidget {
  const CommunicationQuizScreen({super.key});

  @override
  State<CommunicationQuizScreen> createState() => _CommunicationQuizScreenState();
}

class _CommunicationQuizScreenState extends State<CommunicationQuizScreen>
    with SingleTickerProviderStateMixin {
  static const int _questionCount = 20;

  final GeminiService _ai = GeminiService();
  final List<_QuizQuestion> _questions = [];
  final Map<int, int> _selectedByQuestion = <int, int>{};
  final TextEditingController _voiceAnswerCtrl = TextEditingController();
  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final Random _rnd = Random();

  late final AnimationController _pulseController;

  String _language = 'English';
  bool _loading = false;
  bool _started = false;
  int _questionIndex = 0;
  bool _submitted = false;
  int? _score;
  bool _voiceMode = false;
  bool _speechReady = false;
  bool _listening = false;
  String _lastQuizSignature = '';

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _initVoiceServices();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _voiceAnswerCtrl.dispose();
    _speech.stop();
    _tts.stop();
    super.dispose();
  }

  Future<void> _initVoiceServices() async {
    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          setState(() => _listening = status.toLowerCase().contains('listening'));
        },
        onError: (_) {
          if (!mounted) return;
          setState(() => _listening = false);
        },
      );
      if (!mounted) return;
      setState(() => _speechReady = available);
      await _tts.setSpeechRate(0.46);
      await _tts.setPitch(1.0);
      await _tts.setLanguage(_voiceLocale);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _speechReady = false;
        _listening = false;
      });
    }
  }

  String get _voiceLocale {
    switch (_language) {
      case 'French':
        return 'fr-FR';
      case 'Spanish':
        return 'es-ES';
      default:
        return 'en-US';
    }
  }

  Future<void> _startQuiz() async {
    setState(() {
      _loading = true;
      _started = false;
      _submitted = false;
      _score = null;
      _questionIndex = 0;
      _questions.clear();
      _selectedByQuestion.clear();
    });

    final nonce = '${DateTime.now().microsecondsSinceEpoch}-${_rnd.nextInt(1000000)}';
    List<Map<String, dynamic>>? generated = await _ai.generateCommunicationQuiz(
      language: _language,
      count: _questionCount,
      nonce: nonce,
    );

    if (generated != null && generated.isNotEmpty) {
      final sig = _quizSignature(generated);
      if (sig == _lastQuizSignature) {
        final retryNonce = '${DateTime.now().microsecondsSinceEpoch}-${_rnd.nextInt(1000000)}-retry';
        final retry = await _ai.generateCommunicationQuiz(
          language: _language,
          count: _questionCount,
          nonce: retryNonce,
        );
        if (retry != null && retry.isNotEmpty) {
          generated = retry;
        }
      }
    }

    final fallback = _buildFallbackQuestions(_language, nonce: nonce);
    final source = generated != null && generated.length >= _questionCount
        ? _remixQuestions(generated).take(_questionCount).toList()
        : fallback;

    final parsed = source
        .map(
          (q) => _QuizQuestion(
            question: (q['question'] ?? '').toString(),
            options: ((q['options'] as List?) ?? const <dynamic>[])
                .map((e) => e.toString())
                .toList(),
            correctIndex: (q['correctIndex'] as num?)?.toInt() ?? 0,
            explanation: (q['explanation'] ?? '').toString(),
          ),
        )
        .where((q) => q.question.isNotEmpty && q.options.length == 4)
        .take(_questionCount)
        .toList();

    if (!mounted) return;
    _lastQuizSignature = _quizSignature(source);
    setState(() {
      _questions.addAll(parsed);
      _loading = false;
      _started = _questions.isNotEmpty;
    });

    if (_questions.isEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not generate quiz. Please try again.')),
      );
    }
  }

  String _quizSignature(List<Map<String, dynamic>> qs) {
    final key = qs.take(_questionCount).map((q) => (q['question'] ?? '').toString().trim().toLowerCase()).join('||');
    return key;
  }

  List<Map<String, dynamic>> _remixQuestions(List<Map<String, dynamic>> source) {
    final list = source.map((q) {
      final options = ((q['options'] as List?) ?? const <dynamic>[]).map((e) => e.toString()).toList();
      final correct = (q['correctIndex'] as num?)?.toInt() ?? 0;
      if (options.length != 4 || correct < 0 || correct >= options.length) {
        return Map<String, dynamic>.from(q);
      }

      final pairs = <MapEntry<String, bool>>[];
      for (var i = 0; i < options.length; i++) {
        pairs.add(MapEntry(options[i], i == correct));
      }
      pairs.shuffle(_rnd);

      final remixedOptions = pairs.map((e) => e.key).toList();
      final remixedCorrect = pairs.indexWhere((e) => e.value);

      return {
        ...Map<String, dynamic>.from(q),
        'options': remixedOptions,
        'correctIndex': remixedCorrect,
      };
    }).toList();

    list.shuffle(_rnd);
    return list;
  }

  void _pickOption(int optionIndex) {
    if (_submitted) return;
    setState(() {
      _selectedByQuestion[_questionIndex] = optionIndex;
    });
  }

  void _submitCurrent() {
    if (_voiceMode && _selectedByQuestion[_questionIndex] == null) {
      final parsed = _parseSpokenChoice(_voiceAnswerCtrl.text);
      if (parsed != null) {
        _selectedByQuestion[_questionIndex] = parsed;
      }
    }

    if (_selectedByQuestion[_questionIndex] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _voiceMode
                ? 'Say or type option 1, 2, 3 or 4 (or tap an option), then submit.'
                : 'Choose one option before submitting.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _submitted = true;
    });
  }

  void _next() {
    if (_questionIndex >= _questions.length - 1) return;
    _speech.stop();
    setState(() {
      _questionIndex += 1;
      _submitted = false;
      _voiceAnswerCtrl.clear();
      _listening = false;
    });
  }

  int? _parseSpokenChoice(String input) {
    final text = input.toLowerCase().trim();
    if (text.isEmpty) return null;

    final numeric = RegExp(r'\b([1-4])\b').firstMatch(text);
    if (numeric != null) {
      return int.parse(numeric.group(1)!) - 1;
    }

    const words = <String, int>{
      'one': 0,
      'first': 0,
      'two': 1,
      'second': 1,
      'three': 2,
      'third': 2,
      'four': 3,
      'fourth': 3,
      'un': 0,
      'deux': 1,
      'trois': 2,
      'quatre': 3,
      'uno': 0,
      'dos': 1,
      'tres': 2,
      'cuatro': 3,
    };

    for (final e in words.entries) {
      if (RegExp('\\b${RegExp.escape(e.key)}\\b').hasMatch(text)) {
        return e.value;
      }
    }

    const letters = <String, int>{'a': 0, 'b': 1, 'c': 2, 'd': 3};
    for (final e in letters.entries) {
      if (RegExp('\\b${e.key}\\b').hasMatch(text) || RegExp('\\boption\\s+${e.key}\\b').hasMatch(text)) {
        return e.value;
      }
    }
    return null;
  }

  Future<void> _readQuestionAndOptions(_QuizQuestion q) async {
    final script = StringBuffer()
      ..writeln(q.question)
      ..writeln('Option 1: ${q.options[0]}')
      ..writeln('Option 2: ${q.options[1]}')
      ..writeln('Option 3: ${q.options[2]}')
      ..writeln('Option 4: ${q.options[3]}');
    await _tts.stop();
    await _tts.setLanguage(_voiceLocale);
    await _tts.speak(script.toString());
  }

  Future<void> _toggleVoiceCapture() async {
    if (!_speechReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice recognition is not available on this device/browser.')),
      );
      return;
    }

    if (_listening) {
      await _speech.stop();
      if (!mounted) return;
      setState(() => _listening = false);
      return;
    }

    await _speech.listen(
      localeId: _voiceLocale,
      listenMode: stt.ListenMode.confirmation,
      partialResults: true,
      onResult: (result) {
        if (!mounted) return;
        final words = result.recognizedWords.trim();
        setState(() => _voiceAnswerCtrl.text = words);
        final parsed = _parseSpokenChoice(words);
        if (parsed != null && !_submitted) {
          setState(() {
            _selectedByQuestion[_questionIndex] = parsed;
          });
        }
      },
    );
    if (!mounted) return;
    setState(() => _listening = true);
  }

  void _finishQuiz() {
    int score = 0;
    for (var i = 0; i < _questions.length; i++) {
      if (_selectedByQuestion[i] == _questions[i].correctIndex) score++;
    }
    setState(() => _score = score);
    _persistQuizResult(score);
  }

  Future<void> _persistQuizResult(int score) async {
    final token = await AuthStorage.loadToken();
    if (!mounted || token == null) return;

    final readinessBand = _readinessBand(score, _questions.length);
    final communicationStyle = _deriveCommunicationStyle(score, _questions.length);
    final captaincySummary = _deriveCaptaincySummary(score, _questions.length);
    try {
      await AuthApi().saveCommunicationQuizResult(
        token,
        language: _language,
        score: score,
        totalQuestions: _questions.length,
        readinessBand: readinessBand,
        communicationStyle: communicationStyle,
        captaincySummary: captaincySummary,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quiz result saved. Scouters can now see it.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Score saved locally, but sync failed: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  String _deriveCommunicationStyle(int score, int total) {
    final pct = total == 0 ? 0 : (score * 100 / total);
    if (pct >= 80) return 'Vocal organizer';
    if (pct >= 60) return 'Balanced communicator';
    return 'Developing communicator';
  }

  String _deriveCaptaincySummary(int score, int total) {
    final pct = total == 0 ? 0 : (score * 100 / total);
    if (pct >= 80) return 'High captaincy communication potential';
    if (pct >= 60) return 'Good leadership communication foundation';
    return 'Needs mentoring to lead communication under pressure';
  }

  String _readinessBand(int score, int total) {
    final pct = total == 0 ? 0 : (score * 100 / total);
    if (pct >= 80) return 'Excellent';
    if (pct >= 60) return 'Good';
    return 'Needs adaptation';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _questions.isEmpty ? 0.0 : (_questionIndex + 1) / _questions.length;

    return GradientScaffold(
      appBar: AppBar(title: const Text('Communication Quiz')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: [
          _languageCard(),
          const SizedBox(height: 14),
          _heroStartCard(),
          const SizedBox(height: 14),
          if (_loading) ...[
            const SizedBox(height: 26),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 10),
            const Center(
              child: Text(
                'AI is preparing 20 football communication questions...',
                style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700),
              ),
            ),
          ] else if (_started && _questions.isNotEmpty) ...[
            _progressHeader(progress),
            const SizedBox(height: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, anim) {
                final offset = Tween<Offset>(
                  begin: const Offset(0.08, 0),
                  end: Offset.zero,
                ).animate(anim);
                return FadeTransition(
                  opacity: anim,
                  child: SlideTransition(position: offset, child: child),
                );
              },
              child: _questionCard(_questionIndex),
            ),
            const SizedBox(height: 12),
            _actionsRow(),
          ],
          if (_score != null) ...[
            const SizedBox(height: 14),
            _resultCard(),
          ],
        ],
      ),
    );
  }

  Widget _languageCard() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Quiz language', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 8),
          const Text(
            'Default is English. Player can switch to French or Spanish.',
            style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _langChip('English'),
              _langChip('French'),
              _langChip('Spanish'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _langChip(String value) {
    final selected = _language == value;
    return ChoiceChip(
      selected: selected,
      label: Text(value),
      onSelected: _loading
          ? null
          : (v) {
              if (!v) return;
              setState(() {
                _language = value;
                _started = false;
                _score = null;
                _questions.clear();
                _selectedByQuestion.clear();
                _voiceAnswerCtrl.clear();
              });
              _tts.setLanguage(_voiceLocale);
            },
    );
  }

  Widget _heroStartCard() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final t = 1 + (_pulseController.value * 0.02);
        return Transform.scale(scale: t, child: child);
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            colors: [Color(0xFF1D63FF), Color(0xFF00B3A4)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: const [
            BoxShadow(color: Color(0x33226DFF), blurRadius: 18, offset: Offset(0, 10)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.sports_soccer, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'AI Match Communication Quiz',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                '20 multiple-choice questions based on real coach-team communication moments.',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF123B8E),
                ),
                onPressed: _loading ? null : _startQuiz,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Generate 20-question quiz'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _progressHeader(double progress) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(value: progress, minHeight: 9),
          ),
          const SizedBox(height: 8),
          Text(
            'Question ${_questionIndex + 1}/${_questions.length}',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  Widget _questionCard(int index) {
    final q = _questions[index];
    final selected = _selectedByQuestion[index];

    return GlassCard(
      key: ValueKey<int>(index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Scenario', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 8),
          Text(q.question, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _readQuestionAndOptions(q),
            icon: const Icon(Icons.volume_up_outlined),
            label: const Text('AI read question + options'),
          ),
          const SizedBox(height: 10),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment<bool>(
                value: false,
                label: Text('Tap options'),
                icon: Icon(Icons.touch_app_outlined),
              ),
              ButtonSegment<bool>(
                value: true,
                label: Text('Voice answer'),
                icon: Icon(Icons.mic_none),
              ),
            ],
            selected: {_voiceMode},
            onSelectionChanged: (s) {
              setState(() {
                _voiceMode = s.first;
              });
            },
          ),
          if (_voiceMode) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _toggleVoiceCapture,
              icon: Icon(_listening ? Icons.mic_off : Icons.mic_none),
              label: Text(_listening ? 'Stop voice capture' : 'Start voice capture'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _voiceAnswerCtrl,
              decoration: const InputDecoration(
                labelText: 'Voice response transcript',
                hintText: 'Say or type: option 1, 2, 3, 4 (or one/two/three/four)',
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'You can answer by saying the option number, letter, or word (example: option 2, two, B).',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 14),
          for (var i = 0; i < q.options.length; i++) ...[
            _optionTile(optionIndex: i, text: q.options[i], selected: selected == i, question: q),
            if (i != q.options.length - 1) const SizedBox(height: 8),
          ],
          if (_submitted) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: selected == q.correctIndex
                    ? const Color(0x1F22C55E)
                    : const Color(0x1FEF4444),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected == q.correctIndex
                      ? const Color(0xFF22C55E)
                      : const Color(0xFFEF4444),
                ),
              ),
              child: Text(
                selected == q.correctIndex
                    ? 'Correct. ${q.explanation}'
                    : 'Not correct. ${q.explanation}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _optionTile({
    required int optionIndex,
    required String text,
    required bool selected,
    required _QuizQuestion question,
  }) {
    final isCorrect = _submitted && optionIndex == question.correctIndex;
    final isWrongChosen = _submitted && selected && optionIndex != question.correctIndex;

    Color border = selected ? AppColors.primary : AppColors.bdr(context).withValues(alpha: 0.6);
    Color bg = selected ? AppColors.primary.withValues(alpha: 0.16) : AppColors.surf2(context);
    if (isCorrect) {
      border = const Color(0xFF22C55E);
      bg = const Color(0x1F22C55E);
    } else if (isWrongChosen) {
      border = const Color(0xFFEF4444);
      bg = const Color(0x1FEF4444);
    }

    return InkWell(
      onTap: _submitted ? null : () => _pickOption(optionIndex),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: 1.3),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 22,
              width: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? AppColors.primary : Colors.transparent,
                border: Border.all(color: selected ? AppColors.primary : AppColors.textMuted),
              ),
              child: Text(
                String.fromCharCode(65 + optionIndex),
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.textMuted,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionsRow() {
    final isLast = _questionIndex >= _questions.length - 1;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _submitted ? null : _submitCurrent,
            child: const Text('Submit answer'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            onPressed: !_submitted
                ? null
                : isLast
                    ? _finishQuiz
                    : _next,
            child: Text(isLast ? 'Finish quiz' : 'Next question'),
          ),
        ),
      ],
    );
  }

  Widget _resultCard() {
    final score = _score ?? 0;
    final band = _readinessBand(score, _questions.length);
    final pct = _questions.isEmpty ? 0 : (score * 100 / _questions.length).round();

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.emoji_events, color: Color(0xFFF59E0B)),
              SizedBox(width: 8),
              Text('Quiz result', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 10),
          Text('Score: $score/${_questions.length}  ($pct%)', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('Readiness band: $band', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          const Text(
            'Scouter view displays this readiness band after successful sync.',
            style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil(
                    AppRoutes.playerHome,
                    (_) => false,
                  ),
                  icon: const Icon(Icons.home_outlined),
                  label: const Text('Go to Home'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _buildFallbackQuestions(String language, {required String nonce}) {
    final variantTag = (nonce.hashCode.abs() % 900 + 100).toString();
    final contextEn = [
      'Match minute 12',
      'Match minute 33',
      'Match minute 58',
      'Under high press',
      'After a turnover',
      'Late-game situation',
    ];
    final contextFr = [
      'Minute 12',
      'Minute 33',
      'Minute 58',
      'Sous forte pression',
      'Après une perte de balle',
      'Fin de match',
    ];
    final contextEs = [
      'Minuto 12',
      'Minuto 33',
      'Minuto 58',
      'Bajo presión alta',
      'Tras pérdida',
      'Final del partido',
    ];

    List<Map<String, dynamic>> base;
    List<String> contexts;
    switch (language) {
      case 'French':
        base = _fallbackFrench;
        contexts = contextFr;
        break;
      case 'Spanish':
        base = _fallbackSpanish;
        contexts = contextEs;
        break;
      default:
        base = _fallbackEnglish;
        contexts = contextEn;
        break;
    }

    final remixed = _remixQuestions(base);
    final withVariant = remixed.map((q) {
      final question = (q['question'] ?? '').toString();
      final ctx = contexts[_rnd.nextInt(contexts.length)];
      return {
        ...Map<String, dynamic>.from(q),
        'question': '[$ctx #$variantTag] $question',
      };
    }).toList();

    return withVariant.take(_questionCount).toList();
  }
}

class _QuizQuestion {
  const _QuizQuestion({
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });

  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;
}

const List<Map<String, dynamic>> _fallbackEnglish = [
  {
    'question': 'Coach says: "Hold shape, no early press." Best response to back line?',
    'options': ['Press now alone', 'Stay compact and wait signal', 'Drop everyone to goalkeeper', 'Ignore and keep attacking'],
    'correctIndex': 1,
    'explanation': 'It confirms tactical timing and team compactness.',
  },
  {
    'question': 'Your winger is not tracking back. What is the clearest command?',
    'options': ['Do something!', 'Track your fullback now', 'Why are you slow?', 'Leave it, I cover all'],
    'correctIndex': 1,
    'explanation': 'Specific and actionable instruction improves immediate reaction.',
  },
  {
    'question': 'At defensive corner, what call organizes marking quickly?',
    'options': ['Everyone run', 'Man on strongest header, rest zonal', 'No plan', 'Keeper handles all'],
    'correctIndex': 1,
    'explanation': 'Clear assignment avoids confusion before delivery.',
  },
  {
    'question': 'Coach changes to 4-4-2. Best team confirmation phrase?',
    'options': ['Whatever', 'Two banks of four, strikers stay high', 'I did not hear', 'Keep same system'],
    'correctIndex': 1,
    'explanation': 'Repeating key structure confirms shared understanding.',
  },
  {
    'question': 'Counter-press trigger after losing ball?',
    'options': ['Walk back', 'Five-second press together', 'One player presses alone', 'Foul immediately'],
    'correctIndex': 1,
    'explanation': 'Collective immediate press is the tactical trigger.',
  },
  {
    'question': 'Teammate made error and looks frustrated. Best communication?',
    'options': ['Blame him loudly', 'Next action now, stay focused', 'Stop speaking to him', 'Mock him'],
    'correctIndex': 1,
    'explanation': 'Keeps morale and attention on next phase.',
  },
  {
    'question': 'Goalkeeper wants to build short. Your midfield call?',
    'options': ['Hide from ball', 'Show angles, one touch outlets', 'Send all long', 'Wait static'],
    'correctIndex': 1,
    'explanation': 'Provides passing lanes and speed in buildup.',
  },
  {
    'question': 'Opponent overloads your left side. Best adjustment call?',
    'options': ['No change', 'Shift block left, weak side tucks in', 'Everyone man-mark', 'Stop defending'],
    'correctIndex': 1,
    'explanation': 'Compact lateral shift balances overloaded zone.',
  },
  {
    'question': 'Before attacking corner, what is most useful command?',
    'options': ['Run randomly', 'Near post screen, far post attack', 'No one moves', 'Only keeper goes'],
    'correctIndex': 1,
    'explanation': 'Roles are clear and synchronized.',
  },
  {
    'question': 'Fullback steps high, space behind open. Best center-back message?',
    'options': ['Ignore space', 'Cover channel, six drops between us', 'Push both center-backs up', 'Offside trap always'],
    'correctIndex': 1,
    'explanation': 'Channel cover protects transition risk.',
  },
  {
    'question': 'You receive coach instruction but crowd is loud. Best action?',
    'options': ['Pretend understood', 'Repeat instruction to nearest two teammates', 'Say nothing', 'Change position alone'],
    'correctIndex': 1,
    'explanation': 'Verbal relay keeps team aligned under noise.',
  },
  {
    'question': 'Team must lower tempo late in game. Best call?',
    'options': ['Force risky passes', 'Secure possession, one-two touch, draw fouls', 'Shoot from anywhere', 'All-out press'],
    'correctIndex': 1,
    'explanation': 'Controls rhythm and game management.',
  },
  {
    'question': 'Striker asks where to press center-backs. Best cue?',
    'options': ['No cue', 'Force outside, block inside lane', 'Press goalkeeper only', 'Stand still'],
    'correctIndex': 1,
    'explanation': 'Directional pressing cue is clear and collective.',
  },
  {
    'question': 'Midfielder has no passing options. Best supportive call?',
    'options': ['Lose it', 'Set to me, third-man run ready', 'Dribble three players', 'Backheel always'],
    'correctIndex': 1,
    'explanation': 'Gives immediate safe and progressive sequence.',
  },
  {
    'question': 'Defensive line stepping out together: best command?',
    'options': ['Each decide alone', 'Step now together, squeeze space', 'Drop all the time', 'No communication needed'],
    'correctIndex': 1,
    'explanation': 'Synchronized line movement prevents gaps.',
  },
  {
    'question': 'Coach asks for calmer build-up under pressure. Best message?',
    'options': ['Panic clear long', 'Use keeper, switch side, find free man', 'Dribble in own box', 'Ignore request'],
    'correctIndex': 1,
    'explanation': 'Calm circulation removes pressure safely.',
  },
  {
    'question': 'Winger should attack half-space on trigger. Best cue?',
    'options': ['Stay wide forever', 'When fullback jumps, attack inside lane', 'Wait near corner flag', 'Do not move'],
    'correctIndex': 1,
    'explanation': 'Timing-based cue creates advantage in half-space.',
  },
  {
    'question': 'After conceding, what team-talk line is most constructive?',
    'options': ['We are finished', 'Reset shape, win next duel, stay together', 'Argue with referee', 'Blame defenders'],
    'correctIndex': 1,
    'explanation': 'Constructive reset keeps collective stability.',
  },
  {
    'question': 'Need to protect 1-0 lead in last minutes. Best communication?',
    'options': ['All attack', 'Compact block, clear lines, no risky central passes', 'Invite pressure centrally', 'Dribble alone in defense'],
    'correctIndex': 1,
    'explanation': 'Prioritizes security and compact game management.',
  },
  {
    'question': 'Coach wants faster transitions after regain. Best instruction?',
    'options': ['Many touches', 'First pass forward if safe, runners go immediately', 'Always pass backward', 'Wait 10 seconds'],
    'correctIndex': 1,
    'explanation': 'Simple transition rule accelerates attacks with control.',
  },
];

const List<Map<String, dynamic>> _fallbackFrench = [
  {
    'question': 'Le coach dit: "Restez compacts, ne pressez pas trop vite." Quelle consigne?',
    'options': ['Presse seul', 'Reste compact, presse au signal', 'Recule tous sans raison', 'Ignore la consigne'],
    'correctIndex': 1,
    'explanation': 'La consigne confirme le timing collectif.',
  },
  {
    'question': 'Ton ailier ne défend pas. Message le plus clair?',
    'options': ['Bouge!', 'Reviens aider ton latéral maintenant', 'Tu es lent', 'Je fais tout seul'],
    'correctIndex': 1,
    'explanation': 'Instruction précise et actionnable.',
  },
  {
    'question': 'Sur corner défensif, quel appel organise le marquage?',
    'options': ['Courez tous', 'Homme fort au marquage, le reste en zone', 'Pas de plan', 'Gardien seul'],
    'correctIndex': 1,
    'explanation': 'La répartition est claire avant le ballon.',
  },
  {
    'question': 'Le coach passe en 4-4-2. Bonne confirmation?',
    'options': ['Comme tu veux', 'Deux lignes de quatre, deux devant', 'Je ne sais pas', 'On ne change pas'],
    'correctIndex': 1,
    'explanation': 'Répéter la structure aligne l équipe.',
  },
  {
    'question': 'Déclencheur de contre-pressing après perte?',
    'options': ['Marche arrière', 'Cinq secondes de pression ensemble', 'Un seul presse', 'Faute directe'],
    'correctIndex': 1,
    'explanation': 'La pression collective immédiate est clé.',
  },
  {
    'question': 'Un coéquipier rate et se frustre. Tu dis?',
    'options': ['Tu es nul', 'Prochaine action, reste concentré', 'Je ne te parle plus', 'Je me moque'],
    'correctIndex': 1,
    'explanation': 'Le groupe reste focalisé sur la suite.',
  },
  {
    'question': 'Le gardien relance court. Consigne milieu?',
    'options': ['Cache-toi', 'Montre des angles, une touche si possible', 'Balance long', 'Reste statique'],
    'correctIndex': 1,
    'explanation': 'Crée des lignes de passe rapides.',
  },
  {
    'question': 'Adversaire surcharge à gauche. Ajustement?',
    'options': ['Aucun', 'Bloc coulisse à gauche, côté faible ferme', 'Marquage total', 'On arrête de défendre'],
    'correctIndex': 1,
    'explanation': 'Le bloc s équilibre sur la zone de danger.',
  },
  {
    'question': 'Avant corner offensif, meilleure consigne?',
    'options': ['Courez au hasard', 'Écran premier poteau, attaque second', 'Personne ne bouge', 'Gardien monte'],
    'correctIndex': 1,
    'explanation': 'Les rôles sont nets et coordonnés.',
  },
  {
    'question': 'Latéral monte, espace derrière. Message axial?',
    'options': ['Ignore', 'Couvre le couloir, le 6 descend', 'Montez tous', 'Hors-jeu permanent'],
    'correctIndex': 1,
    'explanation': 'La couverture protège la transition.',
  },
  {
    'question': 'Le stade est bruyant, consigne du coach entendue. Que faire?',
    'options': ['Faire semblant', 'Répéter la consigne aux proches', 'Rien dire', 'Bouger seul'],
    'correctIndex': 1,
    'explanation': 'Le relais verbal maintient l alignement.',
  },
  {
    'question': 'Fin de match: baisser le tempo. Appel utile?',
    'options': ['Passes risquées', 'Conserver, une-deux touches, chercher faute', 'Tirer de partout', 'Presser à fond'],
    'correctIndex': 1,
    'explanation': 'Gestion intelligente du rythme.',
  },
  {
    'question': 'Attaquant demande où orienter le pressing. Réponse?',
    'options': ['Aucune', 'Forcer extérieur, fermer l intérieur', 'Presse seulement gardien', 'Rester immobile'],
    'correctIndex': 1,
    'explanation': 'Indice directionnel clair pour l équipe.',
  },
  {
    'question': 'Milieu sans solution. Meilleure aide verbale?',
    'options': ['Perds le ballon', 'Remise sur moi, troisième homme part', 'Dribble trois joueurs', 'Talon à chaque fois'],
    'correctIndex': 1,
    'explanation': 'Offre une sortie sûre et progressive.',
  },
  {
    'question': 'Ligne défensive doit remonter ensemble. Appel?',
    'options': ['Chacun décide', 'On monte ensemble, on serre', 'On recule toujours', 'Pas besoin de parler'],
    'correctIndex': 1,
    'explanation': 'Synchronisation de la ligne.',
  },
  {
    'question': 'Le coach veut une relance calme sous pression. Message?',
    'options': ['Dégage au hasard', 'Passe par gardien, change de côté', 'Dribble dans la surface', 'Ignore'],
    'correctIndex': 1,
    'explanation': 'Sortie propre sous pression.',
  },
  {
    'question': 'Ailier doit attaquer le demi-espace au bon moment. Cue?',
    'options': ['Reste collé ligne', 'Si le latéral sort, attaque intérieur', 'Attends drapeau de corner', 'Ne bouge pas'],
    'correctIndex': 1,
    'explanation': 'Timing clair sur le déclencheur.',
  },
  {
    'question': 'Après un but encaissé, phrase constructive?',
    'options': ['On est morts', 'On se replace, on gagne le prochain duel', 'On crie sur arbitre', 'On accuse la défense'],
    'correctIndex': 1,
    'explanation': 'Recentre l équipe immédiatement.',
  },
  {
    'question': 'Protéger un 1-0 en fin de match. Consigne?',
    'options': ['Tous à l attaque', 'Bloc compact, sécurité au centre', 'Inviter pression axe', 'Dribbler seul derrière'],
    'correctIndex': 1,
    'explanation': 'Sécurise la gestion de fin de match.',
  },
  {
    'question': 'Coach veut transitions plus rapides après récupération. Message?',
    'options': ['Beaucoup de touches', 'Première passe vers l avant si possible', 'Toujours en arrière', 'Attendre 10 secondes'],
    'correctIndex': 1,
    'explanation': 'Transition rapide mais contrôlée.',
  },
];

const List<Map<String, dynamic>> _fallbackSpanish = [
  {
    'question': 'El entrenador dice: "Compactos, no presionar antes." Que orden das?',
    'options': ['Presiona solo', 'Compactos y presion al senal', 'Todos atras sin plan', 'Ignorar orden'],
    'correctIndex': 1,
    'explanation': 'Confirma el tiempo tactico colectivo.',
  },
  {
    'question': 'Tu extremo no repliega. Mensaje mas claro?',
    'options': ['Haz algo', 'Vuelve con tu lateral ahora', 'Eres lento', 'Yo cubro todo'],
    'correctIndex': 1,
    'explanation': 'Instruccion concreta y accionable.',
  },
  {
    'question': 'En corner defensivo, que llamada organiza marcas?',
    'options': ['Corran todos', 'Hombre fuerte marcado, resto en zona', 'Sin plan', 'Portero solo'],
    'correctIndex': 1,
    'explanation': 'Define tareas antes del centro.',
  },
  {
    'question': 'El coach cambia a 4-4-2. Mejor confirmacion?',
    'options': ['Como sea', 'Dos lineas de cuatro, dos arriba', 'No escuche', 'Seguimos igual'],
    'correctIndex': 1,
    'explanation': 'Repetir estructura alinea al equipo.',
  },
  {
    'question': 'Disparador tras perdida para contra-presion?',
    'options': ['Caminar atras', 'Cinco segundos de presion juntos', 'Presiona uno solo', 'Falta inmediata'],
    'correctIndex': 1,
    'explanation': 'La accion colectiva inmediata es clave.',
  },
  {
    'question': 'Companero falla y se frustra. Que dices?',
    'options': ['Tu culpa', 'Siguiente jugada, enfocados', 'No le hablo', 'Me burlo'],
    'correctIndex': 1,
    'explanation': 'Protege foco y energia del grupo.',
  },
  {
    'question': 'Portero quiere salida corta. Orden del medio?',
    'options': ['Escóndete', 'Muestra apoyos, un toque si se puede', 'Balon largo siempre', 'Quedate quieto'],
    'correctIndex': 1,
    'explanation': 'Crea lineas limpias de pase.',
  },
  {
    'question': 'Rival sobrecarga tu lado izquierdo. Ajuste?',
    'options': ['Ninguno', 'Bascula bloque a izquierda y cierra lado debil', 'Marcaje total', 'No defender'],
    'correctIndex': 1,
    'explanation': 'Equilibra zona de mayor riesgo.',
  },
  {
    'question': 'Antes del corner ofensivo, mejor consigna?',
    'options': ['Moverse al azar', 'Bloqueo primer palo, ataque segundo', 'Nadie se mueve', 'Sube el portero'],
    'correctIndex': 1,
    'explanation': 'Roles claros mejoran sincronizacion.',
  },
  {
    'question': 'Lateral sube, queda espacio atras. Mensaje central?',
    'options': ['Ignorar', 'Cubre canal, pivote baja', 'Suban todos', 'Fuera de juego siempre'],
    'correctIndex': 1,
    'explanation': 'Cierra riesgo en transicion.',
  },
  {
    'question': 'Mucho ruido, oiste instruccion del coach. Que haces?',
    'options': ['Fingir que entendi', 'Repetir orden a dos companeros', 'Callarme', 'Cambiar solo'],
    'correctIndex': 1,
    'explanation': 'El relevo verbal mantiene orden.',
  },
  {
    'question': 'Final del partido, bajar ritmo. Mensaje?',
    'options': ['Pase arriesgado', 'Conservar, uno-dos toques, buscar falta', 'Tirar de lejos siempre', 'Presion total'],
    'correctIndex': 1,
    'explanation': 'Gestiona tempo con control.',
  },
  {
    'question': 'Delantero pregunta como orientar presion. Respuesta?',
    'options': ['Ninguna', 'Forzar fuera y cerrar pase interior', 'Solo al portero', 'Quedarse quieto'],
    'correctIndex': 1,
    'explanation': 'Senal direccional para todo el bloque.',
  },
  {
    'question': 'Mediocampista sin salida. Mejor apoyo verbal?',
    'options': ['Pierdela', 'Pared conmigo, tercer hombre ataca', 'Dribla a tres', 'Siempre taco'],
    'correctIndex': 1,
    'explanation': 'Ofrece secuencia segura y progresiva.',
  },
  {
    'question': 'Linea defensiva debe salir junta. Comando?',
    'options': ['Cada uno decide', 'Salimos juntos y cerramos espacios', 'Siempre atras', 'No hablar'],
    'correctIndex': 1,
    'explanation': 'Sincroniza movimientos de linea.',
  },
  {
    'question': 'Coach pide salida calmada bajo presion. Mensaje?',
    'options': ['Pelotazo', 'Usa portero, cambia lado, encuentra libre', 'Regate en area', 'Ignorar'],
    'correctIndex': 1,
    'explanation': 'Quita presion con circulacion limpia.',
  },
  {
    'question': 'Extremo debe atacar medio espacio al disparador. Cual?',
    'options': ['Pegado banda siempre', 'Si salta lateral, ataca carril interior', 'Espera en corner', 'No te muevas'],
    'correctIndex': 1,
    'explanation': 'Timing correcto del movimiento interior.',
  },
  {
    'question': 'Tras encajar gol, frase mas constructiva?',
    'options': ['Estamos muertos', 'Reinicio, ganamos el siguiente duelo', 'Discutir con arbitro', 'Culpar defensa'],
    'correctIndex': 1,
    'explanation': 'Reorganiza al equipo de inmediato.',
  },
  {
    'question': 'Proteger 1-0 al final. Mejor comunicacion?',
    'options': ['Todos al ataque', 'Bloque compacto y sin riesgo por dentro', 'Invitar presion por centro', 'Regatear solo atras'],
    'correctIndex': 1,
    'explanation': 'Prioriza seguridad y control final.',
  },
  {
    'question': 'Coach quiere transicion mas rapida tras recuperar. Orden?',
    'options': ['Muchos toques', 'Primer pase adelante si es seguro', 'Siempre atras', 'Esperar 10 segundos'],
    'correctIndex': 1,
    'explanation': 'Acelera ataque con criterio.',
  },
];