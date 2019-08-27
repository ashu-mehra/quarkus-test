#!/bin/bash

while [[ "$(curl -s -o /dev/null -w ''%{http_code}'' localhost:8080/greeting)" != "200" ]]; do sleep .00001; done
