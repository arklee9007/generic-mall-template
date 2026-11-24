-- 通用商城模板 1.0：店铺配置、N 档会员、规格通用化、退款分路、演示清理。
-- 全部幂等：列/表/约束 IF NOT EXISTS 或 duplicate_object 兜底，函数 CREATE OR REPLACE，
-- 种子行 ON CONFLICT DO NOTHING；本文件可重复执行。
-- 留置说明：custom_*/patterns/gift_*/coupons/membership_records/recharge_tiers 等旧表与
-- memberRules/couponIssueDay 等旧列不再被任何代码读写，仅留置不删，避免破坏既有约束；
-- 定制、赠券、素材导入、自动上下架、邮件提醒的函数在本文件末尾显式 DROP。

-- ============ 1. 店铺配置：settings.shopConfig（品牌、规格轴、规格说明、三段闸、会员开关） ============
ALTER TABLE public.settings ADD COLUMN IF NOT EXISTS "shopConfig" jsonb NOT NULL DEFAULT '{}'::jsonb;
UPDATE public.settings SET "shopConfig" =
'{"brandWord":"","brandColor":"#2563EB","logo":"","footerText":"","specAxes":["规格一","规格二","规格三"],"specChart":{"enabled":true,"title":"规格说明"},"reviewRequired":true,"member":{"enabled":true,"rechargeEnabled":true,"packages":[{"amount":10000,"bonus":0,"label":"充100元"},{"amount":20000,"bonus":2000,"label":"充200元送20元"},{"amount":50000,"bonus":8000,"label":"充500元送80元"}]}}'::jsonb
WHERE _id='global' AND "shopConfig"='{}'::jsonb;

-- ============ 2. 每商品轴名覆盖：products.specLabels（字符串数组，空串=用全局轴名） ============
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS "specLabels" jsonb NOT NULL DEFAULT '[]'::jsonb;
DO $$ BEGIN
  ALTER TABLE public.products ADD CONSTRAINT products_speclabels_shape CHECK (jsonb_typeof("specLabels")='array' AND jsonb_array_length("specLabels")<=3);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============ 3. 等级约束放宽：N 档（0..20 级），累计充值实付定级只升不降 ============
DO $$ DECLARE cname text; BEGIN
  FOR cname IN SELECT conname FROM pg_constraint WHERE conrelid='public.users'::regclass AND contype='c' AND conname<>'users_level_range' AND pg_get_constraintdef(oid) LIKE '%level%' LOOP
    EXECUTE format('ALTER TABLE public.users DROP CONSTRAINT %I', cname);
  END LOOP;
END $$;
DO $$ BEGIN
  ALTER TABLE public.users ADD CONSTRAINT users_level_range CHECK (level BETWEEN 0 AND 20);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ DECLARE cname text; BEGIN
  FOR cname IN SELECT conname FROM pg_constraint WHERE conrelid='public.recharge_records'::regclass AND contype='c' AND conname<>'recharge_records_level_range' AND pg_get_constraintdef(oid) LIKE '%level%' LOOP
    EXECUTE format('ALTER TABLE public.recharge_records DROP CONSTRAINT %I', cname);
  END LOOP;
END $$;
DO $$ BEGIN
  ALTER TABLE public.recharge_records ADD CONSTRAINT recharge_records_level_range CHECK (level BETWEEN 0 AND 20);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
-- 累计充值实付本金（不含赠送），定级唯一口径；充值计划内与余额同事务更新。
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS "totalRecharge" bigint NOT NULL DEFAULT 0 CHECK ("totalRecharge" BETWEEN 0 AND 9007199254740991);

-- ============ 4. 会员档位表 member_tiers（等级唯一源，折扣单位为基点，10000=不打折） ============
CREATE TABLE IF NOT EXISTS public.member_tiers (
  _id text PRIMARY KEY,
  level smallint NOT NULL UNIQUE CHECK (level BETWEEN 1 AND 20),
  name text NOT NULL CHECK (length(name) BETWEEN 1 AND 20),
  threshold bigint NOT NULL CHECK (threshold BETWEEN 0 AND 9007199254740991),
  "discountBps" integer NOT NULL CHECK ("discountBps" BETWEEN 1000 AND 10000),
  "cardBg" text NOT NULL DEFAULT '',
  "cardText" text NOT NULL DEFAULT '',
  sort integer NOT NULL DEFAULT 0,
  enabled boolean NOT NULL DEFAULT true,
  "createdAt" timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.member_tiers ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.member_tiers FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.member_tiers TO service_role;
INSERT INTO public.member_tiers (_id, level, name, threshold, "discountBps", sort, enabled) VALUES
('tier-1', 1, '会员', 10000, 9500, 0, true),
('tier-2', 2, '高级会员', 50000, 9000, 1, true)
ON CONFLICT DO NOTHING;

-- ============ 5. 演示商品轴名覆盖（演示已清空时以下更新命中 0 行，无害） ============
UPDATE public.products SET "specLabels"='["颜色","容量","款式"]'::jsonb WHERE _id='demo-cup';
UPDATE public.products SET "specLabels"='["颜色","规格"]'::jsonb WHERE _id='demo-notebook';
UPDATE public.products SET "specLabels"='["颜色"]'::jsonb WHERE _id='demo-box';
UPDATE public.products SET "specLabels"='[]'::jsonb WHERE _id='demo-pen';
UPDATE public.products SET "specLabels"='["口味","规格"]'::jsonb WHERE _id='demo-nuts';
UPDATE public.products SET "specLabels"='["口味","规格"]'::jsonb WHERE _id='demo-tea';

-- ============ 6. 商品管理 RPC：规格 0..3 维、副标题/关键词/轴名/规格表、三段闸开关、演示清理 ============
CREATE OR REPLACE FUNCTION public.mall_admin_catalog(p_admin text,p_op text,p_id text,p_data jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,pg_temp AS $$
DECLARE item products%ROWTYPE; sku skus%ROWTYPE; s jsonb; stock_after integer; changed jsonb; cfg jsonb; review_req boolean;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM admins WHERE _id=p_admin) THEN RAISE EXCEPTION 'ADMIN_REQUIRED'; END IF;
 IF p_op='clearDemo' THEN
  IF EXISTS(SELECT 1 FROM order_items oi JOIN skus sk ON sk._id=oi."skuId" JOIN products pr ON pr._id=sk."productId" WHERE pr._id LIKE 'demo-%')
     OR EXISTS(SELECT 1 FROM carts c JOIN skus sk ON sk._id=c."skuId" JOIN products pr ON pr._id=sk."productId" WHERE pr._id LIKE 'demo-%') THEN
    RAISE EXCEPTION 'DEMO_IN_USE';
  END IF;
  DELETE FROM skus WHERE "productId" LIKE 'demo-%';
  DELETE FROM home_picks WHERE "productId" LIKE 'demo-%';
  DELETE FROM products WHERE _id LIKE 'demo-%';
  DELETE FROM categories WHERE _id LIKE 'demo-%' AND NOT EXISTS (SELECT 1 FROM products WHERE "categoryId"=categories._id);
  DELETE FROM banners WHERE _id LIKE 'demo-%';
  DELETE FROM announcements WHERE _id LIKE 'demo-%';
  DELETE FROM faqs WHERE _id LIKE 'demo-%';
  INSERT INTO admin_actions("adminId",action,target,detail) VALUES(p_admin,'catalog.clearDemo','demo','{}'::jsonb);
  RETURN jsonb_build_object('id','demo','operation',p_op);
 END IF;
 IF p_op IN ('category.save','category.delete') THEN
  PERFORM pg_advisory_xact_lock(hashtext('generic_categories'));
  IF p_op='category.delete' THEN DELETE FROM categories WHERE _id=p_id;
  ELSE
   IF p_data->>'parentId'=p_id OR EXISTS(WITH RECURSIVE parents AS (SELECT _id,"parentId" FROM categories WHERE _id=p_data->>'parentId' UNION SELECT c._id,c."parentId" FROM categories c JOIN parents p ON c._id=p."parentId") SELECT 1 FROM parents WHERE _id=p_id) THEN RAISE EXCEPTION 'CATEGORY_CYCLE'; END IF;
   INSERT INTO categories(_id,name,"parentId",sort,visible) VALUES(p_id,p_data->>'name',nullif(p_data->>'parentId',''),(p_data->>'sort')::integer,(p_data->>'visible')::boolean)
   ON CONFLICT(_id) DO UPDATE SET name=excluded.name,"parentId"=excluded."parentId",sort=excluded.sort,visible=excluded.visible;
  END IF;
 ELSE
  SELECT * INTO item FROM products WHERE _id=p_id FOR UPDATE;
  IF p_op='save' THEN
   INSERT INTO products(_id,name,"categoryId",images,"detailImages","desc",subtitle,keywords,colors,sizes,patterns,"specLabels","sizeChart",price,"freightMode","freightTemplateId",stage,"reviewStatus","onShelf")
   VALUES(p_id,p_data->>'name',p_data->>'categoryId',ARRAY(SELECT jsonb_array_elements_text(p_data->'images')),ARRAY(SELECT jsonb_array_elements_text(p_data->'detailImages')),p_data->>'desc',coalesce(p_data->>'subtitle',''),ARRAY(SELECT jsonb_array_elements_text(coalesce(p_data->'keywords','[]'::jsonb))),ARRAY(SELECT jsonb_array_elements_text(p_data->'colors')),ARRAY(SELECT jsonb_array_elements_text(p_data->'sizes')),ARRAY(SELECT jsonb_array_elements_text(p_data->'patterns')),coalesce(p_data->'specLabels','[]'::jsonb),coalesce(p_data->'sizeChart','[]'::jsonb),(p_data->>'price')::bigint,p_data->>'freightMode',nullif(p_data->>'freightTemplateId',''),'pool','pending',false)
   ON CONFLICT(_id) DO UPDATE SET name=excluded.name,"categoryId"=excluded."categoryId",images=excluded.images,"detailImages"=excluded."detailImages","desc"=excluded."desc",subtitle=excluded.subtitle,keywords=excluded.keywords,colors=excluded.colors,sizes=excluded.sizes,patterns=excluded.patterns,"specLabels"=excluded."specLabels","sizeChart"=excluded."sizeChart",price=excluded.price,"freightMode"=excluded."freightMode","freightTemplateId"=excluded."freightTemplateId",stage='pool',"reviewStatus"='pending',"onShelf"=false;
   FOR sku IN SELECT * FROM skus WHERE "productId"=p_id ORDER BY _id FOR UPDATE LOOP
    IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p_data->'skus') x WHERE x->>'_id'=sku._id) THEN
     IF sku.reserved>0 OR EXISTS(SELECT 1 FROM order_items WHERE "skuId"=sku._id) OR EXISTS(SELECT 1 FROM carts WHERE "skuId"=sku._id) THEN RAISE EXCEPTION 'SKU_IN_USE'; END IF;
     DELETE FROM skus WHERE _id=sku._id;
    END IF;
   END LOOP;
   FOR s IN SELECT value FROM jsonb_array_elements(p_data->'skus') LOOP
    INSERT INTO skus(_id,"productId",color,size,pattern,stock,reserved) VALUES(s->>'_id',p_id,s->>'color',s->>'size',s->>'pattern',(s->>'stock')::integer,0) ON CONFLICT(_id) DO NOTHING;
   END LOOP;
  ELSIF item._id IS NULL THEN RAISE EXCEPTION 'PRODUCT_NOT_FOUND';
  ELSIF p_op='complete' THEN
   IF item.stage<>'pool' OR cardinality(item.images)=0 OR NOT EXISTS(SELECT 1 FROM skus WHERE "productId"=p_id) THEN RAISE EXCEPTION 'PRODUCT_INCOMPLETE'; END IF;
   SELECT "shopConfig" INTO cfg FROM settings WHERE _id='global';
   review_req := coalesce((cfg->>'reviewRequired')::boolean, true);
   UPDATE products SET stage='shelf',"reviewStatus"=CASE WHEN review_req THEN 'pending' ELSE 'approved' END,"reviewReason"='',"onShelf"=false WHERE _id=p_id;
  ELSIF p_op='approve' THEN
   IF item.stage<>'shelf' OR item."reviewStatus"<>'pending' THEN RAISE EXCEPTION 'REVIEW_NOT_PENDING'; END IF;
   UPDATE products SET "reviewStatus"='approved',"reviewReason"='' WHERE _id=p_id;
  ELSIF p_op='reject' THEN
   IF item.stage<>'shelf' OR item."reviewStatus"<>'pending' OR length(trim(p_data->>'reason'))<1 THEN RAISE EXCEPTION 'REVIEW_REASON_REQUIRED'; END IF;
   UPDATE products SET stage='pool',"reviewStatus"='rejected',"reviewReason"=p_data->>'reason',"onShelf"=false WHERE _id=p_id;
  ELSIF p_op='shelf' THEN
   IF item.stage<>'shelf' OR item."reviewStatus"<>'approved' THEN RAISE EXCEPTION 'PRODUCT_NOT_APPROVED'; END IF;
   UPDATE products SET "onShelf"=(p_data->>'onShelf')::boolean WHERE _id=p_id;
  ELSIF p_op='stock' THEN
   SELECT * INTO sku FROM skus WHERE _id=p_data->>'skuId' AND "productId"=p_id FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'SKU_NOT_FOUND'; END IF;
   stock_after:=sku.stock+(p_data->>'delta')::integer;
   IF stock_after<sku.reserved OR stock_after<0 THEN RAISE EXCEPTION 'STOCK_BELOW_RESERVED'; END IF;
   UPDATE skus SET stock=stock_after WHERE _id=sku._id;
   changed:=jsonb_build_object('skuId',sku._id,'before',sku.stock,'after',stock_after);
  ELSE RAISE EXCEPTION 'UNKNOWN_CATALOG_OPERATION'; END IF;
 END IF;
 INSERT INTO admin_actions("adminId",action,target,detail) VALUES(p_admin,'catalog.'||p_op,p_id,coalesce(changed,jsonb_build_object('reason',p_data->>'reason','onShelf',p_data->'onShelf')));
 RETURN jsonb_build_object('id',p_id,'operation',p_op);
END $$;
REVOKE ALL ON FUNCTION public.mall_admin_catalog(text,text,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mall_admin_catalog(text,text,text,jsonb) TO service_role;

-- ============ 7. 首页管理 RPC：去掉定制横幅分支，其余与第九批一致 ============
CREATE OR REPLACE FUNCTION public.mall_admin_home(p_admin text,p_op text,p_id text,p_data jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,pg_temp AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM admins WHERE _id=p_admin) THEN RAISE EXCEPTION 'ADMIN_REQUIRED'; END IF;
 IF p_op='banner.save' THEN
  INSERT INTO banners(_id,image,link,sort,visible) VALUES(p_id,p_data->>'image',p_data->>'link',(p_data->>'sort')::integer,(p_data->>'visible')::boolean)
  ON CONFLICT(_id) DO UPDATE SET image=excluded.image,link=excluded.link,sort=excluded.sort,visible=excluded.visible;
 ELSIF p_op='banner.delete' THEN DELETE FROM banners WHERE _id=p_id;
 ELSIF p_op='announcement.save' THEN
  INSERT INTO announcements(_id,text,link,sort,visible) VALUES(p_id,p_data->>'text',p_data->>'link',(p_data->>'sort')::integer,(p_data->>'visible')::boolean)
  ON CONFLICT(_id) DO UPDATE SET text=excluded.text,link=excluded.link,sort=excluded.sort,visible=excluded.visible;
 ELSIF p_op='announcement.delete' THEN DELETE FROM announcements WHERE _id=p_id;
 ELSIF p_op='pick.save' THEN
  IF NOT EXISTS(SELECT 1 FROM products p JOIN categories c ON c._id=p."categoryId" WHERE p._id=p_id AND p.stage='shelf' AND p."reviewStatus"='approved' AND p."onShelf" AND c.visible AND (c."parentId" IS NULL OR EXISTS(SELECT 1 FROM categories parent WHERE parent._id=c."parentId" AND parent.visible))) THEN RAISE EXCEPTION 'PICK_PRODUCT_NOT_VISIBLE'; END IF;
  INSERT INTO home_picks("productId",sort) VALUES(p_id,(p_data->>'sort')::integer) ON CONFLICT("productId") DO UPDATE SET sort=excluded.sort;
 ELSIF p_op='pick.delete' THEN DELETE FROM home_picks WHERE "productId"=p_id;
 ELSIF p_op='interval' THEN UPDATE settings SET "announcementIntervalSeconds"=(p_data->>'seconds')::integer WHERE _id='global';
 ELSIF p_op='splash.save' THEN
  IF (p_data->>'seconds')::integer NOT BETWEEN 1 AND 15 THEN RAISE EXCEPTION 'INVALID_SPLASH_SECONDS'; END IF;
  UPDATE settings SET "splashEnabled"=(p_data->>'enabled')::boolean,"splashImage"=p_data->>'image',"splashLink"=p_data->>'link',"splashSeconds"=(p_data->>'seconds')::integer WHERE _id='global';
 ELSE RAISE EXCEPTION 'UNKNOWN_HOME_OPERATION'; END IF;
 INSERT INTO admin_actions("adminId",action,target,detail) VALUES(p_admin,'home.'||p_op,p_id,p_data);
 RETURN jsonb_build_object('id',p_id,'operation',p_op);
END $$;
REVOKE ALL ON FUNCTION public.mall_admin_home(text,text,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mall_admin_home(text,text,text,jsonb) TO service_role;

-- ============ 8. 会员管理 RPC：档位增删、会员开关与套餐、后台手动定级 ============
CREATE OR REPLACE FUNCTION public.mall_admin_membership(p_admin text,p_op text,p_id text,p_data jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,pg_temp AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM admins WHERE _id=p_admin) THEN RAISE EXCEPTION 'ADMIN_REQUIRED'; END IF;
 IF p_op='config.save' THEN
  IF jsonb_typeof(p_data->'member')<>'object' THEN RAISE EXCEPTION 'INVALID_MEMBER_CONFIG'; END IF;
  UPDATE settings SET "shopConfig"=jsonb_set("shopConfig",'{member}',p_data->'member') WHERE _id='global';
 ELSIF p_op='tier.save' THEN
  INSERT INTO member_tiers(_id,level,name,threshold,"discountBps","cardBg","cardText",sort,enabled)
  VALUES(p_id,(p_data->>'level')::smallint,trim(p_data->>'name'),(p_data->>'threshold')::bigint,(p_data->>'discountBps')::integer,coalesce(p_data->>'cardBg',''),coalesce(p_data->>'cardText',''),coalesce((p_data->>'sort')::integer,0),coalesce((p_data->>'enabled')::boolean,true))
  ON CONFLICT(_id) DO UPDATE SET level=excluded.level,name=excluded.name,threshold=excluded.threshold,"discountBps"=excluded."discountBps","cardBg"=excluded."cardBg","cardText"=excluded."cardText",sort=excluded.sort,enabled=excluded.enabled;
 ELSIF p_op='tier.delete' THEN DELETE FROM member_tiers WHERE _id=p_id;
 ELSIF p_op='setLevel' THEN
  UPDATE users SET level=(p_data->>'level')::smallint,version=version+1 WHERE _id=p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'MEMBER_NOT_FOUND'; END IF;
 ELSE RAISE EXCEPTION 'UNKNOWN_MEMBERSHIP_OPERATION'; END IF;
 INSERT INTO admin_actions("adminId",action,target,detail) VALUES(p_admin,'membership.'||p_op,p_id,p_data);
 RETURN jsonb_build_object('id',p_id,'operation',p_op);
END $$;
REVOKE ALL ON FUNCTION public.mall_admin_membership(text,text,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mall_admin_membership(text,text,text,jsonb) TO service_role;

-- ============ 9. 店铺配置 RPC：品牌/规格轴/规格说明/三段闸开关（member 键由会员 RPC 专管，原样保留） ============
CREATE OR REPLACE FUNCTION public.mall_admin_shop_config(p_admin text,p_data jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,pg_temp AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM admins WHERE _id=p_admin) THEN RAISE EXCEPTION 'ADMIN_REQUIRED'; END IF;
 IF jsonb_typeof(p_data)<>'object'
   OR coalesce(p_data->>'brandColor','') !~ '^#[0-9a-fA-F]{6}$'
   OR jsonb_typeof(coalesce(p_data->'specAxes','[]'::jsonb))<>'array'
   OR jsonb_array_length(coalesce(p_data->'specAxes','[]'::jsonb))>3
   OR jsonb_typeof(coalesce(p_data->'specChart','{}'::jsonb))<>'object'
   OR coalesce(jsonb_typeof(p_data->'reviewRequired'),'missing')<>'boolean'
 THEN RAISE EXCEPTION 'INVALID_SHOP_CONFIG'; END IF;
 UPDATE settings SET "shopConfig"=p_data||jsonb_build_object('member',"shopConfig"->'member') WHERE _id='global';
 INSERT INTO admin_actions("adminId",action,target,detail) VALUES(p_admin,'system.shopConfig','global',p_data);
 RETURN jsonb_build_object('id','global');
END $$;
REVOKE ALL ON FUNCTION public.mall_admin_shop_config(text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mall_admin_shop_config(text,jsonb) TO service_role;

-- ============ 10. 退款审核 RPC：管理员选分路（source=各回各路，balance=全部退余额） ============
CREATE OR REPLACE FUNCTION public.mall_admin_refund(p_admin text,p_id text,p_op text,p_data jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,pg_temp AS $$
DECLARE rf refunds%ROWTYPE; o orders%ROWTYPE; u users%ROWTYPE; v_line jsonb; route text; prior_balance bigint; remaining bigint; credit bigint; external bigint;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM admins WHERE _id=p_admin) THEN RAISE EXCEPTION 'ADMIN_REQUIRED'; END IF;
 SELECT * INTO rf FROM refunds WHERE _id=p_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'REFUND_NOT_FOUND'; END IF;
 IF rf.status<>'pending' THEN RAISE EXCEPTION 'REFUND_DECIDED'; END IF;
 SELECT * INTO o FROM orders WHERE _id=rf."orderId" FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
 IF p_op='reject' THEN
  IF length(trim(coalesce(p_data->>'reason',''))) NOT BETWEEN 2 AND 500 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  UPDATE refunds SET status='rejected',"rejectReason"=trim(p_data->>'reason'),"decidedAt"=now() WHERE _id=p_id;
  INSERT INTO admin_actions("adminId",action,target,detail) VALUES(p_admin,'refund.reject',p_id,jsonb_build_object('orderId',rf."orderId",'reason',trim(p_data->>'reason')));
  RETURN jsonb_build_object('id',p_id,'status','rejected');
 END IF;
 IF p_op<>'approve' THEN RAISE EXCEPTION 'UNKNOWN_REFUND_OPERATION'; END IF;
 route:=coalesce(p_data->>'route','source');
 IF route NOT IN ('source','balance') THEN RAISE EXCEPTION 'INVALID_REFUND_ROUTE'; END IF;
 SELECT * INTO STRICT u FROM users WHERE _id=rf."userId" FOR UPDATE;
 SELECT coalesce(sum("balanceAmount"),0) INTO prior_balance FROM refunds WHERE "orderId"=rf."orderId" AND status='done' AND _id<>p_id;
 remaining:=GREATEST(0, o."balancePaid"-prior_balance);
 credit:=CASE WHEN route='balance' THEN rf."totalAmount" ELSE LEAST(rf."totalAmount", remaining) END;
 external:=rf."totalAmount"-credit;
 IF u.balance+credit>9007199254740991 THEN RAISE EXCEPTION 'BALANCE_OVERFLOW'; END IF;
 IF credit>0 THEN
  INSERT INTO balance_logs("userId",type,amount,"orderId","dedupeKey","balanceAfter","operatorId",remark)
  VALUES(u._id,'refund_in',credit,rf."orderId",'refund:'||p_id,u.balance+credit,p_admin,'退款审核通过（余额部分，分路：'||route||'）');
  UPDATE users SET balance=balance+credit,version=version+1 WHERE _id=u._id;
 END IF;
 FOR v_line IN SELECT value FROM jsonb_array_elements(rf.lines) LOOP
  IF v_line->>'skuId' IS NOT NULL THEN
   UPDATE skus SET stock=stock+(v_line->>'qty')::integer WHERE _id=v_line->>'skuId';
  ELSIF v_line->>'giftStockId' IS NOT NULL THEN
   UPDATE gift_stock SET stock=stock+(v_line->>'qty')::integer WHERE _id=v_line->>'giftStockId';
  END IF;
  UPDATE order_items SET "refundedQty"="refundedQty"+(v_line->>'qty')::integer WHERE _id=v_line->>'itemId';
 END LOOP;
 UPDATE refunds SET status='done',"balanceAmount"=credit,"originalAmount"=external,"decidedAt"=now() WHERE _id=p_id;
 UPDATE orders SET "refundedAmount"="refundedAmount"+rf."goodsAmount"+rf."freightAmount",
  status=CASE WHEN NOT EXISTS(SELECT 1 FROM order_items WHERE "orderId"=o._id AND "refundedQty"<qty) THEN 'refunded' ELSE o.status END,
  version=version+1 WHERE _id=o._id;
 INSERT INTO admin_actions("adminId",action,target,detail) VALUES(p_admin,'refund.approve',p_id,jsonb_build_object('orderId',rf."orderId",'route',route,'totalAmount',rf."totalAmount",'balanceAmount',credit,'originalAmount',external));
 RETURN jsonb_build_object('id',p_id,'status','done','route',route,'balanceAmount',credit,'originalAmount',external);
END $$;
REVOKE ALL ON FUNCTION public.mall_admin_refund(text,text,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mall_admin_refund(text,text,text,jsonb) TO service_role;

-- ============ 11. 废弃函数显式删除（签名须与定义一致；缺失时不报错） ============
DROP FUNCTION IF EXISTS public.mall_admin_gift(text,text,text,jsonb);
DROP FUNCTION IF EXISTS public.mall_admin_custom(text,jsonb);
DROP FUNCTION IF EXISTS public.mall_admin_pattern(text,text,text,jsonb);
DROP FUNCTION IF EXISTS public.mall_admin_product_rule(text,text,jsonb);
DROP FUNCTION IF EXISTS public.mall_run_product_schedule();
DROP FUNCTION IF EXISTS public.mall_admin_material_claim(text,text,text,text,text,jsonb);
DROP FUNCTION IF EXISTS public.mall_admin_material_finish(text,text,text,jsonb,jsonb,jsonb);
DROP FUNCTION IF EXISTS public.mall_claim_domain_events(text);
