#!/bin/bash

sudo k3s kubectl get svc -A | grep zabbix | grep 18080

# sudo k3s kubectl get pods -A
# sudo service docker restart; sudo service k3s restart; sudo service docker restart; sudo service docker status; sudo service k3s status


