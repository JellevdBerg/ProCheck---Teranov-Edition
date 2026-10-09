-- The one-argument overload made `admin_create_department('x')` ambiguous
-- (the two-argument version has a default). The app always passes both.
drop function if exists public.admin_create_department(text);
