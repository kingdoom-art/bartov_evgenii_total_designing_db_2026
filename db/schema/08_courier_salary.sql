create or replace procedure bartov_food.courier_salary()
  language plpgsql
  set search_path = bartov_food, pg_catalog
  as $$
declare
  month_start       date := date_trunc('month', current_date)::date;
  saved_year        int := extract(year from current_date)::int;
  saved_month       int := extract(month from current_date)::int;
  saved_coefficient numeric(3, 1);
  next_coefficient  numeric(3, 1);
  rec               record;
begin
  --блокируем курьеров для пересчета
  perform 1 from courier order by courier_id for update;

  --собираем выполненные закзы курьеров в текущем месяце (не уволенных)
  for rec in
    select c.courier_id
          ,c.status
          ,c.coefficient
          ,count(o.order_id) deliveries
          ,coalesce(sum(o.commission), 0) commissions
    from courier c
        left join "order" o 
          on o.courier_id = c.courier_id
          and o.status = 'доставлен'
          and o.order_timestamp >= month_start
          and o.order_timestamp < month_start + interval '1 month'
    group by c.courier_id
  loop
    --получаем коеф на текущий момент
    select coefficient_used 
    into saved_coefficient
    from courier_pay
    where year = saved_year 
      and month = saved_month 
      and courier_id = rec.courier_id;

    --курьер только начал работать - дефолтный коеф
    if not found then
      saved_coefficient := rec.coefficient;
    end if;

    next_coefficient := case when rec.deliveries > 500 then 0.5
                             when rec.deliveries > 250 then 0.3
                             when rec.deliveries > 150 then 0.2
                             else 0.1 end;

    --исключим ситуациюуже расчитанного коефа и апдейтим его при конфликте
    insert into courier_pay (year, month, courier_id, amount, coefficient_used)
    values (saved_year, saved_month, rec.courier_id, round(rec.commissions * saved_coefficient, 2), saved_coefficient)
    on conflict (year, month, courier_id) do 
    update
    set amount = excluded.amount
       ,coefficient_used = excluded.coefficient_used;

    --уволенным не назначаем коеф на следующий месяц
    if rec.status <> 'уволен' then
      update courier 
      set coefficient = next_coefficient
      where courier_id = rec.courier_id;
    end if;
  end loop;
end;
$$;
