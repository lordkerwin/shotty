#!/bin/bash
# One-time: create a stable self-signed code-signing identity so Shotty keeps its Screen Recording
# permission across rebuilds. Ad-hoc signing changes the signature every build, so macOS re-prompts.
set -euo pipefail
NAME="${SHOTTY_SIGN_IDENTITY:-Shotty Self-Signed}"

if security find-identity -p codesigning | grep -q "\"$NAME\""; then
  echo "✓ '$NAME' already exists — just rebuild: ./build-app.sh"
  exit 0
fi

echo "Creating self-signed code-signing certificate '$NAME'…"
dir=$(mktemp -d)
cat > "$dir/cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $NAME
[v3]
keyUsage = digitalSignature
extendedKeyUsage = codeSigning
basicConstraints = critical, CA:false
EOF

if openssl req -x509 -newkey rsa:2048 -keyout "$dir/key.pem" -out "$dir/cert.pem" -days 3650 -nodes -config "$dir/cnf" 2>/dev/null \
   && openssl pkcs12 -export -out "$dir/id.p12" -inkey "$dir/key.pem" -in "$dir/cert.pem" -passout pass: 2>/dev/null \
   && security import "$dir/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "" -T /usr/bin/codesign 2>/dev/null \
   && security find-identity -v -p codesigning | grep -q "$NAME"; then
  rm -rf "$dir"
  echo "✓ Created '$NAME'."
  echo "  Next:  tccutil reset ScreenCapture com.shotty.app   # clear the stale ad-hoc grants"
  echo "  Then:  ./build-app.sh   (codesign may ask to use the key — click Always Allow)"
  echo "  Grant Screen Recording once; it now sticks across rebuilds."
else
  rm -rf "$dir"
  cat <<'TXT'
CLI creation didn't work on this system. Do it once in Keychain Access (30s, no admin):
  1. Open Keychain Access
  2. Menu ▸ Certificate Assistant ▸ Create a Certificate…
  3. Name: Shotty Self-Signed   ·   Identity Type: Self Signed Root   ·   Certificate Type: Code Signing
  4. Create, then run: tccutil reset ScreenCapture com.shotty.app  &&  ./build-app.sh
TXT
  exit 1
fi
