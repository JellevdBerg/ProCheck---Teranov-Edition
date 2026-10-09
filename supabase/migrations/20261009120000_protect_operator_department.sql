-- The Operator department must always exist: it is what is_operator() and the
-- Operator-only admin actions hang off. admin_delete_department() let an
-- Operator remove it. A trigger (rather than a check in that one function)
-- also covers direct deletes and any future RPC. Additive; nothing else changes.

create or replace function public.prevent_operator_department_delete()
returns trigger
language plpgsql
as $$
begin
  raise exception 'The Operator department cannot be deleted';
end;
$$;

drop trigger if exists protect_operator_department on public.departments;
create trigger protect_operator_department
  before delete on public.departments
  for each row
  when (old.is_operator)
  execute function public.prevent_operator_department_delete();
