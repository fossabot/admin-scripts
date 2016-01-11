#!/bin/bash
#
# -=[ 0x19e Networks ]=-
#
# CloudFlare DNS Updater
#
# Author: rwb[at]0x19e[dot]net

wan_dns="8.8.8.8"
auth_email=""
auth_key=""
log_file=""
record_name=""
zone_name=""

if [ -e `dirname $0`/cf.cfg ]; then
  source `dirname $0`/cf.cfg
fi

# LOGGER
log() {
  if [ -n "$log_file" ]; then
    if [ "$1" ]; then
      echo -e "[$(date)] - $1" >> $log_file
    fi
  fi
}

function valid_ip()
{
  local ip=$1
  local stat=1

  if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    OIFS=$IFS
    IFS='.'
    ip=($ip)
    IFS=$OIFS
    [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
    && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
    stat=$?
  fi
  return $stat
}

function valid_hostname()
{
  local host=$1

  if [[ $host =~ ^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$ ]]; then
    return 0
  fi
  return 1
}

exit_script()
{
    # Default exit code is 1
    local exit_code=1
    local re var

    re='^([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$'
    if echo "$1" | egrep -q "$re"; then
        exit_code=$1
        shift
    fi

    re='[[:alnum:]]'
    if echo "$@" | egrep -iq "$re"; then
        echo
        if [ $exit_code -eq 0 ]; then
            echo "INFO: $@"
        else
            echo "ERROR: $@" 1>&2
        fi
    fi

    # Print 'aborting' string if exit code is not 0
    [ $exit_code -ne 0 ] && echo "Aborting script..."

    exit $exit_code
}

usage()
{
    # Prints out usage and exit.
    sed -e "s/^    //" -e "s|SCRIPT_NAME|$(basename $0)|" <<"    EOF"
    USAGE

    Update a CloudFlare DNS record using v4 API

    SYNTAX
            SCRIPT_NAME [OPTIONS]

    OPTIONS

     -e, --email <value>       The e-mail to use for authentication.
     -k, --api-key <value>     The API key to authenticate with.
     -z, --zone <value>        The zone to update.
     -r, --record <value>      The record to update.

     -a, --ip-address <value>  The IP address to update with.
     -l, --local-ip <value>    Use the local WAN IP.

     -f, --force               Skip update checks.

     -o, --log-file <value>    The log file to write output to.
     -v, --verbose             Make the script more verbose.

     -h, --help                Prints this usage.
    EOF

    exit_script $@
}

test_arg()
{
    # Used to validate user input
    local arg="$1"
    local argv="$2"

    if [ -z "$argv" ]; then
        if echo "$arg" | egrep -q '^-'; then
            usage "Null argument supplied for option $arg"
        fi
    fi

    if echo "$argv" | egrep -q '^-'; then
        usage "Argument for option $arg cannot start with '-'"
    fi
}

test_ip_arg()
{
  local arg="$1"
  local argv="$2"

  test_arg "$arg" "$argv"

  if ! valid_ip "$argv"; then
    usage "Argument specified for $arg is not a valid IP address."
  fi
}

check_verbose()
{
  if [ $VERBOSITY -gt 2 ]; then
    VERBOSE="-v"
  fi
}

VERBOSITY=0
VERBOSE=""
FORCE_UPDATE="false"
LOCAL_IP="false"
IP_ADDRESS=""

# process arguments
# [ $# -gt 0 ] || usage
while [ $# -gt 0 ]; do
  case "$1" in
    -e|--email)
      test_arg "$1" "$2"
      shift
      auth_email="$1"
      shift
    ;;
    -k|--api-key)
      test_arg "$1" "$2"
      shift
      auth_key="$1"
      shift
    ;;
    -z|--zone)
      test_arg "$1" "$2"
      shift
      zone_name="$1"
      shift
    ;;
    -r|--record)
      test_arg "$1" "$2"
      shift
      record_name="$1"
      shift
    ;;
    -f|--force)
      FORCE_UPDATE="true"
      shift
    ;;
    -l|--local-ip)
      LOCAL_IP="true"
      shift
    ;;
    -a|--ip-address)
      test_ip_arg "$1" "$2"
      shift
      IP_ADDRESS="$1"
      shift
    ;;
    -o|--log-file)
      test_arg "$1" "$2"
      shift
      log_file="$1"
      shift
    ;;
    -v|--verbose)
      ((VERBOSITY++))
      check_verbose
      shift
    ;;
    -vv)
      ((VERBOSITY++))
      ((VERBOSITY++))
      check_verbose
      shift
    ;;
    -h|--help)
      usage
    ;;
    *)
      # unknown option
      shift
    ;;
  esac
done

if [ -z "$record_name" ]; then
  usage "No record specified."
fi
if [ -z "$zone_name" ]; then
  zone_name=$(echo $record_name | grep -o '[^.]*\.[^.]*$')
fi

if [ -z "$auth_email" ]; then
  usage "Need to provide e-mail address for authentication."
fi
if [ -z "$auth_key" ]; then
  usage "Need to provide API key for authentication."
fi
if [ -z "$zone_name" ]; then
  usage "Zone not specified."
fi
if [ -z "$IP_ADDRESS" ] && [ "$LOCAL_IP" != "true" ]; then
  usage "No IP address specified and local mode not set."
fi

# print options
if [ $VERBOSITY -gt 0 ]; then
  echo AUTH. E-MAIL = "${auth_email}"
  echo AUTH. KEY    = "${auth_key}"
  echo ZONE NAME    = "${zone_name}"
  echo RECORD NAME  = "${record_name}"
fi

log "Check Initiated"

# get current A record IP
registered_ip=$(dig +short $record_name @$wan_dns)

if [ "$LOCAL_IP" == "true" ]; then
  if [ $VERBOSITY -gt 1 ]; then
    echo "Getting local WAN IP for update..."
  fi
  requested_ip=$(dig +short myip.opendns.com @resolver1.opendns.com)
else
  requested_ip="$IP_ADDRESS"
fi

if [ -z "$requested_ip" ]; then
  echo >&2 "Failed to determine IP to update with."
  exit 1
fi

if [ $VERBOSITY -gt 0 ]; then
  echo REQUESTED IP  = "${requested_ip}"
  echo REGISTERED IP = "${registered_ip}"
fi

if [ "$requested_ip" == "$registered_ip" ]; then
  echo "DNS already up to date ($registered_ip)"
  exit 0
fi

zone_identifier=$(curl $VERBOSE -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$zone_name" -H "X-Auth-Email: $auth_email" -H "X-Auth-Key: $auth_key" -H "Content-Type: application/json" | grep -Po '(?<="id":")[^"]*' | head -1 )
record_identifier=$(curl $VERBOSE -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?name=$record_name" -H "X-Auth-Email: $auth_email" -H "X-Auth-Key: $auth_key" -H "Content-Type: application/json"  | grep -Po '(?<="id":")[^"]*')

if [ -z "$zone_identifier" ]; then
  echo >&2 "Failed to retrieve zone identifier."
  exit 1
fi
if [ -z "$record_identifier" ]; then
  echo >&2 "Failed to retrieve record identifier."
  exit 1
fi

if [ $VERBOSITY -gt 1 ]; then
  echo "Zone identifier: $zone_identifier"
  echo "Record identifier: $record_identifier"
fi

update=$(curl $VERBOSE -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records/$record_identifier" -H "X-Auth-Email: $auth_email" -H "X-Auth-Key: $auth_key" -H "Content-Type: application/json" --data "{\"id\":\"$zone_identifier\",\"type\":\"A\",\"name\":\"$record_name\",\"content\":\"$requested_ip\"}")

if [[ $update == *"\"success\":false"* ]]; then
  message="API UPDATE FAILED. DUMPING RESULTS:\n$update"
  log "$message"
  echo -e "$message"
  exit 1
else
  message="IP changed to: $requested_ip"
  log "$message"
  echo "$message"
fi

exit 0