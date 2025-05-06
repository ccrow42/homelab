scp ~/personal/homelab/firewall/* ubuntu@10.0.1.1:/home/ubuntu/
ssh ubuntu@10.0.1.1 "sudo /home/ubuntu/fw2.sh"
ssh ubuntu@10.0.1.1 "sudo iptables-save | sudo tee /etc/iptables/rules.v4"
#ssh ubuntu@10.0.1.1 "sudo /home/ubuntu/fw2-blocklist.sh"