ALTER TABLE public.admins ADD COLUMN failures integer NOT NULL DEFAULT 0 CHECK (failures >= 0),
  ADD COLUMN "lockedUntil" timestamptz, ADD COLUMN version bigint NOT NULL DEFAULT 0;
CREATE TABLE public.admin_sessions (
  _id text PRIMARY KEY CHECK (length(_id)=64), "adminId" text NOT NULL REFERENCES public.admins(_id),
  "createdAt" timestamptz NOT NULL DEFAULT now(), "expiresAt" timestamptz NOT NULL DEFAULT now()+interval '24 hours',
  "revokedAt" timestamptz
);
CREATE TABLE public.admin_login_logs (
  _id text PRIMARY KEY DEFAULT gen_random_uuid()::text, username text NOT NULL,
  success boolean NOT NULL, reason text NOT NULL, "createdAt" timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.admin_actions (
  _id text PRIMARY KEY DEFAULT gen_random_uuid()::text, "adminId" text NOT NULL REFERENCES public.admins(_id),
  action text NOT NULL, target text NOT NULL DEFAULT '', detail jsonb NOT NULL DEFAULT '{}',
  "createdAt" timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX admin_sessions_owner ON public.admin_sessions("adminId");
CREATE INDEX admin_login_recent ON public.admin_login_logs("createdAt");
DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['admin_sessions','admin_login_logs','admin_actions'] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t);
    EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC,anon,authenticated',t);
    EXECUTE format('GRANT SELECT,INSERT,UPDATE ON public.%I TO service_role',t);
  END LOOP;
END $$;
CREATE FUNCTION public.mall_admin_bootstrap(p_username text,p_hash text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,pg_temp AS $$
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('generic_admin_bootstrap'));
  IF NOT EXISTS(SELECT 1 FROM admins) THEN
    INSERT INTO admins(username,"passwordHash",role) VALUES(p_username,p_hash,'owner');
  END IF;
END $$;
CREATE FUNCTION public.mall_admin_login(p_username text,p_expected text,p_accepted boolean,p_session text) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,pg_temp AS $$
DECLARE a admins%ROWTYPE; why text; ok boolean := false;
BEGIN
  SELECT * INTO a FROM admins WHERE username=p_username FOR UPDATE;
  IF NOT FOUND THEN why:='INVALID_CREDENTIALS';
  ELSIF a."lockedUntil">now() THEN why:='ACCOUNT_LOCKED';
  ELSIF NOT p_accepted OR a."passwordHash"<>p_expected THEN
    UPDATE admins SET failures=failures+1,"lockedUntil"=CASE WHEN failures+1>=5 THEN now()+interval '30 minutes' ELSE NULL END,version=version+1 WHERE _id=a._id;
    why:='INVALID_CREDENTIALS';
  ELSE
    UPDATE admins SET failures=0,"lockedUntil"=NULL,version=version+1 WHERE _id=a._id;
    INSERT INTO admin_sessions(_id,"adminId") VALUES(p_session,a._id);
    why:='LOGIN_OK';ok:=true;
  END IF;
  INSERT INTO admin_login_logs(username,success,reason) VALUES(left(p_username,80),ok,why);
  RETURN jsonb_build_object('accepted',ok,'code',why,'username',CASE WHEN ok THEN a.username ELSE NULL END);
END $$;
CREATE FUNCTION public.mall_admin_dashboard() RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER
SET search_path=public,pg_temp AS $$
  SELECT jsonb_build_object(
    'todayOrders',(SELECT count(*) FROM orders WHERE "createdAt">=date_trunc('day',now() AT TIME ZONE 'Asia/Shanghai') AT TIME ZONE 'Asia/Shanghai'),
    'todaySales',coalesce((SELECT sum("payAmount") FROM orders WHERE "paidAt">=date_trunc('day',now() AT TIME ZONE 'Asia/Shanghai') AT TIME ZONE 'Asia/Shanghai'),0),
    'pendingShip',(SELECT count(*) FROM orders WHERE status='pending_ship'),
    'checkedAt',now());
$$;
CREATE FUNCTION public.mall_admin_change_password(p_admin text,p_expected text,p_hash text) RETURNS boolean
LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,pg_temp AS $$
BEGIN
  PERFORM 1 FROM admins WHERE _id=p_admin AND "passwordHash"=p_expected FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  UPDATE admins SET "passwordHash"=p_hash,version=version+1 WHERE _id=p_admin;
  UPDATE admin_sessions SET "revokedAt"=now() WHERE "adminId"=p_admin AND "revokedAt" IS NULL;
  INSERT INTO admin_actions("adminId",action) VALUES(p_admin,'changePassword');
  RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.mall_admin_bootstrap(text,text),public.mall_admin_login(text,text,boolean,text),public.mall_admin_dashboard(),public.mall_admin_change_password(text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mall_admin_bootstrap(text,text),public.mall_admin_login(text,text,boolean,text),public.mall_admin_dashboard(),public.mall_admin_change_password(text,text,text) TO service_role;
