#!/bin/bash


# enable security
yq -i '.spec.security.enabled = true' $1
# disable checks due to https://portworx.atlassian.net/browse/PWX-32111?atlOrigin=eyJpIjoiN2M1NTFiZTY3MTVkNDkwMTliNmM4Zjc0MDY2ODhjZmEiLCJwIjoiamlyYS1zbGFjay1pbnQifQ
#yq -i '.metadata.annotations."portworx.io/preflight-check" = "skip"' px-spec.yaml
# disable guest access
yq -i '.spec.security.auth.guestAccess = "Disabled"' $1