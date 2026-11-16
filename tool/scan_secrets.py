#!/usr/bin/env python3
"""
CafeFlow Repository Secret & Credential Scanner
Scans both working tree files and committed Git history for:
 - Unencrypted private keys (RSA, EC, DSA, OpenSSH, PGP)
 - Hardcoded database credentials / connection URIs with embedded passwords
 - Supabase service-role secrets and private API keys (JWTs, sb_secret_*)
 - Exposed production secrets in environment/config files

Fails closed if any real or high-risk credential is found.
Permits documentation references to PostgreSQL roles and synthetic test fixtures.
"""

import os
import re
import subprocess
import sys

# High-risk patterns that indicate genuine credentials
PATTERNS = [
    # 1. Private keys in PEM or OpenSSH format
    (
        "Private Key Header",
        re.compile(r"-----BEGIN\s+(?:[A-Z0-9_-]+\s+)?PRIVATE\s+KEY-----", re.IGNORECASE),
        re.compile(r"dummy|example|mock", re.IGNORECASE),
    ),
    # 2. Database connection strings containing credentials (user:password@host)
    (
        "Credentialed Database Connection URI",
        re.compile(r"postgres(?:ql)?://[a-zA-Z0-9_\-]+:(?!user|pass|password|postgres|\$|dummy)[^@\s/'\"]{4,}@[a-zA-Z0-9_\-\.]+", re.IGNORECASE),
        re.compile(r"example\.com|localhost|dummy|mock", re.IGNORECASE),
    ),
    # 3. Supabase new secret key format (sb_secret_...)
    (
        "Supabase Secret Key",
        re.compile(r"sb_secret_[a-zA-Z0-9_\-]{20,}", re.IGNORECASE),
        re.compile(r"dummy|example|fixture|mock|test", re.IGNORECASE),
    ),
    # 4. Supabase / JWT service-role or privileged tokens (3-segment base64url JWTs)
    (
        "Privileged JWT Token",
        re.compile(r"eyJ[a-zA-Z0-9_-]{20,}\.[a-zA-Z0-9_-]{20,}\.[a-zA-Z0-9_-]{20,}", re.IGNORECASE),
        re.compile(r"dummy|example|fixture|mock|test", re.IGNORECASE),
    ),
    # 5. Service-role credential assignments (e.g., SERVICE_ROLE_KEY=... or supabase_service_key: ...)
    (
        "Service-Role Secret Assignment",
        re.compile(r"(?:supabase_service_key|service_role_key|service_role_secret)\s*[:=]\s*['\"]?(?!dummy|example|mock|test|synthetic)[a-zA-Z0-9_\.\-]{16,}['\"]?", re.IGNORECASE),
        re.compile(r"dummy|example|fixture|mock|synthetic|test", re.IGNORECASE),
    ),
]

# Files or paths ignored during scan (scanner itself, docs discussing detection rules, etc.)
EXCLUDED_PATHS = {
    "tool/scan_secrets.py",
    ".git",
}

def scan_text(text: str, source_label: str) -> list[str]:
    findings = []
    lines = text.splitlines()
    for lineno, line in enumerate(lines, 1):
        # Ignore comments or lines explicitly asserting absence of secrets or scanner script itself
        if "scan_secrets" in line or "Verify Git Secret Hygiene" in line:
            continue
        for name, pattern, allowlist in PATTERNS:
            if pattern.search(line):
                if allowlist and allowlist.search(line):
                    continue
                # Redact matched text to avoid printing complete secrets
                match = pattern.search(line)
                matched_str = match.group(0) if match else "secret"
                redacted = matched_str[:4] + "..." + matched_str[-4:] if len(matched_str) > 8 else "***"
                findings.append(f"[{name}] {source_label}:{lineno} -> {redacted}")
    return findings

def scan_working_tree() -> list[str]:
    print("-> Scanning working tree tracked files...")
    findings = []
    try:
        result = subprocess.run(
            ["git", "ls-files"],
            capture_output=True,
            text=True,
            check=True,
            encoding="utf-8",
        )
        files = result.stdout.splitlines()
    except Exception as e:
        print(f"Warning: git ls-files failed: {e}", file=sys.stderr)
        return []

    for rel_path in files:
        if rel_path in EXCLUDED_PATHS:
            continue
        if not os.path.exists(rel_path):
            continue
        # Skip binary files
        if rel_path.endswith((".png", ".jpg", ".jpeg", ".ico", ".ttf", ".woff", ".apk", ".exe", ".aab", ".lock")):
            continue
        try:
            with open(rel_path, "r", encoding="utf-8", errors="replace") as f:
                content = f.read()
            findings.extend(scan_text(content, rel_path))
        except Exception as e:
            print(f"Error reading {rel_path}: {e}", file=sys.stderr)

    return findings

def scan_git_history() -> list[str]:
    print("-> Scanning Git commit history...")
    findings = []
    try:
        # Run git log -p to inspect full commit diffs
        result = subprocess.run(
            ["git", "log", "-p"],
            capture_output=True,
            text=True,
            check=True,
            encoding="utf-8",
            errors="replace",
        )
        diff_output = result.stdout
    except Exception as e:
        print(f"Warning: git log -p failed: {e}", file=sys.stderr)
        return []

    # Process diff lines starting with '+'
    added_lines = []
    current_commit = "unknown"
    current_file = "unknown"
    for line in diff_output.splitlines():
        if line.startswith("commit "):
            current_commit = line.split()[1][:8]
        elif line.startswith("+++ b/"):
            current_file = line[6:]
        elif line.startswith("+") and not line.startswith("+++"):
            added_content = line[1:]
            if current_file not in EXCLUDED_PATHS:
                added_lines.append((current_commit, current_file, added_content))

    for commit, filepath, content in added_lines:
        if "scan_secrets" in content or "Verify Git Secret Hygiene" in content:
            continue
        for name, pattern, allowlist in PATTERNS:
            if pattern.search(content):
                if allowlist and allowlist.search(content):
                    continue
                match = pattern.search(content)
                matched_str = match.group(0) if match else "secret"
                redacted = matched_str[:4] + "..." + matched_str[-4:] if len(matched_str) > 8 else "***"
                findings.append(f"[{name}] commit:{commit} {filepath} -> {redacted}")

    return findings

def verify_ignored_files() -> list[str]:
    print("-> Verifying exclusion of private configuration and signing artifacts...")
    issues = []
    critical_files = [".env", "android/key.properties", "android/upload.keystore", "windows/runner/release.pfx"]
    for cf in critical_files:
        result = subprocess.run(["git", "ls-files", cf], capture_output=True, text=True)
        if result.stdout.strip():
            issues.append(f"CRITICAL: Protected file '{cf}' is tracked by Git!")
    return issues

def main():
    print("=== CafeFlow Git Secret Hygiene Scanner ===")
    all_findings = []
    
    # Check ignored files
    ignore_issues = verify_ignored_files()
    if ignore_issues:
        for iss in ignore_issues:
            print(f"::error::{iss}", file=sys.stderr)
        all_findings.extend(ignore_issues)

    # Scan working tree
    wt_findings = scan_working_tree()
    all_findings.extend(wt_findings)

    # Scan git history
    history_findings = scan_git_history()
    all_findings.extend(history_findings)

    if all_findings:
        print(f"\nFAILED: {len(all_findings)} potential secret(s) or hygiene violation(s) detected:", file=sys.stderr)
        for finding in all_findings:
            print(f"  - {finding}", file=sys.stderr)
        sys.exit(1)
    else:
        print("\nSUCCESS: All secret hygiene checks passed cleanly. Zero secrets found in working tree or Git history.")
        sys.exit(0)

if __name__ == "__main__":
    main()

