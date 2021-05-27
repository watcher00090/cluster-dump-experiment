#!/bin/bash

PORT=1181

# if lsof on PORT is not empty, PORT is being used by another process 
while [ ! -z "$(lsof -i:${PORT})" ];
do
    PORT=$(($PORT + 1))
done

# Redirect API requests to localhost:${PORT} to the kubernetes api server
kubectl proxy --port=${PORT} &

# Trap handler to clean up child process if script is ^C ed
trap 'kill $!; wait $!; exit 0' SIGINT SIGTERM

sleep 10
 
APISERVER=localhost:${PORT}

# Get and store all api groups in an array
api_groups=($(curl -s -X GET $APISERVER/apis | jq '.groups[].name'))

# Get and print all namespaces
namespaces=($(curl -s -X GET $APISERVER/api/v1/namespaces | jq '.items[].metadata.name'))

echo ${namespaces[@]}

echo "sleeping..."
sleep 10

if [ -z "$(kill -0 $! 2>&1)" ]; then kill $!; wait $!; fi # kill -0 $CHILD_PID returned nothing so the child is still running

# For all global resources, run kubectl describe

# Get all crds

# Get all resources in the other api groups