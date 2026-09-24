# CyberSafe: Building a Personal Cybersecurity Homelab

2026-09-21 · Sobia R

I'm working toward a career in blue team cybersecurity — SOC analyst, DFIR, and threat intelligence roles — and this homelab, CyberSafe, is how I get hands-on skills, reinforce what I learn, and demonstrate my commitment to continuous growth. It has grown from one refurbished mini PC into a segmented, multi-VLAN environment that mirrors a small enterprise network, complete with a domain, a SIEM, a vulnerability scanner, and its own DMZ.

## Table of Contents

- [Hardware Overview](#m5896fzkxa3.509)
- [Network Topology & Virtual Machines](#m5896fzkxa3.1004)
- [Technical Objectives & Use Cases](#m5896fzkxa3.2270)
- [Conclusion](#m5896fzkxa3.2953)
- [Author](#m5896fzkxa3.3856)

## Hardware Overview

The lab runs on one Lenovo ThinkCentre M720Q, bought used (originally Windows 11 Pro, 32GB RAM, 512GB SSD), wiped and re-provisioned with Proxmox VE.

- Clustered via Proxmox for centralized management and resource scheduling
- TP-Link 8-Port Gigabit Smart Switch (metal case) for internal networking
- Administered remotely from a Lenovo laptop
- Total cost so far: \~$600 USD

## Network Topology & Virtual Machines

CyberSafe simulates an enterprise environment with five active VLANs segmented behind pfSense, running 9 VMs total:

- **WAN** — 192.168.1.X/24 (DHCP) → pfSense (firewall/router)
- **LAN** 10.10.0.0/24 — KALI-JUMPBOX (10.10.0.50): trusted attack/management host
- **CORPORATE** 10.10.20.0/24 — DC01 (10.10.20.10): Active Directory (AD) domain controller; WIN11-CLIENT (10.10.20.11): domain-joined workstation
- **DMZ** 10.10.30.0/24 — WEBSERVER01 (10.10.30.10): web app host
- **APPDATA** 10.10.40.0/24 — DBSERVER01 (10.10.40.10): database host
- **SECOPS** 10.10.50.0/24 — WAZUH01 (10.10.50.10): SIEM; GREENBONE-SCANNER (10.10.50.20): vulnerability scanner; SOAR (10.10.50.30): orchestration (TheHive)

Each VLAN's gateway sits at the .1 address, and every VM is provisioned with resource limits and strict network rules to reinforce segmentation, least privilege, and defense-in-depth.

## Technical Objectives & Use Cases

CyberSafe supports:

- VM provisioning and hypervisor management via Proxmox
- VLAN-based network segmentation and firewall rule enforcement via pfSense
- Centralized log collection, detection rules, and file-integrity monitoring via Wazuh
- Vulnerability scanning against the DMZ and app tier via Greenbone
- Orchestration and response workflow testing via SOAR
- Windows domain administration and Group Policy configuration (DC01, WIN11-CLIENT)
- Offensive testing and reconnaissance from the Kali jumpbox against the DMZ and app-data tiers
- Practical incident response workflows and threat emulation across a segmented, defense-in-depth network

## Conclusion

CyberSafe is my cornerstone for hands-on cybersecurity learning — an evolving lab where I can break things, troubleshoot real hardware and network issues, and build the kind of readiness that translates directly to a SOC/DFIR role. Future work will keep refining the architecture, expand the SOAR playbooks, and stand up the second lab alongside it.

## Author

Sobia R — cybersecurity graduate from WGU and career changer into cybersecurity (former teacher and assessment examiner), now a Cybersecurity Analyst Intern at LOG(N) Pacific, working toward the SANS Undergraduate Certificate in Applied Cybersecurity. Focused on blue team, DFIR, threat intelligence, and AI governance.
