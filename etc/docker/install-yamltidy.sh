#!/bin/sh

set -ex

HOME=/tmp/home
cpanm -l /tmp/yamltidy --notest YAML::Tidy@v0.10.0
