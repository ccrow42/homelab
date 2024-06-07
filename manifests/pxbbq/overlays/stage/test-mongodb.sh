#!/bin/bash

count=$(kubectl -n pxbbq exec pods/mongo-0 -i -- bash <<EOF | sed -n 's/pxbbq> \([0-9]*\)$/\1/p'
mongosh -u porxie -p porxie
use pxbbq;
db.orders.countDocuments();
EOF
)

if [[ $count > 0 ]]; then
  # We have documents!
  exit 0
else
  # We don't have enough documents
  exit 1
fi
