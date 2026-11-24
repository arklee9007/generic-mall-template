-- 统一调整轮第七批（0.3.6）：B-25 定制模型返修（身份解耦/版型种子/定制链接颜色尺码/底板挂入移出）、B-26 退款提交修复。
-- 全部非破坏性：函数 CREATE OR REPLACE 仅改白名单、link.save 一行与两个新 op；种子与回填按固定 _id、幂等。

-- ============ B-26：mall_atomic_commit 白名单补 refunds/auto_refunds，放行 order_items 更新 ============
CREATE OR REPLACE FUNCTION public.mall_atomic_commit(plan jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public, pg_temp AS $fn$
DECLARE
  operation jsonb; old_row jsonb; field record; col_names text; assignments text;
  table_name text; row_id text; changed integer; new_balance bigint; ledger_delta bigint;
  allowed constant text[] := ARRAY['users','member_accounts','carts','addresses','orders','order_items','skus','gift_stock','coupons','balance_logs','recharge_records','gift_allocations','refunds','auto_refunds'];
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
    IF NOT table_name=ANY(allowed) OR table_name IN ('balance_logs','recharge_records','gift_allocations','member_accounts') THEN RAISE EXCEPTION 'INVALID_UPDATE_TABLE'; END IF;
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

-- ============ B-25：定制链接颜色/尺码（全店定制统一一套） ============
ALTER TABLE public.custom_link ADD COLUMN IF NOT EXISTS colors text[] NOT NULL DEFAULT ARRAY[]::text[];
ALTER TABLE public.custom_link ADD COLUMN IF NOT EXISTS sizes text[] NOT NULL DEFAULT ARRAY[]::text[];

-- link.save 同步保存 colors/sizes；新增 base.attach/base.detach（定制链接总台的底板挂入/移出，不动商品上下架与审核状态）
CREATE OR REPLACE FUNCTION public.mall_admin_pattern(p_admin text,p_op text,p_id text,p_data jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,pg_temp AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM admins WHERE _id=p_admin) THEN RAISE EXCEPTION 'ADMIN_REQUIRED'; END IF;
 IF p_op='pattern.save' THEN
  INSERT INTO patterns(_id,name,image,sort) VALUES(p_id,trim(p_data->>'name'),coalesce(p_data->>'image',''),coalesce((p_data->>'sort')::integer,0))
  ON CONFLICT(_id) DO UPDATE SET name=excluded.name,image=excluded.image,sort=excluded.sort;
 ELSIF p_op='pattern.delete' THEN
  IF EXISTS(SELECT 1 FROM products WHERE "patternId"=p_id) THEN RAISE EXCEPTION 'PATTERN_IN_USE'; END IF;
  DELETE FROM patterns WHERE _id=p_id;
 ELSIF p_op='link.save' THEN
  UPDATE custom_link SET enabled=(p_data->>'enabled')::boolean,title=coalesce(nullif(trim(p_data->>'title'),''),title),colors=CASE WHEN p_data ? 'colors' THEN ARRAY(SELECT jsonb_array_elements_text(p_data->'colors')) ELSE colors END,sizes=CASE WHEN p_data ? 'sizes' THEN ARRAY(SELECT jsonb_array_elements_text(p_data->'sizes')) ELSE sizes END,"updatedAt"=now() WHERE _id='global';
 ELSIF p_op='base.attach' THEN
  UPDATE products SET "customEnabled"=true,"patternId"=p_data->>'patternId' WHERE _id=p_id;
 ELSIF p_op='base.detach' THEN
  UPDATE products SET "customEnabled"=false WHERE _id=p_id;
 ELSE RAISE EXCEPTION 'UNKNOWN_PATTERN_OPERATION'; END IF;
 INSERT INTO admin_actions("adminId",action,target,detail) VALUES(p_admin,'custom.'||p_op,p_id,p_data);
 RETURN jsonb_build_object('id',p_id,'operation',p_op);
END $$;
REVOKE ALL ON FUNCTION public.mall_admin_pattern(text,text,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mall_admin_pattern(text,text,text,jsonb) TO service_role;

-- ============ B-25：存量版型种子 + 两件老底板回填 ============
INSERT INTO public.patterns(_id,name,image,sort) VALUES ('pat-hoodie','卫衣','/static/products/hoodie.svg',1),('pat-tee','短袖','/static/products/blank.svg',2) ON CONFLICT(_id) DO NOTHING;
UPDATE public.products SET "patternId"='pat-hoodie',"customEnabled"=true WHERE _id='hoodie-blank';
UPDATE public.products SET "patternId"='pat-tee',"customEnabled"=true WHERE _id='tee-blank';
