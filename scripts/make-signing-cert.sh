#!/bin/sh
# Creates a self-signed code signing certificate for release builds. Run it once and keep the output.
#
# Gatekeeper doesn't trust this certificate, so it isn't a replacement for a Developer ID. It gives the app
# a stable identity, which is what macOS keys the Bluetooth permission on: with ad-hoc signing every update
# asks for Bluetooth access again.
#
# Writes ./signing/ (gitignored): open1000x-signing.p12 and its password, then prints the next steps.
set -eu
cd "$(dirname "$0")/.."

NAME="${NAME:-Open1000X Self-Signed}"
OUT="signing"
# macOS' own LibreSSL writes a PKCS#12 that `security import` reads without extra flags.
OPENSSL=/usr/bin/openssl

if [ -e "$OUT/open1000x-signing.p12" ]; then
    echo "$OUT/open1000x-signing.p12 already exists. Delete it first if you really want a new identity" >&2
    echo "(existing installs will be asked for Bluetooth access again)." >&2
    exit 1
fi
mkdir -p "$OUT"
umask 077

cat > "$OUT/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF

"$OPENSSL" req -new -x509 -newkey rsa:2048 -nodes -days 3650 -sha256 \
    -config "$OUT/cert.cnf" -keyout "$OUT/key.pem" -out "$OUT/cert.pem" 2>/dev/null
"$OPENSSL" rand -base64 24 | tr -d '\n' > "$OUT/password.txt"
"$OPENSSL" pkcs12 -export -name "$NAME" -inkey "$OUT/key.pem" -in "$OUT/cert.pem" \
    -out "$OUT/open1000x-signing.p12" -passout "file:$OUT/password.txt"
rm "$OUT/key.pem" "$OUT/cert.cnf"

cat <<DONE
Created $OUT/open1000x-signing.p12 ("$NAME", valid 10 years).
Back up $OUT/ somewhere safe. Losing it means a new identity and one more Bluetooth prompt for everyone.

Add it to the repo's Actions secrets:
  base64 -i $OUT/open1000x-signing.p12 | gh secret set SIGNING_CERT_P12
  gh secret set SIGNING_CERT_PASSWORD < $OUT/password.txt

Optional, to sign local builds the same way:
  security import $OUT/open1000x-signing.p12 -P "\$(cat $OUT/password.txt)" -T /usr/bin/codesign
  SIGN_IDENTITY="$NAME" ./scripts/build-app.sh
DONE
