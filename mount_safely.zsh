#!/usr/bin/env zsh

if [[ ${#} -lt 1 ]]; then
    print "Usage: $0 DEV [MOUNTPOINT] [NAME] [LV]
Attempt to mount DEV to MOUNTPOINT (or /media/\$(basename DEV) if MOUNTPOINT is omitted). 
If DEV is a LUKS device then prompt for a password, open it and map it to /dev/mapper/NAME (or /dev/mapper/\$(basename DEV) if NAME is omitted). Unless this results in an LVM2 container, mount it. Otherwise try to mount /dev/mapper/LV if the LV arg is supplied, or prompt the user for which logical volume to mount.
If the MOUNTPOINT is already in use or there are other problems, then return without mounting."
    return 1
fi

checkcmds() {
    local cmd
    for cmd in $@; do
	if ! whence $cmd >/dev/null; then
	    print -- "Cannot find $cmd command!"
	    return 1
	fi
    done
}
checkcmds /sbin/cryptsetup /usr/bin/sudo /usr/bin/awk /bin/grep /bin/mount /sbin/blkid /bin/mountpoint /sbin/lvscan || exit 127

local bdev=${1}
local origdev=${bdev}
local mpoint=${2:-/media/${bdev##*/}}
local mdev=${3:-${bdev##*/}}
local lvname=${4}
local cryptsetupcmd=/sbin/cryptsetup
local sudocmd=/usr/bin/sudo
# find out if $bdev is a LUKS device
local isluks=    
if ${sudocmd} ${cryptsetupcmd} isLuks ${bdev}; then
    isluks=1
fi
# If $bdev is already mapped, use the mapper device
local map count=0
local bdev2="${bdev}"
for map in /dev/mapper/*(@); do
    if /bin/ls "/sys/block/${$(readlink ${map})##*/}/slaves"|/bin/grep "${bdev2##*/}" >/dev/null; then
	if ${sudocmd} /sbin/blkid ${map}|/usr/bin/awk '{print $3}'|/bin/grep swap >/dev/null; then
	    continue
	else
	    bdev=${map}
	    count=$((count+1))
	fi
    fi
done
if ((count==1)); then
    print "${origdev} is mapped to ${bdev}"
elif ((count>1)); then
    print "${origdev} is mapped to more than one non-swap device in /dev/mapper (is it an LVM2 container?)"
    return 1
fi
# If $mpoint already has something mounted on it, return
if /bin/mountpoint -q ${mpoint}; then
    local bdev2=$(/bin/grep ${mpoint} /proc/mounts|/usr/bin/tail -n 1|/usr/bin/awk '{print $1}')
    if [[ ${bdev2} == ${bdev} ]]; then
	print "${bdev} is already mounted at ${mpoint}"
	return 0
    else
	print "${bdev2} is mounted at ${mpoint}. I refuse to mount ${bdev} over it."
	return 1
    fi
fi
# If $bdev is already mounted then return
local bdev2=$(/bin/grep ${bdev} /proc/mounts|/usr/bin/tail -n 1|/usr/bin/awk '{print $2}')
if [[ -n ${bdev2} ]]; then
    print "${bdev} is already mounted at ${bdev2}. I refuse to mount it elsewhere."
    return 1
fi
# Check if $bdev is a LUKS partition (so it hasn't been mapped yet), and if so then open it
if ${sudocmd} ${cryptsetupcmd} isLuks ${bdev}; then
    local count2=0
    while ${sudocmd} ${cryptsetupcmd} status ${mdev} >/dev/null; do
	count2=$((count2+1))
	mdev="${mdev}${count2}"
    done
    ${sudocmd} ${cryptsetupcmd} open ${bdev} ${mdev}
    if ! [[ $? == 0 ]]; then
	print "Unable to open encrypted device ${bdev}"
	return 1
    else
	bdev=/dev/mapper/${mdev}
	print "${origdev} has been decrypted and mapped to ${bdev}"	
    fi
fi

# Check if $bdev is an LVM container, and if so use the appropriate member
if ${sudocmd} /sbin/blkid ${bdev}|/bin/grep LVM2_member >/dev/null; then
    # make sure the LVs are properly registered
    ${sudocmd} /sbin/lvscan --cache >/dev/null
    /bin/sleep 1
    local d dm2 dm1="${$(readlink ${bdev})##*/}"
    if [[ -n ${lvname} ]]; then
	# check that ${lvname} is a member of the volume group for ${bdev}
	dm2="${$(readlink /dev/mapper/${lvname})##*/}"
	local dms=($(ls /sys/block/${dm1}/holders))
	if [[ ${dms[(i)${dm2}]} -gt ${#dms} ]]; then
	    print "${lvname} is not a member of the volume group for ${bdev}. I refuse to mount it."
	    return 1
	fi
	bdev="/dev/mapper/${lvname}"
    else
	local lvols=()
	for d in /sys/block/${dm1}/holders/*; do
	    bdev2="/dev/mapper/$(cat /sys/block/${d##*/}/dm/name)"
	    if ${sudocmd} /sbin/blkid ${bdev2}|/usr/bin/awk '{print $3}'|/bin/grep swap >/dev/null; then
		continue
	    else
		lvols+="${bdev2}"
	    fi
	done
	if [[ ${#lvols} -gt 1 ]]; then
	    for bdev2 in ${lvols[@]}; do
		print "${lvols[(i)${bdev2}]}: ${bdev2}"
	    done
	    print "Select which logical device to mount on ${mpoint}"
	    while true; do
		read \?"Enter a number between 1 & ${#lvols}: "
		if [[ ${REPLY} -le ${#lvols} ]] && [[ ${REPLY} -gt 0 ]]; then
		    bdev="${lvols[${REPLY}]}"
		    break
		fi
	    done
	elif [[ ${#lvols} -gt 0 ]]; then
	    bdev="${lvols[1]}"
	else
	    print "No mountable logical volumes found on ${bdev}"
	    return 1
	fi
    fi
fi

# Finally, mount $bdev
${sudocmd} /bin/mount ${bdev} ${mpoint}
if [[ $? -eq 0 ]]; then
    print "Successfully mounted ${bdev} to ${mpoint}"
    return 0
else
    print "Failed to mount ${bdev} to ${mpoint}"
    return 1
fi
