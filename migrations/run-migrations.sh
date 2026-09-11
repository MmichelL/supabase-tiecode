#!/bin/sh
export PGHOST=supabase-db PGUSER=postgres PGDATABASE=postgres PGCONNECT_TIMEOUT=15
LOGTABLE=_migration_log
psql -v ON_ERROR_STOP=0 -q -c "CREATE TABLE IF NOT EXISTS public.$LOGTABLE(id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, ts timestamptz DEFAULT now(), msg text); GRANT ALL ON public.$LOGTABLE TO postgres, anon, authenticated, service_role;" > /dev/null 2>&1
# exposición de la tabla a PostgREST
psql -v ON_ERROR_STOP=0 -q -c "ALTER TABLE public.$LOGTABLE REPLICA IDENTITY FULL; DO \$\$ BEGIN EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', '$LOGTABLE'); EXCEPTION WHEN OTHERS THEN NULL; END \$\$;" > /dev/null 2>&1
wlog() { psql -v ON_ERROR_STOP=0 -q -c "INSERT INTO public.$LOGTABLE(msg) VALUES ('$1');" > /dev/null 2>&1 || true; }
wlog "INICIO"
for f in $(ls /migrations/*.sql | sort); do
  name=$(basename $f)
  wlog "===== $name ====="
  out=$(psql -v ON_ERROR_STOP=1 -f "$f" 2>&1)
  ec=$?
  if [ $ec -ne 0 ]; then
    msg=$(echo "$out" | grep -E "ERROR|NOTICE|DETAIL" | head -10 | tr '\n' ' ' | tr -d "'" | tr -d '"' | cut -c1-400)
    wlog "FALLA-$name -> $msg"
    wlog "FIN-CON-ERROR"
    exit 0
  else
    wlog "OK-$name"
  fi
done
wlog "FIN-OK"
