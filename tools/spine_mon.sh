#!/bin/bash

#
# Get system information including running spine jobs as JSON output
#
# How to run: ssh into a node, then run to get the instantaneous statistics.
# To create a log, use the jq command in a loop to add the previous log with
# the current output, e.g.,
# `rm -f ~/log.json; touch /tmp/log && watch -n 30 -x bash -c "cp ~/log.json /tmp/log; jq -s add <(./spine_mon.sh) /tmp/log > /tmp/log2 && mv /tmp/log2 ~/log.json"`

echo "{"

# echo "\"timestamp\": $(date +%s),"
echo \"$(date +%s)\": {

# sed command for cpu and pid only
# ^\s*(([0-9]+\.?[0-9]*)|([0-9]*\.[0-9]+))\s*.*\s([0-9]+).*\s(.*\.).*/\4 \5 \1

# get spine PIDs name being run
echo "\"spine\":{"
ps -C python -o %cpu=,pid=,args= | grep -v "defunct" \
    | grep run.py | awk '{
        pid = $2;
        cpu = $1;
        cmd = "ls -1 /proc/" pid "/fd 2>/dev/null | wc -l";
        cmd | getline fd_count;
        close(cmd);
        printf("\"%s\": {\"PID\":%s, \"cpu\": %.1f, \"fd\": %s}\n", pid, pid, cpu, fd_count);
    }' \
    | paste -sd ","
echo "},"

# cpu info 10 s interval
mpstat -P ALL -o JSON 10 1 | tr '\n' '\r' | sed 's/^.\(.*\)..$/\1/mg'

# memory
free -k | awk '{if($1=="Mem:"){printf(",\"mem\":{\"total\":%d,\"used\":%d,\"free\":%d}\n", $2, $3, $4)}}'

# disk
echo ",\"disk\":"
jq '.sysstat.hosts[0].statistics[0].disk' <(iostat -o JSON)

# gpu info
echo ",\"gpu\": {"
nvidia-smi --query-gpu=pci.bus_id,name,utilization.gpu,memory.used,memory.total --format=csv,noheader \
    | sed 's/, /,/g' | awk -F"," \
    '{
        printf("\"%s\":{\"name\": \"%s\", \"gpu\": %.1f, \"mem\":%d, \"total_mem\": %d}\n", $1, $2, $3, $4, $5)
    }' | paste -sd,
echo "}"

# Number of file descriptors (total across all user processes)
PIDS=$(ps aux | grep bearc | grep -v grep | awk '{print $2}')

TOT_FD=0
for pid in ${PIDS}; do
    if [ -d "/proc/$pid/fd" ]; then
        NFD=$(ls -1 /proc/$pid/fd 2>/dev/null | wc -l)
        TOT_FD=$((TOT_FD + NFD))
    fi
done

echo ",\"total_file_descriptors\": $TOT_FD"

echo "}}"