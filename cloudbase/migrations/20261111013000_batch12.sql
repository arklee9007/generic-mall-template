-- 统一调整轮第十二批：分片上传缓存（B-31 上传通道改造）
-- 背景：浏览器→云函数网关对请求体大小有上限（实测约70KB可过、约200KB必断），
-- 整包base64塞进函数请求的做法在大图/素材包上必死。改为浏览器分片发送、
-- 本表暂存分片，后台拼装后直存云存储或走素材导入；分片在finish成功后即删除，
-- 中途失败保留原样以便排查，同一uploadId重发同序号分片为覆盖（幂等）。
CREATE TABLE IF NOT EXISTS public.upload_chunks (
  "uploadId" text NOT NULL,
  "adminId" text NOT NULL,
  "idx" integer NOT NULL,
  "data" text NOT NULL,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT upload_chunks_pkey PRIMARY KEY ("uploadId","idx")
);
ALTER TABLE public.upload_chunks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.upload_chunks FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.upload_chunks TO service_role;
