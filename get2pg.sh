#!/bin/bash

#
# Convert Oracle json_table format to PostgreSQL json_table
#

# run: echo "" > 2pars && vim 2pars && ./get2pg.sh 2pars | less # paste columns list to vim and close it

if [ $1 = 'run' ];
then
    echo RUN
    echo "" > 2pars && vim 2pars && ./get2pg.sh 2pars | less
    exit;
fi

echo ',ARRAY[';

i=0

while read LINE;
do
    L=`echo "$LINE" | sed 's/ \{1,\}/ /g' | sed 's/^[ \t]*//'`;
    COL_NAME=`echo $L | awk '{print $1}'`;
    COL_TYPE=`echo $L | awk '{print $2}'`;
    SPATH=`echo $L | awk -F "'" '{print $2}' | sed -e 's/\$\.//g'`;
    COMENT=`echo $L | awk -F "," '{print $2}'`;
    #
    if [ $COL_NAME == "NESTED" ];
    then
	COL_TYPE="NESTEDPATH"
    fi
    #
    echo -n '['\'$COL_TYPE\' | sed 's/varchar2/character varying/g' | sed 's/number/numeric/g' | sed 's/VARCHAR2/character varying/g' 
    echo ','\'$SPATH\''],'$COMENT;

done < 2pars

echo ']) as d(';

i=0

while read LINE;
do
    L=`echo "$LINE" | sed 's/ \{1,\}/ /g' | sed 's/^[ \t]*//'`;
    COL_NAME=`echo $L | awk '{print $1}'`;
    COL_TYPE=`echo $L | awk '{print $2}'`;
    COMENT=`echo $L | awk -F "," '{print $2}'`;
    #
    if [ $COL_NAME != "NESTED" ]; then 

    echo $COL_NAME' '$COL_TYPE','$COMENT |\
	sed 's/varchar2/character varying/g' |\
	sed 's/number/numeric/g' |\
	sed 's/VARCHAR2/character varying/g';
    fi
done < 2pars

echo ')';

echo 'NB!: Delete last , REPLACE s/number/numeric/g AND s/VARCHAR2/character varying/g'
