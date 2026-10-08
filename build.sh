#!/bin/sh
# Build DevinUsageBar.app
set -e
cd "$(dirname "$0")"
mkdir -p DevinUsageBar.app/Contents/MacOS
swiftc -O -o DevinUsageBar.app/Contents/MacOS/DevinUsageBar main.swift
echo "Built DevinUsageBar.app — run with: open DevinUsageBar.app"
