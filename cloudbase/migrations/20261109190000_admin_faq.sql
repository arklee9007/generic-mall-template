CREATE FUNCTION public.mall_admin_faq(p_admin text,p_op text,p_id text,p_data jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,pg_temp AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM admins WHERE _id=p_admin) THEN RAISE EXCEPTION 'ADMIN_REQUIRED'; END IF;
 IF p_op='save' THEN INSERT INTO faqs(_id,question,answer,sort,visible) VALUES(p_id,p_data->>'question',p_data->>'answer',(p_data->>'sort')::integer,(p_data->>'visible')::boolean)
 ON CONFLICT(_id) DO UPDATE SET question=excluded.question,answer=excluded.answer,sort=excluded.sort,visible=excluded.visible;
 ELSIF p_op='delete' THEN DELETE FROM faqs WHERE _id=p_id;
 ELSE RAISE EXCEPTION 'UNKNOWN_FAQ_OPERATION'; END IF;
 INSERT INTO admin_actions("adminId",action,target,detail) VALUES(p_admin,'faq.'||p_op,p_id,p_data);
 RETURN jsonb_build_object('id',p_id,'operation',p_op);
END $$;
REVOKE ALL ON FUNCTION public.mall_admin_faq(text,text,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mall_admin_faq(text,text,text,jsonb) TO service_role;
