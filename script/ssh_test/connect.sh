#!/bin/bash - 
#===============================================================================
#
#          FILE: connect.sh
# 
#         USAGE: ./connect.sh 
# 
#   DESCRIPTION: 
# 
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: YOUR NAME (), 
#  ORGANIZATION: 
#       CREATED: 2020年10月15日 12:30
#      REVISION:  ---
#===============================================================================

set -o nounset                              # Treat unset variables as an error

expect << __EOF
set timeout 15
spawn ssh -o "StrictHostKeyChecking no" admin@192.168.92.12
expect {
    "admin\@192.168.92.12's password:" {send "123\r"}
}
sleep 2
expect {
    "GRP2613>" {send "reboot\r"}
}
send "ls\r"
send "reboot\r"
interact

__EOF

sleep 1
exit 0
