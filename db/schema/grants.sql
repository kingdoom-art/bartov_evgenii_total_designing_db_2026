do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'inspector') then
    create role inspector login password 'NetoSQL2025';
  end if;
end;
$$;

grant all privileges on schema bartov_food to inspector;
grant all privileges on all tables in schema bartov_food to inspector;
grant all privileges on all sequences in schema bartov_food to inspector;
grant execute on all functions in schema bartov_food to inspector;
grant execute on all procedures in schema bartov_food to inspector;

grant usage on schema exts, information_schema, pg_catalog to inspector;
grant execute on function exts.uuid_generate_v4() to inspector;
