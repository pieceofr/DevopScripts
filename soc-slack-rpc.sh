#!/usr/bin/env bash

cd ~
. service-env.sh
set -ex

curl_timeout=5
conn_lost_threshold=1800
max_diff_slot=300
rpc_server_invalid="http://123.123.123.123:8899" # for testing 
rpc_server_cluster=$RPC_URL
rpc_server_local="127.0.0.1:8899"
rpc_server="127.0.0.1:8899"

# Initialzed RPC_URL_HEATH_LAST in env. The variable stores time of last healthy rpc call
if [[ -z "$RPC_URL_HEATH_LAST" ]]; then
	export RPC_URL_HEATH_LAST=$(date +%s)
fi

echo start soc-slack-rpc at $(date)

# send a message to to sre-soc-warning slack channel
slackme(){
	sdata=$(jq --null-input --arg val "$slacktext" '{"text":$val}')
        curl -X POST -H 'Content-type: application/json' --data "$sdata" "https://hooks.slack.com/services/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"
}

# get slot height of a given node. If connection timeout happen, retry it.
get_slot_height(){
	for retry in 0 1
	do
		echo retry=$retry
		if [[ $retry -gt 0 ]];then
			sleep 5
		fi

		slot_height=$(curl --connect-timeout ${curl_timeout} ${rpc_server} -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":1, "method":"getBlockHeight"}' | jq ".result")

		if [[ $slot_height -gt 0 ]];then
			RPC_URL_HEATH_LAST=$(date +%s)
			echo RPC_URL_HEATH_LAST=$RPC_URL_HEATH_LAST
			break
		fi
		echo $rpc_server connection eror 
	done
}

# get cluster slot height
rpc_server=$rpc_server_cluster
#rpc_server=$rpc_server_invalid# unmark to test invalid conneciton

get_slot_height

# get cluster slot fail
if [[ $slot_height -eq 0 ]];then
	cur_time_sec=$(date +%s)
	let conn_lost_time=$cur_time_sec-$RPC_URL_HEATH_LAST
	if [[ $conn_lost_time -gt $threshold ]];then
		slacktext="$rpc_server is not reachable for more thant $conn_lost_time secs"
		slackme
	fi
	echo connection lost time $conn_lost_time
	exit 0
fi
# get localhost slot height
slot_height_cluster=$slot_height
rpc_server=$rpc_server_local
get_slot_height

if [[ $slot_height -eq 0 ]];then
	slacktext="$rpc_server is not reachable"
	slackme
	echo localhost rpc is not reachable
	exit 0 
fi

# check if localhost  catchup cluster
slot_height_local=$slot_height
let slot_diff=$slot_height_cluster-$slot_height_local

if [[ $slot_diff -lt 0 ]];then
	let slot_diff=$slot_height_local - $slot_height_cluster
fi

echo cluster_slot=$slot_height_cluster local_slot=$slot_height_local slack_diff=$slot_diff

if [[ slot_diff -gt $max_diff_slot ]];then
	slacktext="diff-$slot_diff, cluster-$slot_height_cluster, local-$slot_height_local"
	slackme
	exit 0
fi