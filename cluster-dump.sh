#!/bin/bash

PORT=1181

# if lsof on PORT is not empty, PORT is being used by another process 
while [ ! -z "$(lsof -i:${PORT})" ];
do
    PORT=$(($PORT + 1))
done

# Redirect API requests to localhost:${PORT} to the kubernetes api server
kubectl proxy --port=${PORT} &

# Wait for the proxy to start
sleep 10

# Trap handler to clean up child process if script is ^C ed
trap 'kill $!; wait $!; exit 0' SIGINT SIGTERM

# Usage: dequote <INSERT_STRING_HERE>
#function dequote(str) {
#    echo $1 | tr -d \' | tr -d \"
#}
 
APISERVER=localhost:${PORT}

function compute_cumulative() {
    ARR=("$@"); RET=(); tot=0;
    for k in ${!ARR[@]}; do
        tot=$(($tot+${ARR[$k]}))
        RET+=(${tot})
    done
    return $RET
}

contains_element () {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

# merge the two passed-in arrays together
merge_lists() {
    
}

# Get and store all api groups in an array
api_groups=($(curl -s -X GET $APISERVER/apis | jq '.groups[].name' | tr -d \' | tr -d \"))
api_groups=("core" "${api_groups[@]}")

# Get all namespaces
namespaces=($(curl -s -X GET $APISERVER/api/v1/namespaces | jq '.items[].metadata.name' | tr -d \" | tr -d \'))

namespaced_resource_types=()
non_namespaced_resource_types=()

# namespaced_resource_types_api_versions[k] is one of 0-7, indicating which API versions the resource namespaced_resources_types[k] belongs to
namespaced_resource_types_api_versions=()
non_namespaced_resource_types_api_versions=()

num_non_namespaced_resource_types_per_api_group=()
num_namespaced_resource_types_per_api_group=()

for k in ${!api_groups[@]}; do
    group_name=${api_groups[$k]}
    
    
    if [ "$group_name" == "core" ]; then
        STARTER_PATH="${APISERVER}/api/"
    else 
        STARTER_PATH="${APISERVER}/apis/${group_name}"
    fi

    api_versions_for_group=$(curl -s $STARTER_PATH | jq '.versions[].version')

    # For the namespaced_resource_types array
    # 1. Merge the two lists of resource types for the different api versions (v1, v1beta1, v1alpha1) for the same api group to get one list of all resource types that the api group supports
    # 2. For each api group, obtain the: list of resource type names for every api version (so there will be 3 lists: for v1, v1alpha1, and v1beta1)
    # 3. Loop through the merged resource types list and for each resource type find all api groups that it belongs to (by seeing if the list contains a value with that name). Store that value in the namespaced_resource_types_api_versions array
    #                at the same index that the value lives in the merged resource types list 
    # 4. Add the merged resource types list to the back of the namespaced_resource_types array 
    #
    # Do the same with the non_namespaced_resource_types array

    if [ "$group_name" == "core" ]; then
        resource_types=($(curl -s $STARTER_PATH/v1))
    else 
        resource_types=($(curl -s $STARTER_PATH/v1))
    fi

    printf "group_name = ${group_name}\n"
    echo ${resource_types[@]}

    echo "starting_jq..."    
    non_namespaced_resource_types_in_group=$(echo ${resource_types[@]} | jq '.resources[] | select(.namespaced == "false") | .name')
    namespaced_resource_types_in_group=$(echo ${resource_types[@]} | jq '.resources[] | select(.namespaced == "true") | .name')
    echo "ending_jq..."

    # For figuring out the API group of a given resource type, later
    num_non_namespaced_resource_types_per_api_group+=($(echo ${non_namespaced_resource_types_in_group[@]} | jq '.resources | length'))
    num_namespaced_resource_types_per_api_group+=($(echo ${namespaced_resource_types_in_group[@]} | jq '.resources | length'))

    non_namespaced_resource_types+=("${non_namespaced_resource_types_in_group[@]}")
    namespaced_resource_types+=("${namespaced_resource_types_in_group[@]}")

    # printf "namespaced_resource_types = ${namespaced_resource_types[@]}\n"
done

cumulative_num_non_namespaced_resource_types_per_api_group=$(compute_cumulative ${num_non_namespaced_resource_types_per_api_group[@]})
cumulative_num_namespaced_resource_types_per_api_group=$(compute_cumulative ${num_namespaced_resource_types_per_api_group[@]})

printf "num_namespaced_resource_types_per_api_group = ${num_namespaced_resource_types_per_api_group[@]}\n"
printf "cumulative_num_namespaced_resource_types_per_api_group = ${num_namespaced_resource_types_per_api_group[@]}\n"

# printf "############################################################\n"
# printf "######################GLOBAL RESOURCES######################\n"
# printf "############################################################\n"

# for group_name in ${api_groups[@]}; do

#     if [ "${group_name}" == "core" ]
#     then
        
#         resource_types = ($(curl -s $APISERVER/api/v1/ | jq '.resources[].name' | tr -d \' | tr -d \"))
#         resource_types_json = ($(curl -s $APISERVER/api/v1/))
        
#         for i in ${!resource_types[@]}; do

#             resource_type = ${resource_types[$i]}
#             if [ "$(dequote $(echo ${resouce_types_json[$i]} | jq '.namespaced') )" == "false"]; then
            
#                 printf "############## ${resource_type} (API group: ${group_name}) ##############\n"  

#                 printf "############# SUMMARY #############\n"
#                 kubectl get ${resource_type}

#                 printf "############ DETAILED DESCRIPTIONS #############\n"
#                 object_names = ($(curl -s $APISERVER/api/v1/${resource_type}/ | jq '.items[].metadata.name' | tr -d \' | tr -d \"))

#                 for object_name in ${object_names[@]}; do
#                     printf "${object_name}\n"
#                     kubectl describe ${resource_type} ${object_name}
#                     printf "\n"
#                 done
#             fi

#         done

#     else  # non-core api group
#         resource_types = ($(curl -s $APISERVER/apis/${group_name}/v1 | jq '.resources[].name' | tr -d \' | tr -d \"))
#         resource_types_json = ($(curl -s $APISERVER/apis/${group_name}/v1))

#         for i in ${!resource_types[@]}; do
#             resource_type = ${resource_types[$i]}

#             if [ "$(dequote $(echo ${resource_types_json[$i]} | jq '.namespaced') )" == "false"]; then

#                 printf "############## ${resource_type} (API group: ${group_name}) ##############\n"  

#                 printf "############# SUMMARY #############\n"
#                 kubectl get ${resource_type}

#                 printf "############ DETAILED DESCRIPTIONS #############\n"
#                 object_names = ($(curl -s $APISERVER/apis/${group_name}v1/${resource_type}/ | jq '.items[].metadata.name' | tr -d \' | tr -d \"))

#                 for object_name in ${object_names[@]}; do
#                     printf "${object_name}\n"
#                     kubectl describe ${resource_type} ${object_name}
#                     printf "\n"
#                 done

#             done

#         done

#     fi
# done

# printf "############################################################\n"
# printf "####################NAMESPACED RESOURCES####################\n"
# printf "############################################################\n"

# for namespace in ${namespaces[@]}; do
#     printf "############ NAMESPACE : ${namespace} ############\n"

#     for group_name in ${api_groups[@]}; do

#         resource_types = ()
#         resource_types_json = ()
#         if [ "$group_name" == "core"]; then
#             resource_types_json = ($(curl -s $APISEVER/api/v1 | tr -d \' | tr -d \"))
#             resource_types = ($(curl -s $APISERVER/api/v1 | jq '.resources[].name' | tr -d \' | tr -d \"))
#         else 
#             resource_types_json = ($(curl -s $APISERVER/apis/${group_name}/v1 | tr -d \" | tr -d \'))
#             resource_types = ($(curl -s $APISERVER/apis/${group_name}/v1 | jq '.resources[].name' | tr -d \' | tr -d \"))
#         fi

#         for i in ${!resource_types[@]}; do

#             resource_type = $( {resource_types_json}[$i] | 


#         done


#     done

# done

if [ -z "$(kill -0 $! 2>&1)" ]; then kill $!; wait $!; fi # kill -0 $CHILD_PID returned nothing so the child is still running

# For all global resources, run kubectl describe

# Get all crds

# Get all resources in the other api groups