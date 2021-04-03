#!/bin/bash

####################
# Global variables #
####################

# constant paths
sql_py_scripts="sql-and-python"
results_root="tests--artifacts-and-results/kubernetes"
graphs_dir="graphs"

# paths (yet to be determined) to navigate over results
path_for_test=""
path_for_graph=""
path_for_load=""
path_to_merged_csv=""

# pods
ZONES=()
EXECUTOR=""

# number of zones
COUNT_ZONES=10

####################
# Graphs and loads #
####################

# data points - X coordinates
loads=(100 200)
#loads=(100 200 300 400 500 600 700 800 900 1000 \
#        1100 1200 1300 1400 1500 1600 1700 1800 1900 2000 \
#        2100 2200 2300 2400 2500)

# graphs to perform tests on
graphs=("zadanie3.60.json")
#graphs=("zadanie3.0.json" "zadanie3.30.json")
#graphs=("zadanie3.0.json" "zadanie3.30.json" "zadanie3.60.json")

#############
# Functions #
#############

my_printf() {
    echo ""
    echo -n "[PMarshall Script] "
    echo "${1}"
    echo ""
}

load_zones() {
    for ((i=0; i<COUNT_ZONES; i++)); do
      ZONES+=("$(kubectl get pod -l "zone=zone${i}" -o name | sed 's/.*\///')")
    done

    EXECUTOR="$(kubectl get pod -l "zone=zone${COUNT_ZONES}" -o name | sed 's/.*\///')"
}

# NEW DIRECTORY

mkdir_for_whole_test() {
    # create new directory
    timestamp=$(date +"D%Y-%m-%dT%T" | tr : -)
    path_for_test="${results_root}/test-${timestamp}"
    mkdir "${path_for_test}"

    # create file to merged csv file
    path_to_merged_csv="${path_for_test}/wyniki.csv"
    touch "${path_to_merged_csv}"
    echo 'interzone,target,real' > "${path_to_merged_csv}"
}

mkdir_for_graph() {
    # remove file extension from name of the directory
    path_for_graph=$(echo "${path_for_test}/${1}" | sed 's/\.[^.]*$//')
    mkdir "${path_for_graph}"
}

mkdir_for_load() {
    path_for_load=${path_for_graph}/${1}
    mkdir "${path_for_load}"
}

# INSTRUMENTATION

clear_instrumentation() {
    kubectl exec -it "$1" -- touch temp.csv
    kubectl exec -it "$1" -- cp temp.csv instrumentation.csv
    kubectl exec -it "$1" -- rm temp.csv
}

clear_instrumentations() {
    for zone in ${ZONES[*]}; do
      clear_instrumentation "${zone}"
    done
}

get_instrumentation () {
    kubectl cp "${ZONES[$1]}":instrumentation.csv "${path_for_load}/instrumentation-$1.csv"
}

get_all_instrumentations() {
    for ((i=0; i<COUNT_ZONES; i++)); do
      get_instrumentation "${i}"
    done

    my_printf "Artifacts downloaded"
}

# REDIS

clear_redis() {
    kubectl exec -it "$1" -- redis-cli FLUSHALL
}

clear_redises() {
    my_printf "Clearing redis"

    for ((i=0; i<COUNT_ZONES; i++)); do
      clear_redis "${ZONES[i]}"
    done
}

# POSTGRES

database() {
    psql "dbname='postgres' user='postgres' password='admin' host='localhost' port='5432'" -f "$1"
}

postgres_clear() {
    database ${sql_py_scripts}/truncate.sql
}

postgres_report () {
    database ${sql_py_scripts}/get_report.sql 2>&1 | grep 'Operations per second' | cut -d':' -f6 | tr -d ' ' | head -n 1 >> "${path_to_merged_csv}"
}

postgres_import() {
    mvn compile exec:java -Dexec.mainClass="com.github.kjarosh.agh.pp.cli.PostgresImportMain" -Dexec.args="${path_for_load}"
}

# CONSTANT LOAD

load_graph () {
    clear_redises
    kubectl cp "${graphs_dir}/$1" "${EXECUTOR}:$1"

    kubectl exec -it "${EXECUTOR}" -- bash -c "./run-main.sh com.github.kjarosh.agh.pp.cli.ConstantLoadClientMain -l -b 5 -n 0 -g $1 -t 3 -d 1"
}

constant_load () {
    # $1 - graph
    # $2 - load
    kubectl exec -it "${EXECUTOR}" -- bash -c "./run-main.sh com.github.kjarosh.agh.pp.cli.ConstantLoadClientMain -l -b 5 -n $2 -g $1 -t 3 -d 60"
}

######################
# Single-test runner #
######################

run_test() {
    # $1 - graph
    # $2 - load

    # clear csv and postgres
    clear_instrumentations
    postgres_clear
    my_printf "Postgres: CLEARED"

    # perform tests and load results to postgres
    constant_load "$1" "$2"
    get_all_instrumentations
    postgres_import
    my_printf "Postgres: IMPORTED"

    # perform report and write final results to 'wyniki.csv'
    param1=$(echo "$1" | cut -d'.' -f2 | tr -d '\n')
    echo -n "${param1},$2," >> "${path_to_merged_csv}"
    postgres_report
    my_printf "Postgres: REPORT OBTAINED"
}

###################
# SCRIPT EXECUTION #
###################

# obtain references to pods
load_zones

# initialize new directory for test's results, including wyniki.csv file
mkdir_for_whole_test

# for each graph ...
for g in ${graphs[*]}; do

    my_printf "GRAPH = $g"
    mkdir_for_graph "${g}"
    load_graph "$g"

    # for each data point ...
    for load in ${loads[*]}; do

        my_printf "OPERATIONS PER SECOND = $load"
        mkdir_for_load "${load}"
        run_test "${g}" "${load}"

    done
done

# create plot
python3 "${sql_py_scripts}/plot.py" "${path_to_merged_csv}" "${path_for_test}/result-plot.png"
