#!/bin/bash

# Check if a file is provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <file_with_ip_list>"
    exit 1
fi

FILE=$1

# Check if file exists
if [ ! -f "$FILE" ]; then
    echo "Error: File '$FILE' not found!"
    exit 1
fi

# Loop through each line in the file
while IFS= read -r IP; do
    # Trim leading/trailing whitespace and remove Windows-style carriage return
    IP="$(echo -n "$IP" | tr -d '\r' | xargs)"
    
    # Skip empty lines and comments
    if [[ -z "$IP" || "$IP" =~ ^# ]]; then
        continue
    fi
    echo "Blocking IP: $IP"
    
    # Block incoming and outgoing traffic for the IP
    iptables -A INPUT -s "$IP" -j DROP
    iptables -A OUTPUT -d "$IP" -j DROP
    iptables -A FORWARD -d "$IP" -j DROP
    iptables -A FORWARD -s "$IP" -j DROP

done < "$FILE"
