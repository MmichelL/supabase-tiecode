#!/bin/sh
set -e
echo "Waiting for supabase-db..."
until pg_isready -h supabase-db -U postgres -q; do sleep 2; done
echo "DB ready. Applying migrations in order:"
for f in $(ls migrations/*.sql | sort); do
  name=$(basename $f)
  echo "--- applying $name"
  psql -h supabase-db -U postgres -d postgres -v ON_ERROR_STOP=1 -f "$f"
  echo "    OK $name"
done
echo "ALL MIGRATIONS APPLIED"
