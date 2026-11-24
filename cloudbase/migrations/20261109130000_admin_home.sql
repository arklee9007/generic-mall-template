CREATE FUNCTION public.mall_admin_home(p_admin text,p_op text,p_id text,p_data jsonb) RETURNS jsonb
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
 ELSE RAISE EXCEPTION 'UNKNOWN_HOME_OPERATION'; END IF;
 INSERT INTO admin_actions("adminId",action,target,detail) VALUES(p_admin,'home.'||p_op,p_id,p_data);
 RETURN jsonb_build_object('id',p_id,'operation',p_op);
END $$;
REVOKE ALL ON FUNCTION public.mall_admin_home(text,text,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mall_admin_home(text,text,text,jsonb) TO service_role;
