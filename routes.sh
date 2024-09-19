#!/usr/bin/env bash

search_dir=routes
for filename in "$search_dir"/*
do
  echo "file = $filename"
  while read -r line; do
      echo "ip rule add from 10.66.66.0/24 to $line lookup 210"
  done < "$filename"
done