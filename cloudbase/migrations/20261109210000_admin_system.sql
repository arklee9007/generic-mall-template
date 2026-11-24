CREATE FUNCTION public.mall_admin_system(p_admin text,p_data jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,pg_temp AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM admins WHERE _id=p_admin) THEN RAISE EXCEPTION 'ADMIN_REQUIRED'; END IF;
 UPDATE settings SET "shopName"=p_data->>'shopName',"servicePhone"=p_data->>'servicePhone',"serviceHours"=p_data->>'serviceHours',"notifyEmail"=p_data->>'notifyEmail' WHERE _id='global';
 INSERT INTO admin_actions("adminId",action,target,detail) VALUES(p_admin,'system.save','global',p_data);
 RETURN jsonb_build_object('id','global');
END $$;
REVOKE ALL ON FUNCTION public.mall_admin_system(text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mall_admin_system(text,jsonb) TO service_role;
