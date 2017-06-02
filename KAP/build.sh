#!/bin/bash
echo "package solution pack"

dir=$(dirname ${0})
cd ${dir}
mkdir -p dist
pkgName="kap23-"
pkgName+=`date "+%Y%m%d"`
zip dist/"$pkgName".zip createUiDefinition.json mainTemplate.json scripts/* files/*
