#!/bin/sh

help() {
    cat <<EOF
Command line:
  -h  Display this help
  -d  Dry run to update the configuration files.
  -f  Always update on the configuration files (existing files are renamed with
      the .old suffix).  Without this option, the new configuration files are
      copied with the .new suffix
Environment variables:
  INSTANCE_NAME settings.yml : general.instance_name
  AUTOCOMPLETE  settings.yml : search.autocomplete
  BASE_URL      settings.yml : server.base_url

Volume:
  /etc/searxng  the docker entry point copies settings.yml and uwsgi.ini in
                this directory (see the -f command line option)"

EOF
}

# Parse command line
FORCE_CONF_UPDATE=0
DRY_RUN=0

while getopts "fdh" option
do
    case $option in

        f) FORCE_CONF_UPDATE=1 ;;
        d) DRY_RUN=1 ;;

        h)
            help
            exit 0
            ;;
        *)
            echo "unknow option ${option}"
            exit 42
            ;;
    esac
done

echo "SearXNG version $SEARXNG_VERSION"

# helpers to update the configuration files
patch_uwsgi_settings() {
    CONF="$1"

    # update uwsg.ini
    sed -i \
        -e "s|workers = .*|workers = ${UWSGI_WORKERS:-%k}|g" \
        -e "s|threads = .*|threads = ${UWSGI_THREADS:-4}|g" \
        "${CONF}"
}

patch_searxng_settings() {
    CONF="$1"

    # Make sure that there is trailing slash at the end of BASE_URL
    # see https://www.gnu.org/savannah-checkouts/gnu/bash/manual/bash.html#Shell-Parameter-Expansion
    export BASE_URL="${BASE_URL%/}/"

    # update settings.yml
    sed -i \
        -e "s|base_url: false|base_url: ${BASE_URL}|g" \
        -e "s/instance_name: \"SearXNG\"/instance_name: \"${INSTANCE_NAME}\"/g" \
        -e "s/autocomplete: \"\"/autocomplete: \"${AUTOCOMPLETE}\"/g" \
        -e "s/ultrasecretkey/$(head -c 24 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9')/g" \
        "${CONF}"
}

# FIXME: Always use "searxng:searxng" ownership
update_conf() {
    FORCE_CONF_UPDATE=$1
    CONF="$2"
    NEW_CONF="${2}.new"
    OLD_CONF="${2}.old"
    REF_CONF="$3"
    PATCH_REF_CONF="$4"

    if [ -f "${CONF}" ]; then
        if [ "${REF_CONF}" -nt "${CONF}" ]; then
            # There is a new version
            if [ "$FORCE_CONF_UPDATE" -ne 0 ]; then
                # Replace the current configuration
                printf '⚠️  Automatically update %s to the new version\n' "${CONF}"
                if [ ! -f "${OLD_CONF}" ]; then
                    printf 'The previous configuration is saved to %s\n' "${OLD_CONF}"
                    mv "${CONF}" "${OLD_CONF}"
                fi
                cp "${REF_CONF}" "${CONF}"
                $PATCH_REF_CONF "${CONF}"
            else
                # Keep the current configuration
                printf '⚠️  Check new version %s to make sure SearXNG is working properly\n' "${NEW_CONF}"
                cp "${REF_CONF}" "${NEW_CONF}"
                $PATCH_REF_CONF "${NEW_CONF}"
            fi
        else
            printf 'Use existing %s\n' "${CONF}"
        fi
    else
        printf 'Create %s\n' "${CONF}"
        cp "${REF_CONF}" "${CONF}"
        $PATCH_REF_CONF "${CONF}"
    fi
}

# make sure there are uwsgi settings
update_conf "${FORCE_CONF_UPDATE}" "${UWSGI_SETTINGS_PATH}" "/usr/local/searxng/container/uwsgi.ini" "patch_uwsgi_settings"

# make sure there are searxng settings
update_conf "${FORCE_CONF_UPDATE}" "${SEARXNG_SETTINGS_PATH}" "/usr/local/searxng/searx/settings.yml" "patch_searxng_settings"

# dry run (to update configuration files, then inspect them)
if [ $DRY_RUN -eq 1 ]; then
    printf 'Dry run\n'
    exit
fi

printf 'Listen on %s\n' "${BIND_ADDRESS}"

# Start uwsgi
# TODO: "--http-socket" will be removed in the future (see uwsgi.ini.new config file): https://github.com/searxng/searxng/pull/4578
exec /usr/local/searxng/venv/bin/uwsgi --http-socket "${BIND_ADDRESS}" "${UWSGI_SETTINGS_PATH}"
