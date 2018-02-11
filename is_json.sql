-- FUNCTION: public.is_json(text)

-- DROP FUNCTION public.is_json(text);

CREATE OR REPLACE FUNCTION public.is_json(
	testtojson text)
    RETURNS boolean
    LANGUAGE 'plpgsql'
AS $BODY$

begin
	perform testtojson::jsonb; return true; exception when others then return false;
end;

$BODY$;

