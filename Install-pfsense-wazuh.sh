#!/bin/bash
## install-pfsense-wazuh.sh
# Backs up your current Wazuh decoder and rules files (so nothing's lost).
# Adds the pfSense decoder so Wazuh correctly reads filterlog firewall events (instead of mislabeling them as FreePBX).
# Adds firewall rules so blocks become real alerts — including the level-10 "possible port scan" detection that'll catch your nmap.
# Restarts the Wazuh manager so the changes take effect.
# Adds pfSense filterlog decoder + firewall rules to Wazuh manager, then restarts it.
# Run on WAZUH01 as root:  sudo bash install-pfsense-wazuh.sh
set -e
 
DEC=/var/ossec/etc/decoders/local_decoder.xml
RUL=/var/ossec/etc/rules/local_rules.xml
 
echo "[*] Backing up existing files..."
cp -n "$DEC" "${DEC}.bak" 2>/dev/null || true
cp -n "$RUL" "${RUL}.bak" 2>/dev/null || true
 
echo "[*] Adding pfSense decoder..."
cat >> "$DEC" <<'EOF'
 
<!-- pfSense filterlog decoder (CyberSafe lab) -->
<decoder name="pfsense-filterlog">
  <program_name>^filterlog$</program_name>
</decoder>
 
<decoder name="pfsense-filterlog-ipv4">
  <parent>pfsense-filterlog</parent>
  <pcre2>filterlog\[\d+\]:\s\d+,\d*,[^,]*,\d+,([^,]+),[^,]+,(\w+),(\w+),4,[^,]*,[^,]*,\d+,\d+,\d+,[^,]*,\d+,(\w+),\d+,([\d.]+),([\d.]+),(\d+),(\d+)</pcre2>
  <order>srcinterface,action,direction,protocol,srcip,dstip,srcport,dstport</order>
</decoder>
EOF
 
echo "[*] Adding pfSense rules..."
cat >> "$RUL" <<'EOF'
 
<!-- pfSense firewall rules (CyberSafe lab) -->
<group name="pfsense,firewall,">
 
  <rule id="100100" level="0">
    <decoded_as>pfsense-filterlog</decoded_as>
    <description>pfSense firewall event.</description>
  </rule>
 
  <rule id="100101" level="3">
    <if_sid>100100</if_sid>
    <field name="action">^block$</field>
    <description>pfSense: Blocked $(protocol) $(srcip):$(srcport) -> $(dstip):$(dstport) on $(srcinterface)</description>
    <group>firewall_drop,</group>
    <mitre><id>T1190</id></mitre>
  </rule>
 
  <rule id="100102" level="0">
    <if_sid>100100</if_sid>
    <field name="action">^pass$</field>
    <description>pfSense: Allowed $(protocol) $(srcip) -> $(dstip):$(dstport)</description>
  </rule>
 
  <rule id="100103" level="10" frequency="8" timeframe="30">
    <if_matched_sid>100101</if_matched_sid>
    <same_source_ip />
    <description>pfSense: Possible port scan - 8+ blocks from $(srcip) in 30s</description>
    <group>firewall_scan,recon,</group>
    <mitre><id>T1046</id></mitre>
  </rule>
 
</group>
EOF
 
echo "[*] Fixing ownership..."
chown wazuh:wazuh "$DEC" "$RUL" 2>/dev/null || true
 
echo "[*] Restarting wazuh-manager..."
systemctl restart wazuh-manager
 
echo "[+] Done. Test with:  sudo /var/ossec/bin/wazuh-logtest"
echo "[+] Then from Kali:   nmap -Pn 10.10.50.1 -p 1-100"
echo "[+] Then search Wazuh: rule.id:100101  (blocks)  and  rule.id:100103  (scan)"
