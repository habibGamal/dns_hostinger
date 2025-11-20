#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_hostinger_info='Hostinger DNS API
Site: www.hostinger.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_hostinger
Options:
 Hostinger_API_Token API Token
Author: Hostinger API Integration
'

Hostinger_API="https://developers.hostinger.com/api/dns/v1"

########  Public functions ######################

#Usage: dns_hostinger_add _acme-challenge.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_hostinger_add() {
  fulldomain=$1
  txtvalue=$2

  Hostinger_API_Token="${Hostinger_API_Token:-$(_readaccountconf_mutable Hostinger_API_Token)}"
  if [ -z "$Hostinger_API_Token" ]; then
    _err "You must export variable: Hostinger_API_Token"
    _err "The API token for your Hostinger account is necessary."
    _err "You can create it in your Hostinger Panel: https://hpanel.hostinger.com/profile/api"
    return 1
  fi

  # Save the credentials
  _saveaccountconf_mutable Hostinger_API_Token "$Hostinger_API_Token"

  # Extract the domain and subdomain
  if ! _get_root "$fulldomain"; then
    _err "Invalid domain: $fulldomain"
    return 1
  fi

  _debug _domain "$_domain"
  _debug _sub_domain "$_sub_domain"

  # Get existing DNS records first
  _info "Getting existing DNS records for $_domain"
  if ! _hostinger_rest GET "zones/$_domain"; then
    _err "Failed to get existing DNS records"
    return 1
  fi

  # Now add the TXT record to Hostinger
  _info "Adding TXT record for $_sub_domain.$_domain"
  
  # Build the JSON payload
  _json_payload="{\"overwrite\":false,\"zone\":[{\"name\":\"$_sub_domain\",\"type\":\"TXT\",\"ttl\":14400,\"records\":[{\"content\":\"$txtvalue\"}]}]}"
  
  if _hostinger_rest PUT "zones/$_domain" "$_json_payload"; then
    _info "TXT record has been successfully added to your Hostinger domain."
    return 0
  else
    _err "Failed to add TXT record"
    return 1
  fi
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_hostinger_rm() {
  fulldomain=$1
  txtvalue=$2

  Hostinger_API_Token="${Hostinger_API_Token:-$(_readaccountconf_mutable Hostinger_API_Token)}"
  if [ -z "$Hostinger_API_Token" ]; then
    _err "You must export variable: Hostinger_API_Token"
    _err "The API token for your Hostinger account is necessary."
    _err "You can create it in your Hostinger Panel: https://hpanel.hostinger.com/profile/api"
    return 1
  fi

  # Extract the domain and subdomain
  if ! _get_root "$fulldomain"; then
    _err "Invalid domain: $fulldomain"
    return 1
  fi

  _debug _domain "$_domain"
  _debug _sub_domain "$_sub_domain"

  # Remove the TXT record from Hostinger
  _info "Removing TXT record for $_sub_domain.$_domain"
  
  # Build the JSON payload for deletion
  _json_payload="{\"filter\":[{\"name\":\"$_sub_domain\",\"type\":\"TXT\"}]}"
  
  if _hostinger_rest DELETE "zones/$_domain" "$_json_payload"; then
    _info "TXT record has been successfully removed from your Hostinger domain."
    return 0
  else
    _err "Failed to remove TXT record"
    return 1
  fi
}

####################  Private functions below ##################################

# Extract the root domain and subdomain
# _acme-challenge.subdomain.domain.com -> domain.com + _acme-challenge.subdomain
# _acme-challenge.domain.com -> domain.com + _acme-challenge
_get_root() {
  fulldomain=$1

  # Split the domain into parts
  IFS='.' read -r -a parts <<< "$fulldomain"
  len=${#parts[@]}

  # Only handle simple 2-3 level domains for now
  if [ "$len" -lt 2 ]; then
    _err "Invalid domain: $fulldomain"
    return 1
  fi

  # Try the last two parts first (domain.tld)
  root="${parts[$len-2]}.${parts[$len-1]}"
  subdomain=$(printf "%s" "$fulldomain" | sed "s/\.$root\$//")

  # Verify zone exists on Hostinger
  if _hostinger_rest GET "zones/$root"; then
    _domain="$root"
    _sub_domain="$subdomain"
    return 0
  fi

  # If domain has 3 parts, try last three parts (e.g., co.uk)
  if [ "$len" -ge 3 ]; then
    root="${parts[$len-3]}.${parts[$len-2]}.${parts[$len-1]}"
    subdomain=$(printf "%s" "$fulldomain" | sed "s/\.$root\$//")
    if _hostinger_rest GET "zones/$root"; then
      _domain="$root"
      _sub_domain="$subdomain"
      return 0
    fi
  fi

  _err "Could not detect Hostinger zone for $fulldomain"
  return 1
}

#Usage: method URI [data]
_hostinger_rest() {
  method=$1
  endpoint="$2"
  data="$3"

  _debug method "$method"
  _debug endpoint "$endpoint"
  _debug data "$data"

  url="$Hostinger_API/$endpoint"
  _debug url "$url"

  export _H1="Authorization: Bearer $Hostinger_API_Token"
  export _H2="Content-Type: application/json"
  export _H3="Accept: application/json"

  if [ "$method" = "GET" ]; then
    response="$(_get "$url")"
  elif [ "$method" = "PUT" ]; then
    response="$(_post "$data" "$url" "" "PUT")"
  elif [ "$method" = "DELETE" ]; then
    response="$(_post "$data" "$url" "" "DELETE")"
  else
    _err "Unsupported HTTP method: $method"
    return 1
  fi

  _debug2 response "$response"

  # Check if the response contains an error
  if _contains "$response" '"error"'; then
    _err "API error: $response"
    return 1
  fi

  return 0
}
