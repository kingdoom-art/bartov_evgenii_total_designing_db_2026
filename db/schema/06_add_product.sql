create procedure bartov_food.add_product(p_restaurant_id         uuid
                                        ,p_product_category_id   uuid
                                        ,p_name                  varchar
                                        ,p_price                 numeric
                                        ,p_rating                numeric
                                        ,p_status                bartov_food.product_status
                                        ,p_description           text
                                        )
  language plpgsql
  set search_path = bartov_food, pg_catalog, pg_temp
  as $$
declare
  new_product_id uuid;
begin
  perform 1 from restaurant where restaurant_id = p_restaurant_id;
  if not found then
    raise exception 'Ресторан не найден: %', p_restaurant_id;
  end if;

  perform 1 from product_category where product_category_id = p_product_category_id;
  if not found then
    raise exception 'Категория блюда не найдена: %', p_product_category_id;
  end if;

  if p_price < 0 then
    raise exception 'Цена блюда не может быть отрицательной: %', p_price;
  end if;

  if p_rating not between 0 and 5 then
    raise exception 'Рейтинг блюда должен быть от 0 до 5: %', p_rating;
  end if;

  insert into product (restaurant_id, product_category_id, product_name, price, rating, status, description)
  values (p_restaurant_id, p_product_category_id, p_name, p_price, p_rating, p_status, p_description)
  returning product_id into new_product_id;
end;
$$;
