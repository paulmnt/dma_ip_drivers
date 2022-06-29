#!/bin/bash

##############################################################
#
# parse the fio result directory generated by the fio_test.sh
#
##############################################################
function parse_iops() {
	eval str="$1"

	value=$(echo $str | awk -F  "," '{print $1}' | awk -F "=" '{print $2}')
	unit=$(echo $value |  awk -F '[0-9,.]*' '{print $2}')
	value=$(echo $value | sed 's/[^0-9,.]*//g')
#	echo -n " iops: ${value}${unit}"

	if [ -z "$unit" ];then
		value=$(echo "scale=4; $value/1000" | bc -l)
	elif [[ "$unit" == "k" ]];then
		value=$(echo "scale=4; $value" | bc -l)
	elif [[ "$unit" == "m" ]];then
		value=$(echo "scale=4; $value*1000" | bc -l)
	else
		echo "iops: $value$unit, unknown unit $unit."
	fi
}

function parse_bw() {
	eval str="$1"

	value=$(echo $str | awk -F  "," '{print $2}')
	value=$(echo $value | awk -F "[(,)]" '{print $2}')
	unit=$(echo $value |  awk -F '[0-9,.]*' '{print $2}')
	value=$(echo $value | sed 's/[^0-9,.]*//g')
#	echo -n " bw: ${value}${unit}"

	if [[ "$unit" == "kB/s" ]];then
		value=$(echo "scale=4; $value" | bc -l)
	elif [[ "$unit" == "MB/s" ]];then
		value=$(echo "scale=4; $value*1024" | bc -l)
	elif [[ "$unit" == "gB/s" ]];then
		value=$(echo "scale=4; $value*1024*1024" | bc -l)
	else
		echo "bw: $value$unit, unknown unit $unit."
	fi
}

function parse_latency() {
	eval str="$1"

	value=$(echo $str | awk -F  "," '{print $3}' | awk -F "=" '{print $2}')
	unit=$(echo $str |  awk -F "[(,)]" '{print $2}')
#	echo -n " latency: ${value}${unit}"

	if [[ "$unit" == "usec" ]];then
		value=$(echo "scale=4; $value" | bc -l)
	elif [[ "$unit" == "sec" ]];then
		value=$(echo "scale=6; $value*1000000" | bc -l)
	elif [[ "$unit" == "msec" ]];then
		value=$(echo "scale=6; $value*1000" | bc -l)
	elif [[ "$unit" == "nsec" ]];then
		value=$(echo "scale=4; $value/1000" | bc -l)
	else
		echo "latency: $value$unit, unknown unit $unit."
        fi
}

##############
# Main body
##############

if [ $# -lt 1 ];then
	echo "$0 <result directory>"
	exit 1
fi
dir=$1

if  [[ ! -d $dir ]];then
	echo "$dir does NOT exist."
	exit 1
fi

declare -a lat_array
resfname=result.csv

rm -f $dir/$resfname
channel_list=`ls $dir`
for channels in $channel_list; do
	cd $dir/$channels
	rm -f $dir/$channels/$resfname

	iodir_list=`ls`
	for iodir in $iodir_list; do
		cd $dir/$channels/$iodir

		rm -f $resfname
		echo > $resfname

		fio_list=`ls fio*.log`
		for fname in $fio_list; do
			# fio result file format fio_<io size>_t<# threads>.log
			sz=$(echo $fname | cut -d. -f1 | cut -d_ -f2)
			thread=$(echo $fname | cut -d. -f1 | cut -d_ -f3)
			thread=$(echo $thread | sed 's/[^0-9]*//')

			#echo "$dir/$channels/$iodir/$fname:"

			value=0;
			unit=0
			if [ "$iodir" == "h2c" ]; then
				#echo -n "$channels h2c:io $sz thread $thread "

				ln=$(grep "write:" $fname)
				parse_iops "\${ln}"
				echo -n $sz,$thread,$value, >> $resfname
				parse_bw "\${ln}"
				echo -n $value, >> $resfname
				ln=$(grep clat $fname | grep avg)
				parse_latency "\${ln}"
				echo "$value,,,," >> $resfname

			elif [ "$iodir" == "c2h" ]; then
				#echo -n "$channels c2h:io $sz thread $thread "

				ln=$(grep "read:" $fname)
				parse_iops "\${ln}"
				echo -n $sz,$thread,,,,$value, >> $resfname
				parse_bw "\${ln}"
				echo -n $value, >> $resfname
				ln=$(grep clat $fname | grep avg)
				parse_latency "\${ln}"
				echo "$value," >> $resfname

			elif [ "$iodir" == "bi" ]; then
				#echo -n "$channels bidir:io $sz thread $thread "

				readarray lat_array < <(grep clat $fname | \
							grep avg)

				# h2c
				#echo -n "h2c "

				ln=$(grep "write:" $fname)
				parse_iops "\${ln}"
				echo -n $sz,$thread,$value, >> $resfname
				parse_bw "\${ln}"
				echo -n $value, >> $resfname
				parse_latency "\${lat_array[1]}"
				echo -n $value, >> $resfname

				#c2h
				#echo -n " c2h "

				ln=$(grep "read:" $fname)
				parse_iops "\${ln}"
				echo -n $value, >> $resfname
				parse_bw "\${ln}"
				echo -n $value, >> $resfname
				parse_latency "\${lat_array[0]}"
				echo $value >> $resfname

			fi
		done
	done
done

echo
cd $dir
for channels in $channel_list; do
	cd $dir/$channels

	echo -n "iosize(B)","Thread #", > $resfname
	echo -n "H2C IOPS(K)","H2C BW(KB/s)","H2C Latency(usec)," >> $resfname
	echo "C2H IOPS(K)","C2H BW(KB/s)","C2H Latency(usec)," >> $resfname

	for iodir in $iodir_list; do
		cat $iodir/$resfname | sort -t, -k1,1n >> $resfname
	done

	echo "$channels channel results: $dir/$channels/$resfname"
done