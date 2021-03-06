#!/bin/bash
# get some info about the current host in a nifty one-liner
# rwb[at]0x19e.net

(date; \
 hostname --fqdn; \
 id; \
 who -apb; \
 uptime; \
 uname -a; \
 df -hT;\
 cat /proc/cpuinfo | grep "model name" |uniq -c; \
 cat /proc/meminfo | grep MemTotal |uniq -c; \
 ifconfig | grep 'inet addr'; \
 echo; \
 wget --output-document=/dev/null http://speedtest.wdc01.softlayer.com/downloads/test10.zip 2>&1 >/dev/null | grep --before-context=5 saved; \
 echo; \
 finger root; \
 lsof -i) | uniq
