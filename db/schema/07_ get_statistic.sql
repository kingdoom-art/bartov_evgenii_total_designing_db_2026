create or replace function bartov_food.get_statistic()
  returns table (restaurant_name    text
                ,best_product_name  text
                ,total_amount       numeric
                ,avg_amount         numeric
                ,best_user          text
                )
  language sql
  set search_path = bartov_food, pg_catalog
  as $$
  with delivered_orders as materialized (
    select order_id
          ,restaurant_id
          ,client_id
          ,total_amount
    from "order"
    where status = 'доставлен'
  ), amounts as (
    select restaurant_id
          ,sum(total_amount) total_amount
          ,avg(total_amount) as avg_amount
    from delivered_orders
    group by restaurant_id
  ), product_sales as (
    select o.restaurant_id
          ,os.product_id
          ,sum(os.quantity) quantity
    from delivered_orders o
        ,order_structure os 
    where os.order_id = o.order_id
    group by o.restaurant_id, os.product_id
  ), best_products as (
    select distinct on (ps.restaurant_id) ps.restaurant_id
          ,p.product_name
    from product_sales ps
        ,product p 
    where p.product_id = ps.product_id
    order by ps.restaurant_id, ps.quantity desc, random()
  ), user_orders as (
    select restaurant_id
          ,client_id
          ,count(*) orders_count
    from delivered_orders
    group by restaurant_id, client_id
  ), best_users as (
    select distinct on (uo.restaurant_id) uo.restaurant_id
          ,c.login
    from user_orders uo
        ,client c
    where c.client_id = uo.client_id
    order by uo.restaurant_id, uo.orders_count desc, random()
  )
  select r.restaurant_name::text
        ,bp.product_name::text
        ,a.total_amount
        ,a.avg_amount
        ,bu.login::text
  from restaurant r
      left join amounts a 
        on a.restaurant_id = r.restaurant_id
      left join best_products bp 
        on bp.restaurant_id = r.restaurant_id
      left join best_users bu 
        on bu.restaurant_id = r.restaurant_id;
$$;
