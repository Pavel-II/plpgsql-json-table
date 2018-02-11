-- FUNCTION: public.jsonb_search_nests_count_r(jsonb, character varying, character varying, integer)

-- DROP FUNCTION public.jsonb_search_nests_count_r(jsonb, character varying, character varying, integer);

CREATE OR REPLACE FUNCTION public.jsonb_search_nests_count_r(
	jb jsonb,
	main_path character varying,
	new_nest character varying,
	currentlvl integer DEFAULT 0,
	OUT counts numeric[])
    RETURNS numeric[]
    LANGUAGE 'plpgsql'
AS $BODY$

DECLARE
	rec record;
    JBA jsonb;
    inner_main_path character varying;
    inner_sub_path  character varying;    
    inner_nesting_level integer default  0;
    templ_path  CHARACTER VARYING default '';
    insert_path CHARACTER VARYING default '';
    keys character varying[];
    keyindex NUMERIC default 0;
    replkey character varying default '';
    n NUMERIC default 0;
    cur_counts numeric[] default '{}';
BEGIN
	counts:= '{}';
    IF ( (SELECT count(*) FROM nestedpaths) > 0 ) THEN
    	execute 'drop table if exists smfnestedpaths'; 
        CREATE TEMPORARY TABLE IF NOT EXISTS smfnestedpaths (npath CHARACTER VARYING) on commit drop;
        for rec in (select * from nestedpaths order by nesting_level ASC) loop
            templ_path:= templ_path|| IIF(templ_path='','','.') || rec.npath;-- like: path[*].path1[*].path2[*]...
        end loop;
        select into keys regexp_split_to_array(templ_path, '\.'); -- ключи
        select into n array_length(keys, 1);                      -- кол-во
		-----------------------------------------            
        select n1.counts from nestedpaths as n1 where nesting_level=currentlvl into cur_counts;
        FOR i in 1..array_length(cur_counts,1) loop
            for j in 1..cur_counts[i] loop
                insert into smfnestedpaths values(templ_path);
            end loop;
        END loop;
        -----------------------------------------
        FOR i IN 1..n loop -- по всем ключам
            keyindex:=0;
            replkey:= keys[i];
            for rec in (select *, ctid from smfnestedpaths) loop
            	update smfnestedpaths set npath= 
                		REPLACE(rec.npath, '*', trim(to_char(keyindex,'999999999')))
                where ctid=rec.ctid;
                keyindex:= keyindex+1;
            END loop;
        END loop;
        -----------------------------------------
        FOR rec in (select * from smfnestedpaths) loop
            select * into inner_main_path,inner_sub_path from jsonb_parse_path_r(rec.npath||'.'||new_nest);
            select INTO JBA jsonb_extract_path_r(JB, inner_main_path);
            case json_typeof(JBA::json)
                when 'array' then                
                    select * from jsonb_array_length(JBA) INTO inner_nesting_level;
                when 'object' then                
                    select count(*) from jsonb_each(JBA) into inner_nesting_level;
                else
                    raise notice '%: %', 'not array and not object!', JBA;
            end case;
            --
            select array_append(counts, IIF(inner_nesting_level is NULL, 0, inner_nesting_level)) into counts;               
        END loop;
        --
	ELSE
        select * into inner_main_path,inner_sub_path from jsonb_parse_path_r(main_path);		
        select INTO JBA jsonb_extract_path_r(JB, inner_main_path);
        --
        case json_typeof(JBA::json)
            when 'array' then                
                select * from jsonb_array_length(JBA) INTO inner_nesting_level;
            when 'object' then                
                select count(*) from jsonb_each(JBA) into inner_nesting_level;
            else
                raise notice '%: %', 'not array and not object!', JBA;
        end case;        
        --
        select array_append(counts, IIF(inner_nesting_level IS NULL, 0, inner_nesting_level)) into counts;
        INSERT into nestedpaths VALUES(new_nest, 0,counts); 
    END IF;
END;

$BODY$;

COMMENT ON FUNCTION public.jsonb_search_nests_count_r(jsonb, character varying, character varying, integer)
    IS 'function for json_table func';


