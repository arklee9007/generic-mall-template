-- 统一调整轮第六批（0.3.5）：B-21 版型库与定制链接、B-24 按件部分退款与退款原因/退货运费补偿。
-- 非破坏性：products.customBaseId 列保留不用；旧整单退款通道（orders.refunding + admin_refunds + mall_admin_order）原样保留。

-- ============ B-21：版型名单（唯一源） ============
CREATE TABLE public.patterns (
  _id text PRIMARY KEY,
  name text NOT NULL CHECK (length(name) BETWEEN 1 AND 40),
  image text NOT NULL DEFAULT '',
  sort integer NOT NULL DEFAULT 0,
  "createdAt" timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.patterns ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.patterns FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.patterns TO service_role;

ALTER TABLE public.products ADD COLUMN IF NOT EXISTS "patternId" text REFERENCES public.patterns(_id);

-- ============ B-21：定制链接单例（全店定制总开关） ============
CREATE TABLE public.custom_link (
  _id text PRIMARY KEY CHECK (_id='global'),
  enabled boolean NOT NULL DEFAULT true,
  title text NOT NULL DEFAULT '来图定制' CHECK (length(title) BETWEEN 1 AND 40),
  "updatedAt" timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.custom_link(_id) VALUES ('global') ON CONFLICT DO NOTHING;
ALTER TABLE public.custom_link ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.custom_link FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT,UPDATE ON public.custom_link TO service_role;

-- 商品保存写 patternId（函数体以第二批为准，仅 save 的 upsert 增加 patternId 一列）
CREATE OR REPLACE FUNCTION public.mall_admin_catalog(p_admin text,p_op text,p_id text,p_data jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,pg_temp AS $$
DECLARE item products%ROWTYPE; sku skus%ROWTYPE; s jsonb; stock_after integer; changed jsonb;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM admins WHERE _id=p_admin) THEN RAISE EXCEPTION 'ADMIN_REQUIRED'; END IF;
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
   INSERT INTO products(_id,name,"categoryId",images,"detailImages","desc",colors,sizes,patterns,price,"freightMode","freightTemplateId","customEnabled","customBaseId","patternId",stage,"reviewStatus","onShelf")
   VALUES(p_id,p_data->>'name',p_data->>'categoryId',ARRAY(SELECT jsonb_array_elements_text(p_data->'images')),ARRAY(SELECT jsonb_array_elements_text(p_data->'detailImages')),p_data->>'desc',ARRAY(SELECT jsonb_array_elements_text(p_data->'colors')),ARRAY(SELECT jsonb_array_elements_text(p_data->'sizes')),ARRAY(SELECT jsonb_array_elements_text(p_data->'patterns')),(p_data->>'price')::bigint,p_data->>'freightMode',nullif(p_data->>'freightTemplateId',''),(p_data->>'customEnabled')::boolean,nullif(p_data->>'customBaseId',''),nullif(p_data->>'patternId',''),'pool','pending',false)
   ON CONFLICT(_id) DO UPDATE SET name=excluded.name,"categoryId"=excluded."categoryId",images=excluded.images,"detailImages"=excluded."detailImages","desc"=excluded."desc",colors=excluded.colors,sizes=excluded.sizes,patterns=excluded.patterns,price=excluded.price,"freightMode"=excluded."freightMode","freightTemplateId"=excluded."freightTemplateId","customEnabled"=excluded."customEnabled","customBaseId"=excluded."customBaseId","patternId"=excluded."patternId",stage='pool',"reviewStatus"='pending',"onShelf"=false;
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
   UPDATE products SET stage='shelf',"reviewStatus"='pending',"onShelf"=false WHERE _id=p_id;
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

-- 版型与定制链接的写操作（校验＋留痕）：pattern.save / pattern.delete / link.save
CREATE FUNCTION public.mall_admin_pattern(p_admin text,p_op text,p_id text,p_data jsonb) RETURNS jsonb
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
  UPDATE custom_link SET enabled=(p_data->>'enabled')::boolean,title=coalesce(nullif(trim(p_data->>'title'),''),title),"updatedAt"=now() WHERE _id='global';
 ELSE RAISE EXCEPTION 'UNKNOWN_PATTERN_OPERATION'; END IF;
 INSERT INTO admin_actions("adminId",action,target,detail) VALUES(p_admin,'custom.'||p_op,p_id,p_data);
 RETURN jsonb_build_object('id',p_id,'operation',p_op);
END $$;
REVOKE ALL ON FUNCTION public.mall_admin_pattern(text,text,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mall_admin_pattern(text,text,text,jsonb) TO service_role;

-- ============ B-24：按件部分退款 ============
ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS "refundedQty" integer NOT NULL DEFAULT 0 CHECK ("refundedQty" >= 0);
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS "refundedAmount" bigint NOT NULL DEFAULT 0 CHECK ("refundedAmount" >= 0);

CREATE TABLE public.refunds (
  _id text PRIMARY KEY,
  "orderId" text NOT NULL REFERENCES public.orders(_id),
  "userId" text NOT NULL REFERENCES public.users(_id),
  lines jsonb NOT NULL CHECK (jsonb_typeof(lines)='array' AND jsonb_array_length(lines)>0),
  "reasonCode" text NOT NULL CHECK ("reasonCode" IN ('seller_wrong','seller_quality','seller_size','buyer_change','buyer_size','buyer_other')),
  "reasonText" text NOT NULL DEFAULT '',
  "goodsAmount" bigint NOT NULL CHECK ("goodsAmount" >= 0),
  "freightAmount" bigint NOT NULL DEFAULT 0 CHECK ("freightAmount" >= 0),
  "freightComp" bigint NOT NULL DEFAULT 0 CHECK ("freightComp" >= 0),
  "totalAmount" bigint NOT NULL CHECK ("totalAmount" > 0),
  "balanceAmount" bigint NOT NULL DEFAULT 0 CHECK ("balanceAmount" >= 0),
  "originalAmount" bigint NOT NULL DEFAULT 0 CHECK ("originalAmount" >= 0),
  mode text NOT NULL CHECK (mode IN ('instant','review')),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','done','rejected')),
  "rejectReason" text NOT NULL DEFAULT '',
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "decidedAt" timestamptz
);
CREATE INDEX refunds_order_idx ON public.refunds("orderId");
CREATE INDEX refunds_status_idx ON public.refunds(status);
ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.refunds FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT,UPDATE ON public.refunds TO service_role;
GRANT UPDATE ON public.order_items TO service_role;

-- 审核型退款的通过/拒绝（资金、库存、件数、订单进度在一个事务内完成）
CREATE FUNCTION public.mall_admin_refund(p_admin text,p_id text,p_op text,p_data jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,pg_temp AS $$
DECLARE rf refunds%ROWTYPE; o orders%ROWTYPE; u users%ROWTYPE; v_line jsonb;
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
 SELECT * INTO STRICT u FROM users WHERE _id=rf."userId" FOR UPDATE;
 IF u.balance+rf."balanceAmount">9007199254740991 THEN RAISE EXCEPTION 'BALANCE_OVERFLOW'; END IF;
 IF rf."balanceAmount">0 THEN
  INSERT INTO balance_logs("userId",type,amount,"orderId","dedupeKey","balanceAfter","operatorId",remark)
  VALUES(u._id,'refund_in',rf."balanceAmount",rf."orderId",'refund:'||p_id,u.balance+rf."balanceAmount",p_admin,'退款审核通过（余额部分）');
  UPDATE users SET balance=balance+rf."balanceAmount",version=version+1 WHERE _id=u._id;
 END IF;
 FOR v_line IN SELECT value FROM jsonb_array_elements(rf.lines) LOOP
  IF v_line->>'skuId' IS NOT NULL THEN
   UPDATE skus SET stock=stock+(v_line->>'qty')::integer WHERE _id=v_line->>'skuId';
  ELSIF v_line->>'giftStockId' IS NOT NULL THEN
   UPDATE gift_stock SET stock=stock+(v_line->>'qty')::integer WHERE _id=v_line->>'giftStockId';
  END IF;
  UPDATE order_items SET "refundedQty"="refundedQty"+(v_line->>'qty')::integer WHERE _id=v_line->>'itemId';
 END LOOP;
 UPDATE refunds SET status='done',"decidedAt"=now() WHERE _id=p_id;
 UPDATE orders SET "refundedAmount"="refundedAmount"+rf."goodsAmount"+rf."freightAmount",
  status=CASE WHEN NOT EXISTS(SELECT 1 FROM order_items WHERE "orderId"=o._id AND "refundedQty"<qty) THEN 'refunded' ELSE o.status END,
  version=version+1 WHERE _id=o._id;
 INSERT INTO admin_actions("adminId",action,target,detail) VALUES(p_admin,'refund.approve',p_id,jsonb_build_object('orderId',rf."orderId",'totalAmount',rf."totalAmount",'balanceAmount',rf."balanceAmount",'originalAmount',rf."originalAmount"));
 RETURN jsonb_build_object('id',p_id,'status','done');
END $$;
REVOKE ALL ON FUNCTION public.mall_admin_refund(text,text,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mall_admin_refund(text,text,text,jsonb) TO service_role;

-- 看板退款口径并入新退款表（已完成退款按裁定时间计，含即时退款）
CREATE OR REPLACE FUNCTION public.mall_admin_dashboard() RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER
SET search_path=public,pg_temp AS $$
  SELECT jsonb_build_object(
    'todayOrders',(SELECT count(*) FROM orders WHERE "createdAt">=date_trunc('day',now() AT TIME ZONE 'Asia/Shanghai') AT TIME ZONE 'Asia/Shanghai'),
    'todaySales',coalesce((SELECT sum("payAmount") FROM orders WHERE "paidAt">=date_trunc('day',now() AT TIME ZONE 'Asia/Shanghai') AT TIME ZONE 'Asia/Shanghai'),0),
    'todayRefunds',coalesce((SELECT sum("balanceAmount"+"originalAmount") FROM admin_refunds WHERE "createdAt">=date_trunc('day',now() AT TIME ZONE 'Asia/Shanghai') AT TIME ZONE 'Asia/Shanghai'),0)
      +coalesce((SELECT sum("totalAmount") FROM refunds WHERE status='done' AND coalesce("decidedAt","createdAt")>=date_trunc('day',now() AT TIME ZONE 'Asia/Shanghai') AT TIME ZONE 'Asia/Shanghai'),0),
    'monthSales',coalesce((SELECT sum("payAmount") FROM orders WHERE "paidAt">=date_trunc('month',now() AT TIME ZONE 'Asia/Shanghai') AT TIME ZONE 'Asia/Shanghai'),0),
    'monthRefunds',coalesce((SELECT sum("balanceAmount"+"originalAmount") FROM admin_refunds WHERE "createdAt">=date_trunc('month',now() AT TIME ZONE 'Asia/Shanghai') AT TIME ZONE 'Asia/Shanghai'),0)
      +coalesce((SELECT sum("totalAmount") FROM refunds WHERE status='done' AND coalesce("decidedAt","createdAt")>=date_trunc('month',now() AT TIME ZONE 'Asia/Shanghai') AT TIME ZONE 'Asia/Shanghai'),0),
    'pendingShip',(SELECT count(*) FROM orders WHERE status='pending_ship'),
    'checkedAt',now());
$$;
