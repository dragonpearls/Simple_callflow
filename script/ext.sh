#!/bin/bash - 
#===============================================================================
#
#          FILE: ext.sh
# 
#         USAGE: ./ext.sh 
# 
#   DESCRIPTION: 
# 
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: YOUR NAME (), 
#  ORGANIZATION: 
#       CREATED: 2019年07月12日 16:43
#      REVISION:  ---
#===============================================================================

set -o nounset                              # Treat unset variables as an error

# Original Author: Michael Collins <msc@freeswitch.org>
#Standard disclaimer: batteries not included, your mileage may vary...
# Updated by Avi Marcus <avi@bestfone.com>
#
# Accepts arg of pcap file w/only 2 RTP streams
# Creates a .<codec> file and a .wav file
# For codecs other than PCMA and PCMU the script calls fs_cli and does a little recording to create the wav file(s)
# Current codec support: g711a/u, GSM, G722, G729

# check for -h -help or --help

if [[ $1 == "-h" || $1 == "-help" || $1 == "--help" || $1 == "" ]]
then
    cat <<EOF
pcap2wav is a simple utility to make it easier to extract the audio from a pcap
Dependencies:
   apt-get install -y tshark sox
   yum install wireshark sox
   
Usage:
  pcap2wav [opts] filename.pcap [target filename]
Script attempts to create a few files: a .<codec> file and a .wav file for each RTP stream
It requires Tshark to be installed on the system. If a codec other than PCMA or PCMU
 is used then the script will attempt to use fs_cli to decode and create a wav.
Supported codecs:
 PCMU (G711 ulaw)
 PCMA (G711 Alaw)
 GSM
 G722 (requires fs_encode)
 G729 (requres fs_encode with mod_com_g729)
Supported options:
 -z  Perform "clean and zip" - After converting to wav files the program will "clean up"
    by putting the wav files into a .tgz file and then removing
    the .wav and .<codec> files from the disk.
EOF

exit
fi

if [[ $1 == "-z" ]]
then
    CLEAN=true
    CAPFILE="capture.pcap"
    TARGETFILE="result"
else
    CLEAN=false
    CAPFILE="capture.pcap"
    TARGETFILE="result"
fi

LOGDIR="/var/log"
TSHARK=`which tshark`
SOX=`which sox`
FSENCODE=`which fs_encode`
error_log="./error.log"

if [[ $TSHARK == "" ]]
then
    echo "Tshark not found. Please install Tshark and then re-run this script"
    exit
fi

if [[ $SOX == "" ]]
then
    echo "Sox not found. Please install Sox and then re-run this script"
    exit
fi

# Make sure pcap exists
if [ -f $CAPFILE ]
then
    echo "Found $CAPFILE, working..." >> $error_log
else
    echo "$CAPFILE not found, exiting." >> $error_log
    exit
fi

# Set target file names; default is "pcap2wav.<codec>" and "pcap2wav.wav"
if [[ $TARGETFILE == "" ]]
then
    TARGETFILE="/tmp/pcap2wav"
else
    echo "Using $TARGETFILE" >> $error_log
fi

# Locate RTP streams, put into temp file
tshark -n -r $CAPFILE -Y rtp -T fields -e rtp.ssrc -e udp.dstport -Eseparator=, | sort -u > /tmp/pcap2wav.tmp

# Count the RTP streams
num_streams=`grep -c "" /tmp/pcap2wav.tmp`
## exist
streams=( $(cat /tmp/pcap2wav.tmp) )

echo /dev/null > /tmp/countsrc
#Extract stream ssrc and port
for item in `seq 1 $num_streams`; do
    index=$((item-1))
    echo ${index}"--"${streams[$index]} >> /tmp/countsrc
    ssrc[$item]=`echo ${streams[$index]} | cut -d, -f1`
    port[$item]=`echo ${streams[$index]} | cut -d, -f2`
done

payload_type=`tshark -n -r $CAPFILE -T fields -e rtp.p_type | grep -P '\d+' | head -n 1`
case $payload_type in
    0) codec='PCMU'
        for item in `seq 1 $num_streams`; do
            convert[$item]="$SOX -t ul -r 8000 -c 1 ${TARGETFILE}_$item.$codec ${TARGETFILE}_$item.wav"
        done
        ;;
    3) codec='GSM'
        for item in `seq 1 $num_streams`; do
            convert[$item]="$SOX -t gsm -r 8000 -c 1 ${TARGETFILE}_$item.$codec ${TARGETFILE}_$item.wav"
        done
        ;;
    8) codec='PCMA'
        for item in `seq 1 $num_streams`; do
            convert[$item]="$SOX -t al -r 8000 -c 1 ${TARGETFILE}_$item.$codec ${TARGETFILE}_$item.wav"
        done
        ;;
    9) codec='G722'
        for item in `seq 1 $num_streams`; do
            convert[$item]="$FSENCODE ${TARGETFILE}_$item.$codec ${TARGETFILE}_$item.wav"
        done
        ;;
    18) codec='G729'
        for item in `seq 1 $num_streams`; do
            convert[$item]="$FSENCODE -l mod_com_g729 ${TARGETFILE}_$item.$codec ${TARGETFILE}_$item.wav"
        done
        ;;
esac

if [ -z "$codec" ]; then
    echo "Unable to determine codec from payload type: $payload_type"
    exit
fi

echo "Target files to create:"
for item in `seq 1 $num_streams`; do
    echo "${TARGETFILE}_$item.$codec and ${TARGETFILE}_$item.wav"
done

echo
for item in `seq 1 $num_streams`; do
    echo "Stream $item ssrc / port: ${ssrc[$item]} / ${port[$item]}"
done
echo

for item in `seq 1 $num_streams`; do
    echo "Extracting payloads $item from ${ssrc[$item]}..."
    tshark -n -r $CAPFILE -Y "rtp.ssrc == ${ssrc[$item]}" -T fields -e rtp.payload > /tmp/pcap2wav.payloads${item} 2> /dev/null
    for payload in `cat /tmp/pcap2wav.payloads${item}`;do IFS=:;for byte in $payload; do printf "\\x$byte" >> ${TARGETFILE}_$item.$codec; done; done
    unset IFS
    command="${convert[$item]}"
    $command
done

# If two streams then assume they're a pair and combine them nicely
if [[ $num_streams == "2" ]]
then
    echo "Combining 2 streams into a single wav file for convenience"
    # Find shorter recording, calc time diff in samples
    samples1=`soxi -s ${TARGETFILE}_1.wav`
    samples2=`soxi -s ${TARGETFILE}_2.wav`

    if [[ $samples1 -gt $samples2 ]]
    then
        longer="${TARGETFILE}_1.wav"
        shorter="${TARGETFILE}_2.wav"
        delay=`expr $samples1 - $samples2`
    else
        longer="${TARGETFILE}_2.wav"
        shorter="${TARGETFILE}_1.wav"
        delay=`expr $samples2 - $samples1`
    fi

    pad="${delay}s"
    command="$SOX $shorter ${TARGETFILE}_tmp.wav pad $pad 0s"
    $command

    # Create "combined" file, padding beginning with silence
    command="$SOX -m ${TARGETFILE}_tmp.wav $longer ${TARGETFILE}_mixed.wav"
    $command
    rm -fr ${TARGETFILE}_tmp.wav

fi

if [[ $CLEAN == "true" ]]
then
    #echo "Clean option"
    ZIPFILE=${TARGETFILE}.tgz

    mkdir audio

    rm -fr $ZIPFILE
    /bin/tar czf $ZIPFILE ${TARGETFILE}*wav > /dev/null 2>& 1
    for item in `seq 1 $num_streams`; do
        mv  ${TARGETFILE}_$item.* audio
    done
    rm -fr $TARGETFILE.tmp
else
    echo "No clean option specified - leaving .<codec> and .wav files on system." >> $error_log 
fi
