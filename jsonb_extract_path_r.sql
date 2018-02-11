-- FUNCTION: public.jsonb_extract_path_r(jsonb, character varying)

-- DROP FUNCTION public.jsonb_extract_path_r(jsonb, character varying);

CREATE OR REPLACE FUNCTION public.jsonb_extract_path_r(
	jb jsonb,
	jpath character varying)
    RETURNS jsonb
    LANGUAGE 'plpgsql'
AS $BODY$

DECLARE
    res jsonb;
    keys character varying[];
    sub_keys character varying[];
    n NUMERIC default 0;
    sub_n NUMERIC default 0;
    JBbyPath jsonb;
BEGIN
    JBbyPath:= JB;
    select into keys regexp_split_to_array(jpath, '\.');    
    if (trim(jpath)<> '') then
	    select into n array_length(keys, 1);
        for i in 1..n loop
            -- we are reading maps step by step here -- by keys
            if (select position('[' in keys[i]) > 0) then
	            -- if contain [], then read by sub keys
                select into sub_keys regexp_split_to_array(keys[i], '\[|\]');
                select into sub_n array_length(sub_keys, 1);
                for j in 1..sub_n loop
                	if (sub_keys[j] <> '') then
                    	select INTO JBbyPath jsonb_extract_path_text(JBbyPath, sub_keys[j])::jsonb;	
                    end if;
                end loop;
            else
            	select INTO JBbyPath jsonb_extract_path_text(JBbyPath, keys[i])::jsonb;
            end if;
        end loop;
    end if;
    return JBbyPath;
END;

$BODY$;

