import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/donation_provider.dart';
import '../utils/layout.dart';

/// Donation screen: lists the available donation tiers as in-app purchases and
/// shows a thank-you dialog after a successful purchase.
class DonationScreen extends StatefulWidget {
  const DonationScreen({super.key});

  @override
  State<DonationScreen> createState() => _DonationScreenState();
}

class _DonationScreenState extends State<DonationScreen> {
  @override
  void initState() {
    super.initState();
    // The one place that needs the store. Everywhere else only reads the
    // persisted supporter flag, so this is where the connection is paid for.
    context.read<DonationProvider>().connectToStore();
  }

  @override
  Widget build(BuildContext context) {
    final dp = context.watch<DonationProvider>();
    final l = context.l10n;
    final cs = Theme.of(context).colorScheme;

    if (dp.thankYouPending) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        dp.clearThankYou();
        showDialog<void>(
          context: context,
          builder: (_) => Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentMaxWidth(context)),
              child: AlertDialog(
                title: Text(l.donationThankYouTitle),
                content: Text(l.donationThankYouBody),
                actions: [
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l.ok),
                  ),
                ],
              ),
            ),
          ),
        );
      });
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.donationTitle)),
      body: ListView(
        padding: contentPadding(context, top: 24, bottom: 28, innerH: 14),
        children: [
          _Header(),
          const SizedBox(height: 28),
          if (dp.loading)
            const Center(child: CircularProgressIndicator())
          else if (dp.unavailableReason != DonationUnavailableReason.none)
            Center(
              child: Text(
                switch (dp.unavailableReason) {
                  DonationUnavailableReason.storeUnavailable =>
                    l.donationUnavailable,
                  _ => l.donationNoProducts,
                },
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            )
          else ...[
            ...dp.products.map((p) => _TierCard(product: p)),
            if (dp.notFoundProductIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l.donationSomeMissing,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
          ],
          if (dp.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              dp.errorMessage!,
              style: TextStyle(color: cs.error),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

/// Heart icon and subtitle introducing the donation options.
class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Icon(Icons.favorite_rounded, size: 52, color: cs.primary),
        const SizedBox(height: 14),
        Text(
          l.donationSubtitle,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// A tappable card for one donation tier, showing its emoji, label, and price,
/// that starts the purchase when tapped.
class _TierCard extends StatelessWidget {
  final ProductDetails product;
  const _TierCard({required this.product});

  static const _emojis = {
    'donation_coffee': '☕',
    'donation_beer': '🍺',
    'donation_pizza': '🍕',
  };

  @override
  Widget build(BuildContext context) {
    final dp = context.read<DonationProvider>();
    final emoji = _emojis[product.id] ?? '💛';
    final title = product.title.replaceAll(RegExp(r'\s*\(.*?\)\s*$'), '');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 10,
          ),
          leading: Text(emoji, style: const TextStyle(fontSize: 32)),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(product.description),
          trailing: FilledButton(
            onPressed: () => dp.buy(product),
            child: Text(product.price),
          ),
        ),
      ),
    );
  }
}
