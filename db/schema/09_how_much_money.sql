create or replace view bartov_food.how_much_money as
with recursive order_months as (
  select date_trunc('month', o.order_timestamp)::date month_start
        ,sum(o.order_amount) sum_no_commission
        ,sum(o.total_amount) sum_with_commission
  from bartov_food."order" o
  where o.status = 'доставлен'
  group by 1
), month_bounds as (
  select min(month_start) first_month
        ,max(month_start) last_month
  from order_months
), months(month_start) as (
  select first_month 
  from month_bounds 
  where first_month is not null
  union all
  select (m.month_start + interval '1 month')::date
  from months m
      ,month_bounds b
  where m.month_start < b.last_month
), pay_months as (
  select make_date(cp.year, cp.month, 1) month_start
        ,sum(cp.amount) courier_pay
  from bartov_food.courier_pay cp
  group by 1
), monthly as (
  select m.month_start
        ,coalesce(o.sum_no_commission, 0::numeric) sum_no_commission
        ,coalesce(o.sum_with_commission, 0::numeric) sum_with_commission
        ,coalesce(o.sum_with_commission, 0::numeric) - coalesce(o.sum_no_commission, 0::numeric) commission
        ,coalesce(p.courier_pay, 0::numeric) courier_pay
  from months m
      left join order_months o 
        on o.month_start = m.month_start
      left join pay_months p 
        on p.month_start = m.month_start
), with_previous as (
  select monthly.*
        ,lag(commission) over (order by month_start) prev_commission
  from monthly
)
select to_char(month_start, 'YYYY-MM') year_month
      ,sum_no_commission
      ,sum_with_commission
      ,commission
      ,prev_commission
      ,commission - prev_commission commission_diff
      ,courier_pay
      ,commission - courier_pay net_profit
from with_previous;
