#!/bin/sh
# toggle insert button on/off

if [ `xmodmap -pke | awk '/118/{print $4}'` ]; then
    xmodmap -e "keycode 118 = "
    xmodmap -e "keycode 90 = "
    echo Insert key off
else
    xmodmap -e "keycode 118 = Insert"
    xmodmap -e "keycode 90 = Insert"
    echo Insert key on;
fi



