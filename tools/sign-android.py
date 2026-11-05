#!/usr/bin/env python3
"""Local APK signing. Creating a new key requires explicit owner approval."""
import argparse
import hashlib
import os
from pathlib import Path
import secrets
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--create-approved-signing-key', action='store_true')
parser.add_argument('--apk', type=Path)
parser.add_argument('--apksigner', type=Path)
parser.add_argument('--output', type=Path)
args = parser.parse_args()
root = Path('/Users/pava/.codex/app-signing/kodo-ukoly')
java = Path('/Users/pava/.codex/tools/jdk17/bin/java')
keytool = java.with_name('keytool')
key, password = root / 'release.p12', root / 'password'

if args.create_approved_signing_key:
    if key.exists() or password.exists():
        raise SystemExit('STOP: existing identity is never replaced automatically.')
    root.mkdir(parents=True, exist_ok=True)
    root.chmod(0o700)
    password.write_text(secrets.token_urlsafe(36))
    password.chmod(0o600)
    subprocess.run([
        str(keytool), '-genkeypair', '-keystore', str(key), '-storetype', 'PKCS12',
        '-storepass:file', str(password), '-keypass:file', str(password),
        '-alias', 'kodo-ukoly', '-keyalg', 'RSA', '-keysize', '3072',
        '-sigalg', 'SHA256withRSA', '-validity', '10000', '-dname', 'CN=Kodo Ukoly, O=Kodo',
    ], check=True)
    key.chmod(0o600)
    print('Local signing identity created; private values were not displayed or uploaded.')

if args.apk:
    if not key.is_file() or not password.is_file():
        raise SystemExit('Signing identity is missing. Obtain explicit approval before creating it.')
    if not args.apksigner or not args.output:
        raise SystemExit('--apksigner and --output are required.')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([
        str(java), '-jar', str(args.apksigner), 'sign', '--ks', str(key),
        '--ks-pass', 'file:' + str(password), '--key-pass', 'file:' + str(password),
        '--ks-key-alias', 'kodo-ukoly', '--out', str(args.output), str(args.apk),
    ], check=True)
    subprocess.run([
        str(java), '-jar', str(args.apksigner), 'verify', '--verbose', '--print-certs', str(args.output),
    ], check=True)
    digest = hashlib.sha256(args.output.read_bytes()).hexdigest()
    args.output.with_suffix('.apk.sha256').write_text(digest + '  ' + args.output.name + '\n')
    print('Verified Android APK:', args.output)
