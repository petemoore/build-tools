#!/bin/bash
mar_url="${1}"
failures="${2}"
curl --retry 5 --retry-max-time 30 -k -s -I -L "${mar_url}" >/dev/null 2>&1 && echo "${mar_url} succeeded" || echo "FAILURE: Could not retrieve http header for mar file from ${mar_url}" | tee -a "${failures}"
