scp ~/personal/homelab/firewall/* ubuntu@10.0.1.1:/home/ubuntu/

if [[ $1 == "enable_vpn" ]]; then
    ssh ubuntu@10.0.1.1 "sudo /home/ubuntu/fw2.sh enable_vpn"
else
    ssh ubuntu@10.0.1.1 "sudo /home/ubuntu/fw2.sh"
fi
ssh ubuntu@10.0.1.1 "sudo iptables-save | sudo tee /etc/iptables/rules.v4"
#ssh ubuntu@10.0.1.1 "sudo /home/ubuntu/fw2-blocklist.sh"