import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/backend.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cafe_components.dart';
import '../../billing/application/cart_controller.dart';
import '../../menu/presentation/catalog_browser.dart';
import 'customer_cart_bar.dart';
import 'customer_checkout_sheet.dart';

const _links = {
  '/': 'Home',
  '/menu': 'Menu',
  '/about': 'Our story',
  '/contact': 'Visit us',
};

class CustomerShell extends ConsumerWidget {
  const CustomerShell({required this.location, required this.child, super.key});
  final String location;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backend = ref.watch(backendProvider);
    final isLive = backend.status == BackendStatus.initialized;
    final wide =
        MediaQuery.sizeOf(context).width >= 850 &&
        MediaQuery.textScalerOf(context).scale(14) <= 21;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: wide ? 40 : 20,
                vertical: 20,
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: CafeBrand(),
                    ),
                  ),
                  if (wide)
                    for (final link in _links.entries)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: TextButton(
                          onPressed: () => context.go(link.key),
                          style: TextButton.styleFrom(
                            foregroundColor: Theme.of(context)
                                .colorScheme
                                .onSurface,
                            backgroundColor: location == link.key
                                ? Theme.of(context).colorScheme.primaryContainer
                                : null,
                          ),
                          child: Text(link.value),
                        ),
                      ),
                  const SizedBox(width: 8),
                  StatusPill(
                    wide
                        ? (isLive
                              ? 'Live · Flagship Bistro'
                              : 'Offline Simulation')
                        : (isLive ? 'Live' : 'Offline'),
                    icon: isLive
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off_outlined,
                  ),
                  const SizedBox(width: 8),
                  const ThemeControl(),
                  if (!wide)
                    PopupMenuButton<String>(
                      tooltip: 'Site navigation',
                      icon: const Icon(Icons.menu_rounded),
                      onSelected: context.go,
                      itemBuilder: (_) => _links.entries
                          .map(
                            (link) => PopupMenuItem(
                              value: link.key,
                              child: Text(link.value),
                            ),
                          )
                          .toList(),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: SingleChildScrollView(child: child)),
            const CustomerCartBar(),
          ],
        ),
      ),
    );
  }
}

class CustomerHome extends StatelessWidget {
  const CustomerHome({super.key});
  @override
  Widget build(BuildContext context) => PageBody(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const StatusPill(
          'Now Brewing in Indiranagar',
          icon: Icons.local_cafe_outlined,
        ),
        const SizedBox(height: 28),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 850;
            final copy = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Good coffee.\nGreat company.',
                  style: Theme.of(context).textTheme.displayLarge
                      ?.copyWith(fontSize: wide ? 76 : 48, height: 1.04),
                ),
                const SizedBox(height: 24),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Text(
                    'A neighborhood sanctuary crafted for slow sips, sourdough mornings, and genuine hospitality.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                const SizedBox(height: 28),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    CafeButton(
                      label: 'Explore the menu',
                      onPressed: () => context.go('/menu'),
                    ),
                    CafeButton(
                      label: 'Our story',
                      secondary: true,
                      icon: Icons.arrow_outward,
                      onPressed: () => context.go('/about'),
                    ),
                  ],
                ),
              ],
            );
            return wide
                ? Row(
                    children: [
                      Expanded(flex: 6, child: copy),
                      const SizedBox(width: 32),
                      const Expanded(flex: 4, child: _PublicArtwork()),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      copy,
                      const SizedBox(height: 32),
                      const _PublicArtwork(),
                    ],
                  );
          },
        ),
        const SizedBox(height: 56),
        Text(
          'Featured from the Bar & Kitchen',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Seasonal single origins, cultured butter pastries, and fresh brunch plates.',
        ),
        const SizedBox(height: 24),
        const CatalogBrowser(featuredOnly: true),
        const SizedBox(height: 56),
        const AdaptiveColumns(
          children: [
            _PublicNote(
              '01',
              'Direct Origin Coffee',
              'Carefully roasted beans sourced directly from estates in Chikmagalur and Coorg.',
            ),
            _PublicNote(
              '02',
              'Slow Fermented Breads',
              'Wild sourdough baked fresh every morning with organic flours and zero shortcuts.',
            ),
            _PublicNote(
              '03',
              'Warm Community Space',
              'Comfortable seating, reliable quiet corners, and friendly faces behind the counter.',
            ),
          ],
        ),
        const SizedBox(height: 56),
        CafeCard(
          padding: const EdgeInsets.all(28),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 700;
              final info = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Join us for a cup',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '12 Heritage Cross, 100ft Road, Indiranagar, Bengaluru\nOpen daily from 7:30 AM to 10:30 PM',
                  ),
                  const SizedBox(height: 16),
                  CafeButton(
                    label: 'View location & hours',
                    secondary: true,
                    onPressed: () => context.go('/contact'),
                  ),
                ],
              );
              return wide
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: info),
                        const Icon(Icons.storefront_outlined, size: 64),
                      ],
                    )
                  : info;
            },
          ),
        ),
        const SizedBox(height: 48),
        const _CustomerFooter(),
      ],
    ),
  );
}

class CustomerMenuPage extends ConsumerWidget {
  const CustomerMenuPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => PageBody(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text('Cafe Menu', style: Theme.of(context).textTheme.displayMedium),
        const SizedBox(height: 8),
        const Text(
          'All items prepared fresh in-house. Prices are inclusive of all taxes.',
        ),
        const SizedBox(height: 28),
        CatalogBrowser(
          onSelect: (product) {
            ref.read(cartProvider('customer').notifier).add(product);
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Added "${product.name}" to cart.'),
                duration: const Duration(seconds: 2),
                action: SnackBarAction(
                  label: 'View Cart',
                  onPressed: () => CustomerCheckoutSheet.show(context),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 48),
        const _CustomerFooter(),
      ],
    ),
  );
}

class CustomerAboutPage extends StatelessWidget {
  const CustomerAboutPage({super.key});

  @override
  Widget build(BuildContext context) => PageBody(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          'A Little Space for Good Company',
          style: Theme.of(context).textTheme.displayMedium,
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Text(
            'CafeFlow started with a simple belief: that a neighborhood café should be more than a transaction. It should be a pause in the day, a meeting place for friends, and a celebration of mindful craftsmanship.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
        const SizedBox(height: 36),
        const AdaptiveColumns(
          children: [
            CafeCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.coffee_outlined, size: 32),
                  SizedBox(height: 16),
                  Text(
                    'The Coffee Bar',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'We partner with micro-lot growers in Southern India, profiling each roast to highlight its terroir, sweetness, and complexity.',
                  ),
                ],
              ),
            ),
            CafeCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.bakery_dining_outlined, size: 32),
                  SizedBox(height: 16),
                  Text(
                    'Artisanal Bakery',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Our laminations use French-style cultured butter, folded over three days to produce flaky, golden croissants and buns.',
                  ),
                ],
              ),
            ),
            CafeCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.favorite_border, size: 32),
                  SizedBox(height: 16),
                  Text(
                    'Hospitality First',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Our baristas and floor team are here to guide your choices with care, whether you are trying your first pour-over or your hundredth latte.',
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 48),
        const _CustomerFooter(),
      ],
    ),
  );
}

class CustomerContactPage extends StatelessWidget {
  const CustomerContactPage({super.key});

  @override
  Widget build(BuildContext context) => PageBody(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          'Visit & Contact Us',
          style: Theme.of(context).textTheme.displayMedium,
        ),
        const SizedBox(height: 12),
        const Text(
          'Drop by for a brew or reach out for inquiries and private gatherings.',
        ),
        const SizedBox(height: 32),
        AdaptiveColumns(
          minWidth: 300,
          children: [
            CafeCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined),
                      const SizedBox(width: 12),
                      Text(
                        'Our Flagship',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'CafeFlow Flagship\n12 Heritage Cross, 100ft Road\nIndiranagar, Bengaluru, KA 560038',
                    style: TextStyle(height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  const Text('Phone: +91 80 4912 8800'),
                  const SizedBox(height: 4),
                  const Text('Email: hello@cafeflow.local'),
                ],
              ),
            ),
            CafeCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.access_time_rounded),
                      const SizedBox(width: 12),
                      Text(
                        'Opening Hours',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _hoursRow('Monday – Thursday', '7:30 AM – 10:00 PM'),
                  const Divider(height: 16),
                  _hoursRow('Friday – Saturday', '7:30 AM – 11:00 PM'),
                  const Divider(height: 16),
                  _hoursRow('Sunday', '8:00 AM – 10:30 PM'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 48),
        const _CustomerFooter(),
      ],
    ),
  );

  Widget _hoursRow(String days, String hours) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(days, style: const TextStyle(fontWeight: FontWeight.w600)),
      Text(hours),
    ],
  );
}

class _CustomerFooter extends StatelessWidget {
  const _CustomerFooter();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: 24),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const CafeBrand(),
            Text(
              '© 2026 CafeFlow. All rights reserved.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class PublicFoundationPage extends StatelessWidget {
  const PublicFoundationPage({
    required this.title,
    required this.message,
    super.key,
  });
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) => PageBody(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        Text(title, style: Theme.of(context).textTheme.displayMedium),
        const SizedBox(height: 24),
        CafeEmptyState(
          title: 'Something good is on its way',
          message: message,
          icon: Icons.local_cafe_outlined,
        ),
        const SizedBox(height: 24),
        CafeButton(label: 'Back to home', onPressed: () => context.go('/')),
      ],
    ),
  );
}

class _PublicArtwork extends StatelessWidget {
  const _PublicArtwork();
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: double.infinity,
      height: 350,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: CafeColors.coral,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            right: -40,
            top: -65,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: CafeColors.charcoal, width: 1),
              ),
            ),
          ),
          Transform.rotate(
            angle: -0.16,
            child: Container(
              width: 216,
              height: 240,
              decoration: BoxDecoration(
                color: CafeColors.ivory,
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x3320242A),
                    offset: Offset(14, 18),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.coffee_rounded,
                    size: 95,
                    color: CafeColors.charcoal,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'SLOW SIPS.\nGOOD DAYS.',
                    textScaler: TextScaler.noScaling,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'SpaceGrotesk',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: CafeColors.charcoal,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Positioned(
            bottom: 18,
            right: 20,
            child: Text(
              'THE CAFEFLOW WAY',
              style: TextStyle(
                color: CafeColors.charcoal,
                fontSize: 10,
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _PublicNote extends StatelessWidget {
  const _PublicNote(this.number, this.title, this.message);
  final String number;
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) => CafeCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(number, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 24),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Text(message),
      ],
    ),
  );
}
