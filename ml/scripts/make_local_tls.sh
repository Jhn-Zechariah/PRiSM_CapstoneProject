#!/usr/bin/env sh
# Free, self-hosted TLS for the PRISM API on your own machine (no paid certificate, domain or tunnel).
#
#   sh scripts/make_local_tls.sh <server-ip-or-hostname> [out_dir]
#   e.g. sh scripts/make_local_tls.sh 192.168.1.50
#
# Creates a private certificate authority (CA) and a server certificate signed by it:
#   <out>/prism-ca.key      CA private key   - SECRET: keep offline/backed up, never commit or ship
#   <out>/prism-ca.pem      CA certificate   - public: embedded in the app build (see DEPLOYMENT.md)
#   <out>/server.key        server key       - SECRET: readable only by the API process
#   <out>/server.pem        server cert (825 days), SAN = the given IP/hostname
# Run the API with:
#   uvicorn prism_ml.api.asgi:app --host 0.0.0.0 --port 8443 --ssl-keyfile <out>/server.key --ssl-certfile <out>/server.pem
set -eu
export MSYS_NO_PATHCONV=1   # Git Bash on Windows: keep "/CN=..." literal
HOST="${1:?usage: make_local_tls.sh <server-ip-or-hostname> [out_dir]}"
OUT="${2:-$(dirname "$0")/../secrets/tls}"
mkdir -p "$OUT"
case "$HOST" in
  *[!0-9.]*) SAN="DNS:$HOST" ;;
  *) SAN="IP:$HOST" ;;
esac
if [ ! -f "$OUT/prism-ca.key" ]; then
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 3650 \
    -keyout "$OUT/prism-ca.key" -out "$OUT/prism-ca.pem" -subj "/CN=PRISM Local CA" \
    -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign"
fi
openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout "$OUT/server.key" \
  -out "$OUT/server.csr" -subj "/CN=$HOST"
printf "subjectAltName=%s\nbasicConstraints=CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=serverAuth\n" "$SAN" > "$OUT/server.ext"
openssl x509 -req -in "$OUT/server.csr" -CA "$OUT/prism-ca.pem" -CAkey "$OUT/prism-ca.key" -CAcreateserial \
  -days 825 -sha256 -extfile "$OUT/server.ext" -out "$OUT/server.pem"
rm -f "$OUT/server.csr" "$OUT/server.ext"
chmod 600 "$OUT/prism-ca.key" "$OUT/server.key" 2>/dev/null || true
echo "CA certificate (public, for the app): $OUT/prism-ca.pem"
echo "Server certificate for $SAN: $OUT/server.pem"
printf -- "--dart-define=PRISM_API_CA_PEM_B64=%s
" "$(base64 < "$OUT/prism-ca.pem" | tr -d '
')" > "$OUT/dart_define.txt"
echo "App build flag written to: $OUT/dart_define.txt"
