#!/bin/bash
set -euo pipefail
folder="$1"
mkdir -p "$folder"
openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 2 -subj '/CN=WeBox Test Root' \
    -keyout "$folder/root.key" -out "$folder/root.pem" \
    -addext 'basicConstraints=critical,CA:TRUE' -addext 'keyUsage=critical,keyCertSign,cRLSign'
openssl req -new -newkey rsa:2048 -nodes -subj '/CN=webox-transport.test' \
    -keyout "$folder/server.key" -out "$folder/server.csr"
cat > "$folder/server.ext" <<'EXT'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:webox-transport.test
EXT
openssl x509 -req -sha256 -days 2 -in "$folder/server.csr" \
    -CA "$folder/root.pem" -CAkey "$folder/root.key" -CAcreateserial \
    -extfile "$folder/server.ext" -out "$folder/server.pem"
