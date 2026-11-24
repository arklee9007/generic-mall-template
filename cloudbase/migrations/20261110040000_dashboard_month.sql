-- B-08 看板补统计：本月销售额、本月退款金额、今日退款金额（口径与既有今日数一致，上海时区）
CREATE OR REPLACE FUNCTION public.mall_admin_dashboard() RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER
SET search_path=public,pg_temp AS $$
  SELECT jsonb_build_object(
    'todayOrders',(SELECT count(*) FROM orders WHERE "createdAt">=date_trunc('day',now() AT TIME ZONE 'Asia/Shanghai') AT TIME ZONE 'Asia/Shanghai'),
    'todaySales',coalesce((SELECT sum("payAmount") FROM orders WHERE "paidAt">=date_trunc('day',now() AT TIME ZONE 'Asia/Shanghai') AT TIME ZONE 'Asia/Shanghai'),0),
    'todayRefunds',coalesce((SELECT sum("balanceAmount"+"originalAmount") FROM admin_refunds WHERE "createdAt">=date_trunc('day',now() AT TIME ZONE 'Asia/Shanghai') AT TIME ZONE 'Asia/Shanghai'),0),
    'monthSales',coalesce((SELECT sum("payAmount") FROM orders WHERE "paidAt">=date_trunc('month',now() AT TIME ZONE 'Asia/Shanghai') AT TIME ZONE 'Asia/Shanghai'),0),
    'monthRefunds',coalesce((SELECT sum("balanceAmount"+"originalAmount") FROM admin_refunds WHERE "createdAt">=date_trunc('month',now() AT TIME ZONE 'Asia/Shanghai') AT TIME ZONE 'Asia/Shanghai'),0),
    'pendingShip',(SELECT count(*) FROM orders WHERE status='pending_ship'),
    'checkedAt',now());
$$;
