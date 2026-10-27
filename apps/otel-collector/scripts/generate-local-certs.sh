#!/bin/sh
set -eu

cert_dir="${1:-certs}"
umask 077
mkdir -p "$cert_dir/ca" "$cert_dir/server" "$cert_dir/client"
mkdir -p logs
chmod 2770 logs

for file in ca/ca.key ca/ca.crt server/server.key server/server.crt client/client.key client/client.crt; do
    if [ -e "$cert_dir/$file" ]; then
        printf 'Refusing to overwrite existing certificate file: %s\n' "$cert_dir/$file" >&2
        exit 1
    fi
done

openssl req -x509 -newkey rsa:3072 -nodes -sha256 -days 365 \
    -keyout "$cert_dir/ca/ca.key" \
    -out "$cert_dir/ca/ca.crt" \
    -subj "/CN=law-otel-adapter-local-ca" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign"

openssl req -newkey rsa:2048 -nodes \
    -keyout "$cert_dir/server/server.key" \
    -out "$cert_dir/server/server.csr" \
    -subj "/CN=otel-collector"
printf '%s\n' \
    'subjectAltName=DNS:otel-collector,DNS:localhost' \
    'extendedKeyUsage=serverAuth' \
    'keyUsage=digitalSignature,keyEncipherment' > "$cert_dir/server/server.ext"
openssl x509 -req -sha256 -days 365 \
    -in "$cert_dir/server/server.csr" \
    -CA "$cert_dir/ca/ca.crt" \
    -CAkey "$cert_dir/ca/ca.key" \
    -CAcreateserial \
    -extfile "$cert_dir/server/server.ext" \
    -out "$cert_dir/server/server.crt"

openssl req -newkey rsa:2048 -nodes \
    -keyout "$cert_dir/client/client.key" \
    -out "$cert_dir/client/client.csr" \
    -subj "/CN=law-otel-adapter"
printf '%s\n' \
    'extendedKeyUsage=clientAuth' \
    'keyUsage=digitalSignature,keyEncipherment' > "$cert_dir/client/client.ext"
openssl x509 -req -sha256 -days 365 \
    -in "$cert_dir/client/client.csr" \
    -CA "$cert_dir/ca/ca.crt" \
    -CAkey "$cert_dir/ca/ca.key" \
    -CAcreateserial \
    -extfile "$cert_dir/client/client.ext" \
    -out "$cert_dir/client/client.crt"

rm "$cert_dir/server/server.csr" "$cert_dir/server/server.ext" \
    "$cert_dir/client/client.csr" "$cert_dir/client/client.ext" \
    "$cert_dir/ca/ca.key" "$cert_dir/ca/ca.srl"
chmod 0640 \
    "$cert_dir/ca/ca.crt" \
    "$cert_dir/server/server.crt" "$cert_dir/server/server.key" \
    "$cert_dir/client/client.crt" "$cert_dir/client/client.key"
printf 'Generated local development certificates in %s\n' "$cert_dir"
