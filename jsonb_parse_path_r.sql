-- FUNCTION: public.jsonb_parse_path_r(character varying)

-- DROP FUNCTION public.jsonb_parse_path_r(character varying);

CREATE OR REPLACE FUNCTION public.jsonb_parse_path_r(
	path character varying,
	OUT main_path character varying,
	OUT sub_path character varying)
    RETURNS record
    LANGUAGE 'plpgsql'
AS $BODY$

DECLARE
	pos integer=0;
BEGIN
	pos:= POSITION('*' in path);
	if pos > 0 THEN
        path:= REPLACE(path, '.[*].', '*');
        path:= REPLACE(path, '.[*]',  '*');
        path:= REPLACE(path,  '[*].', '*');
        path:= REPLACE(path,  '[*]',  '*');
        path:= REPLACE(path,  '.*.',  '*');
        path:= REPLACE(path,  '.*',   '*');
        pos:= POSITION('*' IN path);
    	main_path:= SUBSTRING(path FROM 0   FOR pos);
        sub_path:=  SUBSTRING(path FROM pos FOR length(path));
        IF POSITION('*' IN sub_path) = 1 THEN
        	sub_path:= SUBSTRING(sub_path FROM 2 FOR length(sub_path));
        END IF;
        IF (sub_path = '') THEN
        	sub_path:= '*';
        END IF;
    ELSE 
    	main_path:= path;
        sub_path:= '';
    END IF;
END

$BODY$;

COMMENT ON FUNCTION public.jsonb_parse_path_r(character varying)
    IS 'вспомогательная функция для json_table';


