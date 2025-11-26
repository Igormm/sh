#!/usr/bin/env bash

set -euo pipefail


if [ $# -lt 1 -o $# -gt 3 ]; then 
        echo -e "Usage: $0 X Y [Monitor Output Port Name:HDMI-0] 60"
        echo -e "Example: $0 1024 768 VGA-0 OR $0 1024 768 HDMI-0 60"
        echo -e "\tcvt-checks available resolutions, create config line for new resolution profile"
        echo -e "\tOR"
        echo -e "\tgtf-checks available resolutions, create config line for new resolution profile"
        echo -e "\tMonitor name, identifier and output port name contains: x11 on /etc/X11/xorg.conf.d/*"
        echo -e "\tOR"
        echo -e "\txrandr --listmonitors"
        echo -e "\tMonitors: 1 0: +VGA-0 1600/423x1200/317+0+0 VGA-0"
        echo -e "\tThere are monitor has output names: HDMI-0 or 1..  VGA-0 or 1.."
        echo -e "\tFor script default monitor output name: VGA-0"
        exit 1
fi

DISPLAY_UTILITY_MODELINE=""
XRANDR_MODE_LINE=""
XRANDR_MODE_NAME=""

cvt 1024 768 &>/dev/null

if [ $? != 0 ]; then
    echo -e "cvt is not work"
    
    gtf 1024 768 60 &>/dev/null

    if [ $? != 0 ]; then
        echo -e "gtf is not work"
        exit 1
    else
        DISPLAY_UTILITY_MODELINE="gtf"
        XRANDR_MODE_LINE=`gtf $1 $2 | sed -n '3 p' | cut -d " " -f4-`
        XRANDR_MODE_NAME=`echo $XRANDR_MODE_LINE | cut -d " " -f1`
    fi
else
    DISPLAY_UTILITY_MODELINE="cvt"
    XRANDR_MODE_LINE=`cvt $1 $2 | sed -n '2 p' | cut -d " " -f2-`
    XRANDR_MODE_NAME=`echo $XRANDR_MODE_LINE | cut -d " " -f1`
fi

DEFAULT_MONITOR_PORT="VGA-0"

MONITOR_OUTPUT_NAME=${3:-${DEFAULT_MONITOR_PORT}}

echo $XRANDR_MODE_LINE
echo $XRANDR_MODE_NAME

xrandr &>/dev/null

if [ $? != 0 ]; then
    echo -e "xrandr not work"
    exit 1
fi

xrandr --newmode $XRANDR_MODE_LINE

if [ $? != 0 ]; then
    echo -e "xrandr new mode [$XRANDR_MODE_LINE] creation failure"
    exit 1
fi

xrandr --addmode $MONITOR_OUTPUT_NAME $XRANDR_MODE_NAME

if [ $? != 0 ]; then
    echo -e "xrandr add mode [$XRANDR_MODE_LINE] name [$MONITOR_OUTPUT_NAME] failure"
    exit 1
fi

xrandr --output $MONITOR_OUTPUT_NAME --mode $XRANDR_MODE_NAME

if [ $? != 0 ]; then
    echo -e "xrandr set mode [$XRANDR_MODE_NAME] name [$MONITOR_OUTPUT_NAME] failure"
    exit 1
fi

