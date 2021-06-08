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
    echo "${RET[@]}"
}

contains_element () {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

# merge the two passed-in arrays of strings together.
# must be called as follows: merge_lists <ARRAY_1_SIZE> <ARRAY_1> <ARRAY_2_SIZE> <ARRAY_2>
# merge_lists() {
#     declare -i _arr1_size _arr2_size _idx_arr1 _idx_arr2; 
#     declare -a _arr1 _arr2;
    
#     _arr1=(); _arr2=();
#     _arr1_size=$1; shift
#     _arr1+=($1); shift
#     _arr2_size=$1; shift
#     _arr2+=($1); shift
    
#     # IFS=$'\n' _sorted_arr1=($(sort <<<"${_arr1[*]}"))
#     # unset IFS
#     # IFS=$'\n' _sorted_arr2=($(sort <<<"${_arr2[*]}"))
#     # unset IFS

#     _idx_arr1=0; _idx_arr2=0;
    
#     declare -a _ret;

#     while [ $_idx_arr1 -leq $_arr1_size ]; do
#         if [ $(contains_element "${_arr1[$_idx_arr1]}" "${ret[@]}") ]; then _ret+=(${_arr1[$_idx_arr1]}); _idx_arr1=$(($_idx_arr1+1)); fi
#     done

#     while [ $_idx_arr2 -leq $_arr2_size ]; do
#         if [ $(contains_element "${_arr2[$_idx_arr2]}" "${ret[@]}") ]; then _ret+=(${_arr2[$_idx_arr2]}); _idx_arr2=$(($_idx_arr2+1)); fi
#     done

#     return ${_ret[@]}
# }

# array_to_string() {
#     # Treat the arguments as an array:
#     local -a array=( "$@" )
#     declare -p array | sed -e 's/^declare -a array=//'
# }

# Called as follows: remove_duplicates <ARRAY>
remove_duplicates() {
    ARR=("$@"); RET=();
    for entry in ${ARR[@]}; do
        contains_element "${entry}" "${RET[@]}"
        RET_CODE=$?
        if [ "$RET_CODE" != "0" ]; then 
            RET+=(${entry});
        fi
    done
    echo "${RET[@]}"
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

    non_namespaced_resource_types_in_group=()
    namespaced_resource_types_in_group=()
    
    if [ "$group_name" == "core" ]; then
        STARTER_PATH="${APISERVER}/api" 

        # the only API version for the core group is v1
        non_namespaced_resource_types_in_group=($(curl -s $STARTER_PATH/v1 | jq '.resources[] | select(.namespaced==false) | .name' | tr -d \" | tr -d \' ) )
        namespaced_resource_types_in_group=($(curl -s $STARTER_PATH/v1 | jq '.resources[] | select(.namespaced==true) | .name' | tr -d \" | tr -d \' ) )
    else 
        STARTER_PATH="${APISERVER}/apis/${group_name}"

        api_versions_for_group=($(curl -s $STARTER_PATH | jq '.versions[].version' | tr -d \" | tr -d \')) 

        # echo "api_versions_for_group = ${api_versions_for_group[@]}"

        contains_element "v1alpha1" "${api_versions_for_group[@]}"; RET=$?
        # echo "v1alpha1: RET = $RET"
        if [ "$RET" == "0" ]; then 
            # echo herev1alpha1

            echo "api_versions_for_group = ${api_versions_for_group[@]}"

            non_namespaced_resource_types_in_group+=($(curl -s $STARTER_PATH/v1alpha1 | jq '.resources[] | select(.namespaced==false) | .name' | tr -d \" | tr -d \') )
            namespaced_resource_types_in_group+=($(curl -s $STARTER_PATH/v1alpha1 | jq '.resources[] | select(.namespaced==true) | .name' | tr -d \" | tr -d \') )
            # echo therev1alpha1
        fi 

        contains_element "v1beta1" "${api_versions_for_group[@]}"; RET=$?
        # echo "v1beta1: RET = $RET"
        if [ "$RET" == "0" ]; then
            # echo herev1beta1
            non_namespaced_resource_types_in_group+=($(curl -s $STARTER_PATH/v1beta1 | jq '.resources[] | select(.namespaced==false) | .name' | tr -d \" | tr -d \') )
            namespaced_resource_types_in_group+=($(curl -s $STARTER_PATH/v1beta1 | jq '.resources[] | select(.namespaced==true) | .name'  | tr -d \" | tr -d \') )
            # echo therev1beta1
        fi

        contains_element "v1" "${api_versions_for_group[@]}"; RET=$?
        # echo "v1: RET=$RET"
        if [ "$RET" == "0" ]; then
            # echo herev1
            non_namespaced_resource_types_in_group+=($(curl -s $STARTER_PATH/v1 | jq '.resources[] | select(.namespaced==false) | .name' | tr -d \" | tr -d \') )
            namespaced_resource_types_in_group+=($(curl -s $STARTER_PATH/v1 | jq '.resources[] | select(.namespaced==true) | .name' | tr -d \" | tr -d \') )
            # echo therev1
        fi

        echo "group_name = ${group_name}"
        echo "starter_path = $STARTER_PATH"
        echo "sz before=${#namespaced_resource_types_in_group[@]}"

        non_namespaced_resource_types_in_group=($(remove_duplicates "${non_namespaced_resource_types_in_group[@]}"))
        namespaced_resource_types_in_group=($(remove_duplicates "${namespaced_resource_types_in_group[@]}"))

        echo "sz after=${#namespaced_resource_types_in_group[@]}"
    fi

    # For figuring out the API group of a given resource type, later
    sz_non_namespaced=${#non_namespaced_resource_types_in_group[@]}
    sz_namespaced=${#namespaced_resource_types_in_group[@]}
    num_non_namespaced_resource_types_per_api_group=("${num_non_namespaced_resource_types_per_api_group[@]}" "${sz_non_namespaced}")
    num_namespaced_resource_types_per_api_group=("${num_namespaced_resource_types_per_api_group[@]}" "${sz_namespaced}")

    non_namespaced_resource_types+=("${non_namespaced_resource_types_in_group[@]}")
    namespaced_resource_types+=("${namespaced_resource_types_in_group[@]}")

    # echo "namespaced_resource_types = ${namespaced_resource_types[@]}"
done

cumulative_num_non_namespaced_resource_types_per_api_group=$(compute_cumulative ${num_non_namespaced_resource_types_per_api_group[@]})
cumulative_num_namespaced_resource_types_per_api_group=$(compute_cumulative ${num_namespaced_resource_types_per_api_group[@]})

echo "num_namespaced_resource_types_per_api_group = ${num_namespaced_resource_types_per_api_group[@]}"
echo "cumulative_num_namespaced_resource_types_per_api_group = ${cumulative_num_namespaced_resource_types_per_api_group[@]}"

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