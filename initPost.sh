#! /usr/bin/bash

filename="$(date +%Y-%m-%d)-$1.md"

index=0
tags=""
for i in $@
do 
    if [ $index -gt 1 ]
    then 
        if [ -z "$tags" ]
        then
            tags="$i"
        else
            tags="$tags,$i"
        fi
    fi 
    index=$((index+1))
done

touch "$filename"
echo "---" >> $filename
echo "title: $1 " >> $filename
echo "date: $(date +%Y-%m-%d) " >> $filename
echo "description: $2 " >> $filename
echo "tags: [$tags] " >> $filename
echo "author: Jameslahm " >> $filename
echo "key: $1" >> $filename

echo "---" >> $filename