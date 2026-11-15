create function bartov_food.check_order_assignment() returns trigger
  language plpgsql 
  set search_path = bartov_food, pg_catalog 
  as $$
begin
  --проверка, что назначенный курьер не уволен
  if tg_op = 'INSERT' or new.courier_id is distinct from old.courier_id then
    perform 1 
    from courier
    where courier_id = new.courier_id 
      and status <> 'уволен' for share;

    if not found then
      raise exception 'Pаказ не может быть зазначен уволенному курьеру.';
    end if;
  end if;
  return new;
end;
$$;
create trigger order_assignment
before insert or update of courier_id on bartov_food."order"
for each row execute function bartov_food.check_order_assignment();

create function bartov_food.check_order_client_address() returns trigger
  language plpgsql 
  set search_path = bartov_food, pg_catalog 
  as $$
begin
  --добавляем проверку связи адреса и клиента, при изменени этих полей
  if tg_op = 'INSERT' or (new.client_id, new.address_id) is distinct from (old.client_id, old.address_id) then
    perform 1 
    from client_address
    where client_id = new.client_id
      and address_id = new.address_id for key share;

    if not found then
      raise exception 'адрес доставки должен принадлежать клиенту.';
    end if;
  end if;
  return new;
end;
$$;
create trigger order_client_address
before insert or update of client_id, address_id on bartov_food."order"
for each row execute function bartov_food.check_order_client_address();

create function bartov_food.check_order_state(p_order_id uuid) returns void
  language plpgsql 
  set search_path = bartov_food, pg_catalog 
  as $$
declare
  saved_order "order"%rowtype;
  food_amount numeric;
begin
  select * 
  into saved_order 
  from "order" 
  where order_id = p_order_id for update;

  if not found then
    return;
  end if;

  --Все блюда должны находиться у удного ресторана
  if exists (
    select 1 
    from order_structure os
        ,product p
    where os.product_id = p.product_id
      and os.order_id = p_order_id 
      and p.restaurant_id <> saved_order.restaurant_id
  ) then
    raise exception 'Все блюда заказа должны принадлжать одному ресторану.';
  end if;

  select round(sum(unit_price), 2)
  into food_amount
  from order_structure 
  where order_id = p_order_id;

  --сумма заказа должна соответсвовать всем позициям в заказе
  if food_amount is null then
    raise exception 'Заказ % должен содержать хотя бы одно блюдо: удаление последней позиции без удаления заказа запрещено.', p_order_id;
  elsif food_amount <> saved_order.order_amount then
    raise exception 'Сумма позиций заказа % не совпадает с order_amount: фактически %, в заказе %.',
      p_order_id, food_amount, saved_order.order_amount;
  end if;
end;
$$;

create function bartov_food.check_order_row() returns trigger
  language plpgsql 
  set search_path = bartov_food, pg_catalog 
  as $$
begin
  perform check_order_state(new.order_id);
  return null;
end;
$$;
create constraint trigger order_integrity
after insert or update on bartov_food."order"
deferrable initially deferred for each row
execute function bartov_food.check_order_row();

create function bartov_food.check_order_lines() returns trigger
  language plpgsql 
  set search_path = bartov_food, pg_catalog 
  as $$
begin
  if tg_op <> 'INSERT' then
    perform check_order_state(old.order_id);
  end if;

  if tg_op <> 'DELETE' then
    perform check_order_state(new.order_id);
  end if;
  return null;
end;
$$;
create constraint trigger order_lines_integrity
after insert or update or delete on bartov_food.order_structure
deferrable initially deferred for each row
execute function bartov_food.check_order_lines();

create function bartov_food.check_product_restaurant() returns trigger
  language plpgsql 
  set search_path = bartov_food, pg_catalog 
  as $$
begin
  if new.restaurant_id is distinct from old.restaurant_id 
    and exists (
        select 1 
        from order_structure 
        where product_id = old.product_id
    ) then
    raise exception 'Нельзя менять ресторан у уже заказанного блюда.';
  end if;
  return new;
end;
$$;
create trigger product_restaurant_history
before update of restaurant_id on bartov_food.product for each row
execute function bartov_food.check_product_restaurant();

create function bartov_food.get_expected_order_status(p_order_id uuid) returns bartov_food.order_pay_status
  language plpgsql 
  set search_path = bartov_food, pg_catalog 
  as $$
declare
  expected_status order_pay_status;
begin
  if exists (
      select 1
      from payment
      where order_id = p_order_id
        and status = 'успех'
  ) then
    expected_status = 'оплачен'::order_pay_status;
  elsif exists (
      select 1
      from payment
      where order_id = p_order_id
        and status = 'в_обработке'
  ) then
    expected_status = 'ожидает'::order_pay_status;
  elsif exists (
      select 1
      from payment
      where order_id = p_order_id
  ) and not exists (
      select 1
      from payment
      where order_id = p_order_id
        and status <> 'ошибка'
  ) then
    expected_status = 'ошибка'::order_pay_status;
  else
    expected_status = 'ожидает'::order_pay_status;
  end if;

  return expected_status;
end;
$$;

create function bartov_food.check_payment_state(p_order_id uuid) returns void
  language plpgsql 
  set search_path = bartov_food, pg_catalog 
  as $$
declare
  saved_order     "order"%rowtype;
  expected_status order_pay_status;
begin
  select * 
  into saved_order 
  from "order" 
  where order_id = p_order_id for update;

  if not found then
      return;
  end if;

  if exists (
      select 1 
      from payment 
      where order_id = p_order_id 
        and amount <> saved_order.total_amount
  ) then
      raise exception 'Сумма платежа должна соответсвовать итоговой сумме заказа.';
  end if;

  expected_status := get_expected_order_status(p_order_id);

  if saved_order.pay_status <> expected_status then
    raise exception 'Статус оплаты заказа не соответсвует статусам платежей.';
  end if;
end;
$$;

create function bartov_food.check_payment_row() returns trigger
  language plpgsql 
  set search_path = bartov_food, pg_catalog 
  as $$
begin
  if tg_op <> 'INSERT' then
    perform check_payment_state(old.order_id);
  end if;
  if tg_op <> 'DELETE' then
    perform check_payment_state(new.order_id);
  end if;
  return null;
end;
$$;
create constraint trigger payment_integrity
after insert or update or delete on bartov_food.payment
deferrable initially deferred for each row
execute function bartov_food.check_payment_row();

create function bartov_food.check_order_payments() returns trigger
  language plpgsql 
  set search_path = bartov_food, pg_catalog 
  as $$
begin
  perform check_payment_state(new.order_id);
  return null;
end;
$$;
create constraint trigger order_payment_integrity
after insert or update on bartov_food."order"
deferrable initially deferred for each row
execute function bartov_food.check_order_payments();

create function bartov_food.validate_review() returns trigger
  language plpgsql 
  set search_path = bartov_food, pg_catalog 
  as $$
declare
  reviewed_order "order"%rowtype;
begin
  select * 
  into reviewed_order 
  from "order" 
  where order_id = new.order_id;
  
  if reviewed_order.client_id <> new.client_id then
    raise exception 'Отзыв должен быть написан заказавшим клиентом.';
  end if;

  if new.entity_type = 'заказ' and new.entity_id <> new.order_id then
    raise exception 'Отзыв на заказ должен соответсвовать заказу';
  elsif new.entity_type = 'ресторан' and new.entity_id <> reviewed_order.restaurant_id then
      raise exception 'Отзыв на ресторан должен соответсвовать ресторану в заказе';
  elsif new.entity_type = 'блюдо' and not exists (
    select 1 
    from order_structure
    where order_id = new.order_id 
      and product_id = new.entity_id
  ) then
      raise exception 'Отзыв на блюдо должен соответсвовать блюду в заказе.';
  end if;
  return new;
end;
$$;
create trigger review_target
before insert or update on bartov_food.review for each row
execute function bartov_food.validate_review();

create function bartov_food.protect_reviewed_line() returns trigger
  language plpgsql 
  set search_path = bartov_food, pg_catalog 
  as $$
begin
  if tg_op = 'DELETE'
    or new.product_id is distinct from old.product_id
    or new.order_id is distinct from old.order_id then
    if exists (
        select 1 
        from review 
        where order_id = old.order_id
          and entity_type = 'блюдо'
          and entity_id = old.product_id
    ) then
        raise exception 'Нельзя удалить или переназначить блюдо % в заказе %: на него есть отзыв.', old.product_id, old.order_id;
    end if;
  end if;
  
  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;
create trigger reviewed_line_history
before update or delete on bartov_food.order_structure for each row
execute function bartov_food.protect_reviewed_line();

create function bartov_food.protect_reviewed_order() returns trigger
  language plpgsql 
  set search_path = bartov_food, pg_catalog 
  as $$
begin
  if (new.restaurant_id is distinct from old.restaurant_id
    or new.client_id is distinct from old.client_id)
    and exists (
      select 1 
      from review 
      where order_id = old.order_id
    ) then
    raise exception 'Запрещено изменять клиента и реторан у заказа с отзывом';
  end if;

  return new;
end;
$$;
create trigger reviewed_order_history
before update of restaurant_id, client_id on bartov_food."order" for each row
execute function bartov_food.protect_reviewed_order();

create function bartov_food.rating_change() returns trigger
  language plpgsql 
  set search_path = bartov_food, pg_catalog 
  as $$
declare
  l_rating numeric(4, 2);
begin
  
  if tg_op <> 'INSERT' then
    select round(avg(rating), 2)
    into l_rating
    from review
    where entity_type = old.entity_type
      and entity_id = old.entity_id;

    if old.entity_type = 'блюдо' then
        update product 
        set rating = l_rating
        where product_id = old.entity_id;
    elsif old.entity_type = 'ресторан' then
        update restaurant 
        set rating = l_rating
        where restaurant_id = old.entity_id;
    end if;
  end if;

  if tg_op <> 'DELETE' then
    select round(avg(rating), 2)
    into l_rating
    from review
    where entity_type = new.entity_type
      and entity_id = new.entity_id;

    if new.entity_type = 'блюдо' then
        update product
        set rating = l_rating
        where product_id = new.entity_id;
    elsif new.entity_type = 'ресторан' then
        update restaurant 
        set rating = l_rating 
        where restaurant_id = new.entity_id;
    end if;
  end if;
  return null;
end;
$$;
create trigger review_rating_change
after insert or update or delete on bartov_food.review for each row
execute function bartov_food.rating_change();
