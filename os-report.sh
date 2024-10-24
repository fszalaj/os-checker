#!/bin/bash

# Define the output file path
output_file="/opt/atosans/test/system_verification_report.txt"

# Ensure the directory exists
mkdir -p /opt/atosans/test

# Get the hostname and date
hostname=$(hostname)
current_date=$(date)

# Start the report with hostname and date
echo "System Verification Report" > "$output_file"
echo "----------------------------------------" >> "$output_file"
echo "Hostname: $hostname" >> "$output_file"
echo "Date: $current_date" >> "$output_file"
echo "----------------------------------------" >> "$output_file"

# Function to append section title
append_title() {
  echo -e "\n## $1 ##" >> "$output_file"
  echo "----------------------------------------" >> "$output_file"
}

# Function to track time for each section
log_time() {
  start_time=$(date +%s)
  start_time_human=$(date "+%Y-%m-%d %H:%M:%S")
  echo "Starting: $1 at $start_time_human"
  echo "----------------------------------------"
  echo "Starting: $1 at $start_time_human" >> "$output_file"
  echo "----------------------------------------" >> "$output_file"
}

end_time() {
  end_time=$(date +%s)
  duration=$((end_time - start_time))
  echo "Completed: $1 in $duration seconds"
  echo "----------------------------------------"
  echo "Completed: $1 in $duration seconds" >> "$output_file"
  echo "----------------------------------------" >> "$output_file"
}

# Function to check if a service exists
service_exists() {
  systemctl list-unit-files --type=service | grep -qw "$1"
}

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to install netcat if it's not already installed
install_netcat() {
  log_time "Netcat Installation"
  append_title "Netcat Installation"
  if ! command_exists nc; then
    echo "Netcat is not installed. Installing via yum..." >> "$output_file"
    yum install -y nc >> "$output_file" 2>&1
    if command_exists nc; then
      echo "Netcat installed successfully." >> "$output_file"
    else
      echo "Netcat installation failed." >> "$output_file"
    fi
  else
    echo "Netcat is already installed." >> "$output_file"
  fi
  end_time "Netcat Installation"
}

# Install netcat if needed
install_netcat

# 1. Timezone Configuration
log_time "Timezone Configuration"
append_title "Timezone Configuration"
echo "Checking timezone configuration..." >> "$output_file"
timedatectl >> "$output_file" 2>&1
end_time "Timezone Configuration"

# 2. NTP Configuration
log_time "NTP Configuration"
append_title "NTP Configuration"
echo "Checking NTP server configuration..." >> "$output_file"
if [ -f /etc/chrony.conf ]; then
  grep -E '^server' /etc/chrony.conf >> "$output_file" 2>&1
else
  echo "/etc/chrony.conf not found." >> "$output_file"
fi

echo "Checking NTP synchronization status..." >> "$output_file"
if command_exists chronyc; then
  chronyc sources >> "$output_file" 2>&1
else
  echo "chronyc command not found." >> "$output_file"
fi
end_time "NTP Configuration"

# 3. Firewall Configuration
log_time "Firewall Configuration"
append_title "Firewall Configuration"
echo "Checking firewalld service status..." >> "$output_file"
if service_exists firewalld.service; then
  systemctl status firewalld.service >> "$output_file" 2>&1
else
  echo "firewalld service not found." >> "$output_file"
fi

echo "Listing active firewall zones and services..." >> "$output_file"
if command_exists firewall-cmd; then
  firewall-cmd --get-active-zones >> "$output_file" 2>&1
  firewall-cmd --list-all >> "$output_file" 2>&1
else
  echo "firewall-cmd command not found." >> "$output_file"
fi
end_time "Firewall Configuration"

# 4. CrowdStrike (AV/EDR)
log_time "CrowdStrike (AV/EDR)"
append_title "CrowdStrike (AV/EDR)"
echo "Checking falcon-sensor status..." >> "$output_file"
if service_exists falcon-sensor.service; then
  systemctl status falcon-sensor.service >> "$output_file" 2>&1
else
  echo "falcon-sensor service not found." >> "$output_file"
fi

echo "Checking CrowdStrike proxy connectivity..." >> "$output_file"
if command_exists curl; then
  curl -k --connect-timeout 10 https://ts01-b.cloudsink.net -x http://nlproxy3.atos-srv.net:8080 >> "$output_file" 2>&1 || echo "Failed to connect to CrowdStrike proxy." >> "$output_file"
else
  echo "curl command not found." >> "$output_file"
fi

echo "Getting falcon-sensor status..." >> "$output_file"
if [ -f /opt/CrowdStrike/falconctl ]; then
  /opt/CrowdStrike/falconctl -g --rfm-state >> "$output_file" 2>&1
  /opt/CrowdStrike/falconctl -g --rfm-history >> "$output_file" 2>&1
  /opt/CrowdStrike/falconctl -g --aid --tags --aph --app >> "$output_file" 2>&1
else
  echo "falconctl not found." >> "$output_file"
fi
end_time "CrowdStrike (AV/EDR)"

# 5. AISAAC Agent (MDR)
log_time "AISAAC Agent (MDR)"
append_title "AISAAC Agent (MDR)"
echo "Checking AISAAC agent status..." >> "$output_file"
if service_exists proddefthmdr.service; then
  systemctl status proddefthmdr.service >> "$output_file" 2>&1
else
  echo "AISAAC agent service not found." >> "$output_file"
fi

echo "Checking connectivity to Paladion gateway..." >> "$output_file"
if command_exists nc; then
  timeout 10 nc -zv 155.45.244.104 443 >> "$output_file" 2>&1 && echo "Connection to Paladion gateway on port 443 successful." >> "$output_file" || echo "Connection to Paladion gateway on port 443 failed or timed out." >> "$output_file"
  timeout 10 nc -zv 155.45.244.104 8443 >> "$output_file" 2>&1 && echo "Connection to Paladion gateway on port 8443 successful." >> "$output_file" || echo "Connection to Paladion gateway on port 8443 failed or timed out." >> "$output_file"
else
  echo "nc command not found." >> "$output_file"
fi
end_time "AISAAC Agent (MDR)"

# 6. Nagios CMF Agents
log_time "Nagios CMF Agents"
append_title "Nagios CMF Agents"
echo "Checking ase service status..." >> "$output_file"
if [ -f /opt/ASE/bin/ase ]; then
  /opt/ASE/bin/ase status >> "$output_file" 2>&1
else
  echo "ASE agent not found." >> "$output_file"
fi

echo "Checking Nagios connectivity..." >> "$output_file"
if command_exists nc; then
  timeout 10 nc -zv 161.89.176.188 443 >> "$output_file" 2>&1 && echo "Connection to Nagios server successful." >> "$output_file" || echo "Connection to Nagios server failed or timed out." >> "$output_file"
  timeout 10 nc -zv 155.45.163.181 443 >> "$output_file" 2>&1 && echo "Connection to Nagios backup server successful." >> "$output_file" || echo "Connection to Nagios backup server failed or timed out." >> "$output_file"
else
  echo "nc command not found." >> "$output_file"
fi

echo "Checking Nagios cron job..." >> "$output_file"
if crontab -l | grep -q NaCl; then
  crontab -l | grep NaCl >> "$output_file" 2>&1
else
  echo "Nagios NaCl cron job not found." >> "$output_file"
fi
end_time "Nagios CMF Agents"

# 7. RSCD (TSSA Agent)
log_time "RSCD (TSSA Agent)"
append_title "RSCD (TSSA Agent)"
echo "Checking RSCD service status..." >> "$output_file"
if service_exists rscd.service; then
  systemctl status rscd.service >> "$output_file" 2>&1
else
  echo "RSCD service not found." >> "$output_file"
fi

echo "Checking if RSCD is listening on port 4750..." >> "$output_file"
if command_exists netstat; then
  netstat -tulpn | grep 4750 >> "$output_file" 2>&1
else
  echo "netstat command not found." >> "$output_file"
fi

echo "Checking /etc/rsc/users.local configuration..." >> "$output_file"
if [ -f /etc/rsc/users.local ]; then
  cat /etc/rsc/users.local >> "$output_file" 2>&1
else
  echo "/etc/rsc/users.local not found." >> "$output_file"
fi

echo "Checking /etc/rsc/exports configuration..." >> "$output_file"
if [ -f /etc/rsc/exports ]; then
  cat /etc/rsc/exports >> "$output_file" 2>&1
else
  echo "/etc/rsc/exports not found." >> "$output_file"
fi
end_time "RSCD (TSSA Agent)"

# 8. CyberArk (cya accounts)
log_time "CyberArk Accounts"
append_title "CyberArk Accounts"
echo "Checking for atosans and atosadm users..." >> "$output_file"
grep -E 'atosans|atosadm' /etc/passwd >> "$output_file" 2>&1 || echo "Users atosans and atosadm not found." >> "$output_file"
grep allowssh /etc/group >> "$output_file" 2>&1 || echo "Group allowssh not found." >> "$output_file"
end_time "CyberArk Accounts"

# 9. Alcatraz Scanner (TOSCA security scan)
log_time "Alcatraz Scanner"
append_title "Alcatraz Scanner"
echo "Running Alcatraz scan..." >> "$output_file"
if [ -f /opt/atos_tooling/alcatraz_scanner/Alcatraz/os/bin/lsecurity.pl ]; then
  /opt/atos_tooling/alcatraz_scanner/Alcatraz/os/bin/lsecurity.pl -i default > /tmp/alcatraz_report.txt
  grep -i finding /tmp/alcatraz_report.txt >> "$output_file" 2>&1 || echo "No findings in Alcatraz scan." >> "$output_file"
else
  echo "Alcatraz scanner not found." >> "$output_file"
fi
end_time "Alcatraz Scanner"

# 10. SOXDB Scanner (User Management)
log_time "SOXDB Scanner"
append_title "SOXDB Scanner"
echo "Checking atosadm user management configuration..." >> "$output_file"
grep atosadm /etc/passwd >> "$output_file" 2>&1 || echo "User atosadm not found." >> "$output_file"
grep wheel /etc/group >> "$output_file" 2>&1 || echo "Group wheel not found." >> "$output_file"
if command_exists chage; then
  chage -l atosadm >> "$output_file" 2>&1 || echo "Failed to get password aging information for atosadm." >> "$output_file"
else
  echo "chage command not found." >> "$output_file"
fi
end_time "SOXDB Scanner"

# End of report
echo "----------------------------------------" >> "$output_file"
echo "Verification Complete. Report saved to $output_file" >> "$output_file"

# Output the location of the report
echo "Report generated and saved to $output_file"
