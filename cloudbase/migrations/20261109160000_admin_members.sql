CREATE FUNCTION public.mall_admin_balance(p_admin text,p_user text,p_delta bigint,p_reason text,p_key text) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,pg_temp AS $$
DECLARE u users; old balance_logs; k text;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM admins WHERE _id=p_admin) THEN RAISE EXCEPTION 'ADMIN_REQUIRED'; END IF;
 IF p_delta=0 OR abs(p_delta)>10000000 OR length(trim(p_reason)) NOT BETWEEN 2 AND 500 OR length(p_key) NOT BETWEEN 8 AND 100 THEN RAISE EXCEPTION 'INVALID_ADJUSTMENT'; END IF;
 k='admin-adjust:'||p_admin||':'||p_user||':'||p_key;
 SELECT * INTO STRICT u FROM users WHERE _id=p_user FOR UPDATE;
 SELECT * INTO old FROM balance_logs WHERE "dedupeKey"=k;
 IF FOUND THEN
  IF old.amount<>p_delta OR old.remark<>trim(p_reason) THEN RAISE EXCEPTION 'ADJUSTMENT_KEY_CONFLICT'; END IF;
  RETURN jsonb_build_object('id',old._id,'balanceAfter',old."balanceAfter",'idempotent',true);
 END IF;
 IF u.balance+p_delta<0 OR u.balance+p_delta>9007199254740991 THEN RAISE EXCEPTION 'BALANCE_OUT_OF_RANGE'; END IF;
 INSERT INTO balance_logs("userId",type,amount,"dedupeKey","balanceAfter","operatorId",remark)
 VALUES(p_user,'admin_adjust',p_delta,k,u.balance+p_delta,p_admin,trim(p_reason)) RETURNING * INTO old;
 UPDATE users SET balance=balance+p_delta,version=version+1 WHERE _id=p_user;
 INSERT INTO admin_actions("adminId",action,target,detail) VALUES(p_admin,'member.balance',p_user,jsonb_build_object('amount',p_delta,'balanceBefore',u.balance,'balanceAfter',u.balance+p_delta,'reason',trim(p_reason),'logId',old._id));
 RETURN jsonb_build_object('id',old._id,'balanceAfter',old."balanceAfter",'idempotent',false);
END $$;
REVOKE ALL ON FUNCTION public.mall_admin_balance(text,text,bigint,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mall_admin_balance(text,text,bigint,text,text) TO service_role;
