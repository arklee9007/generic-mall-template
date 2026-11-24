-- 统一调整轮第十四批（0.3.13）：B-33 会员制推倒重做。
-- 取消充值/余额/双等级/累计升级：单级会员，¥500 开通费买一年；权益＝每月免费领一件（月券赠品）＋可设统一折扣。
-- 发券改个人周期制：以开通日为锚、每月同日一张、每张有效期为个人一个月（至下个发放日）；取消统一发放日。
-- 退款随之只走原路（服务端处理，本迁移只备数据结构）。全部非破坏性：旧列（balance/level/recharge_*）留置不用、不删。

-- ============ 1. 会员期限与券周期字段 ============
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS "memberSince" timestamptz;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS "memberExpiresAt" timestamptz;
ALTER TABLE public.coupons ADD COLUMN IF NOT EXISTS "cycle" integer;
ALTER TABLE public.coupons ADD COLUMN IF NOT EXISTS "periodStart" timestamptz;
ALTER TABLE public.coupons ADD COLUMN IF NOT EXISTS "expiresAt" timestamptz;

-- ============ 2. 会员开通/续费记录表（开通费台账，替代 recharge_records 的新职责） ============
CREATE TABLE IF NOT EXISTS public.membership_records (
  _id text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "userId" text NOT NULL REFERENCES public.users(_id),
  amount bigint NOT NULL CHECK (amount > 0),
  kind text NOT NULL CHECK (kind IN ('activate','renew')),
  "periodStart" timestamptz NOT NULL,
  "periodEnd" timestamptz NOT NULL,
  "requestKey" text NOT NULL,
  simulated boolean NOT NULL DEFAULT true CHECK (simulated),
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  UNIQUE ("userId","requestKey")
);
ALTER TABLE public.membership_records ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.membership_records FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.membership_records TO service_role;

-- ============ 3. mall_atomic_commit 白名单加 membership_records（只插不改） ============
CREATE OR REPLACE FUNCTION public.mall_atomic_commit(plan jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public, pg_temp AS $fn$
DECLARE
  operation jsonb; old_row jsonb; field record; col_names text; assignments text;
  table_name text; row_id text; changed integer; new_balance bigint; ledger_delta bigint;
  allowed constant text[] := ARRAY['users','member_accounts','carts','addresses','orders','order_items','skus','gift_stock','coupons','balance_logs','recharge_records','gift_allocations','refunds','auto_refunds','membership_records'];
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
    IF NOT table_name=ANY(allowed) OR table_name IN ('balance_logs','recharge_records','gift_allocations','member_accounts','membership_records') THEN RAISE EXCEPTION 'INVALID_UPDATE_TABLE'; END IF;
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

-- ============ 4. mall_admin_membership 改口径：只剩 开通价＋统一折扣＋赠品空尺码模式 ============
CREATE OR REPLACE FUNCTION public.mall_admin_membership(p_admin text,p_op text,p_id text,p_data jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,pg_temp AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM admins WHERE _id=p_admin) THEN RAISE EXCEPTION 'ADMIN_REQUIRED'; END IF;
 IF p_op='save' THEN
  UPDATE settings SET "memberRules"=jsonb_build_object('price',(p_data->>'price')::bigint,'discount',(p_data->>'discount')::numeric),"giftEmptySizeMode"=p_data->>'giftEmptySizeMode' WHERE _id='global';
 ELSE RAISE EXCEPTION 'UNKNOWN_MEMBERSHIP_OPERATION'; END IF;
 INSERT INTO admin_actions("adminId",action,target,detail) VALUES(p_admin,'membership.'||p_op,p_id,p_data);
 RETURN jsonb_build_object('id',p_id,'operation',p_op);
END $$;
REVOKE ALL ON FUNCTION public.mall_admin_membership(text,text,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mall_admin_membership(text,text,text,jsonb) TO service_role;

-- ============ 5. 会员规则换新：开通价 ¥500＋统一九折（旧键整体替换） ============
UPDATE public.settings SET "memberRules"='{"price":50000,"discount":0.9}'::jsonb WHERE _id='global';

-- ============ 6. 存量平滑过渡（幂等：只补未迁的行） ============
-- 老会员（level 1/2）一律归一为单级会员：以注册日为锚、迁移之日起给满一年。
UPDATE public.users SET level=1,"memberSince"="createdAt","memberExpiresAt"=now()+interval '1 year'
WHERE level>=1 AND "memberExpiresAt" IS NULL;
-- 旧日历月券补周期字段（月初起、次月初止）；状态不动，新模型的个人周期券由服务端在首次读取时按（userId, 月）复用/重置。
UPDATE public.coupons SET "periodStart"=((month||'-01')::timestamp AT TIME ZONE 'Asia/Shanghai'),
  "expiresAt"=(((month||'-01')::timestamp AT TIME ZONE 'Asia/Shanghai')+interval '1 month'),"cycle"=1
WHERE "periodStart" IS NULL;
