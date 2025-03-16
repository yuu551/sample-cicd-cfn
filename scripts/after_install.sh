#!/bin/bash
# Set permissions
chmod -R 755 /var/www/html/
chown -R apache:apache /var/www/html/
# SELinuxのコンテキストを設定
restorecon -R /var/www/html/