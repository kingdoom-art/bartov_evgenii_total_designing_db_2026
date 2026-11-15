-- пересчитываем статус заказа после изменения попыток оплат
create function bartov_food.refresh_payment_status(p_order_id uuid) returns void
  language plpgsql
  set search_path = bartov_food, pg_catalog, pg_temp
  as $$
declare
  expected_status order_pay_status;
begin
  expected_status := get_expected_order_status(p_order_id);

  update "order"
  set pay_status = expected_status
  where order_id = p_order_id;
end;
$$;

-- создаём попытку и синхронизируем статус в одной транзакции
create function bartov_food.create_payment(p_order_id               uuid
                                          ,p_type                   bartov_food.payment_type
                                          ,p_amount                 numeric
                                          ,p_transaction_reference  varchar
                                          ,p_status                 bartov_food.payment_status
                                          ,p_transaction_timestamp  timestamp default localtimestamp
                                          ) returns bartov_food.payment
  language plpgsql
  security definer
  set search_path = bartov_food, pg_catalog, pg_temp
  as $$
declare
  saved_payment payment%rowtype;
begin
  perform 1 
  from "order" 
  where order_id = p_order_id for update;

  if not found then
    raise exception 'Не найден заказ для оплаты: %', p_order_id;
  end if;

  insert into payment (order_id, type, amount, transaction_reference, status, transaction_timestamp)
  values (p_order_id, p_type, p_amount, p_transaction_reference, p_status, p_transaction_timestamp)
  returning * into saved_payment;

  perform refresh_payment_status(p_order_id);
  return saved_payment;
end;
$$;

-- меняем попытку; при переносе пересчитываем оба заказа
create function bartov_food.update_payment(p_payment_id             uuid
                                          ,p_order_id               uuid
                                          ,p_type                   bartov_food.payment_type
                                          ,p_amount                 numeric
                                          ,p_transaction_reference  varchar
                                          ,p_status                 bartov_food.payment_status
                                          ,p_transaction_timestamp  timestamp default localtimestamp
                                          ) returns bartov_food.payment
  language plpgsql
  security definer
  set search_path = bartov_food, pg_catalog, pg_temp
  as $$
declare
  old_order_id        uuid;
  previous_order_id   uuid;
  locked_order_id     uuid;
  saved_payment       payment%rowtype;
begin
  select order_id
  into old_order_id
  from payment 
  where payment_id = p_payment_id;

  if not found then
    raise exception 'Попытка оплаты не найдена: %', p_payment_id;
  end if;

  previous_order_id := old_order_id;

  --блокируем заказы
  for locked_order_id in
    select order_id 
    from (select old_order_id as order_id
          union 
          select p_order_id
        ) tmp 
    order by order_id
  loop
    perform 1 
    from "order" 
    where order_id = locked_order_id for update;

    if not found then
      raise exception 'Заказ для оплаты не найден: %', locked_order_id;
    end if;
  end loop;

  select order_id 
  into old_order_id
  from payment 
  where payment_id = p_payment_id for update;

  if not found then
    raise exception 'Попытка оплаты не найдена: %', p_payment_id;
  end if;
  
  --если заказ у платежа был изменен - тут больше делать нечего
  if old_order_id <> previous_order_id then
    raise exception 'Попытка оплаты была перенесена: %', p_payment_id;
  end if;

  update payment
  set order_id = p_order_id,
      type = p_type,
      amount = p_amount,
      transaction_reference = p_transaction_reference,
      status = p_status,
      transaction_timestamp = p_transaction_timestamp
  where payment_id = p_payment_id
  returning * into saved_payment;

  perform refresh_payment_status(old_order_id);

  --если заказ менялся - обновим статус у предыдущего
  if p_order_id <> old_order_id then
    perform refresh_payment_status(p_order_id);
  end if;
  return saved_payment;
end;
$$;

-- удаляем попытку; без попыток заказ опять ожидает оплату
create function bartov_food.delete_payment(p_payment_id uuid) returns bartov_food.payment
  language plpgsql
  security definer
  set search_path = bartov_food, pg_catalog, pg_temp
  as $$
declare
  saved_payment payment%rowtype;
begin
  select * 
  into saved_payment
  from payment 
  where payment_id = p_payment_id;

  if not found then
    raise exception 'Попытка оплаты не найдена: %', p_payment_id;
  end if;

  perform 1 
  from "order" 
  where order_id = saved_payment.order_id for update;

  delete from payment
  where payment_id = p_payment_id 
    and order_id = saved_payment.order_id;

  if not found then
    raise exception 'Попытка оплаты была перенесена: %', p_payment_id;
  end if;

  perform refresh_payment_status(saved_payment.order_id);
  return saved_payment;
end;
$$;

--запрет работы с платежами без исспользования функций (в них содержится бизнес-логика)
revoke insert, update, delete on bartov_food.payment from public;
--запрет работы со статусом заказа, он расчитывается самомтоятельно при работе с платежами
revoke update (pay_status) on bartov_food."order" from public;
