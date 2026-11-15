create or replace procedure bartov_food.insert_test_data(value int)
  language plpgsql
  set search_path = bartov_food, pg_catalog, pg_temp
  as $procedure$
declare
  clients               uuid[] := array[]::uuid[];
  couriers              uuid[] := array[]::uuid[];
  categories            uuid[] := array[]::uuid[];
  restaurants           uuid[] := array[]::uuid[];
  restaurant_addresses  uuid[] := array[]::uuid[];
  client_addresses      uuid[] := array[]::uuid[];
  products              uuid[] := array[]::uuid[];
  restaurant_products   uuid[];
  i                     int;
  j                     int;
  client_index          int;
  restaurant_index      int;
  payment_count          int;
  payment_offset         int;
begin
  if value is null or value <= 0 or value > 200000000 then
    raise exception 'value должно быть положительным и не вызывать переполнение: %', value;
  end if;

  --генерация рандомного числа с возможностью избегания 0
  execute $ddl$
    create or replace function pg_temp.get_random_int(p_min int, p_max int) returns int
      language sql 
      as $$
      select p_min + floor(random() * (p_max - p_min + 1))::int;
    $$;
  $ddl$;

  --генерация буквенно-численной строки
  execute $ddl$
    create or replace function pg_temp.get_random_string(p_length int) returns text
      language sql 
      as $$
      select left(repeat(md5(random()::text), (p_length + 31) / 32), p_length);
    $$;
  $ddl$;

  --генерация числовой строки
  execute $ddl$
    create or replace function pg_temp.get_random_digits(p_length int) returns text
      language sql 
      as $$
      select string_agg(floor(random() * 10)::int::text, '' order by n)
      from generate_series(1, p_length) n;
    $$;
  $ddl$;

  --генерация буквенной строки
  execute $ddl$
    create or replace function pg_temp.get_random_letters(p_length int) returns text
      language sql 
      as $$
      select string_agg(chr(97 + floor(random() * 26)::int), '' order by n)
      from generate_series(1, p_length) n;
    $$;
  $ddl$;

  -- Генерация урл
  execute $ddl$
    create or replace function pg_temp.get_random_photo_url() returns text
      language plpgsql 
      set search_path = bartov_food, pg_catalog, pg_temp 
      as $$
    declare 
      host text;
      zone text;
      image_name text;
    begin
      host := pg_temp.get_random_letters(12);
      zone := pg_temp.get_random_letters(3);
      image_name := pg_temp.get_random_string(32);
      
      return 'https://' || host || '.' || zone || '/' || image_name || '.jpg';
    end;
    $$;
  $ddl$;

  --генерация дат в промежутке 6 месяцев
  execute $ddl$
    create or replace function pg_temp.get_random_timestamp() returns timestamp
      language sql 
      as $$
      select localtimestamp - random() *
        (localtimestamp - greatest(date_trunc('month', current_date - interval '5 months'),
                                     localtimestamp - interval '179 days'));
    $$;
  $ddl$;

  -- расчет коефицента для курьера
  execute $ddl$
    create or replace function pg_temp.get_random_next_coefficient(p_deliveries bigint) returns numeric(3, 1) 
      language sql 
      as $$
      select case when p_deliveries > 500 then 0.5
                  when p_deliveries > 250 then 0.3
                  when p_deliveries > 150 then 0.2 
                  else 0.1 end::numeric(3, 1);
    $$;
  $ddl$;

  execute $ddl$
    create or replace function pg_temp.ins_product_category() returns uuid
      language plpgsql 
      set search_path = bartov_food, pg_catalog, pg_temp 
      as $$
    declare 
      saved_id    uuid;
      saved_name  text;
    begin
      saved_name := pg_temp.get_random_string(24);

      insert into product_category (product_category_name)
      values (saved_name) 
      returning product_category_id into saved_id;

      return saved_id;
    end;
    $$;
  $ddl$;

  execute $ddl$
    create or replace function pg_temp.ins_address() returns uuid
      language plpgsql 
      set search_path = bartov_food, pg_catalog, pg_temp 
      as $$
    declare 
      saved_id          uuid;
      saved_street      text;
      saved_house       text;
      saved_apartment   text;
    begin
      saved_street := pg_temp.get_random_string(32);
      saved_house := pg_temp.get_random_int(1, 200)::text;

      --квартира либо непустая, либо разрешённый NULL.
      if random() < 0.5 then
        saved_apartment := pg_temp.get_random_int(1, 300)::text;
      end if;

      insert into address (street, house_number, apartment_office)
      values (saved_street, saved_house, saved_apartment) 
      returning address_id into saved_id;

      return saved_id;
    end;
    $$;
  $ddl$;

  execute $ddl$
    create or replace function pg_temp.ins_client() returns uuid
      language plpgsql 
      set search_path = bartov_food, pg_catalog, pg_temp 
      as $$
    declare saved_id  uuid;
      saved_login     text;
      saved_password  text;
      saved_phone     text;
      domain_name     text;
      domain_zone     text;
    begin
      --создание клиента всемы правдами и неправдами (при дубле повторяем)
      loop
        domain_name := pg_temp.get_random_letters(10);
        domain_zone := pg_temp.get_random_letters(3);
        saved_login := replace(exts.uuid_generate_v4()::text, '-', '') || '@' ||domain_name || '.' || domain_zone;

        saved_password := md5(random()::text);
        saved_phone := '7' || pg_temp.get_random_digits(10);

        insert into client (login, password, phone_number)
        values (saved_login, saved_password, saved_phone)
        on conflict do nothing returning client_id into saved_id;

        exit when saved_id is not null;
      end loop;
      return saved_id;
    end;
    $$;
  $ddl$;

  execute $ddl$
    create or replace function pg_temp.ins_courier() returns uuid
      language plpgsql 
      set search_path = bartov_food, pg_catalog, pg_temp 
      as $$
    declare 
      saved_id uuid;
      saved_name text;
      saved_phone text;
      saved_status courier_status;
      saved_hire_date date;
    begin
      saved_name := pg_temp.get_random_string(32);
      saved_phone := '7' || pg_temp.get_random_digits(10);
      saved_status := (enum_range(null::courier_status))[pg_temp.get_random_int(1, 3)];
      --нанимаем сотрудников до даты первого заказа
      saved_hire_date := greatest(current_date - 179, date_trunc('month', current_date - interval '5 months')::date);

      insert into courier (fio, phone_number, status, hire_date)
      values (saved_name, saved_phone, saved_status, saved_hire_date)
      returning courier_id into saved_id;

      return saved_id;
    end;
    $$;
  $ddl$;

  execute $ddl$
    create or replace function pg_temp.ins_restaurant(p_address_id uuid) returns uuid
      language plpgsql
      set search_path = bartov_food, pg_catalog, pg_temp 
      as $$
    declare saved_id uuid;
      saved_name text;
      saved_description text;
      saved_open time;
      saved_close time;
      saved_inn text;
      saved_ogrn text;
      saved_account text;
      saved_status restaurant_status;
      opening_hour int;
    begin
      saved_name := pg_temp.get_random_string(26);
      saved_description := pg_temp.get_random_string(40);

      --дадим ресторану поработать хотябы несколько часов
      opening_hour := pg_temp.get_random_int(7, 18);
      saved_open := make_time(opening_hour, 0, 0);
      saved_close := make_time(pg_temp.get_random_int(opening_hour + 1, 23), 0, 0);

      saved_inn := pg_temp.get_random_digits(10);
      saved_ogrn := pg_temp.get_random_digits(13);
      saved_account := pg_temp.get_random_digits(20);

      saved_status := (enum_range(null::restaurant_status))[pg_temp.get_random_int(1, 2)];

      insert into restaurant (restaurant_name, address_id, description, work_start, work_end,
                              inn, ogrn, settlement_account, status)
      values (saved_name, p_address_id, saved_description, saved_open, saved_close,
              saved_inn, saved_ogrn, saved_account, saved_status)
      returning restaurant_id into saved_id;

      return saved_id;
    end;
    $$;
  $ddl$;

  execute $ddl$
    create or replace function pg_temp.ins_client_address(p_client_id uuid
                                                        ,p_address_id uuid
                                                        ) returns void 
      language plpgsql 
      set search_path = bartov_food, pg_catalog, pg_temp 
      as $$
    begin
      insert into client_address (client_id, address_id) 
      values (p_client_id, p_address_id);
    end;
    $$;
  $ddl$;

  execute $ddl$
    create or replace function pg_temp.ins_product_photo(p_product_id uuid) returns void
      language plpgsql 
      set search_path = bartov_food, pg_catalog, pg_temp 
      as $$
    declare 
      saved_url text;
    begin
      --добавляем вероятность отсутсвия фотографии
      if random() < 0.5 then
        saved_url := pg_temp.get_random_photo_url();

        insert into product_photo (product_id, photo_url)
        values (p_product_id, saved_url);
      end if;
    end;
    $$;
  $ddl$;

  execute $ddl$
    create or replace function pg_temp.ins_product(p_restaurant_id uuid
                                                  ,p_category_id uuid
                                                  ) returns uuid 
      language plpgsql 
      set search_path = bartov_food, pg_catalog, pg_temp 
      as $$
    declare 
      saved_id          uuid;
      saved_name        text;
      saved_description text;
      saved_price       numeric(14, 2);
      saved_status      product_status;
      ind               int;
    begin
      -- Цена может быть меньше минимального чека: его обеспечит количество в заказе.
      saved_name := pg_temp.get_random_string(28);
      saved_description := pg_temp.get_random_string(40);
      saved_price := pg_temp.get_random_int(100, 3500);
      saved_status := (enum_range(null::product_status))[pg_temp.get_random_int(1, 3)];

      insert into product (product_name, product_category_id, price, restaurant_id, status, description)
      values (saved_name, p_category_id, saved_price, p_restaurant_id, saved_status, saved_description) 
      returning product_id into saved_id;

      for ind in 1..pg_temp.get_random_int(1, 4)
      loop
        perform pg_temp.ins_product_photo(saved_id);
      end loop;
      return saved_id;
    end;
    $$;
  $ddl$;

  execute $ddl$
    create or replace function pg_temp.ins_order_structure(p_order_id     uuid
                                                          ,p_product_id   uuid
                                                          ,p_quantity     int
                                                          ,p_price        numeric
                                                          ) returns void 
      language plpgsql 
      set search_path = bartov_food, pg_catalog, pg_temp 
      as $$
    begin
      insert into order_structure (order_id, product_id, quantity, unit_price)
      values (p_order_id, p_product_id, p_quantity, p_price);
    end;
    $$;
  $ddl$;

  execute $ddl$
    create or replace function pg_temp.ins_payment(p_order_id         uuid
                                                  ,p_amount           numeric
                                                  ,p_order_timestamp  timestamp
                                                  ,p_status           payment_status
                                                  ) returns void
      language plpgsql 
      set search_path = bartov_food, pg_catalog, pg_temp 
      as $$
    declare 
      saved_type        payment_type;
      saved_reference   text;
    begin
      --Тип и внешний реквизит независимы для каждой попытки оплаты.
      saved_type := (enum_range(null::payment_type))[pg_temp.get_random_int(1, 3)];
      saved_reference := exts.uuid_generate_v4()::text;

      insert into payment (order_id, type, amount, transaction_reference, transaction_timestamp, status)
      values (p_order_id, saved_type, p_amount, saved_reference, p_order_timestamp, p_status);
    end;
    $$;
  $ddl$;

  execute $ddl$
    create or replace function pg_temp.ins_review_photo(p_review_id uuid) returns void
      language plpgsql 
      set search_path = bartov_food, pg_catalog, pg_temp 
      as $$
    declare 
      saved_url text;
    begin
      if random() < 0.5 then
        saved_url := pg_temp.get_random_photo_url();

        insert into review_photo (review_id, photo_url)
        values (p_review_id, saved_url);
      end if;
    end;
    $$;
  $ddl$;

  execute $ddl$
    create or replace function pg_temp.ins_review(p_order_id        uuid
                                                 ,p_client_id       uuid
                                                 ,p_restaurant_id   uuid
                                                 ,p_product_id      uuid
                                                 ,p_order_timestamp timestamp
                                                 ) returns void
      language plpgsql 
      set search_path = bartov_food, pg_catalog, pg_temp 
      as $$
    declare 
      saved_id          uuid;
      saved_type        review_entity_type;
      saved_target      uuid;
      saved_timestamp   timestamp;
      saved_description text;
      saved_rating      int;
      ind               int;
    begin
      saved_type := (enum_range(null::review_entity_type))[pg_temp.get_random_int(1, 3)];

      saved_target := case saved_type when 'блюдо' then p_product_id
                                      when 'ресторан' then p_restaurant_id 
                                      else p_order_id end;

      saved_timestamp := p_order_timestamp + (localtimestamp - p_order_timestamp) * random();
      saved_description := pg_temp.get_random_string(42);
      saved_rating := pg_temp.get_random_int(1, 5);

      insert into review (client_id, review_timestamp, entity_id, entity_type, order_id, description, rating)
      values (p_client_id, saved_timestamp, saved_target, saved_type, p_order_id, saved_description, saved_rating) 
      returning review_id into saved_id;
      
      for ind in 1..pg_temp.get_random_int(1, 4)
      loop
        perform pg_temp.ins_review_photo(saved_id);
      end loop;
    end;
    $$;
  $ddl$;

  execute $ddl$
    create or replace function pg_temp.ins_order(p_client_id        uuid
                                                ,p_address_id       uuid
                                                ,p_restaurant_id    uuid
                                                ,p_courier_id       uuid
                                                ,p_products         uuid[]
                                                ,p_payment_count    int
                                                )returns uuid 
      language plpgsql 
      set search_path = bartov_food, pg_catalog, pg_temp 
      as $$
    declare 
      saved_id            uuid;
      order_time          timestamp;
      delivery_time       timestamp;
      saved_status        order_status;
      saved_pay_status    order_pay_status;
      saved_description   text;
      food_amount         numeric(14, 2) := 0;
      total               numeric(14, 2);
      line_count          int;
      indexes             int[] := array[]::int[];
      quantities          int[] := array[]::int[];
      prices              numeric[] := array[]::numeric[];
      chosen_index        int;
      chosen_price        numeric(14, 2);
      additional_quantity int;
      payment_attempts    payment_status[] := enum_range(null::payment_status);
      attempt_status      payment_status;
      successful_attempt  int;
      i                   int;
    begin
      --выбираем к-во блюд
      line_count := pg_temp.get_random_int(1, least(5, cardinality(p_products)));

      for i in 1..line_count loop
        --добавляем блюда исключая повториний одного и тогоже в заказе
        loop
          chosen_index := pg_temp.get_random_int(1, cardinality(p_products));
          exit when not chosen_index = any(indexes);
        end loop;

        --добавляем в массив выбранные блюда
        indexes := array_append(indexes, chosen_index);
        quantities := array_append(quantities, pg_temp.get_random_int(1, 3));

        select price
        into chosen_price
        from product 
        where product_id = p_products[chosen_index];

        --цену сохраняем первозданной, пересчитаем при добавлении
        prices := array_append(prices, chosen_price);
        food_amount := food_amount + chosen_price * quantities[i];
      end loop;

      --При дешёвых продуктах меняем количество, пока итог с комиссией не достигнет 1000.
      while food_amount + round(food_amount * 0.10, 2) < 1000 loop
        additional_quantity := greatest(1, ceil((1000 - food_amount - round(food_amount * 0.10, 2)) / prices[1])::int);
        quantities[1] := quantities[1] + additional_quantity;
        food_amount := food_amount + additional_quantity * prices[1];
      end loop;

      order_time := pg_temp.get_random_timestamp();
      saved_status := (enum_range(null::order_status))[pg_temp.get_random_int(1, 5)];

      --для доставленного заказа генерируем дату
      if saved_status = 'доставлен' then
        delivery_time := order_time + (localtimestamp - order_time) * random();
      end if;

      --При двух попытках одна успешная и одна ошибочная; при нуле ожидаем оплату.
      if p_payment_count = 2 then
        saved_pay_status := 'оплачен'::order_pay_status;
        successful_attempt := pg_temp.get_random_int(1, 2);
      elsif p_payment_count = 1 then
        attempt_status := payment_attempts[pg_temp.get_random_int(1, cardinality(payment_attempts))];
        saved_pay_status := case attempt_status when 'успех' then 'оплачен'::order_pay_status
          when 'ошибка' then 'ошибка'::order_pay_status else 'ожидает'::order_pay_status end;
      else
        saved_pay_status := 'ожидает'::order_pay_status;
      end if;

      saved_description := pg_temp.get_random_string(40);

      insert into "order" (client_id, address_id, restaurant_id, courier_id,
                           order_timestamp, delivery_timestamp, order_amount,
                           status, pay_status, description)
      values (p_client_id, p_address_id, p_restaurant_id, p_courier_id,
              order_time, delivery_time, food_amount, saved_status, saved_pay_status,
              saved_description) 
      returning order_id, total_amount into saved_id, total;

      --вставляем позиции заказа и пересчитываем их сумму
      for i in 1..line_count loop
        perform pg_temp.ins_order_structure(saved_id, p_products[indexes[i]], quantities[i], prices[i]*quantities[i]);
      end loop;

      for i in 1..p_payment_count loop
        if p_payment_count = 2 then
          if i = successful_attempt then
            attempt_status := 'успех'::payment_status;
          else
            attempt_status := 'ошибка'::payment_status;
          end if;
        end if;
        perform pg_temp.ins_payment(saved_id, total, order_time, attempt_status);
      end loop;

      perform pg_temp.ins_review(saved_id, p_client_id, p_restaurant_id, p_products[indexes[pg_temp.get_random_int(1, line_count)]], order_time);

      return saved_id;
    end;
    $$;
  $ddl$;

  execute $ddl$
    create or replace function pg_temp.ins_courier_pay(p_couriers uuid[]) returns void
      language plpgsql 
      set search_path = bartov_food, pg_catalog, pg_temp 
      as $$
    declare 
      saved_year                int;
      saved_month               int;
      saved_courier             uuid;
      saved_amount              numeric(16, 2);
      saved_coefficient         numeric(3, 1);
      saved_month_start         date;
      saved_commissions         numeric;
      saved_previous_deliveries bigint;
      saved_current_deliveries  bigint;
      row_data                  record;
    begin
      for row_data in
        --каждый месяц за последние пол года обрабатываем
        with months as (
          select m::date month_start
          from generate_series(date_trunc('month', current_date - interval '5 months')
                              ,date_trunc('month', current_date), interval '1 month'
                              ) m
        ), monthly as (
          -- собираем доставленные заказы каждым курьером и считаем суммы
          select c.courier_id
                ,m.month_start
                ,count(o.order_id) deliveries
                ,coalesce(sum(o.commission), 0) commissions
          from unnest(p_couriers) as c(courier_id)
              cross join months m
              left join "order" o 
                on o.courier_id = c.courier_id
                and o.status = 'доставлен'
                and o.order_timestamp >= m.month_start
                and o.order_timestamp < m.month_start + interval '1 month'
          group by c.courier_id, m.month_start
        )
        select courier_id
              ,month_start
              ,commissions
              ,deliveries
              --доставки в предыдущем месяце влият на зп в этом
              ,lag(deliveries, 1, 0) over (partition by courier_id order by month_start) previous_deliveries
        from monthly
      loop
        saved_courier := row_data.courier_id;
        saved_month_start := row_data.month_start;
        saved_year := extract(year from saved_month_start)::int;
        saved_month := extract(month from saved_month_start)::int;
        saved_commissions := row_data.commissions;
        saved_previous_deliveries := row_data.previous_deliveries;
        saved_current_deliveries := row_data.deliveries;
        saved_coefficient := pg_temp.get_random_next_coefficient(saved_previous_deliveries);
        saved_amount := round(saved_commissions * saved_coefficient, 2);

        insert into courier_pay (year, month, courier_id, amount, coefficient_used)
        values (saved_year, saved_month, saved_courier, saved_amount, saved_coefficient);

        -- При увольнении за месяц платим, но коэффициент на следующий не назначаем.
        if saved_month_start = date_trunc('month', current_date)::date then
          update courier 
          set coefficient = pg_temp.get_random_next_coefficient(saved_current_deliveries)
          where courier_id = saved_courier 
            and status <> 'уволен';
        end if;

      end loop;
    end;
    $$;
  $ddl$;

  -- Используются только ID текущего вызова, поэтому старые строки не меняются.
  for i in 1..value loop
    categories := array_append(categories, pg_temp.ins_product_category());
    couriers := array_append(couriers, pg_temp.ins_courier());
    restaurant_addresses := array_append(restaurant_addresses, pg_temp.ins_address());
    clients := array_append(clients, pg_temp.ins_client());
  end loop;

  --генерируем для  клиента 4 адреса и заполняем
  for i in 1..value * 4 loop
    client_addresses := array_append(client_addresses, pg_temp.ins_address());
    perform pg_temp.ins_client_address(clients[(i - 1) / 4 + 1], client_addresses[i]);
  end loop;

  for i in 1..value loop
    restaurants := array_append(restaurants, pg_temp.ins_restaurant(restaurant_addresses[i]));
  end loop;

  --заадем продукты для каждого ресторана
  for i in 1..value loop
    for j in 1..5 loop
      products := array_append(products, pg_temp.ins_product(restaurants[i], categories[pg_temp.get_random_int(1, value)]));
    end loop;
  end loop;

  payment_offset := pg_temp.get_random_int(0, 4);
  for i in 1..value * 5 loop
    restaurant_index := pg_temp.get_random_int(1, value);
    client_index := pg_temp.get_random_int(1, value);
    restaurant_products := products[(restaurant_index - 1) * 5 + 1:restaurant_index * 5];
    --В каждой пятёрке один заказ с двумя попытками, один без попыток, прочие с одной.
    payment_count := case (i - 1 + payment_offset) % 5
      when 0 then 2 when 1 then 0 else 1 end;

    perform pg_temp.ins_order(clients[client_index]
                             ,client_addresses[(client_index - 1) * 4 + pg_temp.get_random_int(1, 4)]
                             ,restaurants[restaurant_index]
                             ,couriers[pg_temp.get_random_int(1, value)]
                             ,restaurant_products
                             ,payment_count
                             );
  end loop;

  -- Увольняем только после заказов, чтобы в истории могли быть доставленные заказы.
  for i in 1..value loop
    if i > 1 and i % 7 = 0 then
      update courier
      set status = 'уволен'
         ,dismissal_date = current_date
      where courier_id = couriers[i];
    end if;
  end loop;

  perform pg_temp.ins_courier_pay(couriers);
end;
$procedure$;
