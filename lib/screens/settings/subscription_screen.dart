import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets/widgets.dart';

/// Subscription (Coming Soon).
///
/// Every new user gets a full 1-year free subscription. After the free
/// year, a small plan keeps the shop running: Rs 99 per month or
/// Rs 1000 per year. Nothing is chargeable yet - this screen only
/// explains the upcoming plans.
class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const RubyAppBar(title: 'Subscription'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _heroCard(),
          const SizedBox(height: 14),
          _freeYearCard(),
          const SizedBox(height: 14),
          _plansCard(),
          const SizedBox(height: 14),
          _footerNote(),
        ],
      ),
    );
  }

  // ---------------- hero ----------------

  Widget _heroCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Ruby.ruby, Ruby.rubyDark],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.workspace_premium_outlined,
                    color: Colors.white, size: 28),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'COMING SOON',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    color: Ruby.ruby,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Ruby Invoice Subscription',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Simple plans for every shop. Manage your validity here.',
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- account status ----------------

  Widget _freeYearCard() {
    return _whiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Ruby.greenLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.card_giftcard,
                    color: Ruby.green, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Your account is active',
                  style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: Ruby.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'All features are unlocked: billing, inventory, customer '
            'ledger, reports, purchase invoices, bilty photo sync and '
            '2-device cloud sync. There is no trial period - the Admin '
            'can extend or renew validity from the Ruby Key panel at '
            'any time. No payment is needed today.',
            style: TextStyle(
                fontSize: 13, height: 1.55, color: Ruby.muted),
          ),
        ],
      ),
    );
  }

  // ---------------- plans ----------------

  Widget _plansCard() {
    return _whiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Renewal plans',
            style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: Ruby.ink),
          ),
          const SizedBox(height: 4),
          const Text(
            'Choose a plan that fits your shop:',
            style: TextStyle(fontSize: 12.5, color: Ruby.muted),
          ),
          const SizedBox(height: 14),
          _planTile(
            icon: Icons.calendar_month_outlined,
            name: 'Monthly Plan',
            price: '₹99',
            unit: '/ month',
            tag: 'Coming Soon',
            tagColor: Ruby.rubyLight,
            tagTextColor: Ruby.ruby,
          ),
          const SizedBox(height: 10),
          _planTile(
            icon: Icons.event_available_outlined,
            name: 'Yearly Plan',
            price: '₹1000',
            unit: '/ year',
            tag: 'Save ₹188 a year',
            tagColor: Ruby.greenLight,
            tagTextColor: Ruby.green,
          ),
        ],
      ),
    );
  }

  Widget _planTile({
    required IconData icon,
    required String name,
    required String price,
    required String unit,
    required String tag,
    required Color tagColor,
    required Color tagTextColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: Ruby.fieldBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Ruby.line),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Ruby.rubyLight,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: Ruby.ruby, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: Ruby.ink),
                ),
                const SizedBox(height: 2),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: price,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Ruby.ruby),
                      ),
                      TextSpan(
                        text: '  $unit',
                        style: const TextStyle(
                            fontSize: 12, color: Ruby.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: tagColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              tag,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: tagTextColor),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- footer ----------------

  Widget _footerNote() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 15, color: Ruby.faint),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            'Subscriptions are not active yet. We will remind you inside '
            'the app before your free year ends - your bills and data '
            'always stay yours.',
            style: const TextStyle(fontSize: 11.5, height: 1.5, color: Ruby.faint),
          ),
        ),
      ],
    );
  }

  Widget _whiteCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Ruby.line),
      ),
      child: child,
    );
  }
}
