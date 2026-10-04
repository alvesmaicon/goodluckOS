#!/bin/sh
# SIGTERM to the running app (appd); same as START + SELECT
exec /usr/local/bin/appctl stop-application
