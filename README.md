# XYmonscripts
some external scripts for XYmon

### age.sh
This script monitors files or whole directories when they were last updated and alerts if the last update of them has happened before the given threshold.

### cpu.sh
This script is an alternative load check that can be used to alert at different values than the default check and for a different hostname.

### disk.sh
This script is an alternative disk check for which different mount points will alert different teams.

### gate.sh
This script monitors the GATE architecture of a MISS server (middleware of the German stock exchange).

### hphealth.sh
This script monitors the health of HP servers. hpasmcli, hpacucli are required. Also fio-status and fio-pci-check if you want to monitor SSDs. Additionally, check_hpasm is required.

### logger.sh
This script is an alternative check for log files which will alert different teams.

### oraprocs.sh
This script is used for checking Oracle related processes and alert different teams upon an alert.

### ports.sh
This script is an alternative ports check where monitoring time of ports can be limited and different teams can be alerted for different ports.

### rports.sh
This script is used if certain ports are available on a remote server. Netcat needs to be available on the server where this script runs.

### sendalert.sh
This script is used for sending out notifications about alerts to a Telegram bot.
