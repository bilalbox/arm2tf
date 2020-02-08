#!/bin/bash

#
# Required environment variables:
#  RTF_MULE_LICENSE:     Mule license digest (contents of a muleLicenseKey.lic)
# Optional environment variables:
#  RTF_MONITORING_PROXY: SOCKS5 proxy to use for Anypoint Monitoring publisher outbound connections (eg `socks5://192.169.1.1:1080`, `socks5://user:pass@192.168.1.1:1080`)
#  RTF_HTTP_PROXY:       Server:port to use for http/https proxy
#  RTF_NO_PROXY:         Comma-separated list of hosts to bypass the proxy. (eg 1.1.1.1,no-proxy.com)
#

set -e
CODE_COLOR="\e[32m"
CODE_END="\e[0m"

# detect OS
unameOut="$(uname -s)"
case "${unameOut}" in
    Linux*)
      Base64_OPTS="-w0"
      SED_OPTS="-i'' "
      ;;
    Darwin*)
      Base64_OPTS="-b0"
      SED_OPTS="-i '' -e"
      ;;
    *)
      Base64_OPTS="-w0"
      SED_OPTS="-i'' "
esac

ADDITIONAL_ENV_VARS=""

if [ -n "$RTF_MULE_LICENSE" ]; then
  # strip out carriage returns and line breaks to prevent sed error
  RTF_MULE_LICENSE=$(echo $RTF_MULE_LICENSE | tr -d '\r')
  RTF_MULE_LICENSE=$(echo $RTF_MULE_LICENSE | tr -d '\n')
  ADDITIONAL_ENV_VARS="RTF_MULE_LICENSE='$RTF_MULE_LICENSE';$ADDITIONAL_ENV_VARS"
fi

if [ -n "$RTF_MONITORING_PROXY" ]; then
  ADDITIONAL_ENV_VARS="RTF_MONITORING_PROXY='$RTF_MONITORING_PROXY';$ADDITIONAL_ENV_VARS"
fi

if [ -n "$RTF_HTTP_PROXY" ]; then
  ADDITIONAL_ENV_VARS="RTF_HTTP_PROXY='$RTF_HTTP_PROXY';$ADDITIONAL_ENV_VARS"
fi

if [ -n "$RTF_NO_PROXY" ]; then
  ADDITIONAL_ENV_VARS="RTF_NO_PROXY='$RTF_NO_PROXY';$ADDITIONAL_ENV_VARS"
fi

if [ -z "$ADDITIONAL_ENV_VARS" ]; then
  echo "ERROR: required environment variables not found"
  printf "  RTF_MULE_LICENSE: Mule license digest (contents of a muleLicenseKey.lic)\n"

  exit 1
fi

if [ ! -f $(pwd)/../scripts/init.sh ]; then
  echo "ERROR: init script not found in path ../scripts/init.sh. Make sure you're running this script in /azure directory"

  exit 1
fi

cp ../scripts/init.sh init.sh.tmp
ADDITIONAL_ENV_VARS=${ADDITIONAL_ENV_VARS//\//\\\/}
eval "sed $SED_OPTS \"s/# ADDITIONAL_ENV_VARS_PLACEHOLDER_DO_NOT_REMOVE/\$ADDITIONAL_ENV_VARS/g\" init.sh.tmp"

INIT_BASE64=$(cat init.sh.tmp | gzip -9 | base64 $Base64_OPTS)
INIT_BASE64=${INIT_BASE64//\//\\\/}
rm init.sh.tmp

cp ARM-template-dev.template ARM-template-dev.json
eval "sed $SED_OPTS \"s/<INIT_SCRIPT_PLACEHOLDER>/\$INIT_BASE64/g\" ARM-template-dev.json"
cp ARM-template-prod.template ARM-template-prod.json
eval "sed $SED_OPTS \"s/<INIT_SCRIPT_PLACEHOLDER>/\$INIT_BASE64/g\" ARM-template-prod.json"

printf "Your Azure Resource Template is available at: \n \
${CODE_COLOR}ARM-template-dev.json${CODE_END}\n \
${CODE_COLOR}ARM-template-prod.json${CODE_END}\n"
