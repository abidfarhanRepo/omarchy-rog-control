#!/bin/bash
# One-time root setup for the battery charge-limit control.
#
# Installs:
#   /usr/local/bin/rog-charge-limit                     a helper that accepts
#       only the levels the panel offers and writes the battery's
#       charge_control_end_threshold
#   /usr/share/polkit-1/actions/org.omarchy.rogcontrol.policy
#       a polkit action for that exact path, allowing the locally active
#       session to run it without a password
#
# This deliberately uses polkit rather than a sudoers NOPASSWD rule. The grant
# is bound to one absolute path, applies only to a local active session, and
# cannot be widened by argument because the helper whitelists its input.
#
# Without this the panel still works — it prompts through polkit instead.
#
# Run with:  sudo bash install/install-charge-limit-helper.sh
set -euo pipefail

(( EUID == 0 )) || { echo "Run with: sudo bash $0" >&2; exit 1; }

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

bat=""
for b in /sys/class/power_supply/BAT*; do
  [[ -e $b/charge_control_end_threshold ]] && { bat=$b; break; }
done
[[ -n $bat ]] || { echo "No battery on this machine exposes charge_control_end_threshold." >&2; exit 1; }
echo "Battery: $bat"

echo "== Installing /usr/local/bin/rog-charge-limit =="
cat > /usr/local/bin/rog-charge-limit <<'HELPER'
#!/bin/bash
# Set the battery charge limit. Accepts only the levels the panel offers, and
# resolves the battery at runtime so it works on any laptop exposing the
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

echo "== Installing the polkit action =="
policy=$here/org.omarchy.rogcontrol.policy
[[ -r $policy ]] || { echo "Missing $policy" >&2; exit 1; }
install -m 644 "$policy" /usr/share/polkit-1/actions/org.omarchy.rogcontrol.policy
echo "  installed: /usr/share/polkit-1/actions/org.omarchy.rogcontrol.policy"

echo
echo "Done. The panel's charge-limit control now applies without a password"
echo "for the session physically logged in at this machine."
echo "Current limit: $(<"$bat/charge_control_end_threshold")%"
