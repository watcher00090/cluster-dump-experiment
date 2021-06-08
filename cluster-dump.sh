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

# function compute_cumulative() {
#     ARR=("$@"); RET=(); tot=0;
#     for k in ${!ARR[@]}; do
#         tot=$(($tot+${ARR[$k]}))
#         RET+=(${tot})
#     done
#     echo "${RET[@]}"
# }

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

# Arguments: An index into either the number of namespaced resource types per api group array or the 
#            number of non namespaced resource types per api group array, followed by either the 
#            namespaced resource types array or the non_namespaced resource types array
# Outputs the position into the api_groups array of the api group for the given index
# Outputs -1 if the index is to large to correspond to an api group
api_group() {
    local _given_idx;
    local RESOURCE_COUNT; # stores at index k the number of resources (namespaced or non namespaced depending on the input) in the kth API group
    local _tot; # number of resources in the first k+1 API groups
    local _EXITED_LOOP;
    local _val;

    _given_idx="$1"; shift 
    RESOURCE_COUNT=("$@");
    _tot=0; 

    # echo "_given_idx=$_given_idx"
    # echo "RESOURCE_COUNT = ${RESOURCE_COUNT[@]}"
    
    for _idx in ${!RESOURCE_COUNT[@]}; do
        # echo "tot=$_tot"
        _tot=$(($_tot+${RESOURCE_COUNT[$_idx]}))
        if [ $_given_idx -le $(($_tot-1)) ]; then 
            echo $_idx
            return 0;
        fi
    done

    echo -1; return 1;
}

sift() {
    local versions_arr
    local ret
    
    versions_arr=("$@"); shift

    if [ ${#versions_arr[@]} == 3 ]; then
        echo "v1alpha1 v1beta1 v1"; return 0
    elif [ ${#versions_arr[@]} == 2 ]; then
        if [ ${versions_arr[0]} == "v1" ] || [ ${versions_arr[1]} == "v1" ]; then
            if [ "${versions_arr[0]}" == "v1alpha1" ] || [ "${versions_arr[1]}" == "v1alpha1" ]; then echo "v1alpha1 v1"; return 0; fi
            if [ "${versions_arr[0]}" == "v1beta1" ] || [ "${versions_arr[1]}" == "v1beta1" ]; then echo "v1beta1 v1"; return 0; fi
        else echo "v1alpha1 v1beta1"; fi
    elif [ ${#versions_arr[@]} == 1 ]; then
        echo "${versions_arr[@]}"; return 0
    elif [ ${#versions_arr[@]} == 0 ]; then
        echo ""; return 0
    else
        echo "ERROR: unrecognized version array size in sift()"
        return -1;    
    fi
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

            # echo "api_versions_for_group = ${api_versions_for_group[@]}"

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

        # echo "group_name = ${group_name}"
        # echo "starter_path = $STARTER_PATH"
        # echo "sz before=${#namespaced_resource_types_in_group[@]}"

        non_namespaced_resource_types_in_group=($(remove_duplicates "${non_namespaced_resource_types_in_group[@]}"))
        namespaced_resource_types_in_group=($(remove_duplicates "${namespaced_resource_types_in_group[@]}"))

        # echo "sz after=${#namespaced_resource_types_in_group[@]}"
    fi

    # For figuring out the API group of a given resource type, later
    sz_non_namespaced=${#non_namespaced_resource_types_in_group[@]}
    sz_namespaced=${#namespaced_resource_types_in_group[@]}
    num_non_namespaced_resource_types=("${num_non_namespaced_resource_types[@]}" "${sz_non_namespaced}")
    num_namespaced_resource_types=("${num_namespaced_resource_types[@]}" "${sz_namespaced}")

    non_namespaced_resource_types+=("${non_namespaced_resource_types_in_group[@]}")
    namespaced_resource_types+=("${namespaced_resource_types_in_group[@]}")

    # echo "namespaced_resource_types = ${namespaced_resource_types[@]}"
done

# echo "num_namespaced_resource_types_per_api_group = ${num_namespaced_resource_types_per_api_group[@]}"
# echo "num_non_namespaced_resource_types_per_api_group = ${num_namespaced_resource_types_per_api_group[@]}"

# echo "namespaced_resource_types = ${namespaced_resource_types[@]}"
# echo
# echo "non_namespaced_resource_types = ${non_namespaced_resource_types[@]}"

printf "$ kubectl version\n"
kubectl version

printf "############################################################\n"
printf "######################GLOBAL RESOURCES######################\n"
printf "############################################################\n\n"

for idx in ${!non_namespaced_resource_types[@]}; do

    resource_type=
    api_group_idx=
    api_group=
    STARTER_PATH=
    api_versions=
    belongs_to_group_version_k=
    objects=

    resource_type=${non_namespaced_resource_types[$idx]}
    api_group_idx=$(api_group $idx ${num_non_namespaced_resource_types[@]})
    echo "api_group_idx=$api_group_idx"
    api_group=${api_groups[$api_group_idx]}
    
    if [ "$api_group" == "core" ]; then
        STARTER_PATH="$APISERVER/api"
        api_versions=("v1")
    else
        STARTER_PATH="$APISERVER/apis/$api_group"
        api_versions=($(curl -s $STARTER_PATH | jq '.versions[].version' | tr -d \' | tr -d \"))
    fi

    # order the api_versions array so that 'v1alpha1' comes before 'v1beta1' comes before 'v1'

    # echo "api_versions_before = ${api_versions[@]}"
    sift "${api_versions[@]}"

    api_versions=($(sift "${api_versions[@]}"))
    belongs_to_group_version_k=() # array the same size as the api_versions array, 

    # echo "api_versions_after = ${api_versions[@]}"

    for k in ${!api_versions[@]}; do 
        belongs_to_group_version_k+=("0")
    done

    for k in ${!api_versions[@]}; do 
        status=$(curl -s $STARTER_PATH/${api_versions[$k]}/$resource_type | jq '.status' | tr -d \" | tr -d \')
        if [ "$status" == "Failure" ]; then belongs_to_group_version_k[$k]=0;
        elif [ "$status" == "null" ]; then belongs_to_group_version_k[$k]=1;
        else echo "Unrecognized status received, exiting..."; exit 1; fi
    done

    # echo "belongs_to_group_version_k = ${belongs_to_group_version_k[@]}"
    # echo "api_group = ${api_group}"
    # echo "api_versions = ${api_versions[@]}"
    # echo "belongs_to_group_version_k = ${belongs_to_group_version_k[@]}"

    for k in ${!belongs_to_group_version_k[@]}; do
        if [ "${belongs_to_group_version_k[$k]}" == "1" ]; then
            printf "$resource_type (API group: $api_group)\n:"
            printf "Summary:\n"
            printf "$ kubectl get -A $resource_type\n"
            kubectl get -A ${resource_type}

            objects=($(curl -s $STARTER_PATH/${api_versions[$k]}/$resource_type | jq '.items[].metadata.name' | tr -d \' | tr -d \"))
            for name in ${objects[@]}; do
                printf "${name}:"
                printf "$ kubectl describe ${resource_type}/${name}\n"
                kubectl describe ${resource_type} ${name}
            done
        fi
    done    
done

printf "\n"
printf "############################################################\n"
printf "####################NAMESPACED RESOURCES####################\n"
printf "############################################################\n\n"


if [ -z "$(kill -0 $! 2>&1)" ]; then kill $!; wait $!; fi # kill -0 $CHILD_PID returned nothing so the child is still running

# For all global resources, run kubectl describe

# Get all crds

# Get all resources in the other api groups