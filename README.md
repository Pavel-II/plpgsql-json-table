# plpgsql-json-table
Porting the json_table function from Oracle to PostgreSQL

# Example:
query
```SQL
select * from json_table(
	'{
  "dateLimits": {
    "lowerBound": 1800,
    "upperBound": 2100
  },
  "inclusions": [
    {
      "operator": "and",
      "searchFieldConfigid": "1",
      "term": "mountain and lake"
    },
    {
      "operator": "and",
      "searchFieldConfigid": "3",
      "term": "jokes stories"
    },
    {
      "operator": "or",
      "searchFieldConfigid": "8",
      "term": "\"folklore and legends\""
    }
  ],
  "exclusions": [
    {
      "operator": "and",
      "searchFieldConfigid": "3",
      "term": "desert and ocean"
    },
    {
      "operator": "and",
      "searchFieldConfigid": "4",
      "term": "exercise running"
    },
    {
      "operator": "or",
      "searchFieldConfigid": "9",
      "term": "\"hiking and swimming\""
    }
  ]
}'::jsonb, 					
	'inclusions[*]', 
	ARRAY[
		['character varying', 'operator'], 
		['numeric', 'searchFieldConfigid'], 
		['character varying', 'term']]
) as (
	operator character varying,
	searchFieldConfigid numeric,
	term character varying)

```
return

operator<br />character varying | searchFieldConfigid<br />numeric| term<br />character varying
------------ | ------------ | -------------
and|1|mountain and lake
and|3|jokes stories
or|8|folklore and legends
