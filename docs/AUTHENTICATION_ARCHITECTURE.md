# CafeFlow — Authentication Architecture

**Document Version:** 1.0.0  
**Phase:** 04 — Authentication, RBAC & Security Hardening  
**Target Environments:** Windows Desktop, Android Tablet/Mobile, Flutter Web  

---

## 1. Architectural Overview

CafeFlow utilizes **Supabase Auth** (GoTrue / PostgreSQL `auth.users`) as its single, authoritative authentication provider. The application strictly rejects custom password hashing systems or non-standard authentication layers.

```
                      +---------------------------------------+
                      |       Flutter Client (CafeFlow)       |
                      +---------------------------------------+
                                  |                 |
                   (Email Login)  |                 | (Username Login)
                                  v                 v
                 +-------------------+    +----------------------------+
                 | Supabase Auth API |    | RPC: resolve_username_to_  |
                 | (signInWithPass)  |    | email                      |
                 +-------------------+    +----------------------------+
                           |                            |
                           |       +--------------------+
                           |       | (Resolved Email)
                           v       v
                 +-------------------+
                 | Session JWT &     |
                 | Refresh Tokens    |
                 +-------------------+
                           |
                           v
                 +--------------------------------------+
                 | Session Persistence (SharedPreferences|
                 | via FlutterAuthClientOptions)         |
                 +--------------------------------------+
```

### Core Security Principles

1. **Supabase Auth Exclusive Provider**: No custom password hash generation or verification. Passwords are processed and salted exclusively within Supabase Auth using Argon2id/bcrypt.
2. **Public Signup Strictly Disabled**: Public visitors to the customer-facing Flutter Web site or desktop apps cannot register accounts. All staff and management credentials are provisioned exclusively through authorized administrative channels.
3. **Tenant & Role Scoping**: An authenticated user profile is linked to one or more restaurants through `restaurant_memberships`. The active session binds to a validated restaurant context.
4. **Session Persistence**: Sessions persist securely across application restarts via `FlutterAuthClientOptions(detectSessionInUri: false, autoRefreshToken: true)` on top of platform storage (`SharedPreferences`).

---

## 2. Authentication Workflows

### 2.1 Email + Password Login

- The user supplies an email address and password on the unified `LoginPage`.
- The client calls `SupabaseAuthRepository.loginWithEmail(email, password)`.
- Supabase Auth verifies credentials against `auth.users`.
- Upon successful authentication, user profile details are fetched from `user_profiles` and active memberships from `restaurant_memberships`.
- `AuthController` receives the authenticated `CafeUser` and updates state to `AuthStatus.authenticated`.

### 2.2 Username + Password Login (Secure Resolution Mechanism)

To streamline POS and kitchen terminal operations, staff members can log in using a concise username (e.g., `kabir.cashier`, `mira.kitchen`):

1. **Client Identification**: The client checks whether the identifier contains `@`. If not, it treats the identifier as a username.
2. **Server-Side RPC Resolution**:
   - The client invokes the PostgreSQL `SECURITY DEFINER` function `resolve_username_to_email(p_username TEXT)`.
   - The function queries `public.user_profiles` for a matching `username` (case-insensitive) where the profile and at least one restaurant membership is active (`is_active = TRUE`).
   - If found, it safely returns the associated user's primary email from `auth.users`.
   - If not found or inactive, it returns `NULL`.
3. **Protection Against Enumeration & Leakage**:
   - The RPC has an execution grant for `anon` and `authenticated`.
   - The RPC returns only the email string needed for authentication, without exposing password hashes, metadata, or restaurant details.
   - If resolution fails, the client reports a generic error: `"Invalid login credentials."`, preventing account enumeration.
4. **Standard Supabase Auth Handshake**:
   - With the resolved email, the client executes `signInWithPassword(email: resolvedEmail, password: password)`.

---

## 3. Session Persistence & Restoration

### 3.1 Startup Initialization

During application startup in `BackendService`:
```dart
Supabase.initialize(
  url: config.supabaseUrl,
  anonKey: config.publishableKey,
  authOptions: const FlutterAuthClientOptions(
    detectSessionInUri: false,
    autoRefreshToken: true,
  ),
);
```

When `AuthController` initializes:
1. It queries `_repo.restoreSession()`.
2. Supabase SDK reads cached JWT and refresh tokens from local storage.
3. If valid, the current user identity and active restaurant memberships are reloaded.
4. The user seamlessly bypasses the login screen directly into their assigned workspace.
5. If expired or invalid, the session fails closed, transitioning to `AuthStatus.unauthenticated`.

### 3.2 Token Refresh & Expiration

- `autoRefreshToken: true` ensures that the client automatically refreshes the short-lived access JWT before expiry using the refresh token.
- If refresh fails (e.g., account revoked or deactivated in database), the auth state change stream emits an unauthenticated event, immediately clearing local state.

### 3.3 Explicit Logout & State Purge

When `AuthController.logout()` is invoked:
- It issues `_repo.logout()`, revoking the session token on Supabase Auth.
- State is atomically reset to `const AuthState(status: AuthStatus.unauthenticated)`.
- All tenant context, active restaurant IDs, user profiles, and permission caches are purged from memory, preventing state leakage between consecutive users on shared terminals.

---

## 4. Route Protection & Guards

The internal router (`lib/core/routing/internal_router.dart`) enforces route guards via `GoRouter.redirect`:

```dart
redirect: (context, state) {
  final auth = getAuthState?.call() ?? const AuthState();
  final isLoginRoute = state.uri.path == '/login';

  // 1. Unauthenticated users are redirected to /login
  if (!auth.isAuthenticated) {
    if (!demoEnabled) {
      return isLoginRoute ? null : '/login';
    }
    // Demo fallback logic if configured
    return null;
  }

  // 2. Authenticated users attempting to visit /login are redirected to their workspace
  if (isLoginRoute) {
    final role = auth.activeRole ?? WorkspaceRole.staff;
    return workspaceFor(role).home;
  }

  // 3. Role enforcement: Ensure the user's role permits the target workspace route
  final requestedRoleName = state.uri.pathSegments.firstOrNull;
  if (requestedRoleName != null && auth.activeRole != null) {
    if (auth.activeRole!.name != requestedRoleName &&
        auth.activeRole != WorkspaceRole.owner &&
        auth.activeRole != WorkspaceRole.admin) {
      // Divert to the user's authorized home
      return workspaceFor(auth.activeRole!).home;
    }
  }

  return null;
}
```

The public customer website (`lib/features/customer_site/`) remains entirely separate, using its own router that never exposes internal workspace routes or administrative state.

