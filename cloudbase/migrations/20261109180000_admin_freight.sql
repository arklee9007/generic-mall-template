CREATE FUNCTION public.mall_admin_freight(p_admin text,p_op text,p_id text,p_data jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,pg_temp AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM admins WHERE _id=p_admin) THEN RAISE EXCEPTION 'ADMIN_REQUIRED'; END IF;
 PERFORM pg_advisory_xact_lock(hashtext('mall-freight-default'));
 IF p_op='save' THEN
  IF (p_data->>'isDefault')::boolean THEN UPDATE freight_templates SET "isDefault"=false WHERE "isDefault";
  ELSIF EXISTS(SELECT 1 FROM freight_templates WHERE _id=p_id AND "isDefault") THEN RAISE EXCEPTION 'DEFAULT_TEMPLATE_REQUIRED'; END IF;
  INSERT INTO freight_templates(_id,name,rules,"isDefault") VALUES(p_id,p_data->>'name',p_data->'rules',(p_data->>'isDefault')::boolean)
  ON CONFLICT(_id) DO UPDATE SET name=excluded.name,rules=excluded.rules,"isDefault"=excluded."isDefault";
 ELSIF p_op='delete' THEN
  IF EXISTS(SELECT 1 FROM freight_templates WHERE _id=p_id AND "isDefault") THEN RAISE EXCEPTION 'DEFAULT_TEMPLATE_REQUIRED'; END IF;
  DELETE FROM freight_templates WHERE _id=p_id;
 ELSE RAISE EXCEPTION 'UNKNOWN_FREIGHT_OPERATION'; END IF;
 IF NOT EXISTS(SELECT 1 FROM freight_templates WHERE "isDefault") THEN RAISE EXCEPTION 'DEFAULT_TEMPLATE_REQUIRED'; END IF;
 INSERT INTO admin_actions("adminId",action,target,detail) VALUES(p_admin,'freight.'||p_op,p_id,p_data);
 RETURN jsonb_build_object('id',p_id,'operation',p_op);
END $$;
REVOKE ALL ON FUNCTION public.mall_admin_freight(text,text,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mall_admin_freight(text,text,text,jsonb) TO service_role;
