#!/usr/bin/env zsh

# Print a booklet from a pdf file, using a single sided printer.
# Assumes that CUPS, poppler-utils and imagemagick are installed.

# Usage
local USAGE="Usage: $0 [-h] [-k] [-d] [-N] [-p PRINTER] [-n NUP] [-o STRING] INFILE.pdf

Print a booklet containing the contents of INFILE.pdf with a single side printer.
The user is prompted before printing begins, then after one half of each sheet is printed the user
is prompted to flip the pages over before the other sides are printed.

Options:
  -h           show this help
  -k           keep temp directory used to store intermediate files, and print its location
  -p PRINTER   printer to use (default is $(lpstat -d|awk '{print $4}'))
  -n NUP       No. of pages to print on each side of paper/size of booklet (1=full, 2=half, 4=quarter, default is 2)
  -o STRING    string of extra options to pass to the lp command 
  -N           no-prompt; print immediately without prompting 
  -d           debug: display commands that would be run without actually running them
"
# Check command availability
set -o extendedglob
checkcmds() {
    local cmd
    for cmd in $@; do
	if ! whence $cmd >/dev/null; then
	    print -- "Cannot find $cmd command!"
	    return 1
	fi
    done
}
checkcmds pdfseparate pdfunite convert || exit 127

# Parse command line args
local OUTFILE INFILE KEEP LPOPTS FILE DEBUG 
local NUP=2
local PRINTER=$(lpstat -d|awk '{print $4}')
while getopts "hkNp:o:n:d" option; do
      case $option in
	(k)
	    KEEP=t
	    ;;
	(p)
	    # this variable is checked by lpr
	    PRINTER="${OPTARG}"
	    ;;
	(o)
	    LPOPTS="${OPTARG}"
	    ;;
	(N)
	    NOPROMPT=y
	    ;;
	(n)
	    NUP="${OPTARG}"
	    if ((!(NUP==1||NUP==2||NUP==4))); then
		print -- $USAGE
		print -- "Argument to -n option must be 1, 2 or 4."
		exit 1
	    fi
	    ;;
	(d)
	    DEBUG=y
	    ;;
        (\?|h)
	    print -- $USAGE
	    exit 0
	    ;;
      esac 
done

INFILE=${@[@]:$OPTIND}

LPOPTS+=" -d $PRINTER -o number-up=$NUP -o number-up-layout=tblr" # printer options

if [[ $DEBUG = y ]]; then
    print -- "DEBUG=${DEBUG}, KEEP=${KEEP}, LPOPTS=${LPOPTS}, NOPROMPT=${NOPROMPT}, INFILE=${INFILE}"
fi

if [[ -z $INFILE ]]; then
    print -- $USAGE
    exit 2
elif [[ ! -r $INFILE ]]; then
    print -- "Unable to read $INFILE"
    exit 2
fi
# Utility functions
runcmd() {
    if [[ $DEBUG == y ]]; then
	print -- ${@[@]}
    else
	${@[@]}
    fi
}
cleanup() {
    runcmd cd ${ORIGDIR}
    if [[ -n $KEEP ]]; then
	print -- "Intermediate files stored in ${TEMPDIR}"
    else
	runcmd rm -r $TEMPDIR
    fi
}
# Change directory
local ORIGDIR="${PWD}"
if [[ $DEBUG = y ]]; then
    local TEMPDIR=$(mktemp -u -d)
else
    local TEMPDIR=$(mktemp -d)
fi

runcmd /bin/cp $INFILE ${TEMPDIR}/

runcmd cd $TEMPDIR
# Create pdfs for individual pages
local emptypage=empty.pdf
runcmd convert xc:none -page A4 $emptypage
runcmd pdfseparate $INFILE ${INFILE%%.pdf}_%d.pdf
# Group pages together to be printed on separate sheets
local NPAGES=$(pdfinfo $INFILE |grep "Pages:"|awk '{print $2}')
local i j k n
local -a A_pages B_pages
## 1 page per side
if ((NUP == 1)); then
    for n in {1..$(((NPAGES+1)/2))}; do
	runcmd /bin/cp ${INFILE%%.pdf}_$((2*n-1)) ${INFILE%%.pdf}_A${n}.pdf
	A_pages[n]=$((2*n-1))
	if ((2*n<=NPAGES)); then
	    runcmd /bin/cp ${INFILE%%.pdf}_$((2*n)) ${INFILE%%.pdf}_B${n}.pdf
	    B_pages[n]=$((2*n))
	else
	    runcmd /bin/cp ${emptypage} ${INFILE%%.pdf}_B${n}.pdf
	    B_pages[n]="-"
	fi
    done
    ((n=n+1))
## 2 pages per side    
elif ((NUP == 2)); then
    # Set local parameters
    i=$(((NPAGES+3)/4)) # No. of pieces of paper required
    j=$((2*i-1)) # smallest page No. (odd) printed on centre (last) sheet of paper
    k=$((j+3)) # largest page No. (even) printed on centre (last) sheet of paper
    n=1 # used to label output pdf files, and store the final sheet No.
    # Loop from centre sheets of booklet backwards.
    while ((i>=1)); do
	if ((k<=NPAGES)); then
	    A_pages[n]="${k},${j}"
	    B_pages[n]="$((j+1)),$((k-1))"
	elif (((k-1)==NPAGES)); then
	    A_pages[n]="-,${j}"
	    B_pages[n]="$((j+1)),$((k-1))"
	else # (k-2)==NPAGES
	    A_pages[n]="-,${j}"
	    B_pages[n]="$((j+1)),-"
	fi
	runcmd pdfunite ${${${(s:,:)A_pages[n]}//-/${emptypage}}//(#b)([0-9]##)/${INFILE%%.pdf}_${match[1]}.pdf} \
	       ${INFILE%%.pdf}_A${n}.pdf
	runcmd pdfunite ${${${(s:,:)B_pages[n]}//-/${emptypage}}//(#b)([0-9]##)/${INFILE%%.pdf}_${match[1]}.pdf} \
	       ${INFILE%%.pdf}_B${n}.pdf
	# update looping vars
	((i=i-1))
	((j=j-2))	
	((k=k+2))
	((n=n+1))
    done
## 4 pages per side
else # $NUP == 4
    # Set local parameters
    i=$(((NPAGES+7)/8)) # No. of sheets of paper required
    j=$((i*4-3)) # smallest page No. (odd) printed on centre (last) sheet of paper
    k=$((j+7)) # largest page No. (even) printed on centre (last) sheet of paper
    n=1 # used to label output pdf files, and store the final sheet No.
    # loop from centre sheets of booklet backwards
    while ((i>=1)); do
	if ((k<=NPAGES)); then
	    A_pages[n]="$((k-2)),${k},$((j+2)),${j}"
	    B_pages[n]="$((j+3)),$((j+1)),$((k-3)),$((k-1))"
	elif (((k-1)==NPAGES)); then
	    A_pages[n]="$((k-2)),-,$((j+2)),${j}"
	    B_pages[n]="$((j+3)),$((j+1)),$((k-3)),$((k-1))"
        elif (((k-2)==NPAGES)); then
	    A_pages[n]="$((k-2)),-,$((j+2)),${j}"
	    B_pages[n]="$((j+3)),$((j+1)),$((k-3)),-"
        elif (((k-3)==NPAGES)); then
	    A_pages[n]="-,-,$((j+2)),${j}"
	    B_pages[n]="$((j+3)),$((j+1)),$((k-3)),-"
        else # (k-4)==NPAGES
	    A_pages[n]="-,-,$((j+2)),${j}"
	    B_pages[n]="$((j+3)),$((j+1)),-,-"
	fi
	runcmd pdfunite ${${${(s:,:)A_pages[n]}//-/${emptypage}}//(#b)([0-9]##)/${INFILE%%.pdf}_${match[1]}.pdf} \
	       ${INFILE%%.pdf}_A${n}.pdf
	runcmd pdfunite ${${${(s:,:)B_pages[n]}//-/${emptypage}}//(#b)([0-9]##)/${INFILE%%.pdf}_${match[1]}.pdf} \
	       ${INFILE%%.pdf}_B${n}.pdf
	# update looping vars
	((i=i-1))	
	((j=j-4))	
	((k=k+4))
	((n=n+1))
    done
fi
# Traps
## cleanup on exit
trap cleanup EXIT
## cancel print jobs if Ctrl+c is pressed
trap "
print -- \"Cancelling print jobs...\"
pendingjobs=\$(lpq -a|grep ${INFILE[1,30]}|awk '{print \$3}')
if [[ -n \$pendingjobs ]] lprm \$pendingjobs
exit 130
" SIGINT
# Print pages
## prompt user if necessary
if [[ -z $NOPROMPT ]]; then
    read -q -s "?Place paper in printer and press y to continue, or any other key to quit:
"
fi
if [[ $NOPROMPT == y || $REPLY == y ]]; then
## print 1st side of sheets
    local N request jobid
    for N in {1..$((n-1))}; do # print A sides in order
	print -- "Printing booklet page$(if ((NUP>1));then print s;fi) ${(S)A_pages[N]/%(#b),(*)/ \& ${match[1]}}. Press Ctrl+c to cancel."
	request=$(runcmd lp ${=LPOPTS} -- ${INFILE%%.pdf}_A${N}.pdf)
	# wait for job to finish before adding more to the queue 
	if [[ -z $DEBUG ]]; then
	    jobid=$(awk '{print $4}'<<<${request})
	    while lpstat -o|grep $jobid >/dev/null; do
		sleep 0.3
	    done
	else
	    print -- $request
	fi
    done
    if [[ -z $NOPROMPT ]]; then
	if ((NUP==2)); then
	    read -q -s "?
Remove the $((n-1)) printed pages, flip them vertically so that the top & bottom edges swap position, and then place them in the
paper feed so that the edge that was nearest you goes in first, and the blank side of the first page to be printed is uppermost.
Then press y to continue, or any other key to quit:
"
	else
	    read -q -s "?
Remove the $((n-1)) printed pages, flip them horizontally ensuring that the top & bottom edges do NOT swap position, and then
place them back in the paper feed so that the edge that was nearest you goes in first, and the blank side of the first page to 
be printed is uppermost.
Then press y to continue, or any other key to quit:
"
	fi
    fi
    if [[ $NOPROMPT == y || $REPLY == y ]]; then
## print 2nd side of sheets
	for N in {1..$((n-1))}; do # print B sides with pages swapped so they match pages on A sides
	    print -- "Printing booklet page$(if ((NUP>1));then print s;fi) ${(S)B_pages[N]/%(#b),(*)/ \& ${match[1]}}. Press Ctrl+c to cancel."	    
	    request=$(runcmd lp ${=LPOPTS} -- ${INFILE%%.pdf}_B${N}.pdf)
	    # wait for job to finish before adding more to the queue
	    if [[ -z $DEBUG ]]; then
		jobid=$(awk '{print $4}'<<<${request})
		while lpstat -o|grep $jobid >/dev/null; do
		    sleep 0.3
		done
	    else
		print -- $request
	    fi
	done
    else
	exit 1 # user chose to quit
    fi
## final instructions to user    
    if ((NUP==4)); then
	print -- "Now cut the sheets in half, then fold them in half, then rearrange them so that the pages are
properly oriented & in order, and then staple them together."
    elif ((NUP==2)); then
	print -- "Now collect & arrange the sheets so that the pages are properly oriented & in order, then fold them in half,
and then staple them together."
    else
	print -- "Now collect & arrange the sheets so that the pages are properly oriented & in order, and then staple them together."
    fi
else
    exit 1 # user chose to quit
fi
# exit
exit 0
