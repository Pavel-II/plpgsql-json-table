-- FUNCTION: public.json_table(jsonb, character varying, text[])

-- DROP FUNCTION public.json_table(jsonb, character varying, text[]);

CREATE OR REPLACE FUNCTION public.json_table(
	jb jsonb,
	path character varying,
	elems text[])
    RETURNS SETOF record 
    LANGUAGE 'plpgsql'
AS $BODY$

DECLARE
    main_path character varying;
	sub_path  character varying;
	jal integer=0; -- длинна массива
    JBA jsonb = null; -- Json Base Array/ массив или map по которому собирается таблица
    rec record;
    bs text = '';
BEGIN
    select * into main_path,sub_path from jsonb_parse_path_r(path); -- пути
    select INTO JBA jsonb_extract_path_r(JB, main_path);
    if JBA is not null then
        if (elems && ARRAY['NESTEDPATH']) then
            DECLARE -- NESTEDPATH 
                nl            integer default  0; -- FIXIT
                nesting_level integer default  0;
                etype character varying default '';
                epath character varying default '';
                counts numeric[] default '{}';
                ttmps character varying[] default '{}';     -- список временных таблиц
                ttmp_name CHARACTER VARYING default 'ntt_'; -- шаблон имени текущей временой таблицы
                tmp_name  CHARACTER VARYING default 'ntt_'; -- имя текущей временой таблицы
                -- шаблон создения временной тсблицы:     --
                tmp_create CHARACTER VARYING default 'CREATE temporary table IF NOT EXISTS * (pnp integer, sp integer, np CHARACTER VARYING) ON COMMIT DROP;';
                /* pnp - верхний путь вложенности
                   sp  - индекс в верхнем пути вложенности
                   np  - собственный путь вложенности */
                ttmp_cmd  CHARACTER VARYING default '';-- sql команда для манипулирования временными таблицами            
            BEGIN
            	execute 'drop table if exists nestedpaths'; 
                CREATE temporary table IF NOT EXISTS nestedpaths (
                    npath CHARACTER VARYING, -- путь
                    nesting_level integer,   -- уровень
                    counts integer[])        -- сколько раз повторяется для каждого 
                    ON COMMIT DROP;
                ------------------------------------------
                select * into main_path,sub_path from jsonb_parse_path_r(path);
                --
                if (sub_path <> '') then    	
                    select * into counts from jsonb_search_nests_count_r(JB, path, epath);
                    insert into nestedpaths values(path, nesting_level, counts);
                end if;
                --
                tmp_name:= ttmp_name||trim(to_char(nl,'999'));-- имя временной таблицы ntt_0...999
                -- 
                execute 'drop table if exists '|| tmp_name; 
                EXECUTE replace(tmp_create, '*', tmp_name);   -- создание первой временной таблицы
                select array_append(ttmps, tmp_name) into ttmps;
                --
                for i in 1..array_upper(elems,1) loop
                    etype:= elems[i][1];
                    epath:= elems[i][2];
                    if (etype = 'NESTEDPATH') then
                        declare            
                            rc integer default 0;
                            sticky_str character varying default '';
                        begin
                            nesting_level:= nesting_level+1;
                            nl:= nl+1;
                            tmp_name:= ttmp_name||trim(to_char(nl,'999'));
                            --
                            execute 'drop table if exists '|| tmp_name; 
                            EXECUTE replace(tmp_create, '*', tmp_name); -- создание остальных временых таблиц
                            select array_append(ttmps, tmp_name) into ttmps;
                            sticky_str:= sticky_str||IIF(sticky_str='','','.')||epath;
                            select * into counts  from jsonb_search_nests_count_r( 
                                    JB, path||IIF(path='','','.')|| sticky_str||IIF(sticky_str='','','.'), 
                                    epath, nesting_level-1); -- nesting_level-1 текущий
                            select into rc count(*) from nestedpaths where npath=epath;
                            if (rc=0) then 
                                insert into nestedpaths values(epath, nesting_level, counts);
                            else
                                nesting_level:= nesting_level-1;
                            end if;
                        end;
                    else -- добавить колонку во временную таблицу
                        EXECUTE 'ALTER TABLE '||
                        	tmp_name ||
                            ' ADD COLUMN ' ||
                            '_'||replace(replace(replace(epath, '.','_'),'[','_'),']','_') || '_' ||
                            ' '||etype||';';
                        -- в имени колонки не может быть символов . []  - заменяются на _
                        -- и имя не может быть зарезервированным словом - имя колонки берётся в _                            
                    end if;
                end loop;
                ------------------------------------------     
                ------------------------------------------
                declare -- fill temporary tables!
                    write_to CHARACTER VARYING default '';            -- текущее имя тяблицы куда записываются значения
                    ri INTEGER default 1;                             -- индекс write_to
                    insert_str CHARACTER VARYING default '';          -- строка для вставки значений
                    evalue CHARACTER VARYING     default '';          -- значение по конкретному пути        
                    evalues_by_path CHARACTER VARYING[] default '{}'; -- пути по которым нужно прочитывать значения для текущей таблицы
                    etypes_by_path  CHARACTER VARYING[] default '{}'; -- типы значений
                    all_evbp CHARACTER VARYING[][] default '{}';      -- все пути по которым нужно прочитывать значения | временная таблица, в которую оно пишется       
                    NPlist  CHARACTER VARYING[]    default '{}';      -- пути вложения
                    NP CHARACTER VARYING    default '';               -- путь по которому прочтено значение. Созраняется для получения вложенных значений
                    curNP CHARACTER VARYING default '';               -- текущий путь вложения
                begin
                    write_to:= ttmps[ri];
                    select into insert_str public.script_insert(write_to); -- строка для вставки для таблицы write_to
                    -- писать прочитанные значения в созданную ранее таблицу
                    for i in 1..array_upper(elems,1) loop
                        etype:= elems[i][1]; epath:= elems[i][2];
                        if (etype = 'NESTEDPATH') then
                            curNP:= epath; 
                            select array_append(NPlist, curNP) into NPlist;
                            if ri=1 then -- запись в первую таблицу
                                counts:= '{}'; -- сколько раз повторить чтение из JSON
                                if (main_path <> '') then
                                    select n.counts from nestedpaths as n where npath like main_path||'%' into counts;
                                else 
                                    select n.counts from nestedpaths as n where npath='' into counts;
                                end if;
                                -- NB counts count = 0
                                if array_length(counts,1) > 1 then
                                    -- повторить несколько раз !
                                else -- когда в counts ничего нет
                                     -- единичные значения
                                    IF (sub_path <> '') then -- <- Когда сюда попадает? здесь id && sp начинааются с 0, далее с 1. CHECHIT!
                                        select INTO JBA jsonb_extract_path_r(JB, main_path);
                                        select * INTO jal from jsonb_array_length(JBA);
                                        FOR j IN 0..jal-1 LOOP
                                            NP:= main_path||'.'||trim(to_char(j, '999999999'))||'.'||sub_path;
                                            select regexp_replace(insert_str, '\?', trim(to_char(j, '999999999'))) into insert_str; -- id
                                            select regexp_replace(insert_str, '\?', trim(to_char(j, '999999999'))) into insert_str; -- sp
                                            select regexp_replace(insert_str, '\?', ''''||NP||'''') into insert_str;                -- np
                                            for e in 1..array_upper(evalues_by_path,1) loop                                                                        
                                                select jsonb_extract_path_text_r(jb, NP|| '.'||evalues_by_path[e]) into evalue;
                                                select regexp_replace(insert_str, '\?', IIF(evalue is null,'NULL','$$'||evalue||'$$')||'::'||etypes_by_path[e]) into insert_str;
                                            end loop;
                                            execute insert_str;
                                            select into insert_str public.script_insert(write_to);
                                        END LOOP;                            
                                    ELSE
                                        select regexp_replace(insert_str, '\?',        trim(to_char(1, '999999999')))        into insert_str; -- id                            
                                        select regexp_replace(insert_str, '\?', ''''|| trim(to_char(1, '999999999')) ||'''') into insert_str; -- value for sp
                                        select regexp_replace(insert_str, '\?', ''''||main_path||'''')                       into insert_str; -- value for np
                                        --
                                        for e in 1..array_upper(evalues_by_path,1) loop                               
                                            select jsonb_extract_path_text_r(jb, IIF(main_path<> '', main_path|| '.', '') || evalues_by_path[e]) into evalue;
                                            select regexp_replace(
                                                insert_str, '\?',
                                                IIF(evalue is null,'NULL','$$'||evalue||'$$')||'::'||etypes_by_path[e]) into insert_str;
                                        end loop;
                                        execute insert_str;
                                    end if;
                                end if; --array_length(counts,1) > 1
                            else --if ri=1 then -- write to next tables
            ------------------------------------------ почти так же как и в последнюю таблицу MBRF
                                declare
                                    prNP CHARACTER VARYING default ''; -- значение пути по которому идет вложенность
                                    inc     integer default 1;         -- 
                                    varloop integer default 1;         -- 
                                begin
                                    if (ttmps[ri-1] is not null) then
                                        for rec in EXECUTE format('select np from %I', ttmps[ri-1]) loop 
                                            prNP:= rec.np;
                                            counts:= '{}'; -- сколько раз по этому пути повторить чтение из JSON
                                            select * into main_path,sub_path from jsonb_parse_path_r(NPlist[ri-1]);
                                            --
                                            if (main_path <> '') then
                                                select n.counts from nestedpaths as n where npath like main_path||'%' into counts;
                                            else 
                                                select n.counts from nestedpaths as n where npath='' into counts;
                                            end if;
                                            varloop:= counts[inc];
                                            --
                                            if varloop = 0 then
                                                select regexp_replace(insert_str, '\?', trim(to_char(inc, '999999999'))) into insert_str; -- parent id
                                                select regexp_replace(insert_str, '\?', trim(to_char(inc, '999999999'))) into insert_str; -- sp
                                                select regexp_replace(insert_str, '\?', ''''||NP||'''') into insert_str; -- np
                                                --
                                                for e in 1..array_upper(evalues_by_path,1) loop
                                                    select regexp_replace(insert_str, '\?', '''') into insert_str;                                    
                                                end loop;                        
                                            else
                                                for i in 1..array_length(counts,1) loop -- ?              
                                                    -- здесь sub_path <> ''
                                                    select INTO JBA jsonb_extract_path_r(JB, prNP||IIF(prNP <> '','.','')|| main_path);
                                                    select * INTO jal from jsonb_array_length(JBA);
                                                    --
                                                    select into insert_str public.script_insert(write_to);
                                                    if (JAL is not null) then
                                                        FOR j IN 0..jal-1 LOOP
                                                            NP:= prNP||
                                                                 IIF(prNP<> '','.','')||
                                                                 main_path ||'.'|| trim(to_char(j, '999999999'))||
                                                                 IIF(sub_path<> '*','.'||sub_path,'');                 
                                                            select regexp_replace(insert_str, '\?', trim(to_char(inc, '999999999'))) into insert_str; -- parent id
                                                            select regexp_replace(insert_str, '\?', trim(to_char(j, '999999999'))) into insert_str;  -- sp
                                                            select regexp_replace(insert_str, '\?', ''''||NP||'''') into insert_str; -- NP
                                                            for e in 1..array_upper(evalues_by_path,1) loop
                                                                select jsonb_extract_path_text_r(jb, NP|| '.'||evalues_by_path[e]) into evalue;
                                                                select regexp_replace(insert_str, '\?',
                                                                          IIF(evalue is null,'NULL','$$'||evalue||'$$')||'::'||etypes_by_path[e]) into insert_str;
                                                            end loop;
                                                            execute insert_str;
                                                            select into insert_str public.script_insert(write_to);                                
                                                        END LOOP;
                                                    else
                                                        select regexp_replace(insert_str, '\?', trim(to_char(inc, '999999999'))) into insert_str; -- parent id
                                                        select regexp_replace(insert_str, '\?', trim(to_char(0, '999999999'))) into insert_str; -- sp
                                                        select regexp_replace(insert_str, '\?', ''''||NP||'''') into insert_str;                                                    
                                                        for e in 1..array_upper(evalues_by_path,1) loop                                                                                                                                                                          
                                                            select regexp_replace(insert_str, '\?', 'NULL::'||etypes_by_path[e]) into insert_str;
                                                        end loop;
                                                        execute insert_str;
                                                        select into insert_str public.script_insert(write_to);                                                    
                                                    end if;
                                                end loop;
                                            end if;--varloop = 0
                                            inc:= inc+1;
                                        end loop;--for rec in EXECUTE format('select np from %I', ttmps[ri-1]) loop 
                                    end if;
                                end;
            ------------------------------------------
                            end if/*ri=1*/;
                            ri:= ri+1;
                            write_to:= ttmps[ri];  -- перейти к другой таблице с учетом
                            evalues_by_path:= '{}'; etypes_by_path:=  '{}';
                        else -- набирается строка значений для чтения пока не дойдет до NESTEDPATH. 
                             --Если до NESTEDPATH так и не дошли, то вызов был без вложений                            
                            all_evbp:= all_evbp || ARRAY[[epath, write_to]];                            
                            select array_append(evalues_by_path, epath) into evalues_by_path;
                            select array_append(etypes_by_path,  etype) into etypes_by_path;
                        end if; -- if (etype = 'NESTEDPATH') then  
                    end loop; -- for i in 1..array_upper(elems,1) loop
                    --
                    if ((ttmps[ri-1]) is not null) then -- записать значения в последнюю таблицу
            ------------------------------------------  почти так же как и в последующие таблицы MBRF
                        declare
                            prNP CHARACTER VARYING default ''; -- значение пути по которому идет вложенность
                            inc integer default 1; -- шаг по предыдущему
                            varloop integer default 1; -- количество повторений по предыдущему
                        begin
                            for rec in EXECUTE format('select np from %I', ttmps[ri-1]) loop 
                                prNP:= rec.np;
                                counts:= '{}'; -- сколько раз по этому пути повторить чтение из JSON
                                select * into main_path,sub_path from jsonb_parse_path_r(curNP);
                                if (main_path <> '') then
                                    select n.counts from nestedpaths as n where npath like main_path||'%' into counts;
                                else
                                    select n.counts from nestedpaths as n where npath='' into counts;
                                end if;
                                varloop:= counts[inc];
                                if varloop = 0 then
                                    --
                                	select into insert_str public.script_insert(write_to); 
                                    --
                                    select regexp_replace(insert_str, '\?', trim(to_char(inc, '999999999'))) into insert_str; -- parent id
                                    select regexp_replace(insert_str, '\?', trim(to_char(inc, '999999999'))) into insert_str; -- sp
                                    select regexp_replace(insert_str, '\?', ''''||NP||'''') into insert_str; -- np
                                    for e in 1..array_upper(evalues_by_path,1) loop
                                        select regexp_replace(insert_str, '\?', 'NULL::'||etypes_by_path[e]) into insert_str;                                    
                                    end loop;
                                    execute insert_str;
                                    select into insert_str public.script_insert(write_to);  
                                else
                                	select into insert_str public.script_insert(write_to);
                                    select INTO JBA jsonb_extract_path_r(JB, IIF(prNP<> '', prNP||'.', '')|| main_path); -- здесь(sub_path <> '') 
                                    -- Здесь(и не только здесь) JBA может быть не массивом, а объектом.
                                    case json_typeof(JBA::json)
                                        when 'array' then
                                            select * INTO jal from jsonb_array_length(JBA);                                            
                                            if (JAL is not null) then 
                                                FOR j IN 0..jal-1 LOOP -- по всем элементам массива
                                                    NP:= IIF(prNP<> '', prNP||'.', '')||
                                                    	main_path||'.'||trim(to_char(j, '999999999'))||
                                                        IIF(sub_path <> '*','.'||sub_path,'');
                                                    select regexp_replace(insert_str, '\?', trim(to_char(inc, '999999999'))) into insert_str; -- parent id
                                                    select regexp_replace(insert_str, '\?', trim(to_char(j, '999999999'))) into insert_str;
                                                    select regexp_replace(insert_str, '\?', ''''||NP||'''') into insert_str;
                                                    --
                                                    for e in 1..array_upper(evalues_by_path,1) loop                                    
                                                        select jsonb_extract_path_text_r(jb, NP|| '.'||evalues_by_path[e]) into evalue;
                                                        select regexp_replace(insert_str, '\?', 
                                                              --IIF(evalue is null,'NULL',''''||evalue||'''')||'::'||etypes_by_path[e]) into insert_str;
                                                              IIF(evalue is null,'NULL','$$'||evalue||'$$')||'::'||etypes_by_path[e]) into insert_str;                
                                                    end loop;
                                                    execute insert_str;
                                                    select into insert_str public.script_insert(write_to);                                
                                                END LOOP;
                                            else
                                                select regexp_replace(insert_str, '\?', trim(to_char(inc, '999999999'))) into insert_str; -- parent id
                                                select regexp_replace(insert_str, '\?', trim(to_char(0, '999999999'))) into insert_str;
                                                select regexp_replace(insert_str, '\?', ''''||NP||'''') into insert_str;
                                                for e in 1..array_upper(evalues_by_path,1) loop                                                                                                                                                                          
                                                    select regexp_replace(insert_str, '\?', 'NULL::'||etypes_by_path[e]) into insert_str;
                                                end loop;
                                                execute insert_str;
                                                select into insert_str public.script_insert(write_to);                                
                                            end if;                                            
                                        when 'object' then
                                            declare
                                                JIO jsonb; -- JSON intra object
                                                jkey character varying = '';
                                                rec_o record;
                                            begin
                                            	select count(*) from jsonb_each(JBA) into jal;
                                            	if ((JAL is not null) and (jal <> 0)) then -- not JAL here but JOL - JSON Object length
                                                	--
                                                    for rec_o in (select row_number() over() as j, key,value::jsonb from jsonb_each(JBA)) loop
                                                    	-- по всем элементам объекта
                                                        JIO:= rec_o.value;
														jkey:= rec_o.key;
                                                        --
                                                        NP:= IIF(prNP<>'',prNP||'.','')||main_path||'.'|| jkey ||
                                                             IIF(sub_path<> '*','.'||sub_path,'');
                                                        --  
                                                        select regexp_replace(insert_str, '\?', trim(to_char(inc, '999999999'))) into insert_str; -- parent id
                                                        select regexp_replace(insert_str, '\?', trim(to_char(rec_o.j, '999999999'))) into insert_str;
                                                        select regexp_replace(insert_str, '\?', ''''||NP||'''') into insert_str;
                                                        --
                                                        for e in 1..array_upper(evalues_by_path,1) loop                                    
                                                        select jsonb_extract_path_text_r(jb, NP|| '.'||evalues_by_path[e]) into evalue;
                                                        select regexp_replace(insert_str, '\?', 
                                                              --IIF(evalue is null,'NULL',''''||evalue||'''')||'::'||etypes_by_path[e]) into insert_str;                                                              
                                                              IIF(evalue is null,'NULL','$$'||evalue||'$$')||'::'||etypes_by_path[e]) into insert_str;                
                                                        end loop;
                                                        execute insert_str;
                                                        select into insert_str public.script_insert(write_to);                                                       
                                                    end loop;
                                                else
                                                	raise notice 'Rücksicht: %', '(JAL is not null) and (jal <> 0)';
                                                end if;
                                            end;
                                        else
                                            raise notice 'Rücksicht! %: %', 'not array and not object', JBA;
                                    end case;                                    
                                    --
                                end if;--varloop = 0
                                inc:= inc+1;
                            end loop;
                        end;
                    	--  собрать строку для выборки 
                        declare 
                        	c_names character varying = '';
                            al numeric = 0;
                        begin
                        	al = array_length(all_evbp,1);
                            for i in 1..array_upper(all_evbp,1) loop
                                c_names:= c_names || all_evbp[i][2]||'._'||
                                replace(replace(replace(all_evbp[i][1],'.','_'), '[', '_'),']','_')
                                ||'_'|| ' as ' || 
                                replace(replace(replace(all_evbp[i][1],'.','_'), '[', '_'),']','_');
                                if (i<> al) then
                                	c_names:= c_names ||',';
                                end if;
                            end loop;
                            --
                            bs:= 'select ' || c_names || ' from '|| chr(10);
                            bs:= bs || '     (select * from '||ttmps[1]||') as ' || ttmps[1] || chr(10);
                            if (ttmps[2] is not null) then
                                for t in 2..array_upper(ttmps,1) loop
                                    bs:= bs ||'left join (select * from '||ttmps[t]||') as ' || ttmps[t] ||
                                                            ' on ('||ttmps[t-1]||'.sp = '||ttmps[t]||'.pnp)'|| chr(10);
                                end loop;-- on ntt_0.sp = ntt_1.pnp
                            end if;
                        end;                       
                        ------------------------------------------------------------
                        for rec in EXECUTE bs
                        loop
                            return next rec;
                        end loop;            
                        ------------------------------------------------------------            
                    --else -- Например для случая not NESTED. Можно было бы написать здесь разбор with out NESTEDPATH
                    end if;
                end;  -- fill temporary tables!
            END; -- declare NESTEDPATH
        else
            DECLARE -- with out NESTEDPATH
                intra_map jsonb = null;
                bsf text = '';
                bsfval text = '';            
            BEGIN
                /* Если не указан main_path - подразумевается корневаой JSON */ -- jsonb_extract_path_r вернет в JBA значение JB
                /* Если не указан sub_path  - подразумевается выбор единичных значений из JSON */
                if sub_path = '' then
                    select into bs jsonb_make_select_r(JBA, elems);
                    --
                    for rec in EXECUTE $$ $$ || bs || $$ $$
                    loop
                        return next rec;
                    end loop;
                else
                    if ((main_path <> '') and (sub_path <> '')) 
                    or ((main_path <> '') and (sub_path = '*')) -- Example: json_table(json,  '$.map.model.map.age1[*]'
                    then -- Если указаны *_path - подразумевается выбор набора значений из списка JSON
                        if sub_path = '*' then  sub_path:= ''; end if;
                        case json_typeof(JBA::json)
                            when 'array' then                    
                                select * from jsonb_array_length(JBA) INTO jal;                    
                                if (jal <> 0) then
                                    --if sub_path = '*' then  sub_path:= ''; end if;
                                    FOR i IN 0..jal-1 LOOP
                                        bsf:= '';
                                        if (sub_path = '') then 
                                            select into intra_map jsonb_extract_path(JBA, to_char(i, '999999999'));
                                        else
                                            select into intra_map jsonb_extract_path(JBA, to_char(i, '999999999'), sub_path);
                                        end if;
                                        select into bsf jsonb_make_select_r(intra_map, elems);
                                        bs:= bs || bsf;
                                        if i <> jal-1 THEN bs:= bs || chr(10) ||'union all'|| chr(10); END IF;
                                    END LOOP;
                                end if;										
                            when 'object' then                    
                                declare
                                    JIO jsonb; -- JSON intra object
                                    jkey character varying = '';
                                    JOL integer = 0; -- JSON Object length
                                begin
                                    select count(*) from jsonb_each(JBA) into JOL;
                                    if (JOL <> 0) then
                                        for rec in (select row_number() over() as i, key,value::jsonb from jsonb_each(JBA)) loop
                                            JIO:= rec.value;
                                            jkey:= rec.key;
                                            bsf:= '';
                                            if (sub_path = '') then 
                                                select into intra_map jsonb_extract_path(JBA, jkey);
                                            else
                                                select into intra_map jsonb_extract_path(JBA, jkey, sub_path);
                                            end if;	
                                            select into bsf jsonb_make_select_r(intra_map, elems);							
                                            bs:= bs || bsf;
                                            if rec.i <> JOL THEN bs:= bs || chr(10) ||'union all'|| chr(10); END IF;						
                                        end loop;
                                    end if;
                                end;
                            else
                                raise notice '%: %', 'not array and not object', JBA;
                        end case;
                        if (bs <> '') then
                            for rec in EXECUTE $$ $$ || bs || $$ $$
                            loop
                                return next rec;
                            end loop;
                        end if;                              	
                    end if;
                end if; --if sub_path = '' then
            END; -- DECLARE -- with out NESTEDPATH
        end if; -- elems && ARRAY['NESTEDPATH']
    else 
    	--RAISE NOTICE '(%)', 'JBA IS NULL';
    end if; -- if JBA is not null then
END

$BODY$;

REVOKE ALL ON FUNCTION public.json_table(jsonb, character varying, text[]) FROM PUBLIC;

COMMENT ON FUNCTION public.json_table(jsonb, character varying, text[])
    IS 'Порт функции json_table из Oracle
json_table(
	jb jsonb,               -- JSON
	path character varying, -- основной путь по которому читать значения. Делится на main_path и sub_path	
	elems text[])           -- описание колонок в массиве [[''coltype'',''value_path''],...]
Например: -----------------------------------------
select * from public.json_table(jsonb, ''path.path1.pathlist[*].map'',
	ARRAY[[''character varying'',''path''],
    	[''character varying'',''path.1''] , 
        ...
        [''character varying'',''path.id''],
        [''NESTEDPATH'',''path[1][*]''],
        	[''character varying'',''path'']]
        ...            
) as (
    name character varying,
    name1 character varying,
	...
    nameN character varying)';
