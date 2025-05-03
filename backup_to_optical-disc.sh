#!/usr/bin/env zsh

## Backup important files to DVD with error correcting information for long-term storage

# variables
isofile=/tmp/backup.iso
ducmd=/usr/bin/du
discdevice=/dev/cdrom
mountpoint=/media/cdrom
REPLY=
noprompt=
testrun=
burnspeed=6
bluray=
# use Joliet extensions by default to enable long file names
genisoflags=("-J" "-joliet-long")
genisoargs=()
volumename=
continueprompt1="Continue? (y/n): "
continueprompt2="Continue? (y)es/(n)o/(s)kip this step: "
usagestr="Usage: backup_to_optical-disc.sh [-n] [-r] [-i <FILE>] [<ROOT>=]<PATH>..

where: 
  -t         test run (show commands but dont execute them)
  -n         skip prompts
  -r         use Rock Ridge ISO extensions (saves file permissions & ownership, but not backwards compatible with ISO9660)
  -i <FILE>  location of temporary ISO file <FILE> (default = ${isofile} or ${isofile//.iso/.udf})
  -s <N>     set burn speed to <N>x (default = ${burnspeed})
  -v <NAME>  set the volume name to <NAME> (upto 32 characters)
  -b         burn to Blu-ray disc (default assumes CD/DVD)
  -u <SIZE>  use UDF filesystem of size <SIZE> (use this option if you have files larger than 2GB)  
  -h, -?     show this help text
  
  <PATH> = file or directory to be backed up.
  [<ROOT>] = optional destination directory on disc where <PATH> should be copied to
             (otherwise it will be copied into a directory of the same name, or the root directory
	     if it is a file).
E.g: backup_to_optical-disc.sh -r -s -v 'TESTDVD' films=~/Video/movies ~/Music
(this will copy ~/Videos/movies & ~/Music into /films & /Music on the CD/DVD)."

checkcmds() {
    local cmd
    for cmd in $@; do
	if ! whence $cmd >/dev/null; then
	    print -- "Cannot find $cmd command!"
	    return 1
	fi
    done
}
checkcmds wodim genisoimage mkudffs rsync dvdisaster growisofs truncate || exit 127


# Code for parsing command line options.
# Variables: OPTIND=index of next argument to be processed, OPTARG=set to current option argument
# Place a colon after every option that has an argument (initial colon means silent error reporting mode)
while getopts "tnri:s:v:bu:h?" option; do
    case $option in
	(t)
	    echo "Test run"
	    testrun=y
	    ;;
      	(n)
	    noprompt=y
	    ;;
	(r)
	    genisoflags+=("-R")
	    ;;
	(i)
	    isofile="${OPTARG}"
	    ;;
	(s)
	    burnspeed="${OPTARG}"
	    ;;
	(v)
	    volumename="${OPTARG}"
	    ;;
	(b)
	    bluray=y
	    ;;
	(u)
	    udf="${OPTARG}"
	    ;;
        (h)
	    echo "${usagestr}"
	    exit 1
	    ;;
        (\?)
	    echo "${usagestr}"
	    exit 1
	    ;;
    esac 
done

prompttocontinue() {
    REPLY=
    read -q -r "REPLY?
${1-${continueprompt1}}"
}

exitonerror1() {
    local err=$?
    if [[ "${err}" -ne 0 ]]; then
	echo "${1-ERROR!}"
	exit "${err}"
    fi
}

exitonerror2() {
    local err=$?
    if [[ ! "${REPLY}" =~ "[Ss]" ]]; then 
	if [[ "${err}" -ne 0 ]]; then
	    echo "${1-ERROR!}"
	    exit "${err}"
	fi
    fi
}

# Extract files and directories from remaining arguments
# TODO: properly handle spaces and other strange chars in directory names
backupfiles=( ${~@[$OPTIND,-1]} )
for dir in ${backupfiles[@]}; do
    if [[ "${dir}" =~ = ]]; then
	genisoflags+=("/${dir#/}")
    elif [[ -d "${dir}" ]]; then
	genisoargs+=("/${$(basename ${dir})// /_}=${dir}")
    else
	genisoargs+=("/=${dir}")
    fi
done
genisoflags+=("-graft-points")
if [[ -n ${volumename} ]]; then
    genisoflags+=("-V ${volumename}")
fi

# Make sure we can sudo
sudo -v

# check total size of data to be backed up
if [[ -z "${backupfiles[1]}" ]]; then
    echo "No files or directories specified! 
You need to specify files & directories to backup as command line args.
${usagestr}"
    exit 1
fi
echo "The following data will be backed up:\n"
${ducmd} -c -s -h ${backupfiles[@]}

if [[ -z "${noprompt}" ]]; then
    prompttocontinue
    exitonerror1 "Quitting!"
fi

# check ISO file
if [[ -n "${udf}" ]]; then
    isofile="${isofile%.(iso|udf)}.udf"
else
    isofile="${isofile%.(iso|udf)}.iso"
fi
if [[ -z "${noprompt}" ]]; then
    while [[ -a "${isofile}" ]]; do
	prompttocontinue "File ${isofile} already exists.
Overwrite it? (y/n): "
	if [[ "${?}" -eq 1 ]]; then
	    read -r "isofile?
New path to backup file: "
	else
	    break
	fi
    done
fi

if [[ -z "${udf}" ]]; then
    # create an .iso file containing all the data in directories passed as command line args
    createimagecmd="genisoimage -o ${isofile} ${genisoflags[@]} ${genisoargs[@]}"
    if [[ -z "${noprompt}" ]]; then
	prompttocontinue "Creating ISO file using following command:
  ${createimagecmd}
${continueprompt2}"
	exitonerror2 "Quitting!"
    fi
    if [[ ! "${REPLY}" =~ "[Ss]" ]]; then
	echo "\n\n${createimagecmd}\n"
	if [[ -z "${testrun}" ]]; then
	    eval "${createimagecmd}"
	    exitonerror1
	fi
    fi
else
    if [[ -z "${noprompt}" ]]; then
	prompttocontinue "Creating UDF file using following commands:
    truncate -s \"${udf}\" \"${isofile}\"
    mkudffs --media-type=dvdrw \"${isofile}\"
    sudo mkdir \"${mountpoint}\"
    sudo mount -t udf -o loop,rw \"${isofile}\" \"${mountpoint}\"
    COPY FILES TO ${mountpoint} USING RSYNC
    sudo umount ${mountpoint}
${continueprompt2}"
	exitonerror2 "Quitting!"
    fi
    if [[ ! "${REPLY}" =~ "[Ss]" ]]; then
	if [[ -z "${testrun}" ]]; then
	    truncate -s "${udf}" "${isofile}"
	    exitonerror1
	    mkudffs --media-type=dvdrw "${isofile}"
	    exitonerror1
	    if [[ ! -a "${mountpoint}" ]]; then
		sudo mkdir "${mountpoint}"
		exitonerror1
	    fi
	    sudo mount -t udf -o loop,rw "${isofile}" "${mountpoint}"
	    exitonerror1
	    for dir in "${genisoargs[@]}"; do
		if [[ ! -d "${mountpoint}/${${dir%%=*}#/}" ]]; then
		    sudo mkdir "${mountpoint}/${${dir%%=*}#/}"
		    exitonerror1
		fi
		echo "Copying ${dir#*=} to ${mountpoint}/${${dir%%=*}#/}"
		sudo rsync -ah --progress "${dir#*=}" "${mountpoint}/${${dir%%=*}#/}"
		exitonerror1
	    done
	    sudo umount "${mountpoint}"
	    exitonerror1
	elif [[ -n "${noprompt}" ]]; then
	    echo "\n\ntruncate -s ${udf} ${isofile}\nmkudffs --media-type=dvdrw ${isofile}"
	    if [[ ! -a "${mountpoint}" ]]; then
		echo "sudo mkdir ${mountpoint}"
	    fi
	    echo "sudo mount -t udf -o loop,rw ${isofile} ${mountpoint}"
	    for dir in "${genisoargs[@]}"; do
		if [[ ! -d "${mountpoint}/${${dir%%=*}#/}" ]]; then
		    echo "sudo mkdir ${mountpoint}/${${dir%%=*}#/}"
		fi
		echo "sudo rsync -ah --progress ${dir#*=} ${mountpoint}/${${dir%%=*}#/}"
	    done
	    echo "sudo umount ${mountpoint}"
	fi
    fi
fi

# append error correcting codes (ECC) to end of .iso file
createecccmd="dvdisaster -i ${isofile} -mRS03 -x 3 --encoding-io-strategy readwrite -c"
if [[ -z "${noprompt}" ]]; then
    prompttocontinue "Adding error correcting codes using following command:
  ${createecccmd}
${continueprompt2}"
    exitonerror2 "Quitting!"
fi
if [[ ! "${REPLY}" =~ "[Ss]" ]]; then
    if [[ -n "${noprompt}" ]]; then
	echo "\n\n${createecccmd}\n"
    fi
    if [[ -z "${testrun}" ]]; then
	eval "${createecccmd}"
	exitonerror1
    fi
fi

# burn the .iso file to disc
if [[ -n ${bluray} ]]; then
    burnimagecmd="growisofs -Z ${discdevice}=${isofile}"
else
    burnimagecmd="sudo wodim -v speed=${burnspeed} -dao dev=${discdevice} ${isofile}"
fi
if [[ -z "${noprompt}" ]]; then
    prompttocontinue "Burning ISO file to disc using following command:
  ${burnimagecmd}
${continueprompt2}"
    exitonerror2 "Quitting!"
fi
if [[ ! "${REPLY}" =~ "[Ss]" ]]; then
    if [[ -n "${noprompt}" ]]; then
	echo "\n\n${burnimagecmd}\n"
    fi
    if [[ -z "${testrun}" ]]; then
	eval "${burnimagecmd}"
    fi
fi
