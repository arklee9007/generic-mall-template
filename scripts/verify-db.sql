-- 通用模板数据库验收：断言失败即抛错（ON_ERROR_STOP 下回放脚本随即失败）。
INSERT INTO public.admins (_id, username, "passwordHash", role) VALUES ('test-admin','verify-admin','x','owner');
INSERT INTO public.users (_id, openid) VALUES ('user-verify-1','openid-verify-1'), ('user-verify-2','openid-verify-2');

-- A. 演示数据与默认配置
DO $$ BEGIN
  IF (SELECT count(*) FROM categories WHERE _id LIKE 'demo-%')<>3 THEN RAISE EXCEPTION 'VERIFY A1: demo categories <> 3'; END IF;
  IF (SELECT count(*) FROM products WHERE _id LIKE 'demo-%')<>6 THEN RAISE EXCEPTION 'VERIFY A2: demo products <> 6'; END IF;
  IF (SELECT count(*) FROM skus WHERE "productId" LIKE 'demo-%')<>21 THEN RAISE EXCEPTION 'VERIFY A3: demo skus <> 21'; END IF;
  IF (SELECT count(*) FROM banners WHERE _id LIKE 'demo-%')<>2 THEN RAISE EXCEPTION 'VERIFY A4: demo banners <> 2'; END IF;
  IF (SELECT count(*) FROM announcements WHERE _id LIKE 'demo-%')<>1 THEN RAISE EXCEPTION 'VERIFY A5: demo announcements <> 1'; END IF;
  IF (SELECT count(*) FROM faqs WHERE _id LIKE 'demo-%')<>2 THEN RAISE EXCEPTION 'VERIFY A6: demo faqs <> 2'; END IF;
  IF (SELECT count(*) FROM home_picks)<>2 THEN RAISE EXCEPTION 'VERIFY A7: home picks <> 2'; END IF;
  IF (SELECT "shopName" FROM settings WHERE _id='global')<>'我的店铺' THEN RAISE EXCEPTION 'VERIFY A8: shopName'; END IF;
  IF (SELECT "shopConfig"->>'brandColor' FROM settings WHERE _id='global')<>'#2563EB' THEN RAISE EXCEPTION 'VERIFY A9: brandColor'; END IF;
  IF (SELECT jsonb_array_length("shopConfig"->'specAxes') FROM settings WHERE _id='global')<>3 THEN RAISE EXCEPTION 'VERIFY A10: specAxes'; END IF;
  IF (SELECT ("shopConfig"->>'reviewRequired')::boolean FROM settings WHERE _id='global')<>true THEN RAISE EXCEPTION 'VERIFY A11: reviewRequired default'; END IF;
  IF (SELECT ("shopConfig"->'member'->>'enabled')::boolean FROM settings WHERE _id='global')<>true THEN RAISE EXCEPTION 'VERIFY A12: member enabled'; END IF;
  IF (SELECT jsonb_array_length("shopConfig"->'member'->'packages') FROM settings WHERE _id='global')<>3 THEN RAISE EXCEPTION 'VERIFY A13: packages'; END IF;
  RAISE NOTICE 'VERIFY A OK: demo data + default shopConfig';
END $$;

-- B. 档位表与轴名覆盖
DO $$ BEGIN
  IF (SELECT count(*) FROM member_tiers)<>2 THEN RAISE EXCEPTION 'VERIFY B1: member_tiers <> 2'; END IF;
  IF (SELECT threshold FROM member_tiers WHERE level=1)<>10000 OR (SELECT "discountBps" FROM member_tiers WHERE level=1)<>9500 THEN RAISE EXCEPTION 'VERIFY B2: tier-1 values'; END IF;
  IF (SELECT "specLabels" FROM products WHERE _id='demo-cup')<>'["颜色","容量","款式"]'::jsonb THEN RAISE EXCEPTION 'VERIFY B3: demo-cup specLabels'; END IF;
  IF (SELECT "specLabels" FROM products WHERE _id='demo-nuts')<>'["口味","规格"]'::jsonb THEN RAISE EXCEPTION 'VERIFY B4: demo-nuts specLabels'; END IF;
  IF (SELECT "sizeChart"->'columns' FROM products WHERE _id='demo-cup') IS NULL THEN RAISE EXCEPTION 'VERIFY B5: demo-cup chart'; END IF;
  RAISE NOTICE 'VERIFY B OK: tiers + specLabels';
END $$;

-- C. 等级约束与废弃函数
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='users_level_range') THEN RAISE EXCEPTION 'VERIFY C1: users_level_range missing'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='recharge_records_level_range') THEN RAISE EXCEPTION 'VERIFY C2: recharge_records_level_range missing'; END IF;
  IF (SELECT count(*) FROM pg_proc WHERE proname IN ('mall_admin_gift','mall_admin_custom','mall_admin_pattern','mall_admin_product_rule','mall_run_product_schedule','mall_admin_material_claim','mall_admin_material_finish','mall_claim_domain_events'))<>0 THEN RAISE EXCEPTION 'VERIFY C3: obsolete functions remain'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='mall_admin_shop_config') THEN RAISE EXCEPTION 'VERIFY C4: mall_admin_shop_config missing'; END IF;
  RAISE NOTICE 'VERIFY C OK: constraints + function inventory';
END $$;
INSERT INTO public.users (_id, openid, level) VALUES ('user-lvl-20','openid-lvl-20',20);
DO $$ BEGIN
  IF (SELECT level FROM users WHERE _id='user-lvl-20')<>20 THEN RAISE EXCEPTION 'VERIFY C5: level 20 rejected'; END IF;
  BEGIN
    INSERT INTO public.users (_id, openid, level) VALUES ('user-lvl-21','openid-lvl-21',21);
    RAISE EXCEPTION 'VERIFY C6: level 21 accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  DELETE FROM users WHERE _id='user-lvl-20';
  RAISE NOTICE 'VERIFY C5-C6 OK: level range 0..20 enforced';
END $$;

-- D. 商品流：0维保存、三段闸、审核开关、规格表
SELECT mall_admin_catalog('test-admin','save','test-prod-0','{"name":"验 0维","categoryId":"demo-home","images":["https://x/y.png"],"detailImages":[],"desc":"","subtitle":"副","keywords":["验"],"colors":[],"sizes":[],"patterns":[],"specLabels":[],"sizeChart":[],"price":100,"freightMode":"free","freightTemplateId":null,"skus":[{"_id":"test-prod-0-sku","color":"","size":"","pattern":"","stock":5}]}'::jsonb);
DO $$ BEGIN
  IF (SELECT stage FROM products WHERE _id='test-prod-0')<>'pool' THEN RAISE EXCEPTION 'VERIFY D1: save stage'; END IF;
  IF (SELECT subtitle FROM products WHERE _id='test-prod-0')<>'副' THEN RAISE EXCEPTION 'VERIFY D2: subtitle'; END IF;
  IF (SELECT count(*) FROM skus WHERE "productId"='test-prod-0')<>1 THEN RAISE EXCEPTION 'VERIFY D3: 0-dim sku count'; END IF;
  IF EXISTS (SELECT 1 FROM skus WHERE "productId"='test-prod-0' AND (color<>'' OR size<>'' OR pattern<>'')) THEN RAISE EXCEPTION 'VERIFY D4: sentinel'; END IF;
  RAISE NOTICE 'VERIFY D1-D4 OK: 0-dim save';
END $$;
SELECT mall_admin_catalog('test-admin','complete','test-prod-0','{}'::jsonb);
DO $$ BEGIN
  IF (SELECT "reviewStatus" FROM products WHERE _id='test-prod-0')<>'pending' THEN RAISE EXCEPTION 'VERIFY D5: complete keeps pending when reviewRequired'; END IF;
END $$;
SELECT mall_admin_catalog('test-admin','approve','test-prod-0','{}'::jsonb);
SELECT mall_admin_catalog('test-admin','shelf','test-prod-0','{"onShelf":true}'::jsonb);
SELECT mall_admin_catalog('test-admin','stock','test-prod-0','{"skuId":"test-prod-0-sku","delta":5}'::jsonb);
DO $$ BEGIN
  IF (SELECT "onShelf" FROM products WHERE _id='test-prod-0')<>true THEN RAISE EXCEPTION 'VERIFY D6: shelf'; END IF;
  IF (SELECT stock FROM skus WHERE _id='test-prod-0-sku')<>10 THEN RAISE EXCEPTION 'VERIFY D7: stock delta'; END IF;
  RAISE NOTICE 'VERIFY D5-D7 OK: review + shelf + stock';
END $$;
SELECT mall_admin_shop_config('test-admin','{"brandWord":"","brandColor":"#2563EB","logo":"","footerText":"","specAxes":["规格一","规格二","规格三"],"specChart":{"enabled":true,"title":"规格说明"},"reviewRequired":false}'::jsonb);
SELECT mall_admin_catalog('test-admin','save','test-prod-1','{"name":"验 1维","categoryId":"demo-home","images":["https://x/y.png"],"detailImages":[],"desc":"","subtitle":"","keywords":[],"colors":["红"],"sizes":[],"patterns":[],"specLabels":["颜色"],"sizeChart":[],"price":200,"freightMode":"free","freightTemplateId":null,"skus":[{"_id":"test-prod-1-sku","color":"红","size":"","pattern":"","stock":3}]}'::jsonb);
SELECT mall_admin_catalog('test-admin','complete','test-prod-1','{}'::jsonb);
DO $$ BEGIN
  IF (SELECT "reviewStatus" FROM products WHERE _id='test-prod-1')<>'approved' THEN RAISE EXCEPTION 'VERIFY D8: complete auto-approves when review off'; END IF;
  IF (SELECT ("shopConfig"->'member'->>'enabled')::boolean FROM settings WHERE _id='global')<>true THEN RAISE EXCEPTION 'VERIFY D9: shop_config preserves member key'; END IF;
  BEGIN
    PERFORM mall_admin_shop_config('test-admin','{"brandWord":"","brandColor":"red","logo":"","footerText":"","specAxes":[],"specChart":{"enabled":true,"title":"规格说明"},"reviewRequired":true}'::jsonb);
    RAISE EXCEPTION 'VERIFY D10: bad brandColor accepted';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE '%INVALID_SHOP_CONFIG%' THEN RAISE; END IF; END;
  RAISE NOTICE 'VERIFY D8-D10 OK: review gate + shop_config validation';
END $$;
SELECT mall_admin_shop_config('test-admin','{"brandWord":"","brandColor":"#2563EB","logo":"","footerText":"","specAxes":["规格一","规格二","规格三"],"specChart":{"enabled":true,"title":"规格说明"},"reviewRequired":true}'::jsonb);

-- E. 会员流：档位、开关、手动定级
SELECT mall_admin_membership('test-admin','tier.save','tier-3','{"level":3,"name":"尊享","threshold":100000,"discountBps":8500,"cardBg":"","cardText":"","sort":2,"enabled":true}'::jsonb);
SELECT mall_admin_membership('test-admin','config.save','global','{"member":{"enabled":false,"rechargeEnabled":false,"packages":[]}}'::jsonb);
SELECT mall_admin_membership('test-admin','setLevel','user-verify-1','{"level":3}'::jsonb);
DO $$ BEGIN
  IF (SELECT count(*) FROM member_tiers WHERE level=3)<>1 THEN RAISE EXCEPTION 'VERIFY E1: tier.save'; END IF;
  IF (SELECT ("shopConfig"->'member'->>'enabled')::boolean FROM settings WHERE _id='global')<>false THEN RAISE EXCEPTION 'VERIFY E2: config.save'; END IF;
  IF (SELECT "shopConfig"->>'brandColor' FROM settings WHERE _id='global')<>'#2563EB' THEN RAISE EXCEPTION 'VERIFY E3: config.save preserves brand'; END IF;
  IF (SELECT level FROM users WHERE _id='user-verify-1')<>3 THEN RAISE EXCEPTION 'VERIFY E4: setLevel'; END IF;
  RAISE NOTICE 'VERIFY E1-E4 OK: membership admin';
END $$;
SELECT mall_admin_membership('test-admin','tier.delete','tier-3','{}'::jsonb);
SELECT mall_admin_membership('test-admin','config.save','global','{"member":{"enabled":true,"rechargeEnabled":true,"packages":[{"amount":10000,"bonus":0,"label":"充100元"},{"amount":20000,"bonus":2000,"label":"充200元送20元"},{"amount":50000,"bonus":8000,"label":"充500元送80元"}]}}'::jsonb);
DO $$ BEGIN
  IF (SELECT count(*) FROM member_tiers WHERE level=3)<>0 THEN RAISE EXCEPTION 'VERIFY E5: tier.delete'; END IF;
  RAISE NOTICE 'VERIFY E5 OK: tier.delete + config restore';
END $$;

-- F. 退款流：分路 source/balance、上限、驳回（夹具用非演示商品，演示清理不受夹具订单牵连）
INSERT INTO public.products (_id,name,"categoryId",images,"detailImages","desc",subtitle,keywords,colors,sizes,patterns,price,"freightMode",stage,"reviewStatus","onShelf") VALUES ('test-prod-2','验退款商品','demo-home',ARRAY['https://x/y.png']::text[],ARRAY[]::text[],'','',ARRAY[]::text[],ARRAY['红']::text[],ARRAY[]::text[],ARRAY[]::text[],5000,'free','shelf','approved',true);
INSERT INTO public.skus (_id,"productId",color,size,pattern,stock,reserved) VALUES ('test-sku-2','test-prod-2','红','','',10,0);
UPDATE users SET balance=10000, level=1, version=0 WHERE _id='user-verify-1';
INSERT INTO public.orders (_id,"userId","requestKey",items,"goodsAmount","discountAmount","freightAmount","payAmount","balancePaid","wxPaid","useBalance",address,status,"paidAt","payDeadline",version,"refundedAmount") VALUES ('order-verify-1','user-verify-1','verify-r1','[{"name":"x"}]'::jsonb,10000,0,0,10000,6000,4000,true,'{}'::jsonb,'pending_recv',now(),now()+interval '1 hour',0,0);
INSERT INTO public.order_items (_id,"orderId","productId","skuId",name,image,color,size,pattern,price,qty,"refundedQty") VALUES ('item-verify-1','order-verify-1','test-prod-2','test-sku-2','验退款商品','','红','','',5000,2,0);
INSERT INTO public.refunds (_id,"orderId","userId",lines,"reasonCode","reasonText","goodsAmount","freightAmount","freightComp","totalAmount","balanceAmount","originalAmount",mode,status) VALUES ('refund-verify-1','order-verify-1','user-verify-1','[{"itemId":"item-verify-1","skuId":"test-sku-2","qty":1,"name":"x","price":5000}]'::jsonb,'buyer_change','',5000,0,0,5000,5000,0,'review','pending');
SELECT mall_admin_refund('test-admin','refund-verify-1','approve','{"route":"source"}'::jsonb);
DO $$ BEGIN
  IF (SELECT balance FROM users WHERE _id='user-verify-1')<>15000 THEN RAISE EXCEPTION 'VERIFY F1: source route credit'; END IF;
  IF (SELECT "balanceAmount" FROM refunds WHERE _id='refund-verify-1')<>5000 OR (SELECT "originalAmount" FROM refunds WHERE _id='refund-verify-1')<>0 THEN RAISE EXCEPTION 'VERIFY F2: source split'; END IF;
  IF (SELECT stock FROM skus WHERE _id='test-sku-2')<>11 THEN RAISE EXCEPTION 'VERIFY F3: stock restore'; END IF;
  IF (SELECT "refundedQty" FROM order_items WHERE _id='item-verify-1')<>1 THEN RAISE EXCEPTION 'VERIFY F4: refundedQty'; END IF;
  IF (SELECT "refundedAmount" FROM orders WHERE _id='order-verify-1')<>5000 OR (SELECT status FROM orders WHERE _id='order-verify-1')<>'pending_recv' THEN RAISE EXCEPTION 'VERIFY F5: partial refund order state'; END IF;
  IF NOT EXISTS (SELECT 1 FROM balance_logs WHERE "dedupeKey"='refund:refund-verify-1' AND amount=5000 AND type='refund_in') THEN RAISE EXCEPTION 'VERIFY F6: refund ledger'; END IF;
  RAISE NOTICE 'VERIFY F1-F6 OK: refund source route';
END $$;
INSERT INTO public.refunds (_id,"orderId","userId",lines,"reasonCode","reasonText","goodsAmount","freightAmount","freightComp","totalAmount","balanceAmount","originalAmount",mode,status) VALUES ('refund-verify-2','order-verify-1','user-verify-1','[{"itemId":"item-verify-1","skuId":"test-sku-2","qty":1,"name":"x","price":5000}]'::jsonb,'buyer_change','',5000,0,0,5000,1000,4000,'review','pending');
SELECT mall_admin_refund('test-admin','refund-verify-2','approve','{"route":"balance"}'::jsonb);
DO $$ BEGIN
  IF (SELECT balance FROM users WHERE _id='user-verify-1')<>20000 THEN RAISE EXCEPTION 'VERIFY F7: balance route credit'; END IF;
  IF (SELECT "balanceAmount" FROM refunds WHERE _id='refund-verify-2')<>5000 OR (SELECT "originalAmount" FROM refunds WHERE _id='refund-verify-2')<>0 THEN RAISE EXCEPTION 'VERIFY F8: balance split overrides proposal'; END IF;
  IF (SELECT status FROM orders WHERE _id='order-verify-1')<>'refunded' THEN RAISE EXCEPTION 'VERIFY F9: full refund order status'; END IF;
  RAISE NOTICE 'VERIFY F7-F9 OK: refund balance route';
END $$;
UPDATE users SET balance=0, version=0 WHERE _id='user-verify-2';
INSERT INTO public.orders (_id,"userId","requestKey",items,"goodsAmount","discountAmount","freightAmount","payAmount","balancePaid","wxPaid","useBalance",address,status,"paidAt","payDeadline",version,"refundedAmount") VALUES ('order-verify-2','user-verify-2','verify-r2','[{"name":"x"}]'::jsonb,5000,0,0,5000,1000,4000,true,'{}'::jsonb,'pending_recv',now(),now()+interval '1 hour',0,0);
INSERT INTO public.order_items (_id,"orderId","productId","skuId",name,image,color,size,pattern,price,qty,"refundedQty") VALUES ('item-verify-2','order-verify-2','test-prod-2','test-sku-2','验退款商品','','红','','',5000,1,0);
INSERT INTO public.refunds (_id,"orderId","userId",lines,"reasonCode","reasonText","goodsAmount","freightAmount","freightComp","totalAmount","balanceAmount","originalAmount",mode,status) VALUES ('refund-verify-3','order-verify-2','user-verify-2','[{"itemId":"item-verify-2","skuId":"test-sku-2","qty":1,"name":"x","price":5000}]'::jsonb,'buyer_change','',5000,0,0,5000,5000,0,'review','pending');
SELECT mall_admin_refund('test-admin','refund-verify-3','approve','{"route":"source"}'::jsonb);
DO $$ BEGIN
  IF (SELECT balance FROM users WHERE _id='user-verify-2')<>1000 THEN RAISE EXCEPTION 'VERIFY F10: source route capped by balancePaid'; END IF;
  IF (SELECT "balanceAmount" FROM refunds WHERE _id='refund-verify-3')<>1000 OR (SELECT "originalAmount" FROM refunds WHERE _id='refund-verify-3')<>4000 THEN RAISE EXCEPTION 'VERIFY F11: capped split'; END IF;
  RAISE NOTICE 'VERIFY F10-F11 OK: refund source cap';
END $$;
INSERT INTO public.refunds (_id,"orderId","userId",lines,"reasonCode","reasonText","goodsAmount","freightAmount","freightComp","totalAmount","balanceAmount","originalAmount",mode,status) VALUES ('refund-verify-4','order-verify-2','user-verify-2','[{"itemId":"item-verify-2","skuId":"test-sku-2","qty":1,"name":"x","price":5000}]'::jsonb,'buyer_change','',5000,0,0,5000,0,5000,'review','pending');
SELECT mall_admin_refund('test-admin','refund-verify-4','reject','{"reason":"不符合退款条件"}'::jsonb);
DO $$ BEGIN
  IF (SELECT status FROM refunds WHERE _id='refund-verify-4')<>'rejected' THEN RAISE EXCEPTION 'VERIFY F12: reject'; END IF;
  IF (SELECT balance FROM users WHERE _id='user-verify-2')<>1000 THEN RAISE EXCEPTION 'VERIFY F13: reject moves no money'; END IF;
  RAISE NOTICE 'VERIFY F12-F13 OK: refund reject';
END $$;

-- G. 原子提交：余额账本不变式与锁
UPDATE users SET balance=500, version=0 WHERE _id='user-verify-2';
SELECT mall_atomic_commit('{"locks":[{"table":"users","id":"user-verify-2","expected":{"version":0,"balance":500}}],"inserts":[{"table":"balance_logs","data":{"_id":"log-verify-1","userId":"user-verify-2","type":"recharge","amount":200,"orderId":null,"dedupeKey":"verify-ac-1","balanceAfter":700,"remark":"验"}}],"updates":[{"table":"users","id":"user-verify-2","data":{"balance":700,"version":1}}],"deletes":[]}'::jsonb);
DO $$ BEGIN
  IF (SELECT balance FROM users WHERE _id='user-verify-2')<>700 THEN RAISE EXCEPTION 'VERIFY G1: atomic commit balance'; END IF;
  BEGIN
    PERFORM mall_atomic_commit('{"locks":[{"table":"users","id":"user-verify-2","expected":{"version":1,"balance":700}}],"inserts":[{"table":"balance_logs","data":{"_id":"log-verify-2","userId":"user-verify-2","type":"recharge","amount":200,"orderId":null,"dedupeKey":"verify-ac-2","balanceAfter":900,"remark":"验"}}],"updates":[{"table":"users","id":"user-verify-2","data":{"balance":800,"version":2}}],"deletes":[]}'::jsonb);
    RAISE EXCEPTION 'VERIFY G2: ledger mismatch accepted';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE '%BALANCE_LEDGER_MISMATCH%' THEN RAISE; END IF; END;
  IF (SELECT balance FROM users WHERE _id='user-verify-2')<>700 THEN RAISE EXCEPTION 'VERIFY G3: failed plan moved money'; END IF;
  BEGIN
    PERFORM mall_atomic_commit('{"locks":[{"table":"users","id":"user-verify-2","expected":{"version":99}}],"inserts":[],"updates":[],"deletes":[]}'::jsonb);
    RAISE EXCEPTION 'VERIFY G4: stale lock accepted';
  EXCEPTION WHEN SQLSTATE '40001' THEN NULL; END;
  PERFORM mall_atomic_commit('{"locks":[{"table":"order_items","id":"item-verify-1","expected":{"refundedQty":2}}],"inserts":[],"updates":[{"table":"order_items","id":"item-verify-1","data":{"refundedQty":2}}],"deletes":[]}'::jsonb);
  RAISE NOTICE 'VERIFY G1-G4 OK: atomic commit invariant + locks + order_items update';
END $$;

-- G2. 审计留痕不可变（真实行探针）
DO $$ DECLARE aid text; BEGIN
  SELECT _id INTO aid FROM admin_actions LIMIT 1;
  IF aid IS NULL THEN RAISE EXCEPTION 'VERIFY G2-0: no admin_actions row to probe'; END IF;
  BEGIN
    UPDATE admin_actions SET _id=_id WHERE _id=aid;
    RAISE EXCEPTION 'VERIFY G2-1: audit update allowed';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'AUDIT_IMMUTABLE' THEN RAISE; END IF; END;
  BEGIN
    DELETE FROM admin_actions WHERE _id=aid;
    RAISE EXCEPTION 'VERIFY G2-2: audit delete allowed';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'AUDIT_IMMUTABLE' THEN RAISE; END IF; END;
  RAISE NOTICE 'VERIFY G2 OK: audit immutability';
END $$;

-- H. 看板冒烟
DO $$ DECLARE d jsonb; BEGIN
  d := mall_admin_dashboard();
  IF d->>'todayOrders' IS NULL OR d->>'checkedAt' IS NULL THEN RAISE EXCEPTION 'VERIFY H1: dashboard shape'; END IF;
  RAISE NOTICE 'VERIFY H OK: dashboard smoke';
END $$;

-- I. 演示清理：先验守卫（演示商品已有订单时拒绝），再撤守卫单、清演示
INSERT INTO public.orders (_id,"userId","requestKey",items,"goodsAmount","discountAmount","freightAmount","payAmount","balancePaid","wxPaid","useBalance",address,status,"payDeadline",version,"refundedAmount") VALUES ('order-verify-guard','user-verify-1','verify-guard','[{"name":"x"}]'::jsonb,100,0,0,100,0,0,true,'{}'::jsonb,'pending_pay',now()+interval '1 hour',0,0);
INSERT INTO public.order_items (_id,"orderId","productId","skuId",name,image,color,size,pattern,price,qty,"refundedQty") VALUES ('item-verify-guard','order-verify-guard','demo-cup','demo-cup-0-0-0','[示例]双层保温杯','','米白','350ml','简约款',100,1,0);
DO $$ BEGIN
  BEGIN
    PERFORM mall_admin_catalog('test-admin','clearDemo','demo','{}'::jsonb);
    RAISE EXCEPTION 'VERIFY I1: clearDemo allowed with demo orders';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE '%DEMO_IN_USE%' THEN RAISE; END IF; END;
  RAISE NOTICE 'VERIFY I1 OK: clearDemo guard';
END $$;
DELETE FROM order_items WHERE _id='item-verify-guard';
DELETE FROM orders WHERE _id='order-verify-guard';
SELECT mall_admin_catalog('test-admin','clearDemo','demo','{}'::jsonb);
DO $$ BEGIN
  IF (SELECT count(*) FROM products WHERE _id LIKE 'demo-%')<>0 THEN RAISE EXCEPTION 'VERIFY I2: demo products remain'; END IF;
  IF (SELECT count(*) FROM skus WHERE "productId" LIKE 'demo-%')<>0 THEN RAISE EXCEPTION 'VERIFY I3: demo skus remain'; END IF;
  IF (SELECT count(*) FROM banners WHERE _id LIKE 'demo-%')<>0 THEN RAISE EXCEPTION 'VERIFY I4: demo banners remain'; END IF;
  IF (SELECT count(*) FROM announcements WHERE _id LIKE 'demo-%')<>0 THEN RAISE EXCEPTION 'VERIFY I5: demo announcements remain'; END IF;
  IF (SELECT count(*) FROM faqs WHERE _id LIKE 'demo-%')<>0 THEN RAISE EXCEPTION 'VERIFY I6: demo faqs remain'; END IF;
  IF (SELECT count(*) FROM home_picks)<>0 THEN RAISE EXCEPTION 'VERIFY I7: home picks remain'; END IF;
  IF (SELECT count(*) FROM categories WHERE _id='demo-home')<>1 THEN RAISE EXCEPTION 'VERIFY I8: referenced demo category must be kept'; END IF;
  IF (SELECT count(*) FROM categories WHERE _id IN ('demo-office','demo-food'))<>0 THEN RAISE EXCEPTION 'VERIFY I9: unreferenced demo categories must go'; END IF;
  IF (SELECT count(*) FROM products WHERE _id LIKE 'test-prod-%')<>3 THEN RAISE EXCEPTION 'VERIFY I10: non-demo products touched'; END IF;
  IF NOT EXISTS (SELECT 1 FROM settings WHERE _id='global') THEN RAISE EXCEPTION 'VERIFY I11: settings touched'; END IF;
  IF (SELECT count(*) FROM member_tiers)<>2 THEN RAISE EXCEPTION 'VERIFY I12: tiers touched'; END IF;
  RAISE NOTICE 'VERIFY I2-I12 OK: clearDemo';
END $$;
