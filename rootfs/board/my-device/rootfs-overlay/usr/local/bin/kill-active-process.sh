#!/bin/sh
# SIGKILL to the running app (appd); same as FN + START + SELECT
exec /usr/local/bin/appctl kill-application
