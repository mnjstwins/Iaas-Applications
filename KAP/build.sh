#!/bin/bash
echo "package solution pack"

dir=$(dirname ${0})
cd ${dir}
mkdir -p dist
zip dist/kap23.zip createUiDefinition.json mainTemplate.json scripts/* files/*
