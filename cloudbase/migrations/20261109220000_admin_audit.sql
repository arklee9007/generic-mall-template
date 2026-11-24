CREATE FUNCTION public.mall_deny_audit_mutation() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'AUDIT_IMMUTABLE'; END $$;
DROP TRIGGER IF EXISTS admin_actions_immutable ON admin_actions;
CREATE TRIGGER admin_actions_immutable BEFORE UPDATE OR DELETE ON admin_actions FOR EACH ROW EXECUTE FUNCTION mall_deny_audit_mutation();
DROP TRIGGER IF EXISTS admin_login_logs_immutable ON admin_login_logs;
CREATE TRIGGER admin_login_logs_immutable BEFORE UPDATE OR DELETE ON admin_login_logs FOR EACH ROW EXECUTE FUNCTION mall_deny_audit_mutation();
DROP TRIGGER IF EXISTS admin_refunds_immutable ON admin_refunds;
CREATE TRIGGER admin_refunds_immutable BEFORE UPDATE OR DELETE ON admin_refunds FOR EACH ROW EXECUTE FUNCTION mall_deny_audit_mutation();
REVOKE ALL ON FUNCTION public.mall_deny_audit_mutation() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mall_deny_audit_mutation() TO service_role;
-- Bounded live negative probes. A missing/ineffective guard aborts this migration;
-- exceptions roll back each attempted mutation, preserving every existing row.
-- Fresh installs have empty audit tables: an empty table skips its probe instead of
-- failing the migration (immutability with real rows is covered by verify-db.sql).
DO $$ DECLARE t text; target text; BEGIN
 FOREACH t IN ARRAY ARRAY['admin_actions','admin_login_logs','admin_refunds'] LOOP
  EXECUTE format('SELECT _id FROM public.%I LIMIT 1',t) INTO target;
  IF target IS NULL THEN CONTINUE; END IF;
  BEGIN
   EXECUTE format('UPDATE public.%I SET _id=_id WHERE _id=$1',t) USING target;
   RAISE EXCEPTION 'AUDIT_UPDATE_PROBE_FAILED';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'AUDIT_IMMUTABLE' THEN RAISE; END IF; END;
  BEGIN
   EXECUTE format('DELETE FROM public.%I WHERE _id=$1',t) USING target;
   RAISE EXCEPTION 'AUDIT_DELETE_PROBE_FAILED';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'AUDIT_IMMUTABLE' THEN RAISE; END IF; END;
 END LOOP;
END $$;
