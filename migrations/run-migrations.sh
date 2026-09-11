#!/bin/sh
LOG=/tmp/migration.log
: > $LOG
echo "inicio $(date -Iseconds)" >> $LOG
set -x 2>>$LOG
export PGCONNECT_TIMEOUT=15
export PGHOST=supabase-db PGUSER=postgres PGDATABASE=postgres

pg_isready -t 60 -h supabase-db -U postgres -d postgres >> $LOG 2>&1
echo "pg_isready exit: $? " >> $LOG

for f in $(ls /migrations/*.sql | sort); do
  name=$(basename $f)
  echo "--- $name" >> $LOG
  psql -v ON_ERROR_STOP=1 -f "$f" >> $LOG 2>&1
  ec=$?
  echo "  exit=$ec" >> $LOG
  if [ $ec -ne 0 ]; then
    echo "ABORT en $name" >> $LOG
    exit $ec
  fi
done
echo "TODAS-APLICADAS" >> $LOG
