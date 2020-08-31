# sinfo_mon
Sends notifications when Slurm compute nodes are down. Designed to be run via cron or equivalent.

Usage:
  sinfo_mon.sh </path/to/config_file>

The "DATA_DIR" must exist.

The contents of the config file should look something like this:
DATA_DIR="/var/local/adm/bin/sinfo_mon.data"
SINFO_PATH="/usr/slurm/bin/sinfo"
SCONTROL_PATH="/usr/slurm/bin/scontrol"
MAIL_CMD="/usr/sbin/sendmail"
CONTACT="foo@my.org"
FROM="root@mynode.my.org" # or some "no-reply" type address, etc.

