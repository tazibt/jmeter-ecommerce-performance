#!/bin/sh
# Usage : ./run.sh [validation|charge] [options JMeter, ex. -JPAYMENT_MOCK=true]
PROFIL=${1:-validation}
[ $# -gt 0 ] && shift
RESULTS=results/$PROFIL

rm -rf "$RESULTS" && mkdir -p "$RESULTS"
jmeter -n -t tests/ecommerce.jmx -q "config/$PROFIL.properties" \
  -l "$RESULTS/result.jtl" -j "$RESULTS/jmeter.log" -e -o "$RESULTS/report" "$@"
