#!/bin/sh

# Toggle the screensaver on/off
if [ `xset q | grep timeout | awk '{print $2}'` -ne 0 ] || [ "$(pgrep xscreensaver)" ]; then
    xscreensaver-command -exit
    xset -dpms 
    xset -display :0 s off
elif [ "$(which xscreensaver)"]; then
    xscreensaver &
else
    xset -display :0 +dpms
    xset -display :0 s on
fi

