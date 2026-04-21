import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/api_config.dart';
import '../services/auth_storage.dart';
import '../theme/app_colors.dart';

/// A notification bell icon with a red badge showing the unread count.
/// Polls every 30 seconds for new notifications.
class NotificationBadge extends StatefulWidget {
  final VoidCallback onTap;

  const NotificationBadge({super.key, required this.onTap});

  @override
  State<NotificationBadge> createState() => _NotificationBadgeState();
}

class _NotificationBadgeState extends State<NotificationBadge>
    with SingleTickerProviderStateMixin {
  int _count = 0;
  Timer? _timer;
  late AnimationController _animCtrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut));

    _fetchCount();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _fetchCount());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchCount() async {
    try {
      final token = await AuthStorage.loadToken();
      if (token == null || !mounted) return;
      final uri = Uri.parse('${ApiConfig.baseUrl}/notifications/unread-count');
      final res = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      if (!mounted || res.statusCode != 200) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final newCount = (data['count'] ?? 0) as int;
      if (newCount != _count) {
        setState(() => _count = newCount);
        if (newCount > 0) {
          _animCtrl.forward(from: 0);
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () {
        widget.onTap();
        // Reset after navigating — will refresh on next poll
        if (_count > 0) setState(() => _count = 0);
      },
      tooltip: 'Notifications',
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            _count > 0
                ? Icons.notifications_active
                : Icons.notifications_outlined,
            color: _count > 0 ? AppColors.primary : null,
          ),
          if (_count > 0)
            Positioned(
              right: -6,
              top: -4,
              child: ScaleTransition(
                scale: _scaleAnim,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.surf(context),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      _count > 99 ? '99+' : '$_count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
