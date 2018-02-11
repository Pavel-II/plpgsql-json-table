# plpgsql-json-table
Porting the json_table function from Oracle to PostgreSQL

# Example:
select * from json_table(
'{"dateLimits":{"lowerBound":1800,"upperBound":2100},"inclusions":[{"operator":"and","searchFieldConfigid":"1","term":"mountain and lake"},{"operator":"and","searchFieldConfigid":"3","term":"jokes stories"},{"operator":"or","searchFieldConfigid":"8","term":"\"folklore and legends\""}],"exclusions":[{"operator":"and","searchFieldConfigid":"3","term":"desert and ocean"},{"operator":"and","searchFieldConfigid":"4","term":"exercise running"},{"operator":"or","searchFieldConfigid":"9","term":"\"hiking and swimming\""}]}'::jsonb,
	'inclusions[*]',
	ARRAY[['character varying', 'operator'],
		['numeric', 'searchFieldConfigid'],
['character varying', 'term']])
	as (
	a1 character varying,
	a2 numeric,
	a3 character varying
	)

