create or replace procedure bartov_food.erase_test_data()
  language plpgsql
  set search_path = bartov_food, pg_catalog, pg_temp
  as $procedure$
declare
  rec "order".order_id%type;
begin
   delete from review_photo;
  delete from review;
  delete from payment;
  delete from order_structure;
  delete from "order";
  delete from product_photo;
  delete from product;
  delete from product_category;
  delete from courier_pay;
  delete from courier;
  delete from client_address;
  delete from client;
  delete from restaurant;
  delete from address;
end;
$procedure$;