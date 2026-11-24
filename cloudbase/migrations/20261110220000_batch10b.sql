-- 通用模板：会员称谓默认值 + 会员编号（M000001 起递增、终身绑定）
ALTER TABLE public.users ALTER COLUMN nickname SET DEFAULT '商城会员';
CREATE SEQUENCE IF NOT EXISTS public.users_member_no_seq START WITH 1;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS "memberNo" text;
UPDATE public.users u SET "memberNo"=s.code FROM (SELECT _id, 'M'||lpad((row_number() OVER (ORDER BY "createdAt",_id))::text,6,'0') AS code FROM public.users WHERE "memberNo" IS NULL) s WHERE u._id=s._id;
DO $$ DECLARE m bigint; BEGIN SELECT COALESCE(max(substring("memberNo" from 2)::bigint),0) INTO m FROM public.users; IF m=0 THEN PERFORM setval('public.users_member_no_seq',1,false); ELSE PERFORM setval('public.users_member_no_seq',m,true); END IF; END $$;
ALTER TABLE public.users ALTER COLUMN "memberNo" SET DEFAULT 'M'||lpad(nextval('public.users_member_no_seq')::text,6,'0');
ALTER TABLE public.users ALTER COLUMN "memberNo" SET NOT NULL;
DO $$ BEGIN ALTER TABLE public.users ADD CONSTRAINT users_member_no_unique UNIQUE ("memberNo"); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
