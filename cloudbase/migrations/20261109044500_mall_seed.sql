-- 通用模板中性演示数据：3 个示例分类、6 件示例商品、2 条轮播、1 条公告、2 条 FAQ。
-- 商品名带 [示例] 前缀；图片为中性占位图 /static/products/placeholder.svg。
-- 演示行 _id 均以 demo- 开头；后台「一键清空演示数据」只删这些行，不动店铺配置。
-- 规格用三轴槽位：colors/sizes/patterns 为轴 0/1/2；某轴数组为空表示该商品不用此轴，
-- SKU 行里不用的轴填空字符串哨兵。specLabels（每商品轴名覆盖）由通用迁移补写。

INSERT INTO public.categories ("_id","name","parentId","sort","visible") VALUES
('demo-home','[示例]家居日用',NULL,0,true),
('demo-office','[示例]文具办公',NULL,1,true),
('demo-food','[示例]休闲食品',NULL,2,true)
ON CONFLICT DO NOTHING;

INSERT INTO public.freight_templates ("_id","name","rules","isDefault") VALUES
('default','默认运费','[{"regions":["*"],"price":1000,"type":"normal"},{"regions":["新疆","西藏","青海","宁夏","甘肃","内蒙古","偏远地区"],"price":1000,"type":"extra"},{"regions":["香港","澳门","台湾","港澳台"],"price":0,"type":"no_delivery"}]'::jsonb,true)
ON CONFLICT DO NOTHING;

INSERT INTO public.products ("_id","name","categoryId","images","detailImages","desc","subtitle","keywords","colors","sizes","patterns","price","freightMode","freightTemplateId","stage","reviewStatus","onShelf","customEnabled","sizeChart") VALUES
('demo-cup','[示例]双层保温杯','demo-home',ARRAY['/static/products/placeholder.svg']::text[],ARRAY['/static/products/placeholder.svg']::text[],'示例商品：双层不锈钢保温杯，占位图非实拍。','保温保冷 / 食品级内胆',ARRAY['[示例]双层保温杯','保温杯','水杯']::text[],ARRAY['米白','深灰']::text[],ARRAY['350ml','500ml']::text[],ARRAY['简约款','磨砂款']::text[],8900,'template','default','shelf','approved',true,false,'{"columns":["容量","高度","口径"],"rows":[["350ml","19cm","6cm"],["500ml","22cm","6.5cm"]]}'::jsonb),
('demo-notebook','[示例]布面笔记本','demo-office',ARRAY['/static/products/placeholder.svg']::text[],ARRAY['/static/products/placeholder.svg']::text[],'示例商品：布面精装笔记本，占位图非实拍。','96 页 / 点阵内页',ARRAY['[示例]布面笔记本','笔记本','本子']::text[],ARRAY['藏青','砖红']::text[],ARRAY['A5','B5']::text[],ARRAY[]::text[],3900,'template','default','shelf','approved',true,false,'[]'::jsonb),
('demo-box','[示例]桌面收纳盒','demo-home',ARRAY['/static/products/placeholder.svg']::text[],ARRAY['/static/products/placeholder.svg']::text[],'示例商品：多格桌面收纳盒，占位图非实拍。','三格 / 可叠放',ARRAY['[示例]桌面收纳盒','收纳盒']::text[],ARRAY['透明','白色']::text[],ARRAY[]::text[],ARRAY[]::text[],5900,'template','default','shelf','approved',true,false,'[]'::jsonb),
('demo-pen','[示例]中性笔三支装','demo-office',ARRAY['/static/products/placeholder.svg']::text[],ARRAY['/static/products/placeholder.svg']::text[],'示例商品：0.5mm 中性笔三支装，占位图非实拍。','0.5mm / 速干',ARRAY['[示例]中性笔三支装','中性笔','笔']::text[],ARRAY[]::text[],ARRAY[]::text[],ARRAY[]::text[],1900,'template','default','shelf','approved',true,false,'[]'::jsonb),
('demo-nuts','[示例]坚果礼盒','demo-food',ARRAY['/static/products/placeholder.svg']::text[],ARRAY['/static/products/placeholder.svg']::text[],'示例商品：混合坚果礼盒，占位图非实拍。','四种坚果 / 独立小包',ARRAY['[示例]坚果礼盒','坚果','零食']::text[],ARRAY['原味','椒盐']::text[],ARRAY['500g','1kg']::text[],ARRAY[]::text[],12800,'template','default','shelf','approved',true,false,'[]'::jsonb),
('demo-tea','[示例]红茶小罐','demo-food',ARRAY['/static/products/placeholder.svg']::text[],ARRAY['/static/products/placeholder.svg']::text[],'示例商品：红茶小罐装，占位图非实拍。','小罐 / 密封防潮',ARRAY['[示例]红茶小罐','红茶','茶叶']::text[],ARRAY['正山小种','金骏眉']::text[],ARRAY['50g']::text[],ARRAY[]::text[],6800,'template','default','shelf','approved',true,false,'[]'::jsonb)
ON CONFLICT DO NOTHING;

INSERT INTO public.skus ("_id","productId","color","size","pattern","stock","reserved") VALUES
('demo-cup-0-0-0','demo-cup','米白','350ml','简约款',10,0),
('demo-cup-0-0-1','demo-cup','米白','350ml','磨砂款',10,0),
('demo-cup-0-1-0','demo-cup','米白','500ml','简约款',10,0),
('demo-cup-0-1-1','demo-cup','米白','500ml','磨砂款',10,0),
('demo-cup-1-0-0','demo-cup','深灰','350ml','简约款',10,0),
('demo-cup-1-0-1','demo-cup','深灰','350ml','磨砂款',10,0),
('demo-cup-1-1-0','demo-cup','深灰','500ml','简约款',10,0),
('demo-cup-1-1-1','demo-cup','深灰','500ml','磨砂款',10,0),
('demo-notebook-0-0','demo-notebook','藏青','A5','',10,0),
('demo-notebook-0-1','demo-notebook','藏青','B5','',10,0),
('demo-notebook-1-0','demo-notebook','砖红','A5','',10,0),
('demo-notebook-1-1','demo-notebook','砖红','B5','',10,0),
('demo-box-0','demo-box','透明','','',10,0),
('demo-box-1','demo-box','白色','','',10,0),
('demo-pen-0','demo-pen','','','',10,0),
('demo-nuts-0-0','demo-nuts','原味','500g','',10,0),
('demo-nuts-0-1','demo-nuts','原味','1kg','',10,0),
('demo-nuts-1-0','demo-nuts','椒盐','500g','',10,0),
('demo-nuts-1-1','demo-nuts','椒盐','1kg','',10,0),
('demo-tea-0','demo-tea','正山小种','50g','',10,0),
('demo-tea-1','demo-tea','金骏眉','50g','',10,0)
ON CONFLICT DO NOTHING;

INSERT INTO public.settings ("_id","shopName","serviceHours","memberRules","notices","sizeChart") VALUES
('global','我的店铺','周一至周六 10:00–19:00','{}'::jsonb,'["示例商品仅用于演示，占位图非实拍。","下单前请联系客服确认库存与运费。"]'::jsonb,'[]'::jsonb)
ON CONFLICT DO NOTHING;

INSERT INTO public.banners ("_id","image","link","sort","visible") VALUES
('demo-banner-1','/static/products/placeholder.svg','',0,true),
('demo-banner-2','/static/products/placeholder.svg','',1,true)
ON CONFLICT DO NOTHING;

INSERT INTO public.announcements ("_id","text","link","sort","visible") VALUES
('demo-ann-1','[示例]欢迎光临本店，演示数据可在后台一键清空。','',0,true)
ON CONFLICT DO NOTHING;

INSERT INTO public.home_picks ("productId","sort") VALUES
('demo-cup',0),
('demo-nuts',1)
ON CONFLICT DO NOTHING;

INSERT INTO public.faqs ("_id","question","answer","sort","visible") VALUES
('demo-faq-1','运费怎么算？','按收货地区与运费模板计算，下单时显示实收运费。',0,true),
('demo-faq-2','收到商品有问题怎么办？','请先联系客服，售后按店铺公示规则处理。',1,true)
ON CONFLICT DO NOTHING;
