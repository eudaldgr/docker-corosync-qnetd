#!/bin/sh
set -xe

CONFIG_DIR="/etc/corosync/qnetd"
DB_DIR="$CONFIG_DIR/nssdb"
# Validity of certificate (months)
CRT_VALIDITY=1200
CA_NICKNAME="QNet CA"
SERVER_NICKNAME="QNetd Cert"
CA_SUBJECT="CN=QNet CA"
SERVER_SUBJECT="CN=Qnetd Server"
PWD_FILE="$DB_DIR/pwdfile.txt"
NOISE_FILE="$DB_DIR/noise.txt"
#SERIAL_NO_FILE="$DB_DIR/serial.txt"
CA_EXPORT_FILE="$DB_DIR/qnetd-cacert.crt"

mkdir -p "$DB_DIR"

init() {
  [ ! -f "$PWD_FILE" ] && [ ! -s "$PWD_FILE" ] && printf "%s\n" "" > "$PWD_FILE"

  certutil -N -d "sql:$DB_DIR" -f "$PWD_FILE"

  [ ! -f "$DB_DIR/noise.txt" ] && \
    (ps -elf; date; w) | sha1sum | (read -r sha_sum rest; echo "$sha_sum") \
    > "$NOISE_FILE"

  printf "y\n0\ny\n" | certutil -S -n "$CA_NICKNAME" -s "$CA_SUBJECT" -x \
    -t "CT,," -m 0 -v "$CRT_VALIDITY" -d "$DB_DIR" \
    -z "$NOISE_FILE" -f "$PWD_FILE" -2

  [ -f "$CA_EXPORT_FILE" ] && {
    certutil -L -d "sql:$DB_DIR" -n "$CA_NICKNAME" > "$CA_EXPORT_FILE"
    certutil -L -d "sql:$DB_DIR" -n "$CA_NICKNAME" -a >> "$CA_EXPORT_FILE"
  }

  certutil -S -n "$SERVER_NICKNAME" -s "$SERVER_SUBJECT" -c "$CA_NICKNAME" \
    -t "u,u,u" -m 1 -v "$CRT_VALIDITY" -d "sql:$DB_DIR" -z "$NOISE_FILE" \
    -f "$PWD_FILE"
}

# https://fedoraproject.org/wiki/Changes/NSSDefaultFileFormatSql
[ ! -f "$DB_DIR/cert9.db" ] && {
  if [ -f "$DB_DIR/cert8.db" ]; then
    # password file should have an empty line to be accepted
    [ -f "$PWD_FILE" ] && [ ! -s "$PWD_FILE" ] && printf "%s\n" "" > "$PWD_FILE"

    # upgrade to SQLite database
    certutil -N -d "sql:$DB_DIR" -f "$PWD_FILE" -@ "$PWD_FILE"
    chmod g+r "$DB_DIR/cert9.db" "$DB_DIR/key4.db"
  else
    init
  fi
  chgrp 1000 "$DB_DIR" "$DB_DIR/cert9.db" "$DB_DIR/key4.db"
}