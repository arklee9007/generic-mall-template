-- Detailed specification v2: quoted camelCase names preserve its field contract.
-- No business data is created here. All mutations are server-only.
CREATE TABLE public.users (
  _id text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  openid text NOT NULL UNIQUE,
  "cloudUid" text UNIQUE,
  phone text UNIQUE CHECK (phone IS NULL OR phone ~ '^1[0-9]{10}$'),
  nickname text NOT NULL DEFAULT '商城会员',
  level smallint NOT NULL DEFAULT 0 CHECK (level IN (0,1,2)),
  balance bigint NOT NULL DEFAULT 0 CHECK (balance BETWEEN 0 AND 9007199254740991),
  "totalPurchase" bigint NOT NULL DEFAULT 0 CHECK ("totalPurchase" BETWEEN 0 AND 9007199254740991),
  version bigint NOT NULL DEFAULT 0,
  "createdAt" timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.member_accounts (
  "userId" text PRIMARY KEY REFERENCES public.users(_id),
  version bigint NOT NULL DEFAULT 0,
  "updatedAt" timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.member_accounts IS 'Membership account lock/version; balance/level/totalPurchase have one source of truth in users per detailed specification.';
CREATE TABLE public.recharge_tiers (
  _id text PRIMARY KEY,
  amount bigint NOT NULL CHECK (amount BETWEEN 1 AND 9007199254740991),
  level smallint NOT NULL CHECK (level IN (1,2)),
  enabled boolean NOT NULL DEFAULT true,
  sort integer NOT NULL DEFAULT 0
);
CREATE TABLE public.categories (
  _id text PRIMARY KEY,
  name text NOT NULL,
  "parentId" text REFERENCES public.categories(_id),
  sort integer NOT NULL DEFAULT 0,
  visible boolean NOT NULL DEFAULT true,
  CHECK ("parentId" IS DISTINCT FROM _id)
);
CREATE TABLE public.freight_templates (
  _id text PRIMARY KEY,
  name text NOT NULL,
  rules jsonb NOT NULL CHECK (jsonb_typeof(rules) = 'array'),
  "isDefault" boolean NOT NULL DEFAULT false
);
CREATE UNIQUE INDEX freight_one_default ON public.freight_templates ("isDefault") WHERE "isDefault";
CREATE TABLE public.products (
  _id text PRIMARY KEY,
  name text NOT NULL,
  "categoryId" text NOT NULL REFERENCES public.categories(_id),
  images text[] NOT NULL DEFAULT '{}',
  "detailImages" text[] NOT NULL DEFAULT '{}',
  "desc" text NOT NULL DEFAULT '',
  subtitle text NOT NULL DEFAULT '',
  keywords text[] NOT NULL DEFAULT '{}',
  colors text[] NOT NULL DEFAULT '{}',
  sizes text[] NOT NULL DEFAULT '{}',
  patterns text[] NOT NULL DEFAULT '{}',
  price bigint NOT NULL CHECK (price BETWEEN 0 AND 9007199254740991),
  "freightMode" text NOT NULL CHECK ("freightMode" IN ('template','free')),
  "freightTemplateId" text REFERENCES public.freight_templates(_id),
  stage text NOT NULL DEFAULT 'pool' CHECK (stage IN ('pool','shelf')),
  "reviewStatus" text NOT NULL DEFAULT 'pending' CHECK ("reviewStatus" IN ('pending','approved','rejected')),
  "reviewReason" text NOT NULL DEFAULT '',
  "onShelf" boolean NOT NULL DEFAULT false,
  "autoRule" jsonb NOT NULL DEFAULT '{}',
  "customEnabled" boolean NOT NULL DEFAULT false,
  "sizeChart" jsonb NOT NULL DEFAULT '[]',
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  CHECK (NOT "onShelf" OR (stage = 'shelf' AND "reviewStatus" = 'approved'))
);
CREATE INDEX products_catalog ON public.products ("categoryId") WHERE stage='shelf' AND "reviewStatus"='approved' AND "onShelf";
CREATE TABLE public.skus (
  _id text PRIMARY KEY,
  "productId" text NOT NULL REFERENCES public.products(_id),
  color text NOT NULL,
  size text NOT NULL,
  pattern text NOT NULL,
  stock integer NOT NULL CHECK (stock >= 0),
  reserved integer NOT NULL DEFAULT 0 CHECK (reserved >= 0 AND reserved <= stock),
  UNIQUE ("productId",color,size,pattern)
);
CREATE TABLE public.carts (
  _id text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "userId" text NOT NULL REFERENCES public.users(_id),
  "skuId" text NOT NULL REFERENCES public.skus(_id),
  qty integer NOT NULL CHECK (qty BETWEEN 1 AND 99),
  selected boolean NOT NULL DEFAULT true,
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  UNIQUE ("userId","skuId")
);
CREATE TABLE public.addresses (
  _id text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "userId" text NOT NULL REFERENCES public.users(_id),
  name text NOT NULL,
  phone text NOT NULL CHECK (phone ~ '^1[0-9]{10}$'),
  region text NOT NULL,
  detail text NOT NULL,
  "isDefault" boolean NOT NULL DEFAULT false
);
CREATE INDEX addresses_owner ON public.addresses ("userId");
CREATE UNIQUE INDEX address_one_default ON public.addresses ("userId") WHERE "isDefault";
CREATE TABLE public.gift_items (
  _id text PRIMARY KEY,
  name text NOT NULL,
  image text NOT NULL,
  "freightMode" text NOT NULL CHECK ("freightMode" IN ('template','free')),
  "freightTemplateId" text REFERENCES public.freight_templates(_id),
  enabled boolean NOT NULL DEFAULT true
);
CREATE TABLE public.gift_stock (
  _id text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "giftItemId" text NOT NULL REFERENCES public.gift_items(_id),
  size text NOT NULL,
  stock integer NOT NULL CHECK (stock >= 0),
  reserved integer NOT NULL DEFAULT 0 CHECK (reserved >= 0 AND reserved <= stock),
  UNIQUE ("giftItemId",size)
);
CREATE TABLE public.coupons (
  _id text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "userId" text NOT NULL REFERENCES public.users(_id),
  month text NOT NULL CHECK (month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  status text NOT NULL DEFAULT 'unused' CHECK (status IN ('unused','used','expired')),
  "orderId" text,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  UNIQUE ("userId",month)
);
CREATE TABLE public.orders (
  _id text PRIMARY KEY,
  "userId" text NOT NULL REFERENCES public.users(_id),
  "requestKey" text NOT NULL,
  items jsonb NOT NULL CHECK (jsonb_typeof(items)='array' AND jsonb_array_length(items)>0),
  "goodsAmount" bigint NOT NULL CHECK ("goodsAmount" BETWEEN 0 AND 9007199254740991),
  "discountAmount" bigint NOT NULL DEFAULT 0 CHECK ("discountAmount" >= 0 AND "discountAmount" <= "goodsAmount"),
  "freightAmount" bigint NOT NULL CHECK ("freightAmount" BETWEEN 0 AND 9007199254740991),
  "payAmount" bigint NOT NULL CHECK ("payAmount" BETWEEN 0 AND 9007199254740991),
  "balancePaid" bigint NOT NULL DEFAULT 0 CHECK ("balancePaid" >= 0),
  "wxPaid" bigint NOT NULL DEFAULT 0 CHECK ("wxPaid" >= 0),
  "useBalance" boolean NOT NULL DEFAULT true,
  address jsonb NOT NULL CHECK (jsonb_typeof(address)='object'),
  remark text NOT NULL DEFAULT '',
  status text NOT NULL DEFAULT 'pending_pay' CHECK (status IN ('pending_pay','pending_ship','pending_recv','done','cancelled','refunding','refunded')),
  "isGift" boolean NOT NULL DEFAULT false,
  "giftItemId" text REFERENCES public.gift_items(_id),
  "couponId" text REFERENCES public.coupons(_id),
  "isCustom" boolean NOT NULL DEFAULT false,
  "customDetail" jsonb,
  "customReview" text CHECK ("customReview" IN ('pending','approved','rejected')),
  "customRejectReason" text NOT NULL DEFAULT '',
  "expressCompany" text NOT NULL DEFAULT '',
  "expressNo" text NOT NULL DEFAULT '',
  "refundReason" text NOT NULL DEFAULT '',
  "refundPreviousStatus" text,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "payDeadline" timestamptz NOT NULL,
  "paidAt" timestamptz,
  "cancelledAt" timestamptz,
  version bigint NOT NULL DEFAULT 0,
  UNIQUE ("userId","requestKey"),
  CHECK ("payAmount" = "goodsAmount" - "discountAmount" + "freightAmount"),
  CHECK (("isCustom" AND "customDetail" IS NOT NULL AND "customReview" IS NOT NULL) OR (NOT "isCustom" AND "customDetail" IS NULL AND "customReview" IS NULL)),
  CHECK (NOT "isGift" OR ("giftItemId" IS NOT NULL AND "couponId" IS NOT NULL AND "goodsAmount"=0)),
  CHECK ("balancePaid" + "wxPaid" <= "payAmount")
);
ALTER TABLE public.coupons ADD CONSTRAINT coupons_order_fk FOREIGN KEY ("orderId") REFERENCES public.orders(_id);
CREATE INDEX orders_owner_created ON public.orders ("userId","createdAt" DESC);
CREATE INDEX orders_unpaid_deadline ON public.orders ("payDeadline") WHERE status='pending_pay';
CREATE TABLE public.order_items (
  _id text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "orderId" text NOT NULL REFERENCES public.orders(_id),
  "productId" text REFERENCES public.products(_id),
  "skuId" text REFERENCES public.skus(_id),
  "giftStockId" text REFERENCES public.gift_stock(_id),
  name text NOT NULL,
  image text NOT NULL,
  color text NOT NULL DEFAULT '',
  size text NOT NULL,
  pattern text NOT NULL DEFAULT '',
  price bigint NOT NULL CHECK (price BETWEEN 0 AND 9007199254740991),
  qty integer NOT NULL CHECK (qty BETWEEN 1 AND 99),
  CHECK (("skuId" IS NOT NULL)::integer + ("giftStockId" IS NOT NULL)::integer = 1)
);
CREATE INDEX order_items_order ON public.order_items ("orderId");
CREATE TABLE public.balance_logs (
  _id text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "userId" text NOT NULL REFERENCES public.users(_id),
  type text NOT NULL CHECK (type IN ('recharge','pay','refund_in','refund_out','admin_adjust')),
  amount bigint NOT NULL CHECK (amount BETWEEN -9007199254740991 AND 9007199254740991),
  "orderId" text REFERENCES public.orders(_id),
  "dedupeKey" text NOT NULL UNIQUE,
  "balanceAfter" bigint NOT NULL CHECK ("balanceAfter" >= 0),
  "operatorId" text,
  remark text NOT NULL DEFAULT '',
  "createdAt" timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX balance_logs_owner_created ON public.balance_logs ("userId","createdAt" DESC);
CREATE TABLE public.recharge_records (
  _id text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  "userId" text NOT NULL REFERENCES public.users(_id),
  "tierId" text NOT NULL REFERENCES public.recharge_tiers(_id),
  amount bigint NOT NULL CHECK (amount > 0),
  level smallint NOT NULL CHECK (level IN (1,2)),
  "requestKey" text NOT NULL,
  "termsVersion" text NOT NULL,
  "balanceLogId" text NOT NULL UNIQUE REFERENCES public.balance_logs(_id),
  simulated boolean NOT NULL DEFAULT true CHECK (simulated),
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  UNIQUE ("userId","requestKey")
);
CREATE TABLE public.gift_allocations (
  "orderId" text PRIMARY KEY REFERENCES public.orders(_id),
  "giftStockId" text NOT NULL REFERENCES public.gift_stock(_id),
  "giftItemId" text NOT NULL REFERENCES public.gift_items(_id),
  "userId" text NOT NULL REFERENCES public.users(_id),
  size text NOT NULL,
  "createdAt" timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.custom_config (
  _id text PRIMARY KEY CHECK (_id='global'),
  "galleryUrl" text NOT NULL DEFAULT '',
  positions jsonb NOT NULL CHECK (jsonb_typeof(positions)='array')
);
CREATE TABLE public.banners (_id text PRIMARY KEY, image text NOT NULL, link text NOT NULL DEFAULT '', sort integer NOT NULL DEFAULT 0, visible boolean NOT NULL DEFAULT true);
CREATE TABLE public.home_picks ("productId" text PRIMARY KEY REFERENCES public.products(_id), sort integer NOT NULL DEFAULT 0);
CREATE TABLE public.announcements (_id text PRIMARY KEY, text text NOT NULL, link text NOT NULL DEFAULT '', sort integer NOT NULL DEFAULT 0, visible boolean NOT NULL DEFAULT true);
CREATE TABLE public.faqs (_id text PRIMARY KEY, question text NOT NULL, answer text NOT NULL, sort integer NOT NULL DEFAULT 0, visible boolean NOT NULL DEFAULT true);
CREATE TABLE public.settings (
  _id text PRIMARY KEY CHECK (_id='global'),
  "shopName" text NOT NULL,
  "servicePhone" text NOT NULL DEFAULT '',
  "serviceHours" text NOT NULL DEFAULT '',
  "notifyEmail" text NOT NULL DEFAULT '',
  "couponIssueDay" integer NOT NULL DEFAULT 1 CHECK ("couponIssueDay" BETWEEN 1 AND 28),
  "giftEmptySizeMode" text NOT NULL DEFAULT 'grey' CHECK ("giftEmptySizeMode" IN ('grey','hidden')),
  "smsEnabled" boolean NOT NULL DEFAULT false CHECK (NOT "smsEnabled"),
  "smsKeys" jsonb NOT NULL DEFAULT '{}' CHECK ("smsKeys"='{}'::jsonb),
  "wxpayKeys" jsonb NOT NULL DEFAULT '{}' CHECK ("wxpayKeys"='{}'::jsonb),
  "realPaymentEnabled" boolean NOT NULL DEFAULT false CHECK (NOT "realPaymentEnabled"),
  "memberRules" jsonb NOT NULL,
  notices jsonb NOT NULL DEFAULT '[]',
  "sizeChart" jsonb NOT NULL DEFAULT '[]',
  "paymentTimeoutMinutes" integer NOT NULL DEFAULT 30 CHECK ("paymentTimeoutMinutes">0),
  "announcementIntervalSeconds" integer NOT NULL DEFAULT 5 CHECK ("announcementIntervalSeconds">0)
);
CREATE TABLE public.admins (_id text PRIMARY KEY DEFAULT gen_random_uuid()::text, username text NOT NULL UNIQUE, "passwordHash" text NOT NULL, role text NOT NULL CHECK (role IN ('owner','operator')));
-- Server-only access: table-level grants AND RLS. No client-facing policies.
DO $security$
DECLARE table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY['users','member_accounts','recharge_tiers','categories','freight_templates','products','skus','carts','addresses','gift_items','gift_stock','coupons','orders','order_items','balance_logs','recharge_records','gift_allocations','custom_config','banners','home_picks','announcements','faqs','settings','admins'] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', table_name);
    EXECUTE format('REVOKE ALL ON TABLE public.%I FROM PUBLIC, anon, authenticated', table_name);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', table_name);
  END LOOP;
END
$security$;
