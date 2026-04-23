import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class ListPaginator extends StatelessWidget {
  const ListPaginator({
    super.key,
    required this.totalItems,
    required this.itemsPerPage,
    required this.currentPage,
    required this.onPageChanged,
  });

  final int totalItems;
  final int itemsPerPage;
  final int currentPage;
  final ValueChanged<int> onPageChanged;

  int get _totalPages => math.max(1, (totalItems / itemsPerPage).ceil());

  @override
  Widget build(BuildContext context) {
    if (totalItems <= itemsPerPage) return const SizedBox.shrink();

    final totalPages = _totalPages;
    final safePage = currentPage.clamp(1, totalPages);

    final pages = <int>{
      1,
      totalPages,
      safePage,
      safePage - 1,
      safePage + 1,
    }
        .where((p) => p >= 1 && p <= totalPages)
        .toList()
      ..sort();

    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            _PageButton(
              icon: Icons.chevron_left,
              enabled: safePage > 1,
              onTap: () => onPageChanged(safePage - 1),
            ),
            for (final page in pages)
              _PageChip(
                label: '$page',
                selected: page == safePage,
                onTap: () => onPageChanged(page),
              ),
            _PageButton(
              icon: Icons.chevron_right,
              enabled: safePage < totalPages,
              onTap: () => onPageChanged(safePage + 1),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Page $safePage of $totalPages',
          style: TextStyle(
            color: AppColors.txMuted(context),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _PageChip extends StatelessWidget {
  const _PageChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? AppColors.primary : AppColors.surface.withValues(alpha: 0.75);
    final fg = selected ? Colors.white : AppColors.text;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border.withValues(alpha: 0.8),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(color: fg, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _PageButton extends StatelessWidget {
  const _PageButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled
              ? AppColors.surface.withValues(alpha: 0.75)
              : AppColors.surface.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
        ),
        child: Icon(
          icon,
          size: 20,
          color: enabled ? AppColors.text : AppColors.textMuted,
        ),
      ),
    );
  }
}
