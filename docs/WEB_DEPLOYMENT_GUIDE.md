# CafeFlow — Web Deployment & Hosting Guide

This guide details the deployment of the CafeFlow web application, focusing on the public customer storefront, SPA routing configuration, and production security headers.

---

## 1. Web Architecture & Public Isolation

CafeFlow features a dual-routing design:
1. **Public Customer Portal:** Serves patrons visiting the cafe's website to browse the live menu, check cafe hours, and view location details (`/`, `/menu`, `/contact`).
2. **Internal Role Workspaces:** Gated behind authentication (`/login`, `/pos`, `/kitchen`, `/admin`, `/reports`, `/inventory`).

When accessed on the public web domain, the router resolves purely to public routes, completely isolating internal business state, financial totals, and kitchen queues from unauthenticated visitors.

---

## 2. Compilation

Compile the web application for production:
```powershell
flutter build web --release
```
**Output Directory:** `build\web\`
- `index.html` (Application entrypoint)
- `flutter.js` (Flutter web loader)
- `main.dart.js` (Compiled Dart application code)
- `assets/` (Fonts, images, icons, and configuration)
- `canvaskit/` (High-performance graphics rendering engine)

---

## 3. Vercel Hosting Configuration (`vercel.json`)

To prevent HTTP 404 errors when users refresh deep URLs (e.g., `/menu` or `/contact`), and to enforce enterprise security headers, `vercel.json` is configured at the workspace root:

```json
{
  "$schema": "https://openapi.vercel.sh/vercel.json",
  "cleanUrls": true,
  "outputDirectory": "build/web",
  "rewrites": [
    {
      "source": "/(.*)",
      "destination": "/index.html"
    }
  ],
  "headers": [
    {
      "source": "/(.*)",
      "headers": [
        { "key": "X-Content-Type-Options", "value": "nosniff" },
        { "key": "X-Frame-Options", "value": "DENY" },
        { "key": "X-XSS-Protection", "value": "1; mode=block" },
        { "key": "Referrer-Policy", "value": "strict-origin-when-cross-origin" },
        { "key": "Permissions-Policy", "value": "geolocation=(), camera=(), microphone=()" }
      ]
    },
    {
      "source": "/(assets|canvaskit)/(.*)",
      "headers": [
        { "key": "Cache-Control", "value": "public, max-age=31536000, immutable" }
      ]
    }
  ]
}
```

### Deploying to Vercel
```bash
# Using Vercel CLI
vercel --prod
```
Or link the GitHub repository directly to Vercel:
- **Framework Preset:** Other
- **Build Command:** `flutter build web --release`
- **Output Directory:** `build/web`

---

## 4. Alternative Hosting Providers

### Nginx (Self-Hosted Ubuntu/Debian)
If hosting on a Linux server via Nginx:

```nginx
server {
    listen 443 ssl http2;
    server_name cafe.yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/cafe.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/cafe.yourdomain.com/privkey.pem;

    root /var/www/cafeflow/web;
    index index.html;

    # Security Headers
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Single Page Application fallback
    location / {
        try_files $uri $uri/ /index.html;
    }

    # Static Assets Long-term Caching
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|wasm)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
```

### Firebase Hosting
In `firebase.json`:
```json
{
  "hosting": {
    "public": "build/web",
    "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
    "rewrites": [
      {
        "source": "**",
        "destination": "/index.html"
      }
    ]
  }
}
```

---

## 5. Web Verification Checklist

- [x] Application compiles cleanly via `flutter build web --release`.
- [x] `vercel.json` provides wildcard URL rewrite to `/index.html`.
- [x] Strict security headers prevent clickjacking and MIME spoofing.
- [x] Static assets (Canvaskit / fonts) are cached with 1-year immutability.
- [x] Direct navigation to `/menu` loads without 404 error.

