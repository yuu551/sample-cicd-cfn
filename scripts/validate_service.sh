#!/bin/bash
# Check if Apache is running
if systemctl is-active --quiet httpd; then
  echo "Apache is running"
  exit 0
else
  echo "Apache is not running"
  exit 1
fi