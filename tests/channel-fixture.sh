#!/usr/bin/env bash
# Local stand-in for a GitHub repository with deploy keys: an unprivileged
# sshd on 127.0.0.1 serving one bare git repository, with
#   licence.key    read-only key (git-upload-pack only), as a GitHub deploy key
#   publisher.key  read-write key, as the vendor's release credentials
#
#   channel-fixture.sh start <dir> [port]   prints the remote URL
#   channel-fixture.sh stop  <dir>
set -euo pipefail

cmd=${1:?usage: $0 start|stop <dir> [port]}
dir=$(realpath -m "${2:?usage: $0 start|stop <dir> [port]}")
port=${3:-22222}

case "$cmd" in
stop)
  if [ -f "$dir/sshd.pid" ]; then
    kill "$(cat "$dir/sshd.pid")" && rm -f "$dir/sshd.pid"
  fi
  exit 0 ;;
start) ;;
*) echo "$0: unknown command $cmd" >&2; exit 2 ;;
esac

mkdir -p "$dir"
cd "$dir"
[ -f hostkey ] || ssh-keygen -q -t ed25519 -N '' -f hostkey -C fixture-host
[ -f licence.key ] || ssh-keygen -q -t ed25519 -N '' -f licence.key -C licence
[ -f publisher.key ] || ssh-keygen -q -t ed25519 -N '' -f publisher.key -C publisher
[ -d channel.git ] || git init --quiet --bare channel.git

# Read-only: only git-upload-pack (fetch) of this one repository is allowed.
cat > readonly-shell <<EOF
#!/usr/bin/env bash
case "\$SSH_ORIGINAL_COMMAND" in
  "git-upload-pack '$dir/channel.git'"|"git-upload-pack $dir/channel.git") exec git-shell -c "\$SSH_ORIGINAL_COMMAND" ;;
  *) echo "fixture: licence key is read-only, refused: \$SSH_ORIGINAL_COMMAND" >&2; exit 1 ;;
esac
EOF
chmod 755 readonly-shell
{
  echo "command=\"$dir/readonly-shell\",no-pty,no-port-forwarding,no-agent-forwarding,no-X11-forwarding $(cat licence.key.pub)"
  echo "command=\"git-shell -c \\\"\$SSH_ORIGINAL_COMMAND\\\"\",no-pty,no-port-forwarding $(cat publisher.key.pub)"
} > authorized_keys
chmod 600 authorized_keys

cat > sshd_config <<EOF
Port $port
ListenAddress 127.0.0.1
HostKey $dir/hostkey
AuthorizedKeysFile $dir/authorized_keys
PidFile $dir/sshd.pid
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
StrictModes no
AllowUsers $USER
EOF
echo "[127.0.0.1]:$port $(cut -d' ' -f1,2 hostkey.pub)" > known_hosts

if [ -f sshd.pid ] && kill -0 "$(cat sshd.pid)" 2> /dev/null; then
  kill "$(cat sshd.pid)"
  rm -f sshd.pid
fi
/usr/sbin/sshd -f "$dir/sshd_config" -E "$dir/sshd.log"
for _ in $(seq 50); do [ -f sshd.pid ] && break; sleep 0.1; done
[ -f sshd.pid ] || { echo "$0: sshd did not start, see $dir/sshd.log" >&2; exit 1; }
echo "ssh://$USER@127.0.0.1:$port$dir/channel.git"
