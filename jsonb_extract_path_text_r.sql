-- FUNCTION: public.jsonb_extract_path_text_r(jsonb, character varying)

-- DROP FUNCTION public.jsonb_extract_path_text_r(jsonb, character varying);

CREATE OR REPLACE FUNCTION public.jsonb_extract_path_text_r(
	jb jsonb,
	jpath character varying)
    RETURNS text
    LANGUAGE 'plpgsql'
AS $BODY$

DECLARE
    res text DEFAULT '';
    keys character varying[];
    sub_keys character varying[];
    n  NUMERIC;
    sub_n NUMERIC default 0;
    valbyPath text;
    JBbyPath jsonb;
BEGIN    
    select into keys regexp_split_to_array(jpath, '\.');
    if (trim(jpath)<> '') then
        select into n array_length(keys, 1);
        --
        JBbyPath:= JB;
        for i in 1..n loop
            if i<> n then 
            	if (select position('[' in keys[i]) > 0) then
                    select into sub_keys regexp_split_to_array(keys[i], '\[|\]');
                    select into sub_n array_length(sub_keys, 1);
                    for j in 1..sub_n loop
                        if (sub_keys[j] <> '') then
                            select INTO valbyPath jsonb_extract_path_text(JBbyPath, sub_keys[j]);
                            if(is_json(valbyPath)) then
                            	JBbyPath:= valbyPath::jsonb;
                            else 
                            	JBbyPath:= '{}'::jsonb;
                            end if;
                        end if;
                    end loop;
                else
                    select INTO valbyPath jsonb_extract_path_text(JBbyPath, keys[i]);
                    if(is_json(valbyPath)) then
                        JBbyPath:= valbyPath::jsonb;
                    else 
                        JBbyPath:= '{}'::jsonb;
                    end if;
                end if;
            else
            	if (select position('[' in keys[i]) > 0) then
                	-- в последнем ключе есть вложенность, например from[0]
                    select into sub_keys regexp_split_to_array(keys[i], '\[|\]');
                    select into sub_n array_length(sub_keys, 1);
                    --
                    for k1 in 1..sub_n-1 loop -- так как from[0] =>  {from,0,""}
                    	if (k1 <> sub_n-1) then
                            select INTO valbyPath jsonb_extract_path_text(JBbyPath, sub_keys[k1]);
                            if(is_json(valbyPath)) then
                                JBbyPath:= valbyPath::jsonb;
                            else 
                                JBbyPath:= '{}'::jsonb;
                            end if;                            
                        else
                            select INTO res jsonb_extract_path_text(JBbyPath, sub_keys[k1]);
                        end if;
                    end loop;
                else
                	select INTO res jsonb_extract_path_text(JBbyPath, keys[i]);
                end if;
            end if;
        end loop;
    end if;
    return res;
END;

$BODY$;

