#!/bin/sh
. /usr/share/libubox/jshn.sh

# 获取无线设备的数量
RADIO_NUM=$(uci show wireless | grep -c "wifi-device")

# 如果没有找到无线设备，直接退出
if [ "$RADIO_NUM" -eq 0 ]; then
	exit 0
fi

# 默认WIFI设置
BASE_SSID='OWRT'
BASE_WORD='12345678'

# 配置无线设备
configure_wifi() {
	local radio=$1
	local channel=$2
	local htmode=$3
	local ssid=$4
	local current_encryption=$(uci get wireless.default_radio${radio}.encryption)

	# 如果当前加密方式已设置且不为"none"，则不更新配置
	if [ -n "$current_encryption" ] && [ "$current_encryption" != "none" ]; then
		echo "No update needed for radio${radio} with channel ${channel} and SSID ${ssid}"
		return 0
	fi

	# 设置无线设备参数
	uci set wireless.radio${radio}.channel="${channel}"
	uci set wireless.radio${radio}.htmode="${htmode}"
	uci set wireless.radio${radio}.country='CN'
	uci set wireless.radio${radio}.disabled='0'
	uci set wireless.radio${radio}.cell_density='0'
	uci set wireless.radio${radio}.mu_beamformer='1'

	uci set wireless.default_radio${radio}.ssid="${ssid}"
	uci set wireless.default_radio${radio}.encryption='psk2+ccmp'
	uci set wireless.default_radio${radio}.key="${BASE_WORD}"
	uci set wireless.default_radio${radio}.ieee80211k='1'
	uci set wireless.default_radio${radio}.time_advertisement='2'
	uci set wireless.default_radio${radio}.time_zone='CST-8'
	uci set wireless.default_radio${radio}.bss_transition='1'
	uci set wireless.default_radio${radio}.wnm_sleep_mode='1'
	uci set wireless.default_radio${radio}.wnm_sleep_mode_no_keys='1'
}

# 设置无线设备的默认配置
FIRST_5G=''
set_wifi_default_config() {
	local radio=$1
	local htmode=$2
	local band=$(uci get wireless.radio${radio}.band)
	local channel

	if [ "$band" = '5g' ]; then
		channel=149
		if [ "$htmode" = 'HE160' ] || [ "$htmode" = 'VHT160' ]; then
			channel=44
		fi
		if [ -z "$FIRST_5G" ]; then
			if [ "$RADIO_NUM" -eq 2 ]; then
				configure_wifi "$radio" "$channel" "$htmode" "${BASE_SSID}-5G"
			else
				configure_wifi "$radio" "$channel" "$htmode" "${BASE_SSID}-5G_1"
			fi
			FIRST_5G='1'
		else
			configure_wifi "$radio" "$channel" "$htmode" "${BASE_SSID}-5G_2"
		fi
	else
		configure_wifi "$radio" '6' "$htmode" "${BASE_SSID}"
	fi
}

# 读取 /etc/board.json 文件
json_load_file /etc/board.json

# 提取 WLAN 信息
json_select wlan

# 遍历所有 PHY 接口
id=0
json_get_keys phy_keys
for phy in $phy_keys; do
	json_select $phy
	json_select info
	json_select bands
	json_get_keys band_keys
	for band in $band_keys; do
		json_select $band
		json_select modes
		json_get_keys mode_keys
		last_mode=""
		for mode in $mode_keys; do
			json_get_var mode_value $mode
			last_mode=$mode_value
		done
		set_wifi_default_config $id $last_mode
		json_select ..
		json_select ..
		json_select ..
	done
	json_select ..
	json_select ..
	id=$((id + 1))
done

# 提交配置并重启网络服务
uci commit wireless

exit 0
