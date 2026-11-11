#! /bin/bash

mkdir -p device-ca

docker run --rm -it \
    -v "$PWD/device-ca:/home/step" \
    smallstep/step-ca \
    step ca init