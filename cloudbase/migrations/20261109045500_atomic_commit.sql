-- Only service_role can submit server-computed plans. No pricing lives in SQL.
CREATE FUNCTION public.mall_atomic_commit(plan jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public, pg_temp AS $fn$
DECLARE
  operation jsonb; old_row jsonb; field record; col_names text; assignments text;
  table_name text; row_id text; changed integer; new_balance bigint; ledger_delta bigint;
  allowed constant text[] := ARRAY['users','member_accounts','carts','addresses','orders','order_items','skus','gift_stock','coupons','balance_logs','recharge_records','gift_allocations'];
BEGIN
  -- Locks are sorted globally to avoid inconsistent acquisition order.
  FOR operation IN SELECT value FROM jsonb_array_elements(coalesce(plan->'locks','[]')) ORDER BY value->>'table',value->>'id' LOOP
    table_name := operation->>'table'; row_id := operation->>'id';
    IF NOT table_name=ANY(allowed) OR table_name='member_accounts' THEN RAISE EXCEPTION 'INVALID_LOCK_TABLE'; END IF;
    EXECUTE format('SELECT to_jsonb(t) FROM public.%I t WHERE _id=$1 FOR UPDATE',table_name) INTO old_row USING row_id;
    IF old_row IS NULL THEN RAISE EXCEPTION 'STALE_ROW' USING ERRCODE='40001'; END IF;
    FOR field IN SELECT key,value FROM jsonb_each(coalesce(operation->'expected','{}')) LOOP
      IF old_row->>field.key IS DISTINCT FROM operation->'expected'->>field.key THEN
        RAISE EXCEPTION 'STALE_ROW' USING ERRCODE='40001';
      END IF;
    END LOOP;
    IF table_name='users' THEN
      SELECT (value->'data'->>'balance')::bigint INTO new_balance FROM jsonb_array_elements(coalesce(plan->'updates','[]'))
        WHERE value->>'table'='users' AND value->>'id'=row_id AND value->'data' ? 'balance';
      IF new_balance IS NOT NULL AND new_balance<>(old_row->>'balance')::bigint THEN
        SELECT coalesce(sum((value->'data'->>'amount')::bigint),0) INTO ledger_delta
          FROM jsonb_array_elements(coalesce(plan->'inserts','[]')) WHERE value->>'table'='balance_logs' AND value->'data'->>'userId'=row_id;
        IF new_balance<>(old_row->>'balance')::bigint+ledger_delta THEN RAISE EXCEPTION 'BALANCE_LEDGER_MISMATCH'; END IF;
      END IF;
    END IF;
  END LOOP;
  FOR operation IN SELECT value FROM jsonb_array_elements(coalesce(plan->'inserts','[]')) LOOP
    table_name:=operation->>'table';
    IF NOT table_name=ANY(allowed) THEN RAISE EXCEPTION 'INVALID_WRITE_TABLE'; END IF;
    SELECT string_agg(format('%I',key),',' ORDER BY key) INTO col_names FROM jsonb_object_keys(operation->'data') AS keys(key);
    EXECUTE format('INSERT INTO public.%I (%s) SELECT %s FROM jsonb_populate_record(NULL::public.%I,$1)',table_name,col_names,col_names,table_name) USING operation->'data';
  END LOOP;
  FOR operation IN SELECT value FROM jsonb_array_elements(coalesce(plan->'updates','[]')) LOOP
    table_name:=operation->>'table';row_id:=operation->>'id';
    IF NOT table_name=ANY(allowed) OR table_name IN ('balance_logs','recharge_records','gift_allocations','order_items','member_accounts') THEN RAISE EXCEPTION 'INVALID_UPDATE_TABLE'; END IF;
    IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(plan->'locks','[]')) l WHERE l->>'table'=table_name AND l->>'id'=row_id) THEN RAISE EXCEPTION 'UPDATE_WITHOUT_LOCK'; END IF;
    SELECT string_agg(format('%I=s.%I',key,key),',' ORDER BY key) INTO assignments FROM jsonb_object_keys(operation->'data') AS keys(key) WHERE key<>'_id';
    EXECUTE format('UPDATE public.%I t SET %s FROM jsonb_populate_record(NULL::public.%I,$1) s WHERE t._id=$2',table_name,assignments,table_name) USING operation->'data',row_id;
    GET DIAGNOSTICS changed=ROW_COUNT;
    IF changed<>1 THEN RAISE EXCEPTION 'STALE_ROW' USING ERRCODE='40001'; END IF;
  END LOOP;
  FOR operation IN SELECT value FROM jsonb_array_elements(coalesce(plan->'deletes','[]')) LOOP
    table_name:=operation->>'table';
    IF table_name NOT IN ('carts','addresses') THEN RAISE EXCEPTION 'INVALID_DELETE_TABLE'; END IF;
    IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(plan->'locks','[]')) l WHERE l->>'table'=table_name AND l->>'id'=operation->>'id') THEN RAISE EXCEPTION 'DELETE_WITHOUT_LOCK'; END IF;
    EXECUTE format('DELETE FROM public.%I WHERE _id=$1',table_name) USING operation->>'id';
  END LOOP;
  RETURN jsonb_build_object('ok',true);
END $fn$;
REVOKE ALL ON FUNCTION public.mall_atomic_commit(jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mall_atomic_commit(jsonb) TO service_role;
CREATE FUNCTION public.mall_immutable_ledger() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN RAISE EXCEPTION 'LEDGER_IS_APPEND_ONLY'; END $fn$;
CREATE TRIGGER balance_logs_immutable BEFORE UPDATE OR DELETE ON public.balance_logs FOR EACH ROW EXECUTE FUNCTION public.mall_immutable_ledger();
