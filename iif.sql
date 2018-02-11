-- FUNCTION: public.iif(boolean, character varying, character varying)

-- DROP FUNCTION public.iif(boolean, character varying, character varying);

CREATE OR REPLACE FUNCTION public.iif(
c boolean,
a character varying,
b character varying)
    RETURNS character varying
    LANGUAGE 'plpgsql'
AS $BODY$

begin
if c then 
    return a;
   else 
    return b;
    end if;
end;

$BODY$;

-- FUNCTION: public.iif(boolean, numeric, numeric)

-- DROP FUNCTION public.iif(boolean, numeric, numeric);

CREATE OR REPLACE FUNCTION public.iif(
c boolean,
a numeric,
b numeric)
    RETURNS numeric
    LANGUAGE 'plpgsql'
AS $BODY$

begin
if c then 
    return a;
   else 
    return b;
    end if;
end;

$BODY$;

