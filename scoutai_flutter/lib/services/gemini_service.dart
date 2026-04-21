import 'dart:convert';
import 'package:http/http.dart' as http;

/// Multi-provider AI chat service.
/// Tries Gemini models first, falls back to Groq (Llama 3.3) if quota exceeded.
class GeminiService {
  static const _defaultGeminiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );

  String _geminiKey = '';
  String _groqKey = const String.fromEnvironment('GROQ_API_KEY', defaultValue: '');
  String _systemPrompt = '';
  bool _sessionStarted = false;

  // Conversation history for context
  final List<Map<String, String>> _history = [];

  // Models to try in order (different quota pools)
  static const _geminiModels = [
    'gemini-1.5-flash',
    'gemini-2.0-flash',
  ];

  bool get isConfigured => _resolvedGeminiKey.isNotEmpty || _groqKey.isNotEmpty;

  String get _resolvedGeminiKey {
    if (_geminiKey.isNotEmpty) return _geminiKey;
    return _defaultGeminiKey;
  }

  void setApiKey(String key) {
    // Auto-detect provider by key prefix
    final k = key.trim();
    if (k.startsWith('gsk_')) {
      _groqKey = k;
    } else {
      _geminiKey = k;
    }
    _sessionStarted = false;
    _history.clear();
  }

  void setGroqKey(String key) {
    _groqKey = key.trim();
  }

  void startSession({required Map<String, dynamic> playerStats}) {
    _systemPrompt = _buildSystemPrompt(playerStats);
    _history.clear();
    _sessionStarted = true;
  }

  Future<String> sendMessage(String userMessage) async {
    if (!_sessionStarted) {
      return 'Session not started. Please provide an API key.';
    }

    _history.add({'role': 'user', 'content': userMessage});

    // Try Groq first (Llama 3.3 70B — generous free tier, fast)
    if (_groqKey.isNotEmpty) {
      final result = await _tryGroq();
      if (result != null) {
        _history.add({'role': 'assistant', 'content': result});
        return result;
      }
    }

    // Fallback: Gemini models
    if (_resolvedGeminiKey.isNotEmpty) {
      for (final model in _geminiModels) {
        final result = await _tryGemini(model);
        if (result != null) {
          _history.add({'role': 'assistant', 'content': result});
          return result;
        }
      }
    }

    // Remove the failed user message from history
    if (_history.isNotEmpty && _history.last['role'] == 'user') {
      _history.removeLast();
    }
    return 'All AI providers are unavailable. Please try again later or add a Groq API key (free at console.groq.com).';
  }

  /// Generates a structured communication quiz for scouting scenarios.
  /// Returns a list of questions with 4 options each and a correct index.
  Future<List<Map<String, dynamic>>?> generateCommunicationQuiz({
    required String language,
    int count = 20,
    String? nonce,
  }) async {
    final prompt = '''
Generate exactly $count multiple-choice football communication quiz questions in $language.
Context: player communication with coach and teammates during real match situations.
Variation nonce: ${nonce ?? DateTime.now().millisecondsSinceEpoch}.

Output JSON only (no markdown, no commentary) with this exact shape:
{
  "questions": [
    {
      "question": "...",
      "options": ["...", "...", "...", "..."],
      "correctIndex": 0,
      "explanation": "short reason"
    }
  ]
}

Rules:
- Exactly 4 options per question.
- Exactly one correct answer.
- Keep each question under 160 characters.
- Use practical football communication scenarios (pressing, marking, transitions, set pieces, morale).
- Keep language level natural and useful for scouts.
- Make this quiz distinct from prior generations by using different situations and wording.
''';

    String? raw;
    if (_groqKey.isNotEmpty) {
      raw = await _generateQuizViaGroq(prompt);
    }
    raw ??= await _generateQuizViaGemini(prompt);
    if (raw == null || raw.trim().isEmpty) return null;

    return _decodeQuizPayload(raw);
  }

  /// Try a Gemini model via REST API with retry on 429
  Future<String?> _tryGemini(String model) async {
    final key = _resolvedGeminiKey;
    if (key.isEmpty) return null;

    final url = 'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$key';

    // Build contents array with system instruction + history
    final contents = <Map<String, dynamic>>[];

    // Add conversation history
    for (final msg in _history) {
      contents.add({
        'role': msg['role'] == 'assistant' ? 'model' : 'user',
        'parts': [{'text': msg['content']}],
      });
    }

    final body = jsonEncode({
      'system_instruction': {
        'parts': [{'text': _systemPrompt}],
      },
      'contents': contents,
      'generationConfig': {
        'temperature': 0.8,
        'topP': 0.95,
        'maxOutputTokens': 1024,
      },
    });

    // Retry with backoff on 429
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final res = await http.post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: body,
        ).timeout(const Duration(seconds: 30));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final candidates = data['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final parts = candidates[0]['content']?['parts'] as List?;
            if (parts != null && parts.isNotEmpty) {
              return parts[0]['text'] as String?;
            }
          }
          return null;
        } else if (res.statusCode == 429) {
          // Rate limited — wait and retry once, then try next model
          if (attempt == 0) {
            await Future.delayed(const Duration(seconds: 2));
            continue;
          }
          return null; // Move to next model/provider
        } else {
          return null; // Non-retryable error, try next
        }
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Fallback: Groq API (OpenAI-compatible, Llama 3.3 70B, free tier)
  Future<String?> _tryGroq() async {
    if (_groqKey.isEmpty) return null;

    const url = 'https://api.groq.com/openai/v1/chat/completions';

    final messages = <Map<String, String>>[
      {'role': 'system', 'content': _systemPrompt},
      ..._history,
    ];

    final body = jsonEncode({
      'model': 'llama-3.3-70b-versatile',
      'messages': messages,
      'temperature': 0.8,
      'max_tokens': 1024,
    });

    try {
      final res = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_groqKey',
        },
        body: body,
      ).timeout(const Duration(seconds: 30));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final choices = data['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          return choices[0]['message']?['content'] as String?;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _generateQuizViaGroq(String prompt) async {
    if (_groqKey.isEmpty) return null;

    const url = 'https://api.groq.com/openai/v1/chat/completions';
    final body = jsonEncode({
      'model': 'llama-3.3-70b-versatile',
      'messages': [
        {
          'role': 'system',
          'content': 'You are a quiz generator that outputs strict JSON only.',
        },
        {
          'role': 'user',
          'content': prompt,
        },
      ],
      'temperature': 0.6,
      'max_tokens': 2500,
      'response_format': {
        'type': 'json_object',
      },
    });

    try {
      final res = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_groqKey',
        },
        body: body,
      ).timeout(const Duration(seconds: 40));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final choices = data['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          return choices[0]['message']?['content'] as String?;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _generateQuizViaGemini(String prompt) async {
    final key = _resolvedGeminiKey;
    if (key.isEmpty) return null;

    final url = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$key';
    final body = jsonEncode({
      'system_instruction': {
        'parts': [
          {'text': 'You are a quiz generator that outputs strict JSON only.'},
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt},
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.6,
        'maxOutputTokens': 4096,
        'responseMimeType': 'application/json',
      },
    });

    try {
      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 40));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final candidates = data['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final parts = candidates[0]['content']?['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            return parts[0]['text'] as String?;
          }
        }
      }
    } catch (_) {}

    return null;
  }

  List<Map<String, dynamic>>? _decodeQuizPayload(String raw) {
    final cleaned = raw
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();

    dynamic decoded;
    try {
      decoded = jsonDecode(cleaned);
    } catch (_) {
      final start = cleaned.indexOf('{');
      final end = cleaned.lastIndexOf('}');
      if (start < 0 || end <= start) return null;
      try {
        decoded = jsonDecode(cleaned.substring(start, end + 1));
      } catch (_) {
        return null;
      }
    }

    if (decoded is! Map) return null;
    final items = decoded['questions'];
    if (items is! List || items.isEmpty) return null;

    final out = <Map<String, dynamic>>[];
    for (final item in items) {
      if (item is! Map) continue;
      final question = (item['question'] ?? '').toString().trim();
      final optionsRaw = item['options'];
      final options = optionsRaw is List
          ? optionsRaw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList()
          : <String>[];
      final idx = item['correctIndex'];
      final correctIndex = idx is num ? idx.toInt() : -1;
      final explanation = (item['explanation'] ?? '').toString().trim();

      if (question.isEmpty || options.length != 4) continue;
      if (correctIndex < 0 || correctIndex >= options.length) continue;

      out.add({
        'question': question,
        'options': options,
        'correctIndex': correctIndex,
        'explanation': explanation,
      });
    }

    return out.isEmpty ? null : out;
  }

  String _buildSystemPrompt(Map<String, dynamic> stats) {
    final pac = stats['pac'] ?? '?';
    final sho = stats['sho'] ?? '?';
    final pas = stats['pas'] ?? '?';
    final dri = stats['dri'] ?? '?';
    final def = stats['def'] ?? '?';
    final phy = stats['phy'] ?? '?';
    final ovr = stats['ovr'] ?? '?';
    final position = stats['position'] ?? 'CM';
    final maxSpeed = stats['maxSpeedKmh'] ?? '?';
    final avgSpeed = stats['avgSpeedKmh'] ?? '?';
    final distance = stats['distanceKm'] ?? '?';
    final sprints = stats['sprints'] ?? '?';
    final trackingPoints = stats['trackingPoints'] ?? '?';

    return '''
You are an elite football (soccer) AI performance coach inside the ScoutAI app.
You have just analyzed a video of a football player and computed the following FIFA-style stats:

PLAYER PROFILE:
- Position: $position
- Overall Rating (OVR): $ovr / 99

STATS (each out of 99):
- PAC (Pace/Speed): $pac
- SHO (Shooting/Explosiveness): $sho
- PAS (Passing/Vision): $pas
- DRI (Dribbling/Agility): $dri
- DEF (Defensive Work): $def
- PHY (Physical/Stamina): $phy

MATCH METRICS:
- Top Speed: $maxSpeed km/h
- Average Speed: $avgSpeed km/h
- Distance Covered: $distance km
- Sprint Count: $sprints
- Tracking Points Analyzed: $trackingPoints

YOUR ROLE:
1. You can see and discuss these stats with the player.
2. Identify strengths and weaknesses based on the stats.
3. Provide specific, practical training exercises to improve weak areas.
4. Give tactical advice based on their position and movement patterns.
5. Motivate the player and be encouraging but honest.
6. When suggesting exercises, be specific: sets, reps, duration, rest periods.
7. Reference real professional players as role models when relevant.
8. Keep responses concise but informative (2-4 paragraphs max).
9. Use football terminology naturally.
10. If asked about something outside football coaching, politely redirect to football topics.

Start by greeting the player, briefly summarizing their key strengths and areas to improve, and asking what they'd like to work on.
''';
  }
}
