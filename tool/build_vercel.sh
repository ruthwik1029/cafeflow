#!/usr/bin/env bash
set -e

# ==============================================================================
# CafeFlow — Vercel Web Production Build Script
# Compiles Flutter Web Release into build/web for Vercel Static Hosting.
# ==============================================================================

FLUTTER_VERSION="3.47.9"
FLUTTER_DIR="${HOME}/.flutter-sdk"

echo "============================================================"
echo "  CafeFlow Vercel Web Release Builder"
echo "  Target Output: build/web"
echo "  Flutter Target: ${FLUTTER_VERSION} (stable)"
echo "============================================================"

# Ensure git does not block operations on different owners in container
git config --global --add safe.directory "*" 2>/dev/null || true

# 1. Acquire Flutter SDK
if command -v flutter >/dev/null 2>&1; then
    echo "✓ Found Flutter on PATH: $(which flutter)"
elif [ -x "${FLUTTER_DIR}/bin/flutter" ]; then
    echo "✓ Reusing existing Flutter SDK at: ${FLUTTER_DIR}"
    export PATH="${FLUTTER_DIR}/bin:${PATH}"
else
    echo "→ Installing Flutter SDK v${FLUTTER_VERSION} from GitHub..."
    mkdir -p "$(dirname "${FLUTTER_DIR}")"
    git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git "${FLUTTER_DIR}"
    export PATH="${FLUTTER_DIR}/bin:${PATH}"
fi

# 2. Display environment diagnostics
echo "→ Flutter Environment:"
flutter --version
dart --version

# 3. Disable telemetry & prepare web engine artifacts
echo "→ Configuring Flutter for headless Web build..."
flutter config --no-analytics
flutter precache --web

# 4. Resolve project dependencies
echo "→ Resolving Flutter dependencies..."
flutter pub get

# 5. Build arguments (strictly allowing only public, non-secret parameters)
DART_DEFINES=""
if [ -f ".env" ]; then
    DART_DEFINES="--dart-define-from-file=.env"
fi
if [ -n "${SUPABASE_URL}" ]; then
    DART_DEFINES="${DART_DEFINES} --dart-define=SUPABASE_URL=${SUPABASE_URL}"
fi
if [ -n "${SUPABASE_PUBLISHABLE_KEY}" ]; then
    # Security guard: only accept public publishable keys (sb_publishable_ or anon JWT)
    if [[ "${SUPABASE_PUBLISHABLE_KEY}" =~ ^sb_publishable_ ]] || [[ "${SUPABASE_PUBLISHABLE_KEY}" =~ ^eyJ ]]; then
        DART_DEFINES="${DART_DEFINES} --dart-define=SUPABASE_PUBLISHABLE_KEY=${SUPABASE_PUBLISHABLE_KEY}"
    else
        echo "⚠ WARNING: SUPABASE_PUBLISHABLE_KEY does not start with sb_publishable_ or eyJ; omitting to prevent privileged token exposure."
    fi
fi
if [ -n "${APP_ENV}" ]; then
    DART_DEFINES="${DART_DEFINES} --dart-define=APP_ENV=${APP_ENV}"
fi
if [ -n "${DEMO_MODE}" ]; then
    DART_DEFINES="${DART_DEFINES} --dart-define=DEMO_MODE=${DEMO_MODE}"
fi

# 6. Compile Web Release Bundle
echo "→ Compiling Flutter Web release bundle..."
flutter build web --release --base-href / ${DART_DEFINES}

# 7. Validate build output integrity
echo "→ Verifying build output in build/web..."
if [ ! -f "build/web/index.html" ]; then
    echo "✗ ERROR: build/web/index.html was not generated!" >&2
    exit 1
fi

if [ ! -f "build/web/flutter_bootstrap.js" ] && [ ! -f "build/web/main.dart.js" ]; then
    echo "✗ ERROR: Flutter Web entrypoint scripts not found in build/web!" >&2
    exit 1
fi

FILE_COUNT=$(find build/web -type f | wc -l)
echo "============================================================"
echo "  ✓ SUCCESS: Web release compiled successfully!"
echo "  Artifact directory: build/web"
echo "  Total files generated: ${FILE_COUNT}"
echo "============================================================"

