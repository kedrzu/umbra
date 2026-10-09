#!/bin/zsh
# Kto budzi Maca pakietem z sieci? Diagnoza wybudzeń E_RX_IP_PACKET.
#
# Po co: przy zamkniętej klapie karta Wi-Fi zostaje w sieci i budzi system, gdy
# przyjdzie pakiet na otwarty port jakiejkolwiek aplikacji. pmset tego nie wyłącza
# (tcpkeepalive/womp/powernap = 0, a wybudzeń dalej setki na godzinę).
#
# Jądro trzyma nagłówek ostatniego pakietu budzącego w sysctl
# net.link.generic.system.port_used.last_unattributed_wake_event - czytelny bez roota.
# Zbieracz co sekundę sprawdza, czy pojawił się nowy, wyciąga z niego adres i porty,
# a lokalny port mapuje przez lsof na proces, który go trzyma.
#
# Tryby:
#   ./scripts/wake-attribution.sh start     # zbieraj (sam kończy po MAX_HOURS)
#   ./scripts/wake-attribution.sh stop
#   ./scripts/wake-attribution.sh report    # kto budził, posortowane
#
# Z sudo `start` dodatkowo włącza port_used.verbose (jądro loguje więcej szczegółów).

set -u

SELF="$0"
MAX_HOURS=36
POLL_SECONDS=1
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(dscl . -read "/Users/$TARGET_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
TARGET_HOME="${TARGET_HOME:-$HOME}"
LOG_FILE="$TARGET_HOME/Library/Logs/wake-attribution.log"
PID_FILE="$TARGET_HOME/.cache/wake-attribution.pid"
SYSCTLS=(net.link.generic.system.port_used.verbose net.link.generic.system.wake_pkt_debug)

COLLECTOR='
import ctypes, ctypes.util, subprocess, sys, time, datetime, socket
libc = ctypes.CDLL(ctypes.util.find_library("c"), use_errno=True)
KEYS = ["net.link.generic.system.port_used.last_unattributed_wake_event",
        "net.link.generic.system.port_used.last_attributed_wake_event"]
def get(name):
    size = ctypes.c_size_t(4096)
    buf = ctypes.create_string_buffer(4096)
    if libc.sysctlbyname(name.encode(), buf, ctypes.byref(size), None, 0) != 0:
        return None
    return buf.raw[:size.value]
def local_ips():
    out = subprocess.run(["ifconfig"], capture_output=True, text=True).stdout
    return [socket.inet_aton(l.split()[1]) for l in out.splitlines()
            if l.strip().startswith("inet ") and not l.split()[1].startswith("127.")]
def owner(port):
    out = subprocess.run(["lsof", "-nP", "-i", f":{port}", "-Fcp"], capture_output=True, text=True).stdout
    names = sorted({l[1:] for l in out.splitlines() if l.startswith("c")})
    pids = sorted({l[1:] for l in out.splitlines() if l.startswith("p")})
    pid_list = ",".join(pids)
    return (",".join(names) or "?") + (f" (pid {pid_list})" if pids else "")
def decode(b):
    # Nagłówek jest w strukturze jako surowe pola: [src ip][dst ip][src port][dst port].
    for ip in local_ips():
        i = b.find(ip)
        if i >= 4:
            src = socket.inet_ntoa(b[i-4:i])
            sport = int.from_bytes(b[i+4:i+6], "big")
            dport = int.from_bytes(b[i+6:i+8], "big")
            return f"{src}:{sport} -> :{dport}", dport
    return "nie rozpoznano adresu", None
log = open(sys.argv[1], "a", buffering=1)
deadline = time.time() + float(sys.argv[2]) * 3600
now = lambda: datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
log.write(f"{now()} START\n")
last = {}
while time.time() < deadline:
    for k in KEYS:
        b = get(k)
        if b and any(b) and b != last.get(k):
            fresh = k in last          # pierwszy odczyt = stare zdarzenie sprzed startu
            last[k] = b
            if not fresh:
                continue
            flow, dport = decode(b)
            who = owner(dport) if dport else "?"
            log.write(f"{now()} WAKE\t{who}\t{flow}\n")
    time.sleep(float(sys.argv[3]))
log.write(f"{now()} STOP (limit czasu)\n")
'

stop_collector() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(<"$PID_FILE")
        kill "$pid" 2>/dev/null && print -r -- "Zatrzymałem zbieracza (pid $pid)."
        rm -f "$PID_FILE"
    fi
}

case "${1:-}" in
    start)
        stop_collector
        if [[ $EUID -eq 0 ]]; then
            for s in $SYSCTLS; do sysctl -w "$s=1" > /dev/null 2>&1 && print -r -- "  ✓ $s=1"; done
        fi
        mkdir -p "${PID_FILE:h}" "${LOG_FILE:h}"
        nohup /usr/bin/python3 -c "$COLLECTOR" "$LOG_FILE" "$MAX_HOURS" "$POLL_SECONDS" > /dev/null 2>&1 &
        print -r -- $! > "$PID_FILE"
        print -r -- "Zbieracz działa (pid $!, max ${MAX_HOURS} h). Log: $LOG_FILE"
        ;;
    stop)
        stop_collector
        if [[ $EUID -eq 0 ]]; then
            for s in $SYSCTLS; do sysctl -w "$s=0" > /dev/null 2>&1; done
        fi
        ;;
    report)
        [[ -f "$LOG_FILE" ]] || { print -r -- "Brak $LOG_FILE - najpierw: $SELF start"; exit 1; }
        total=$(grep -c "WAKE" "$LOG_FILE")
        print -r -- "=== Wybudzenia z pakietu wg procesu (łącznie $total) ==="
        grep "WAKE" "$LOG_FILE" | cut -f2 | sed -E 's/ \(pid.*//' | sort | uniq -c | sort -rn | head -15
        print; print -r -- "=== Nadawcy (adres zdalny) ==="
        grep "WAKE" "$LOG_FILE" | cut -f3 | sed -E 's/:[0-9]+ ->.*//' | sort | uniq -c | sort -rn | head -10
        ;;
    *)
        sed -n '2,19p' "$SELF" | sed 's/^# \{0,1\}//'
        exit 1
        ;;
esac
