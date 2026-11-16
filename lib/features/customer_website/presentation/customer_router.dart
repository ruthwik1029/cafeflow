import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/cafe_components.dart';
import 'customer_site.dart';

/// Deliberately imports no internal router, roles, or administration screens.
GoRouter createCustomerRouter({String? initialLocation}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    ShellRoute(
      builder: (context, state, child) =>
          CustomerShell(location: state.uri.path, child: child),
      routes: [
        GoRoute(path: '/', builder: (_, _) => const CustomerHome()),
        GoRoute(path: '/menu', builder: (_, _) => const CustomerMenuPage()),
        GoRoute(path: '/about', builder: (_, _) => const CustomerAboutPage()),
        GoRoute(
          path: '/contact',
          builder: (_, _) => const CustomerContactPage(),
        ),
      ],
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    body: SafeArea(
      child: PageBody(
        child: Column(
          children: [
            const CafeBrand(),
            const SizedBox(height: 40),
            const CafeEmptyState(
              title: 'This page is not on the menu',
              message: 'Return to the CafeFlow homepage to continue.',
            ),
            const SizedBox(height: 24),
            CafeButton(label: 'Back to home', onPressed: () => context.go('/')),
          ],
        ),
      ),
    ),
  ),
);
