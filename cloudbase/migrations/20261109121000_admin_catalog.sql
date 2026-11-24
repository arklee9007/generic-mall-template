INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
VALUES('admin-media','admin-media',true,2097152,ARRAY['image/png','image/jpeg','image/webp']);
CREATE POLICY admin_media_read ON storage.objects FOR SELECT TO anon,authenticated USING(bucket_id='admin-media');
CREATE FUNCTION public.mall_admin_catalog(p_admin text,p_op text,p_id text,p_data jsonb) RETURNS jsonb
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
   INSERT INTO products(_id,name,"categoryId",images,"detailImages","desc",colors,sizes,patterns,price,"freightMode","freightTemplateId","customEnabled",stage,"reviewStatus","onShelf")
   VALUES(p_id,p_data->>'name',p_data->>'categoryId',ARRAY(SELECT jsonb_array_elements_text(p_data->'images')),ARRAY(SELECT jsonb_array_elements_text(p_data->'detailImages')),p_data->>'desc',ARRAY(SELECT jsonb_array_elements_text(p_data->'colors')),ARRAY(SELECT jsonb_array_elements_text(p_data->'sizes')),ARRAY(SELECT jsonb_array_elements_text(p_data->'patterns')),(p_data->>'price')::bigint,p_data->>'freightMode',nullif(p_data->>'freightTemplateId',''),(p_data->>'customEnabled')::boolean,'pool','pending',false)
   ON CONFLICT(_id) DO UPDATE SET name=excluded.name,"categoryId"=excluded."categoryId",images=excluded.images,"detailImages"=excluded."detailImages","desc"=excluded."desc",colors=excluded.colors,sizes=excluded.sizes,patterns=excluded.patterns,price=excluded.price,"freightMode"=excluded."freightMode","freightTemplateId"=excluded."freightTemplateId","customEnabled"=excluded."customEnabled",stage='pool',"reviewStatus"='pending',"onShelf"=false;
   -- Existing stock is changed only by a separate locked delta operation.
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
