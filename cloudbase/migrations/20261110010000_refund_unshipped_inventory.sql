-- Unshipped paid refunds restore consumed stock atomically with funds and audit.
CREATE OR REPLACE FUNCTION public.mall_admin_order(p_admin text,p_op text,p_id text,p_version bigint,p_data jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,pg_temp AS $$
DECLARE o orders; u users; credit bigint; external_amount bigint; detail jsonb; line record; restocked boolean := false; inventory_changes jsonb := '[]'::jsonb; before_stock integer; before_reserved integer;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM admins WHERE _id=p_admin) THEN RAISE EXCEPTION 'ADMIN_REQUIRED'; END IF;
 SELECT * INTO o FROM orders WHERE _id=p_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
 IF o.version<>p_version THEN RAISE EXCEPTION 'ORDER_CHANGED_REFRESH'; END IF;
 IF p_op='ship' THEN
  IF o.status<>'pending_ship' OR o."paidAt" IS NULL OR (o."isCustom" AND o."customReview"<>'approved') THEN RAISE EXCEPTION 'ORDER_NOT_SHIPPABLE'; END IF;
  IF length(trim(p_data->>'company')) NOT BETWEEN 1 AND 60 OR length(trim(p_data->>'tracking')) NOT BETWEEN 1 AND 80 THEN RAISE EXCEPTION 'SHIPPING_REQUIRED'; END IF;
  UPDATE orders SET status='pending_recv',"expressCompany"=trim(p_data->>'company'),"expressNo"=trim(p_data->>'tracking'),version=version+1 WHERE _id=p_id;
  detail=p_data;
 ELSIF p_op IN ('custom.approve','custom.reject') THEN
  IF NOT o."isCustom" OR o.status<>'pending_ship' OR o."paidAt" IS NULL OR o."customReview"<>'pending' THEN RAISE EXCEPTION 'CUSTOM_REVIEW_NOT_ALLOWED'; END IF;
  IF p_op='custom.reject' THEN
   IF length(trim(coalesce(p_data->>'reason',''))) NOT BETWEEN 2 AND 500 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
   UPDATE orders SET "customReview"='rejected',"customRejectReason"=trim(p_data->>'reason'),status='refunding',"refundPreviousStatus"='pending_ship',"refundReason"='商家驳回定制：'||trim(p_data->>'reason'),version=version+1 WHERE _id=p_id;
  ELSE UPDATE orders SET "customReview"='approved',version=version+1 WHERE _id=p_id; END IF;
  detail=p_data||jsonb_build_object('fundsChanged',false);
 ELSIF p_op='refund.reject' THEN
  IF o.status<>'refunding' OR coalesce(o."customReview"='rejected',false) OR coalesce(o."refundPreviousStatus",'') NOT IN ('pending_recv','done') THEN RAISE EXCEPTION 'REFUND_REJECTION_NOT_ALLOWED'; END IF;
  IF length(trim(coalesce(p_data->>'reason',''))) NOT BETWEEN 2 AND 500 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  UPDATE orders SET status=o."refundPreviousStatus",version=version+1 WHERE _id=p_id;
  detail=p_data;
 ELSIF p_op='refund.approve' THEN
  IF o.status<>'refunding' OR o."paidAt" IS NULL OR o."balancePaid"+o."wxPaid"<>o."payAmount" THEN RAISE EXCEPTION 'REFUND_NOT_ALLOWED'; END IF;
  IF p_data->>'mode' NOT IN ('balance','original') OR p_data->>'mode' IS NULL THEN RAISE EXCEPTION 'INVALID_REFUND_MODE'; END IF;
  credit=CASE WHEN p_data->>'mode'='balance' THEN o."payAmount" ELSE o."balancePaid" END;
  external_amount=CASE WHEN p_data->>'mode'='original' THEN o."wxPaid" ELSE 0 END;
  SELECT * INTO STRICT u FROM users WHERE _id=o."userId" FOR UPDATE;
  IF u.balance+credit>9007199254740991 THEN RAISE EXCEPTION 'BALANCE_OVERFLOW'; END IF;
  IF credit>0 THEN
   INSERT INTO balance_logs("userId",type,amount,"orderId","dedupeKey","balanceAfter","operatorId",remark)
   VALUES(u._id,'refund_in',credit,o._id,'admin-refund:'||o._id,u.balance+credit,p_admin,'订单退款审核：'||(p_data->>'mode'));
   UPDATE users SET balance=balance+credit,version=version+1 WHERE _id=u._id;
  END IF;
  INSERT INTO admin_refunds("orderId","adminId",mode,"balanceAmount","originalAmount","originalStatus")
  VALUES(o._id,p_admin,p_data->>'mode',credit,external_amount,CASE WHEN external_amount>0 THEN 'pending_simulated' ELSE 'none' END);
  -- Payment already consumed both stock and reservation. Restore stock only.
  -- A shipping trace always wins over a stale refundPreviousStatus.
  IF o."refundPreviousStatus"='pending_ship' AND o."expressNo"='' AND o."expressCompany"='' THEN
   IF NOT EXISTS(SELECT 1 FROM order_items WHERE "orderId"=o._id) THEN RAISE EXCEPTION 'REFUND_ITEMS_MISSING'; END IF;
   FOR line IN
    SELECT 'skus' AS tbl,"skuId" AS id,sum(qty)::bigint AS qty FROM order_items WHERE "orderId"=o._id AND "skuId" IS NOT NULL GROUP BY "skuId"
    UNION ALL
    SELECT 'gift_stock',"giftStockId",sum(qty)::bigint FROM order_items WHERE "orderId"=o._id AND "giftStockId" IS NOT NULL GROUP BY "giftStockId"
    ORDER BY tbl,id
   LOOP
    EXECUTE format('SELECT stock,reserved FROM %I WHERE _id=$1 FOR UPDATE',line.tbl) INTO before_stock,before_reserved USING line.id;
    IF before_stock IS NULL OR line.qty<=0 OR before_stock::bigint+line.qty>2147483647 THEN RAISE EXCEPTION 'REFUND_INVENTORY_INVALID'; END IF;
    EXECUTE format('UPDATE %I SET stock=stock+$1 WHERE _id=$2',line.tbl) USING line.qty,line.id;
    inventory_changes=inventory_changes||jsonb_build_array(jsonb_build_object('table',line.tbl,'id',line.id,'quantity',line.qty,'stockBefore',before_stock,'stockAfter',before_stock::bigint+line.qty,'reservedBefore',before_reserved,'reservedAfter',before_reserved));
   END LOOP;
   restocked=true;
  END IF;
  UPDATE orders SET status='refunded',version=version+1 WHERE _id=p_id;
  detail=jsonb_build_object('mode',p_data->>'mode','balanceAmount',credit,'originalAmount',external_amount,'originalStatus',CASE WHEN external_amount>0 THEN 'pending_simulated' ELSE 'none' END,'inventoryRestocked',restocked,'inventoryChanges',inventory_changes);
 ELSE RAISE EXCEPTION 'UNKNOWN_ORDER_OPERATION'; END IF;
 INSERT INTO admin_actions("adminId",action,target,detail) VALUES(p_admin,'order.'||p_op,p_id,detail);
 RETURN jsonb_build_object('id',p_id,'operation',p_op,'detail',detail);
END $$;
REVOKE ALL ON FUNCTION public.mall_admin_order(text,text,text,bigint,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mall_admin_order(text,text,text,bigint,jsonb) TO service_role;
