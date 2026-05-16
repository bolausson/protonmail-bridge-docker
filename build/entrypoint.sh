#!/bin/bash

set -ex

# In the `build` image the launcher binary is `proton-bridge`; it spawns a
# child worker named `bridge`. (The deb package's single binary is named
# `protonmail-bridge` instead - hence the difference from deb/entrypoint.sh.)
# Match both by full path so neither is missed. || true keeps these calls
# no-ops when nothing is running.
kill_bridge() {
    pkill -TERM -f /protonmail/bridge        || true  # worker (stateful) first
    pkill -TERM -f /protonmail/proton-bridge || true  # then the launcher
}

# Gracefully tear the bridge down when the container is stopped/restarted so
# `docker stop` / `docker restart` (e.g. from protonmail-bridge-guardian) is
# fast and clean instead of waiting out the SIGKILL grace period.
shutdown() {
    kill_bridge
    tmux kill-server 2>/dev/null || true
    exit 0
}
trap shutdown SIGTERM SIGINT

# Initialize
if [[ $1 == init ]]; then
    shift  # drop `init` so it is not passed through to the bridge CLI

    # Initialize pass
    gpg --generate-key --batch /protonmail/gpgparams
    pass init pass-key

    # Kill any other instance as only one can be running at a time. This
    # allows users to run `entrypoint init` inside a running container,
    # which is useful in a k8s environment.
    kill_bridge

    # Login
    tmux new-session -d -s bridge-init "/protonmail/proton-bridge --cli $@"
    echo "ProtonMail Bridge init running inside tmux session 'bridge-init'"
    echo "Attach with: docker exec -it <container> tmux attach -t bridge-init"

    # `& wait` so the SIGTERM/SIGINT trap can interrupt us (a foreground
    # `sleep infinity` would defer the trap until docker SIGKILLs us).
    sleep infinity & wait $!

else

    # socat will make the conn appear to come from 127.0.0.1
    # ProtonMail Bridge currently expects that.
    # It also allows us to bind to the real ports :)
    socat TCP-LISTEN:25,fork TCP:127.0.0.1:1025 &
    socat TCP-LISTEN:143,fork TCP:127.0.0.1:1143 &

    tmux new-session -d -s bridge "/protonmail/proton-bridge --cli $@"
    echo "ProtonMail Bridge running inside tmux session 'bridge'"
    echo "Attach with: docker exec -it <container> tmux attach -t bridge"

    # Block until the bridge session ends, then exit non-zero so Docker's
    # restart policy (the guardian-less docker-compose.yml) replaces the
    # container instead of it lingering with a dead bridge. Tracing is
    # disabled so the poll loop doesn't flood `docker logs` (which the
    # guardian and operators read). `& wait` keeps the trap responsive.
    set +x
    sleep 5  # give the tmux server time to come up before the first check
    while tmux has-session -t bridge 2>/dev/null; do
        sleep 5 & wait $!
    done
    echo "Bridge tmux session ended; exiting so the container can restart."
    exit 1

fi
