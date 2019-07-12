
#!/bin/bash - 
#===============================================================================
#
#          FILE: extract.sh
# 
#         USAGE: ./extract.sh pcap
# 
#   DESCRIPTION: callflow project reuse
# 
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: ELI, 
#  ORGANIZATION: 
#       CREATED: 20190516 14:57
#      REVISION:  ---
#===============================================================================

set -o nounset                              # Treat unset variables as an error

TMPDIR="/tmp"
PRGNAME="test"

tshark -r ./capture.pcap -Y "sip" -t a -T fields -E separator='|' \
    -e frame.number -e ip.src -e ip.dst -e sip.CSeq -e sip.Call-ID \
    -e sdp.connection_info -e sdp.media -e sdp.media_attr | awk '
  BEGIN {
    FS = "|"
    OFS = "|"
    NOC = 1 # Number Of Call-IDs
  }
  {
    # Map the often very long Call-IDs to a short index, with only 1 or 2 digits
    if (( $5 != "" ) && ( CALLID[$5] == "" )) {
      CALLID[$5] = NOC
      NOC++
    }
    # Process connection info and obtain the ip addr
    sub("IN IP4 ", "", $6)
    # Process SDP media info and obtain the port and RTP format
    split($7, S, " ")
    PORT = S[2]
    FORMAT = S[4]
    # Process SDP media attributes and get the direction information
    if ($8 ~ "sendrecv") {
      DIRECTION = "sendrecv"
    } else if ($8 ~ "recvonly") {
      DIRECTION = "recvonly"
    } else if ($8 ~ "sendonly") {
      DIRECTION = "sendonly"
    } else if ($8 ~ "inactive") {
      DIRECTION = "inactive"
    } else {
      DIRECTION = ""
    }
    # The printf line below results in the following fields and order.  For now we assume
    # that the delivered media contains audio, but that may change one day when
    # for example audio and video are involved.
    #
    # No Description
    #  1 frame.number
    #  2 tracefile
    #  3 ip.src
    #  4 ip.dst
    #  5 sip.CSeq
    #  6 sip.Call-ID
    #  7 sdp.connection_info (ip addr)
    #  8 sdp.media (audio port)
    #  9 sdp.media (audio format)
    # 10 sdp.media_attr (audio direction (sendrecv, sendonly, recvonly))
    printf "%s||%s|%s|%s|{%s}|%s|%s|%s|%s\n", $1, $2, $3, $4, CALLID[$5], $6, PORT, FORMAT, DIRECTION
  }' > $TMPDIR/${PRGNAME}-tshark-1.$$

tshark -r ./capture.pcap -Y "sip" -t a \
    -o 'gui.column.format: "No.", "%m", "Time", %t, "Protocol", "%p", "srcport", %S, "dstport", %D, "Info", "%i"' |
      sed -e 's/^[[:blank:]]*//' \
        -e 's/[[:blank:]]*|=/=/' \
        -e 's/ Status: / /' \
        -e 's/ Request: / /' \
        -e 's/(ITU)//' \
        -e 's/SCCP (Int. ITU)/SCCP/' \
        -e 's/with session description/SDP/g' | awk '{
    # Time value ($2) looks like: 13:35:43.868013000
    # The last zeros are unwanted.  Desired time string: 13:35:43.868013
    # This strings has a length of 16.
    if (length($2) > 16 ) sub ("000$", "", $2)
    split($0, A, " ")
    # The line below results in the following fields and order.
    #
    # No Description
    #  1 frame number
    #  2 time
    #  3 protocol
    #  4 srcport
    #  5 dstport
    #  6 info
    for (i = 1; i <= 5; i++) {
      printf "%s|", $i
    }
    L = length(A)
    for (i = 6; i < L; i++) {
      printf "%s ", $i
    }
    printf "%s\n", $L
  }' > $TMPDIR/${PRGNAME}-tshark-2.$$



join -t "|" --nocheck-order $TMPDIR/${PRGNAME}-tshark-1.$$ $TMPDIR/${PRGNAME}-tshark-2.$$ > $TMPDIR/${PRGNAME}-tshark-3.$$

  # Order the fields
  awk 'BEGIN {
    FS = "|"
    # The order in which the fields will be arranged in the output file
    #
    # No Description
    #  1 time
    #  2 tracefile
    #  3 frame.number
    #  4 ip.src
    #  5 ip.srcport 
    #  6 session information
    #  7 ip.dst
    #  8 ip.dstport
    #  9 protocol
    # 10 info field
    # 11 SIP CSeq
    # 12 Connection info (IP addr)
    # 13 Media info (Port)
    # 14 Media info (Protocol)
    # 15 Media attribute direction
    # The array (A) that the 'split' command creates, maps the input fields
    # to the output file order.  As example: input field 11 is mapped to
    # output field 1 and input field 5 is mapped to output field 11.
    split("11 2 1 3 13 6 4 14 12 15 5 7 8 9 10", A, " ")
  }
  {
    # Look for "200 OK" or "200 Ok" and add the SIP method, from the
    # call sequence field to the 200 OK message.
    #
    # Attention: use the input fields values and not the ones mentioned in
    # the BEGIN part.
    # - $5 contains the sip.CSeq data.
    # - $8 contains the protocol
    # - $11 contains the info field data.
    if (($8 ~ "SIP") && ($11 ~ "200 O")) {
      # split the call sequence message (#ID SIP_method)
      split($5, S, " ")
      $11 = sprintf("%s (%s)", $11, S[2])
    }
    # Perform the actual mapping of the input to the output fields
    L = length(A)
    for (i = 1; i < L; i++) {
      printf "%s|", $A[i]
    }
    printf "%s\n", $A[L]
  }' $TMPDIR/${PRGNAME}-tshark-3.$$ > $TMPDIR/callflow.short.$$

rm $TMPDIR/${PRGNAME}-tshark-[123].$$

# Call this script with as input file, a file formatted as the callflow.short file.
 awk 'BEGIN {
    FS = "|"
    CNT = 0
    DEBUG = 0
  }
  {
    if ($0 !~ "#" ) {
      # IP address only
      ADDRESS[0] = sprintf ("%s", $4)
      ADDRESS[1] = sprintf ("%s", $7)
      # IP address with port
      ADDRPRT[0] = sprintf ("%s:%s", $4, $5)
      ADDRPRT[1] = sprintf ("%s:%s", $7, $8)
      for (i = 0; i <= 1; i++) {
        ADR = ADDRESS[i]
        if (!(ADR in NODES)) {
          # The order in which the nodes appear is important, for this
          # reason 2 arrays are used.  The order is important to keep,
          # as it gives an indication how the SIP messages flow from one
          # system to the other.
          NODES[ADR] = CNT
          POS[CNT] = ADDRESS[i]
          if (DEBUG) printf("Order: %s\nCNT: %s\n", POS[CNT], CNT)
          CNT++
        }
        # Lookup whether the IP address + port have been seen before
        POSITION = NODES[ADR]
        if (DEBUG) printf("pos: %s\n", POSITION)
        L = split(DEVICES[POSITION], DEV, "|")
        Found = 0
        for (j = 0; j <= L; j++) {
          if (DEV[j] == ADDRPRT[i]) {
            Found = 1
            break
          }
        }
        if (Found == 0) {
          L = length(DEVICES[POSITION])
          if (L == 0 ) {
            DEVICES[POSITION] = ADDRPRT[i]
          } else {
            DEVICES[POSITION] = ADDRPRT[i] "|" DEVICES[POSITION]
          }
          if (DEBUG) printf ("Fnd = 0: %s\n", DEVICES[POSITION])
        }
      }
    }
  } END {
    # Create an array with node names, the index is the IP address of the node
    if (NODENAMES != "") {
      while ( getline < NODENAMES > 0 ) {
        sub(" ", "|")
        NAMES[$1] = $2
      }
    }
    MAX = length(POS)
    for (i=0; i < MAX; i++) {
      if (POS[i] in NAMES) {
        ID = POS[i]
        ALIAS = NAMES[ID]
      } else {
        ALIAS = POS[i]
      }
      print DEVICES[i], ALIAS
    }
  }' $TMPDIR/callflow.short.$$ > $TMPDIR/callflow_node.$$

cut -d " " -f 2 $TMPDIR/callflow_node.$$ > $TMPDIR/callflow_shortnode.$$

# ** (process:1484): WARNING **: Preference "column.format" has been converted to "gui.column.format"
# get rtp for pcap2wav script
tshark -r ./capture.pcap -Y "rtp" -t a -o 'gui.column.format: "No.", "%m", "Time", %t, "Source", "%s", "Destination", "%d", "Protocol", "%p", "srcport", %S, "dstport", %D, "Info", "%i"' | uniq -f 14 | grep ", Mark" > $TMPDIR/callflow_rtp.$$
