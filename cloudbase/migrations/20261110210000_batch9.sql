-- 统一调整轮第九批：B-25R 底板价 / B-29R 横幅图 / B-26R 退款撤销状态
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS "customBasePrice" bigint;
UPDATE public.products SET "customBasePrice"=price WHERE "customEnabled" AND "customBasePrice" IS NULL;
ALTER TABLE public.settings ADD COLUMN IF NOT EXISTS "customBannerImage" text NOT NULL DEFAULT '';
ALTER TABLE public.refunds DROP CONSTRAINT IF EXISTS refunds_status_check;
ALTER TABLE public.refunds ADD CONSTRAINT refunds_status_check CHECK (status IN ('pending','done','rejected','cancelled'));

CREATE OR REPLACE FUNCTION public.mall_admin_pattern(p_admin text,p_op text,p_id text,p_data jsonb) RETURNS jsonb
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
  UPDATE custom_link SET enabled=(p_data->>'enabled')::boolean,title=coalesce(nullif(trim(p_data->>'title'),''),title),colors=CASE WHEN p_data ? 'colors' THEN ARRAY(SELECT jsonb_array_elements_text(p_data->'colors')) ELSE colors END,sizes=CASE WHEN p_data ? 'sizes' THEN ARRAY(SELECT jsonb_array_elements_text(p_data->'sizes')) ELSE sizes END,"updatedAt"=now() WHERE _id='global';
 ELSIF p_op='base.attach' THEN
  UPDATE products SET "customEnabled"=true,"patternId"=p_data->>'patternId',"customBasePrice"=coalesce("customBasePrice",price) WHERE _id=p_id;
 ELSIF p_op='base.price' THEN
  IF (p_data->>'price')::bigint IS NULL OR (p_data->>'price')::bigint<0 OR (p_data->>'price')::bigint>100000000 THEN RAISE EXCEPTION 'INVALID_BASE_PRICE'; END IF;
  UPDATE products SET "customBasePrice"=(p_data->>'price')::bigint WHERE _id=p_id;
 ELSIF p_op='base.detach' THEN
  UPDATE products SET "customEnabled"=false WHERE _id=p_id;
 ELSE RAISE EXCEPTION 'UNKNOWN_PATTERN_OPERATION'; END IF;
 INSERT INTO admin_actions("adminId",action,target,detail) VALUES(p_admin,'custom.'||p_op,p_id,p_data);
 RETURN jsonb_build_object('id',p_id,'operation',p_op);
END $$;
REVOKE ALL ON FUNCTION public.mall_admin_pattern(text,text,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mall_admin_pattern(text,text,text,jsonb) TO service_role;

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
 ELSIF p_op='custombanner.save' THEN
  UPDATE settings SET "customBannerEnabled"=(p_data->>'enabled')::boolean,"customBannerImage"=coalesce(p_data->>'image',"customBannerImage") WHERE _id='global';
 ELSE RAISE EXCEPTION 'UNKNOWN_HOME_OPERATION'; END IF;
 INSERT INTO admin_actions("adminId",action,target,detail) VALUES(p_admin,'home.'||p_op,p_id,p_data);
 RETURN jsonb_build_object('id',p_id,'operation',p_op);
END $$;
REVOKE ALL ON FUNCTION public.mall_admin_home(text,text,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mall_admin_home(text,text,text,jsonb) TO service_role;
