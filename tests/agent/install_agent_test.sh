#!bin/bash
chmod +x /home/zero-trust-netwoking/scripts/install-agent.sh && echo "=== Hub Info for Agent Installation ===" && echo "HUB_PUBLIC_KEY=$(cat /etc/wireguard/public.key)" && echo "HUB_ENDPOINT=$(curl -s ifconfig.me):51820" && echo "HUB_URL=http://$(curl -s ifconfig.me):8000"

#
PUBLIC_IP=$(curl -4 -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}') && echo "=== AGENT INSTALLATION COMMAND ===" && echo "" && echo "# Copy và chạy trên node cần cài Agent:" && echo "" && echo "curl -sL https://raw.githubusercontent.com/maithanhduyan/zero-trust-netwoking/main/scripts/install-agent.sh | \\" && echo "  sudo HUB_URL=\"http://${PUBLIC_IP}:8000\" \\" && echo "       HUB_ENDPOINT=\"${PUBLIC_IP}:51820\" \\" && echo "       HUB_PUBLIC_KEY=\"$(cat /etc/wireguard/public.key)\" \\" && echo "       NODE_ROLE=\"app\" \\" && echo "       bash"
