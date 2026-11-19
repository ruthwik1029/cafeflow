# Changelog

All notable changes to the CafeFlow project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0+2] - 2026-11-19

### Added
- **Live-Connected Demonstration Mode**: Integrated Supabase backend session isolation and ephemeral workspace provisioning via Edge Function (`provision-demo-session`).
- **Customer Online Ordering**: Public storefront order placement with rate-limiting protection, 6-digit pairing code verification, and real-time order tracking (`create_public_online_order`).
- **Production Access and Recovery Architecture**: Formalized comprehensive deployment runbooks and verified disaster-recovery standards (`CAFEFLOW_PRODUCTION_ACCESS_GUIDE.md`).

### Changed
- **Version Bump**: Incremented Flutter application build to `1.0.0+2` in `pubspec.yaml` aligned with release packaging standards.
- **Enterprise RBAC Hardening**: Eliminated implicit role fallbacks to enforce cryptographically verified staff memberships across all desktop, tablet, and mobile workspaces.
- **Migration Ledger Reconciliation**: Prepared clean dependency sequencing for migrations `000004` (security hardening), `000003` (storage provisioning), `000011` (immutable security audits), and `000012` (isolated demo seeding).

### Fixed
- **Secret Hygiene & Scanner**: Enhanced pre-commit secret detection script (`tool/scan_secrets.py`) to prevent false positives and block credential leaks.
- **Cross-Platform Window Routing**: Ensured clean Owner, Cashier, Kitchen, and Customer navigation routing across Windows, Android, and Flutter Web.
- **Continuous Integration Stability**: Unified Flutter and Dart SDK matrix and Inno Setup automation in GitHub Actions workflow.

## [1.0.0+1] - 2026-11-16

### Initial Release
- Multi-platform Cafe POS & Operations platform for Windows, Android, and Web.
- Offline-first local database caching with cloud synchronization.
- KDS ticket routing, Dine-in table management, inventory recipes, and receipt printing.

