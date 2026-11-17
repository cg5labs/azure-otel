#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
cert_dir="${1:-$project_dir/certs}"
server_dns_names="${OTEL_SERVER_DNS_NAMES:-otel-collector,localhost}"
server_ip_addresses="${OTEL_SERVER_IP_ADDRESSES:-}"
server_common_name="${server_dns_names%%,*}"
server_sans=""
umask 077

append_server_sans() {
    san_type="$1"
    san_values="$2"
    old_ifs="$IFS"

    [ -n "$san_values" ] || return 0
    IFS=,
    for san_value in $san_values; do
        case "$san_type:$san_value" in
            DNS:)
                printf 'DNS Subject Alternative Names cannot be empty.\n' >&2
                exit 1
                ;;
            DNS:.*|DNS:*..*|DNS:*.|DNS:*[!A-Za-z0-9.-]*)
                printf 'Invalid DNS Subject Alternative Name: %s\n' "$san_value" >&2
                exit 1
                ;;
            IP:)
                printf 'IP Subject Alternative Names cannot be empty.\n' >&2
                exit 1
                ;;
            IP:*[!0-9.:]*)
                printf 'Invalid IP Subject Alternative Name: %s\n' "$san_value" >&2
                exit 1
                ;;
        esac

        if [ -n "$server_sans" ]; then
            server_sans="$server_sans,"
        fi
        server_sans="$server_sans$san_type:$san_value"
    done
    IFS="$old_ifs"
}

append_server_sans DNS "$server_dns_names"
append_server_sans IP "$server_ip_addresses"

if [ -z "$server_sans" ]; then
    printf 'At least one valid server DNS or IP Subject Alternative Name is required.\n' >&2
    exit 1
fi

mkdir -p "$cert_dir/ca" "$cert_dir/server" "$cert_dir/client"
mkdir -p "$project_dir/logs"
chmod 2770 "$project_dir/logs"

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
    -subj "/CN=$server_common_name"
printf '%s\n' \
    "subjectAltName=$server_sans" \
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
