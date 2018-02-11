-- FUNCTION: public.jsonb_make_select_r(jsonb, text[])

-- DROP FUNCTION public.jsonb_make_select_r(jsonb, text[]);

CREATE OR REPLACE FUNCTION public.jsonb_make_select_r(
	jb jsonb,
	elems text[])
    RETURNS text
    LANGUAGE 'plpgsql'
AS $BODY$

declare
    j      integer=0;
    ec     integer=0;
    bs     text = '';
    bsf    text = '';
    bsfval text = '';
begin
	--
	select INTO ec array_length(elems, 1);
	bs:= bs || 'select ';
    FOR j IN 1 .. array_upper(elems, 1) LOOP
    	--       
        select into bsfval jsonb_extract_path_text_r(jb, elems[j][2]);
        --
        if (bsfval is null) then bsfval:= 'null'||'::'||elems[j][1];
                            else bsfval:= '$$'||bsfval||'$$'||'::'||elems[j][1]; end if;
        --
        bsf:= bsf || bsfval;
        if j <> ec then bsf:= bsf || ','; end if;
    END LOOP;
    bs:= bs || bsf;
    return bs;
end;

$BODY$;

COMMENT ON FUNCTION public.jsonb_make_select_r(jsonb, text[])
    IS 'вспомогательная функция для функции json_table';


