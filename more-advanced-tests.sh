#!/bin/bash

####################
# Global constants #
####################

# kubernetes
path_to_kubernetes_config="/home/pawel/.kube/student-k8s-cyf.yaml"
kubernetes_user_name="gmm-pmarszal"

# constant paths
sql_py_scripts="sql-and-python"
results_root="tests--artifacts-and-results/kubernetes"

# file names
test_config_path="test-config.txt"
merged_csv_name="merged.csv"
graph_name="graph.json"
queries_name="queries.json"
plot_name="plot.png"
report_name="report.txt"
avg_report_name="avg-report.txt"

####################
# Global variables #
####################

# paths (yet to be determined) to navigate over results
path_for_test=""
path_for_graph=""
path_for_load=""
path_for_repetition=""

path_to_merged_csv=""
path_to_plot=""
path_to_report=""
path_to_average_report=""

path_to_graph=""
path_to_queries=""

# pods
COUNT_ZONES=0
ZONES=()
EXECUTOR=""

# number of repetition
TEST_TIME=0
REPETITIONS=0

####################
# Graphs and loads #
####################

# interzone levels
inter_zone_levels=()

# nodes per zone
nodes_per_zone=()

# data points - X coordinates
loads=()

#############
# Functions #
#############

my_printf() {
  echo ""
  echo -n "[PMarshall Script] "
  echo "${1}"
  echo ""
}

parse_config() {
  counter=0
  while read -r line; do
    case ${counter} in
    0)
      COUNT_ZONES=${line}
      ;;
    1)
      inter_zone_levels+=("${line}")
      ;;
    2)
      nodes_per_zone+=("${line}")
      ;;
    3)
      loads+=("${line}")
      ;;
    4)
      TEST_TIME=${line}
      ;;
    5)
      REPETITIONS=${line}
      ;;
    esac
    ((counter++))
  done <"${test_config_path}"
}

# ZONES ON KUBERNETES

create_zones() {
  total_zones=$((COUNT_ZONES + 1))
  mvn compile exec:java -Dexec.mainClass="com.github.kjarosh.agh.pp.cli.KubernetesClient" \
                        -Dexec.args="-z ${total_zones} -c ${path_to_kubernetes_config} -n ${kubernetes_user_name}"
}

load_zones() {
  for ((i = 0; i < COUNT_ZONES; i++)); do
    ZONES+=("$(kubectl get pod -l "zone=zone${i}" -o name | sed 's/.*\///')")
  done

  EXECUTOR="$(kubectl get pod -l "zone=zone${COUNT_ZONES}" -o name | sed 's/.*\///')"
}

# NEW DIRECTORIES

mkdir_for_whole_test() {
  # create new directory
  timestamp=$(date +"D%Y-%m-%dT%T" | tr : -)
  path_for_test="${results_root}/test--${timestamp}"
  mkdir "${path_for_test}"

  # prepare paths
  path_to_merged_csv="${path_for_test}/${merged_csv_name}"
  path_to_plot="${path_for_test}/${plot_name}"

  # copy config
  cp "test-config.txt" "${path_for_test}/test-config.txt"

  # create merged_csv file
  touch "${path_to_merged_csv}"
  echo 'interzone,target,real' >"${path_to_merged_csv}"
}

mkdir_for_graph() {
  # remove file extension from name of the directory
  path_for_graph="${path_for_test}/graph--${1}-${2}"
  mkdir "${path_for_graph}"
}

mkdir_for_load() {
  path_for_load="${path_for_graph}/${1}"
  mkdir "${path_for_load}"

  path_to_average_report="${path_for_load}/${avg_report_name}"
  touch "${path_to_average_report}"
}

mkdir_for_repetition() {
  path_for_repetition="${path_for_load}/${1}"
  mkdir "${path_for_repetition}"

  path_to_report="${path_for_repetition}/${report_name}"
  touch "${path_to_report}"
}

# GENERATE GRAPHS AND QUERIES

generate_graph() {
  path_to_graph="${path_for_graph}/${graph_name}"

  # TODO implement me :(
  echo "Graph" > "${path_to_graph}"
}

generate_queries() {
  path_to_queries="${path_for_graph}/${queries_name}"
  total_operations=$((TEST_TIME * ${2} * 12 / 10))

  mvn compile exec:java -Dexec.mainClass="com.github.kjarosh.agh.pp.cli.OperationSequenceGeneratorMain" \
                        -Dexec.args="${path_to_graph}" "${total_operations}" "${path_to_queries}"
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

get_instrumentation() {
  kubectl cp "${ZONES[$1]}":instrumentation.csv "${path_for_repetition}/instrumentation-$1.csv"
}

get_all_instrumentations() {
  for ((i = 0; i < COUNT_ZONES; i++)); do
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

  for ((i = 0; i < COUNT_ZONES; i++)); do
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

postgres_report() {
  database ${sql_py_scripts}/get_report.sql > "${path_to_report}"
}

postgres_import() {
  mvn compile exec:java -Dexec.mainClass="com.github.kjarosh.agh.pp.cli.PostgresImportMain" \
                        -Dexec.args="${path_for_repetition}"
}

calculate_avg_report() {
  # TODO implement me :(
  echo "TODO"
}

# CONSTANT LOAD

load_graph() {
  clear_redises
  kubectl cp "${path_to_graph}" "${EXECUTOR}:${graph_name}"
}

constant_load() {
  # $1 - graph
  # $2 - queries
  # $3 - load
  kubectl exec -it "${EXECUTOR}" -- bash \
          -c "./run-main.sh com.github.kjarosh.agh.pp.cli.ConstantLoadClientMain -l -b 5 -g ${1} -s ${2} -n ${3} -d ${TEST_TIME} -t 3"
}

naive_query() {
  # $1 - graph
  # $2 - queries
  # $3 - load
  kubectl exec -it "${EXECUTOR}" -- bash \
          -c "./run-main.sh com.github.kjarosh.agh.pp.cli.QueryClientMain -l -b 5 -g ${1} -s ${2} -n ${3} -d ${TEST_TIME} -t 3"
}

######################
# Single-test runner #
######################

run_test() {
  # $1 - graph
  # $2 - queries
  # $3 - load
  # $4 - naive (true/false)

  # clear csv and postgres
  clear_instrumentations
  postgres_clear
  my_printf "Postgres: CLEARED"

  # perform test
  if [[ ${naive} = true ]] ; then
    naive_query "${1}" "${2}" "${3}"
  else
    constant_load "${1}" "${2}" "${3}"
  fi

  # load results to postgres
  get_all_instrumentations
  postgres_import
  my_printf "Postgres: IMPORTED"

  # perform report and write final results to '${merged_csv_name}'
  postgres_report
  my_printf "Postgres: REPORT OBTAINED"
}

####################
# SCRIPT EXECUTION #
####################

# read config file
parse_config

# create pods and obtain references to them
create_zones
load_zones

## initialize new directory for test's results, including merged_csv file
mkdir_for_whole_test

# for each interzone..
for interzone in ${inter_zone_levels[*]}; do

  # for each nodes-per-zone..
  for npz in ${nodes_per_zone[*]}; do
    mkdir_for_graph "${interzone}" "${npz}"

    naive=false
    if [[ ${interzone} = "naive" || ${npz} = "naive" ]] ; then
      naive=true
    fi

    # generate graph and queries to perform
    generate_graph "${interzone}" "${npz}"
    generate_queries "${path_to_graph}" "$(echo "${loads[*]}" | sort -nr | head -n1)"

    # load graph to kubernetes
    load_graph

    # for each load..
    for load in ${loads[*]}; do
      mkdir_for_load "${load}"

      # start new record in merged csv
      echo -n "${interzone},${npz},${load}," >> "${path_to_merged_csv}"

      # repeat test
      for ((i = 0; i < REPETITIONS; i++)); do
        mkdir_for_repetition "${i}"
        run_test "${path_to_graph}" "${path_to_queries}" "${load}" ${naive}
      done

      # TODO calculate average report
      #...

      # TODO get value from average report to merged csv
      #grep 'Operations per second' "${path_to_average_report}" | cut -d':' -f6 | tr -d ' ' | head -n 1 >> "${path_to_merged_csv}"

    done

    # create plot from merged.csv
    python3 "${sql_py_scripts}/plot.py" "${path_to_merged_csv}" "${path_to_plot}"

  done

done
