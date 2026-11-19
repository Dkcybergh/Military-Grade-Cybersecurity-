# C1DC Network Academy

A hands-on networking course for cybersecurity students, in **one script** that runs on Kali Linux.
It takes you from "what is a network?" to packet analysis, firewalls, TLS, IPv6, reconnaissance,
threat hunting and real troubleshooting, all inside a private lab on your own machine.

This is not a script that does the work for you. In every exercise you **read** the concept,
**predict** the result, **type** the real command yourself, **read** the live output with a guide,
and **explain** what you saw. Your predictions and answers are saved in a journal.

## Quick start

```bash
# 1. Download the script
wget https://raw.githubusercontent.com/Dkcybergh/Military-Grade-Cybersecurity-/main/networking/cybersecurity_network.sh

# 2. Install the tools (once)
sudo apt update && sudo apt install -y iproute2 iputils-ping tcpdump tshark wireshark nmap dnsutils curl python3 nftables dnsmasq-base traceroute openssl

# 3. Check that everything is ready
bash cybersecurity_network.sh --check

# 4. Start the course (as your normal user, NOT with sudo)
bash cybersecurity_network.sh
```

The script asks for your sudo password only when a lab needs it.

## What you will learn

| Track | Modules |
|---|---|
| Foundations | 01 Networks and hardware · 02 OSI and TCP/IP · 03 Addressing and subnetting · 04 ARP |
| Core protocols | 05 DHCP and DNS · 06 TCP, UDP, ICMP and ports · 07 Packet analysis (tcpdump, tshark, Wireshark) |
| Infrastructure | 08 Routing and NAT · 09 Switching and VLANs · 10 Firewalls with nftables |
| Applied and advanced | 11 HTTP, TLS and certificates · 12 IPv6 and MTU · 13 Authorized recon with Nmap · 14 Forensics and threat hunting |
| Operations | 15 Troubleshooting (10 break-and-fix tickets) · 16 Final exam |

Plan about 11 hours in total, for example three 4-hour sessions, or go at your own pace.
Your progress is saved, so you can stop and continue any time.

## The lab

From module 04 on you work in a **cyber-range**: five virtual hosts (your PC, a colleague's PC,
a switch, a router and a server) built inside your Kali machine with Linux network namespaces.
The server runs web, HTTPS, DNS, DHCP and UDP services for you to explore.
The lab is fully isolated: nothing you do in it touches your real network.

Practice tools in the menu:

- **S**: open a root shell on any lab host and explore freely
- **T**: troubleshooting tickets. The lab is secretly broken; you find and fix the fault
- **D**: subnetting drill with random questions and full binary explanations
- **M**: lab map and service status

## Useful options

```
bash cybersecurity_network.sh --module 4    jump to a module
bash cybersecurity_network.sh --drill       subnetting practice
bash cybersecurity_network.sh --tickets     troubleshooting tickets
bash cybersecurity_network.sh --cleanup     remove the lab
bash cybersecurity_network.sh --ascii       plain text, if your terminal shows odd symbols
bash cybersecurity_network.sh --help        all options
```

Your journal and saved captures are in `~/c1dc-network-labs/`.

## Rules

Use these techniques only on the course lab or on systems you own or have **written permission** to test.
Do not scan public networks. Packet captures can contain passwords and personal data, so keep them private.

## For instructors

Before class, run this once on a Kali VM to check every lab works:

```bash
sudo -v && bash cybersecurity_network.sh --self-test
```
