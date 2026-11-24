CREATE FUNCTION public.mall_admin_membership(p_admin text,p_op text,p_id text,p_data jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,pg_temp AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM admins WHERE _id=p_admin) THEN RAISE EXCEPTION 'ADMIN_REQUIRED'; END IF;
 IF p_op='tier.save' THEN
  INSERT INTO recharge_tiers(_id,amount,level,enabled,sort) VALUES(p_id,(p_data->>'amount')::bigint,(p_data->>'level')::smallint,(p_data->>'enabled')::boolean,(p_data->>'sort')::integer)
  ON CONFLICT(_id) DO UPDATE SET amount=excluded.amount,level=excluded.level,enabled=excluded.enabled,sort=excluded.sort;
 ELSIF p_op='tier.delete' THEN DELETE FROM recharge_tiers WHERE _id=p_id;
 ELSIF p_op='save' THEN
  UPDATE settings SET "memberRules"="memberRules"||jsonb_build_object('v1Discount',(p_data->>'v1Discount')::numeric,'v2Discount',(p_data->>'v2Discount')::numeric,'upgradeThreshold',(p_data->>'upgradeThreshold')::bigint),"couponIssueDay"=(p_data->>'couponIssueDay')::integer,"giftEmptySizeMode"=p_data->>'giftEmptySizeMode' WHERE _id='global';
 ELSE RAISE EXCEPTION 'UNKNOWN_MEMBERSHIP_OPERATION'; END IF;
 INSERT INTO admin_actions("adminId",action,target,detail) VALUES(p_admin,'membership.'||p_op,p_id,p_data);
 RETURN jsonb_build_object('id',p_id,'operation',p_op);
END $$;
REVOKE ALL ON FUNCTION public.mall_admin_membership(text,text,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mall_admin_membership(text,text,text,jsonb) TO service_role;
