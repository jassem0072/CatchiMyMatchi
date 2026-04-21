import 'package:flutter/material.dart';

import '../services/translations.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';

/// Billing History screen — shows past transactions (currently empty state).
class BillingHistoryScreen extends StatelessWidget {
  const BillingHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return GradientScaffold(
      appBar: AppBar(
        title: Text(s.billingHistory),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.receipt_long, size: 64, color: AppColors.txMuted(context)),
              const SizedBox(height: 16),
              Text(
                s.noBillingHistory,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                s.noBillingYet,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.txMuted(context), fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
