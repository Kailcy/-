#!/bin/bash
set -e

# Define colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo -e "${RED}==== 网络流量监控系统卸载脚本 (vnStat 2.x + Postfix) ====${NC}"

#-----------------------------
# 1. Root Check
#-----------------------------
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误：请使用 root 运行此脚本： sudo bash $0${NC}"
    exit 1
fi

#-----------------------------
# 2. Define Files and Services
#-----------------------------
REPORT_SCRIPT="/usr/local/bin/vnstat_monthly_report.sh"
REPORT_DIR="/var/log/vnstat_reports"

POSTFIX_CONFIG_FILES=(
    "/etc/postfix/sasl_passwd"
    "/etc/postfix/sasl_passwd.db"
    "/etc/postfix/generic"
    "/etc/postfix/generic.db"
)
POSTFIX_MAIN_CF="/etc/postfix/main.cf"
POSTFIX_MAIN_CF_BAK="/etc/postfix/main.cf.bak"
POSTFIX_PKGS="postfix mailutils"
VNSTAT_PKGS="vnstat bc jq curl" # 卸载所有安装的依赖（只卸载主要的，基础依赖如libssl不卸载）

#-----------------------------
# 3. Remove Cron Job
#-----------------------------
echo -e "${YELLOW}[1/5] 删除定时任务...${NC}"
(crontab -l 2>/dev/null | grep -v "vnstat_monthly_report") | crontab -
echo "已从 crontab 中移除 vnstat_monthly_report 相关的任务。"

#-----------------------------
# 4. Remove Report Script and Directory
#-----------------------------
echo -e "${YELLOW}[2/5] 删除报告脚本和文件...${NC}"
if [ -f "$REPORT_SCRIPT" ]; then
    rm -f "$REPORT_SCRIPT"
    echo "已删除报告脚本: $REPORT_SCRIPT"
else
    echo "报告脚本 $REPORT_SCRIPT 未找到，跳过。"
fi

if [ -d "$REPORT_DIR" ]; then
    echo "报告目录 $REPORT_DIR 将被保留，但建议手动检查并删除。"
    # rm -rf "$REPORT_DIR" # 可选：如果确定要删除，取消注释此行
fi

#-----------------------------
# 5. Restore Postfix Configuration
#-----------------------------
echo -e "${YELLOW}[3/5] 清理 Postfix 配置...${NC}"

# 1. 删除 Postfix 相关的密码和映射文件
for file in "${POSTFIX_CONFIG_FILES[@]}"; do
    if [ -f "$file" ]; then
        rm -f "$file"
        echo "已删除 Postfix 配置文件: $file"
    fi
done

# 2. 还原 main.cf
if [ -f "$POSTFIX_MAIN_CF_BAK" ]; then
    cp "$POSTFIX_MAIN_CF_BAK" "$POSTFIX_MAIN_CF"
    rm -f "$POSTFIX_MAIN_CF_BAK"
    echo "已从备份文件 $POSTFIX_MAIN_CF_BAK 还原 $POSTFIX_MAIN_CF"
    systemctl restart postfix
else
    # 如果没有备份文件，至少清理安装脚本设置的参数
    echo "未找到 Postfix 备份文件，尝试清理 main.cf 中的自定义参数..."
    postconf -X relayhost smtp_sasl_auth_enable smtp_sasl_password_maps smtp_sasl_security_options smtp_use_tls smtp_tls_wrappermode smtp_tls_security_level smtp_generic_maps
    systemctl restart postfix
fi

#-----------------------------
# 6. Remove Packages
#-----------------------------
echo -e "${YELLOW}[4/5] 卸载软件包...${NC}"

echo "正在卸载 vnstat 和 Postfix..."
# 使用 autoremove 来删除可能不再需要的依赖
DEBIAN_FRONTEND=noninteractive apt purge -y $VNSTAT_PKGS $POSTFIX_PKGS
apt autoremove -y

#-----------------------------
# 7. Final Verification
#-----------------------------
echo -e "${GREEN}[5/5] 卸载完成！${NC}"
echo "请注意："
echo "* vnStat 的数据库文件（通常在 /var/lib/vnstat/）未被删除。如果您需要完全清理，请手动删除它们。"
echo "* 报告目录 $REPORT_DIR 被保留，请手动检查或删除。"
echo "* Postfix 已被卸载，其配置已被还原（或清理）。"
echo -e "${RED}----------------------------------------------------------${NC}"
