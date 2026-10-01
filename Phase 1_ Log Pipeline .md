# **CyberSafe Lab — Phase 1: Log Pipeline** 

Phase 1 wired up the log pipeline — the plumbing that carries evidence from every machine into one searchable place. Every action on a host (a login, a new process, a blocked connection) leaves a log entry. On its own that entry sits on the machine where it happened. The pipeline collects those entries from every machine and ships them into one place to search: **Wazuh** (the SIEM) on **WAZUH01 at 10.10.50.10**.

The principle behind doing this first: you cannot detect what you cannot see. If DC01 isn't sending its logs, a brute-force attack against it is invisible — no alert, no evidence. Phase 1 is the groundwork that makes every later phase work — security cameras installed before the break-in, not after.

## **What Phase 1 delivered**

* A Wazuh agent on every machine VM (DC01, WIN11-CLIENT, WEBSERVER01, DBSERVER01), shipping logs to WAZUH01.  
* Detailed Windows audit logging, so failed logins and new processes are actually recorded.  
* Sysmon on the Windows boxes, capturing process trees, network connections, and file/registry changes.  
* pfSense firewall logs flowing into Wazuh for network-level visibility.  
* A written baseline of what "normal" looks like, so abnormal stands out later.

---

## **Environment**

| VM | IP | OS | Role in Phase 1 |
| ----- | ----- | ----- | ----- |
| WAZUH01 | 10.10.50.10 | Linux | SIEM — receives all logs (manager \+ dashboard) |
| DC01 | 10.10.20.10 | Windows Server | Domain controller — agent \+ audit policy |
| WIN11-CLIENT | 10.10.20.11 | Windows 11 | Workstation — agent \+ Sysmon |
| WEBSERVER01 | 10.10.30.10 | Ubuntu | Web host — Linux agent |
| DBSERVER01 | 10.10.40.10 | Ubuntu | Database host — Linux agent |
| pfSense | .1 on each VLAN | pfSense | Firewall — sends syslog to WAZUH01 |
| KALI-JUMPBOX | 10.10.0.50 | Kali | Attacker — untouched in Phase 1 |

## **Prerequisites that were in place**

* Admin access on every box: Domain Admin for Windows, a sudo user on Ubuntu, and the pfSense web login.  
* Proxmox snapshots taken before changes, for fast rollback.  
* Network reachability from each machine VM to the SIEM confirmed (agent on TCP 1514; pfSense syslog on UDP 514; both allowed through pfSense from the VLANs to SECOPS, 10.10.50.0/24).  
* Dashboard access at `https://10.10.50.10`.

Order the steps were completed in: install agents (1) → Windows audit logging (2) → Sysmon (3) → Wazuh collects Sysmon (4) → pfSense syslog (5) → verify \+ baseline (6).

---

## **Step 1 — Wazuh agent on every VM**

The agent is a small program on each machine that reads its logs and forwards them to WAZUH01. The dashboard's **Deploy new agent** wizard generated the exact install command per OS (server address `10.10.50.10`, agent name \= hostname).

* **Windows boxes (DC01, WIN11-CLIENT):** the wizard's PowerShell command (run as Administrator) downloaded and installed the MSI, then the service was started with `NET START WazuhSvc`.  
* **Ubuntu boxes (WEBSERVER01, DBSERVER01):** the wizard's Linux command installed the `.deb`, then `systemctl enable --now wazuh-agent` started it at boot and immediately.

All agents confirmed **Active** on the dashboard (and via `sudo /var/ossec/bin/agent_control -l` on the manager). A disconnected agent almost always means TCP 1514 blocked from that VLAN to SECOPS.

## **Step 2 — Windows audit logging**

Windows logs little by default, so Advanced Audit Policy was enabled via Group Policy on DC01 (which pushes to every domain machine). In `gpmc.msc` → Default Domain Policy → Edit:

Computer Configuration → Policies → Windows Settings → Security Settings  
→ Advanced Audit Policy Configuration → Audit Policies

These subcategories were set to **Success and Failure**:

| Category | Subcategory | What it catches |
| ----- | ----- | ----- |
| Account Logon | Credential Validation | Password checks — brute force (4776) |
| Account Logon | Kerberos Authentication Service | Kerberos tickets — Kerberoasting hunts |
| Logon/Logoff | Logon | Every login (4624 success / 4625 fail) |
| Logon/Logoff | Logoff | Sessions ending |
| Logon/Logoff | Account Lockout | Lockouts after too many fails (4740) |
| Account Management | User Account Management | Accounts created/changed/deleted (4720, 4726\) |
| Account Management | Security Group Management | Group changes e.g. Domain Admins (4728) |
| Detailed Tracking | Process Creation | Every program that starts (4688) |
| Policy Change | Audit Policy Change | Tampering with the logging itself |

Command-line auditing was also enabled so Event 4688 records the full command, not just the program name:

Computer Configuration → Policies → Administrative Templates → System  
→ Audit Process Creation → Include command line in process creation events → Enabled

Policy was applied with `gpupdate /force` and verified with `auditpol /get /category:*`; a deliberate wrong-password login produced **Event ID 4625**, confirming auditing works.

## **Step 3 — Sysmon on the Windows boxes**

Sysmon records far more than built-in logging — process trees, network connections, file and registry changes. Installed on DC01 and WIN11-CLIENT with a community-tuned config (SwiftOnSecurity `sysmonconfig-export.xml`):

.\\Sysmon64.exe \-accepteula \-i sysmonconfig.xml

Confirmed with `Get-Service Sysmon64` (Running) and Event **ID 1** (process creation) appearing in the `Microsoft-Windows-Sysmon/Operational` channel. Config can be swapped later without reinstalling via `.\Sysmon64.exe -c sysmonconfig.xml`.

## **Step 4 — Wazuh collects Sysmon**

By default the agent forwards only the standard Windows logs. A `<localfile>` block was added to each agent's `ossec.conf` to pull the Sysmon channel, then the agent restarted:

\<localfile\>  
  \<location\>Microsoft-Windows-Sysmon/Operational\</location\>  
  \<log\_format\>eventchannel\</log\_format\>  
\</localfile\>

Enabling Sysmon surfaced expected **rule.id 204 "agent buffer flooded"** alerts (Sysmon out-paces the agent's default 500 events/sec). Resolved by raising `<client_buffer>` limits (`queue_size` 100000, `events_per_second` 1000\) and restarting the agent. Sysmon events confirmed in the SIEM via `data.win.system.channel:"Microsoft-Windows-Sysmon/Operational"`.

## **Step 5 — pfSense firewall logs to Wazuh**

pfSense can't run an agent, so it ships logs over syslog. Remote logging was enabled (**Status → System Logs → Settings**, Remote Syslog Contents \= **Everything**, target `10.10.50.10:514`), and the Wazuh manager was set to listen for syslog with a `<remote>` block (UDP 514\) in its `ossec.conf`, then restarted.

Delivery was verified end to end: `tcpdump -i any udp port 514 -A` on WAZUH01 showed `filterlog` block events arriving from pfSense, matching the blocks visible in **Status → System Logs → Firewall**. (Firewall logs reach the SIEM; converting them into tuned alerts via a custom pfSense decoder/ruleset is carried into Phase 2 detection work.)

## **Step 6 — Verify end to end, then baseline**

The whole pipeline was proven with a real event per source:

* All four agents **Active**.  
* Windows: a wrong-password login produced **4625**, visible in the SIEM.  
* Sysmon: a process event (Event ID 1\) visible per Windows agent.  
* Linux: a wrong-password SSH on WEBSERVER01 and DBSERVER01 produced `authentication_failed` events — a repeated attempt escalated to a **brute-force** alert (level 10\) mapped to MITRE **T1110**.  
* Firewall: `filterlog` block events from pfSense arriving at the SIEM.

A written baseline of normal was recorded — normal logons per box, normal running processes and startup items, expected network talk (e.g. WEBSERVER01 → DBSERVER01 on the DB port is normal; DC01 → internet is not), and rough idle log volume per agent. Fresh `phase1-complete` Proxmox snapshots were taken of every VM as the clean, fully-instrumented starting point.

---

## **Phase 1 completion checklist**

* \[x\] Proxmox snapshots taken before starting  
* \[x\] Wazuh agent installed and Active on DC01  
* \[x\] Wazuh agent installed and Active on WIN11-CLIENT  
* \[x\] Wazuh agent installed and Active on WEBSERVER01  
* \[x\] Wazuh agent installed and Active on DBSERVER01  
* \[x\] Advanced Audit Policy enabled via Group Policy (logon, process creation, account mgmt)  
* \[x\] Command-line included in process creation events (4688)  
* \[x\] `gpupdate /force` run and Event 4625 confirmed on a Windows box  
* \[x\] Sysmon installed with a tuned config on DC01 and WIN11-CLIENT  
* \[x\] Agent `ossec.conf` updated to collect the Sysmon channel, agent restarted  
* \[x\] Sysmon events visible in the SIEM  
* \[x\] pfSense remote syslog enabled, pointing at 10.10.50.10:514  
* \[x\] Wazuh manager syslog listener enabled and restarted  
* \[x\] `filterlog` (firewall) events reaching the SIEM  
* \[x\] Baseline of normal logons, processes, network talk, and log volume written down  
* \[x\] Fresh `phase1-complete` snapshots taken

Phase 1 complete — full visibility across the lab and a clean starting point. Ready for Phase 2 (attack \+ detect).

---

*CyberSafe Home Lab · Phase 1 · Overview*

