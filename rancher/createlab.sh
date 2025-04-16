#!/usr/bin/env bash
#
./newvm.sh create --ip 10.0.5.9 --vmname util2 --pxdisk false
#./newvm.sh create --ip 10.0.5.10 --vmname util1 --pxdisk false
./newvm.sh create --ip 10.0.5.11 --vmname rke2-01 --pxdisk false
./newvm.sh create --ip 10.0.5.12 --vmname rke2-02 --pxdisk true
./newvm.sh create --ip 10.0.5.13 --vmname rke2-03 --pxdisk true
#./newvm.sh create --ip 10.0.5.14 --vmname rke2-04 --pxdisk true
