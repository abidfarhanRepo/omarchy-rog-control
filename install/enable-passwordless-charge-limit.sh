#!/bin/bash
# One-time root setup so the panel's charge-limit control needs no password.
#
# Installs:
#   /usr/local/bin/rog-charge-limit        a helper that accepts only a fixed
#                                          set of levels and writes them to the
#                                          battery's charge_control_end_threshold
#   /etc/sudoers.d/50-rog-charge-limit     NOPASSWD for exactly that command
#
# Without this the panel still works — it falls back to a polkit prompt.
#
# Run with:  sudo bash install/enable-passwordless-charge-limit.sh
set -euo pipefail

(( EUID == 0 )) || { echo "Run with: sudo bash $0" >&2; exit 1; }

target_user=${SUDO_USER:-}
[[ -n $target_user ]] || { echo "Could not determine the invoking user; run via sudo, not as root directly." >&2; exit 1; }

bat=""
for b in /sys/class/power_supply/BAT*; do
  [[ -e $b/charge_control_end_threshold ]] && { bat=$b; break; }
done
[[ -n $bat ]] || { echo "No battery exposes charge_control_end_threshold on this machine." >&2; exit 1; }
echo "Battery: $bat"

echo "== Installing /usr/local/bin/rog-charge-limit =="
cat > /usr/local/bin/rog-charge-limit <<'HELPER'
#!/bin/bash
# Set the battery charge limit. Accepts only the levels the panel offers, and
# resolves the battery at runtime so it works on any laptop that exposes the
# standard sysfs attribute.
set -uo pipefail
case "${1:-}" in
  50|60|70|80|90|100) ;;
  *) echo "usage: rog-charge-limit 50|60|70|80|90|100" >&2; exit 1 ;;
esac
for b in /sys/class/power_supply/BAT*; do
  if [[ -w $b/charge_control_end_threshold ]]; then
    echo "$1" > "$b/charge_control_end_threshold"
    exit 0
  fi
done
echo "no writable charge_control_end_threshold found" >&2
exit 1
HELPER
chmod 755 /usr/local/bin/rog-charge-limit

echo "== Installing sudoers rule for $target_user =="
rule=/etc/sudoers.d/50-rog-charge-limit
printf '%s ALL=(root) NOPASSWD: /usr/local/bin/rog-charge-limit *\n' "$target_user" > "$rule"
chmod 440 "$rule"
visudo -c -f "$rule"

echo "== Verifying (must return with no prompt) =="
current=$(<"$bat/charge_control_end_threshold")
if sudo -u "$target_user" sudo -n /usr/local/bin/rog-charge-limit "$current" 2>/dev/null; then
  echo "OK: the charge-limit control is now passwordless."
else
  echo "FAILED: sudo -n still prompts. Check $rule" >&2
  exit 1
fi
