#!/bin/bash


## IDENTITY
# sinfo_mon
# v2.2


## DESCRIPTION
# Checks Slurm to see if any new Slurm nodes are down and, if so, sends
# a notification.


## CHECK FOR PARAMETERS / ENFORCE PROPER USAGE
if [ "$#" -lt 2 -o "$#" -gt 3 ]; then
	echo "sinfo_mon: incorrect number of varibles"
	echo "sinfo_mon: usage:"
	echo "sinfo_mon:   $0 </path/to/data_dir> <email@address>"
	echo "sinfo_mon: OR"
	echo "sinfo_mon:   $0 </path/to/data_dir> <to_email@address> <from_email@address>"
	exit 1
fi


## BIND USER-DEFINED VARIABLES
DATA_DIR="$1" # e.g., /root/cron/sinfo_mon_data
CONTACT="$2" # e.g., blah@my.org
FROM="$2" # set from address equal to to address in case it is not specified
if [ -n "$3" ]; then
	# if from address is specified, override
	FROM="$3"
fi


## DEFINE GLOBAL VARIABLES
STATE_PREVIOUS_FILE=$DATA_DIR/sinfo_mon_state_previous # STATE FROM LAST RUN
STATE_CURRENT_UNSORTED_FILE=$DATA_DIR/sinfo_mon_state_current_unsorted # CURRENT STATE, UNSORTED
STATE_CURRENT_FILE=$DATA_DIR/sinfo_mon_state_current # CURRENT STATE, SORTED
NEW_NODES_FILE=$DATA_DIR/sinfo_mon_new_nodes # NEW NODES THAT ARE down/down*
DOWN_NODES_CURRENT_FILE=$DATA_DIR/sinfo_mon_down_nodes_current # CURRENT down NODES
DOWNSTAR_NODES_CURRENT_FILE=$DATA_DIR/sinfo_mon_downstar_nodes_current # CURRENT down* NODES
OLD_NODES_FILE=$DATA_DIR/sinfo_mon_old_nodes # NODES THAT WERE PREVIOUSLY DOWN
MAIL_FILE=$DATA_DIR/sinfo_mon_mail # FILE THAT CONTAINS TEXT FOR SENDMAIL


## REMOVE THE EPHEMERAL FILES, IF THEY EXIST
rm -f $STATE_CURRENT_UNSORTED_FILE \
	$STATE_CURRENT_FILE \
	$NEW_NODES_FILE \
	$DOWN_NODES_CURRENT_FILE \
	$DOWNSTAR_NODES_CURRENT_FILE \
	$OLD_NODES_FILE \
	$MAIL_FILE


## CHECK TO SEE IF NODES ARE DOWN AND REPORT INTO THE APPROPRIATE FILES
down_nodes_compact=$(sinfo | grep "down " | awk '{print $6}' | tr '\n' ',')
downstar_nodes_compact=$(sinfo | grep "down\* " | awk '{print $6}' | tr '\n' ',')

if [[ ! -z $down_nodes_compact ]]; then
	down_nodes_list=$(scontrol show hostname $down_nodes_compact | sort)
	for i in $down_nodes_list
	do
		# echo the node names into the file adding a comma to aid future parsing
		echo "${i}," >> $STATE_CURRENT_UNSORTED_FILE
		echo "${i}," >> $DOWN_NODES_CURRENT_FILE
	done
fi

if [[ ! -z $downstar_nodes_compact ]]; then
	downstar_nodes_list=$(scontrol show hostname $downstar_nodes_compact | sort)
	for i in $downstar_nodes_list
	do
		# echo the node names into the file adding a comma to aid future parsing
		echo "${i}," >> $STATE_CURRENT_UNSORTED_FILE
		echo "${i}," >> $DOWNSTAR_NODES_CURRENT_FILE
	done
fi


# IF THERE ARE NO down/down* NODES, THEN REFRESH STATE_PREVIOUS_FILE AND EXIT.
if [[ ! -f $STATE_CURRENT_UNSORTED_FILE ]]; then
	rm -f $STATE_PREVIOUS_FILE
	touch $STATE_PREVIOUS_FILE
	exit 0
fi


## IF STATE_CURRENT_UNSORTED FILE EXISTS, WE NEED TO CREATE A SORTED VERSION
cat $STATE_CURRENT_UNSORTED_FILE | sort >> $STATE_CURRENT_FILE


## CHECK TO SEE IF THE STATE_PREVIOUS_FILE EXISTS; IF SO COMPARE IT TO THE STATE_CURRENT_FILE
# NOTE: If the STATE_PREVIOUS_FILE does NOT exist, or if there are new nodes down/down* then
# we need to prepare and send a report. If either is the case, we'll proceed past this section.
if [[ -f $STATE_PREVIOUS_FILE ]]; then
	grep -v -f $STATE_PREVIOUS_FILE $STATE_CURRENT_FILE >> "$NEW_NODES_FILE"
	# If there are no new nodes, then exit (no need to report).
	are_new_nodes=$(cat $NEW_NODES_FILE)
	if [[ -z $are_new_nodes ]]; then
		# Make the current state the new previous state for the next run.
		cp $STATE_CURRENT_FILE $STATE_PREVIOUS_FILE
		exit 0
	fi
fi


## IF WE MADE IT THIS FAR, GO ON
# Either the STATE_PREVIOUS_FILE does NOT exist, or we have new nodes down since the last run.
# Either way, we need to prepare and send a report, then capture the current state as the new
# previous state.


## PREPARE AND SEND A REPORT
echo "To: $CONTACT" >> $MAIL_FILE
echo "Subject: LSST: new verify-worker nodes down according to Slurm" >> $MAIL_FILE
echo "From: $FROM" >> $MAIL_FILE
echo "" >> $MAIL_FILE
echo "The following new nodes are down/down* according to Slurm (down = unavailable for use, down* = down and not responding):" >> $MAIL_FILE
if [[ ! -f $NEW_NODES_FILE ]]; then
	touch $NEW_NODES_FILE
fi
for j in $(cat $NEW_NODES_FILE)
do
	if [[ -f $DOWN_NODES_CURRENT_FILE && $(grep ${j} $DOWN_NODES_CURRENT_FILE) ]]; then
		echo "${j} down" >> $MAIL_FILE
	elif [[ -f $DOWNSTAR_NODES_CURRENT_FILE && $(grep ${j} $DOWNSTAR_NODES_CURRENT_FILE) ]]; then
		echo "${j} down*" >> $MAIL_FILE
	else
		exit 1
	fi
done
for k in $(cat $STATE_CURRENT_FILE)
do
	if [[ ! $(grep ${k} $NEW_NODES_FILE) ]]; then
		echo "${k}" >> $OLD_NODES_FILE
	fi
done
if [[ -f $OLD_NODES_FILE ]]; then
	echo "" >> $MAIL_FILE
	echo "The following other nodes are still down/down* according to Slurm:" >> $MAIL_FILE
	for l in $(cat $OLD_NODES_FILE)
	do
		if [[ -f $DOWN_NODES_CURRENT_FILE && $(grep ${l} $DOWN_NODES_CURRENT_FILE) ]]; then
			echo "${l} down" >> $MAIL_FILE
		elif [[ -f $DOWNSTAR_NODES_CURRENT_FILE && $(grep ${l} $DOWNSTAR_NODES_CURRENT_FILE) ]]; then
			echo "${l} down*" >> $MAIL_FILE
		else
			exit 1
		fi
	done
fi
sendmail $CONTACT < $MAIL_FILE


## MAKE THE CURRENT STATE THE NEW PREVIOUS STATE FOR THE NEXT RUN
cp $STATE_CURRENT_FILE $STATE_PREVIOUS_FILE
