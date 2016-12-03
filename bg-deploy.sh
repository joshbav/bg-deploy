#!/bin/bash
# arguments

echo
echo "This script will launch a canary blue green deployment that will create a single instance of the new version."
echo "After that new canary instance has been tested, it will be necessary to either rollout the new version completey,"
echo "and therefore terminate the existing version's instances, OR to rollback by terminating the canary version." 
echo "To complete the rollout, run ROLLOUT-NAME, or to rollback run ROLLBACK-NAME"
echo
echo "You must be logged into your cluster with the DC/OS cli."
echo

# to do add description of inputs if there's not 3 provided

######
###### TODO: Add parameter validation, are they present? handle -h and -help and --help. 
###### show parameters and point to readme.md
######

echo
echo Blue Green Marathon-lb deploy with canary and connection draining. 
echo Revision 1-1-16. See https://github.com/joshbav/bg-deploy
echo

# Check if the DC/OS CLI is in the PATH
CMD_FILE=$(which dcos)
 
if [ "$CMD_FILE" == "" ] 
then
    echo
    echo " The DC/OS Command Line Interface binary is not installed or not in your path. Please install it."
    echo " Existing."
    echo
    exit 1
fi
 
 
# Check if the JQ program is in the PATH
 
CMD_FILE=$(which jq)
 
if [ "$CMD_FILE" == "" ] 
then
    echo
    echo " The JSON Query (jq) binary is not installed or not in your path. Please install it."
    echo " Existing."
    echo
    exit 1
fi
 
# Check if the DC/OS CLI is 0.4.12
 
CLI_VER=$(dcos --version | grep dcoscli.version | cut -d '=' -f 2)
 
if [ "$CLI_VER" != "0.4.13" ] && [ "$CLI_VER" != "0.4.14" ]
then
    echo
    echo " Your DC/OS CLI version is too old. Please upgrade the DC/OS CLI" 
    echo " Exiting. "
    exit 1
fi
 
# Check if user is logged into the CLI
 
while true 
do
    AUTH_TOKEN=$(dcos config show core.dcos_acs_token 2>&1)
 
    if [[ "$AUTH_TOKEN" = *"doesn't exist"* ]] 
    then
        echo
        echo " Not logged into the DC/OS CLI. Running login command now. Or press CTL-C "
        echo
        dcos auth login
    else
        break
    fi
done
 
# Check if the dcos acs token is valid
 
while true 
do
    RESULT=$(dcos node 2>&1)
 
    if [[ "$RESULT" = *"Your core.dcos_acs_token is invalid"* ]] 
    then
        echo
        echo " Your DC/OS dcos_acs_token is invalid. Running login command now. Or press CTRL-C "
        echo
        dcos auth login
    else
        break
    fi
done


CONTAINER=$1
echo "New container to use:" "$CONTAINER"
echo

APP_NAME="$2"
echo "Name of DC/OS Marathon application to be upgraded with this new container:" $APP_NAME
echo

#####
##### TODO: verify that dcos cli connected to cluster, login with credentials to the url
##### 

APP_REVISION=$3
echo "App revision:"$APP_REVISION

CLUSTER_URL=$4
echo "DC/OS cluster URL:"$CLUSTER_URL
echo

DCOS_USER_NAME=$5
echo "DC/OS user account to be used by DC/OS Jobs that will be created, and to login to the cluster now"
echo "And add/modify Jobs:"$DCOS_USER_NAME
echo

DCOS_USER_PASSWORD=$6


# todo: check that app template file exists
# todo: check that job template file exists

# todo check all arguments, if none then display help

# This is a generic job template file that can be used for all apps, and probably shouldn't be modified
# There probalby is not a valid reason to have a job template that is specific to an app or an app revision

JOB_TEMPLATE_FILE=bg-deploy-job.template.json

echo DC/OS Job template file to be used: $JOB_TEMPLATE_FILE 
echo "From this generic Job template a new DC/OS Job definition containing the new app with the new container"
echo "will be created as a temp file at /tmp/$APP_NAME-$APP_REVISION-deploy-single-canary.json"
echo "From this resulting Job, two other Jobs will be created." 
echo

# TODO: If a revision specific template does not already exist, abort. 

APP_TEMPLATE_FILE="$APP_NAME"."$APP_REVISION".template.json
echo "Applicaiton template file to be used:" $APP_TEMPLATE_FILE 
echo "From this app template, and the new container, a new app definition will be created as a temp file at /tmp/new-app-definition.json" 
echo

# STEP 1 ##### Put the container in the app template, thus filling it in. 
# Note this template is specific to the revision of the app, which is a parameter passed to the bg-deploy script. 
# This is bg-deploy's concept of a version, it's a string. If your concept of a version is a container label (nginx:v1), 
# then it is best to use the same version string for bg-deploy. For example: bash bg-deploy.sh myapp:v1 v1
# bg-deploy could have been designed to require a container label, and to use it as the version, but that would
# likely be constraining. 

#### TODO: check for HAPROXY_DEPLOYMENT_GROUP & HAPROXY_DEPLOYMENT_ALT_PORT labels, they are mandatory in any app 
# template .json file that deploy-canary.sh takes as an input. Both labels must be unique among all app templates. 
####

# Stream the app template file thru sed, which will swap out a unique key with the new container
# and save it as /tmp/$APP_NAME-$APP_REVISION-new-app-definition.json in compact json format via jq
echo "Creating new DC/OS Marathon application definition as temp file /tmp/$APP_NAME-$APP_REVISION-new-app-definition.json"
echo 

cat $APP_TEMPLATE_FILE | sed 's|ThisIsAUniqueKey|'$CONTAINER'|g' | jq -c . > /tmp/$APP_NAME-$APP_REVISION-new-app-definition.json

# From the new app definition create a variable that is the new app definition in base64, which is easy to pass around
# since it doesnt need to be escaped. This is a form of encapsulation, since this definition is going to be passed on 
# the command line inside the job, and since bg-deploy programmatically builds jobs, this is all deterministic. 
# The jobs are specific to apps, and thus named with the app's version, because the jobs contain the app definition.
# The jobs use the app definion to run the joshbav/bg-deploy container, which controls marathon-lb and performs 
# blue green with connection draining. How the jobs (of the same app revision) differ from each other is how they
# manage the rollout. One is a single new instance, aka the test canary, another rolls it back, and another rolls 
# out the canary completely. All three of an app jobs contain the same app definition. 

NEW_APP_DEFINITION_AS_BASE64_JSON=$(cat /tmp/$APP_NAME-$APP_REVISION-new-app-definition.json | jq -c -r @base64)

# STEP 2 ##### Put the filled in app template into the job template
# stream the job template file thru sed, which will swap out a unique key with the new app template file that was just created, 
# saving it as /tmp/$APP_NAME-$APP_REVISION-new-app-definition.json 
# Soon the rollout and rollback jobs will be created from it, by modifying the job created using this app definition

echo "Creating DC/OS Job definition as temp file /tmp/$APP_NAME-$APP_REVISION-deploy-single-canary.json"

cat $JOB_TEMPLATE_FILE | sed 's|ThisIsAUniqueKey|'$NEW_APP_DEFINITION_AS_BASE64_JSON'|g; s|ThisIsAnotherUniqueString|'$APP_NAME'-'$APP_REVISION'-deploy-single-canary|g' > /tmp/"$APP_NAME"-"$APP_REVISION"-deploy-single-canary.json 

echo "Creating DC/OS Job definition as temp file /tmp/$APP_NAME-$APP_REVISION-deploy-canary-completely.json"
# This is done by changing a single argument given to the zero downtime script, from rollout 1 new canary instance 
# to complete the previous rollout of the single canary instance. And changing the job's name.

cat /tmp/"$APP_NAME"-"$APP_REVISION"-deploy-single-canary.json | sed 's|--new-instances 1|--complete-cur|g; s|-deploy-single-canary|-deploy-canary-completely|g' > /tmp/"$APP_NAME"-"$APP_REVISION"-deploy-canary-completely.json


# -deploy-single-canary    ->   -deploy-canary-completely


echo "Creating DC/OS Job definition as temp file /tmp/$APP_NAME-$APP_REVISION-rollback-single-canary.json" 
echo
# This is done by changing a single argument given to the zero downtime script, from rollout 1 new canary instance 
# to abort and rollback the previous deployment of the single canary instance. And changing the job's name.

cat /tmp/"$APP_NAME"-"$APP_REVISION"-deploy-single-canary.json | sed 's|--new-instances 1|--complete-prev|g; s|-deploy-single-canary|-rollback-single-canary|g' > /tmp/"$APP_NAME"-"$APP_REVISION"-rollback-single-canary.json




#-deploy-single-canary  -> -rollback-single-canary




echo "Using the DC/OS CLI, removing any existing DC/OS Jobs for app $APP_NAME."
echo "bg-deploy will overwrite an app's jobs that are the same version (as the version parameter given to bg-deploy.sh)"
echo "However, it will not overwrite an app's jobs for different versions."
echo

dcos job kill $APP_NAME-$APP_REVISION-deploy-single-canary
dcos job remove $APP_NAME-$APP_REVISION-deploy-single-canary
dcos job kill $APP_NAME-$APP_REVISION-deploy-canary-completely
dcos job remove $APP_NAME-$APP_REVISION-deploy-canary-completely
dcos job kill $APP_NAME-$APP_REVISION-rollback-single-canary
dcos job remove $APP_NAME-$APP_REVISION-rollback-single-canary
echo

# LOAD THE 3 NEW JOBS INTO DC/OS

dcos job add /tmp/$APP_NAME-$APP_REVISION-deploy-single-canary.json

echo "DC/OS Job $APP_NAME-$APP_REVISION-deploy-single-canary added, it has not been started." 
echo "This job will enable a single instance of the new canary build."
echo

dcos job add /tmp/$APP_NAME-$APP_REVISION-deploy-canary-completely.json

echo "DC/OS Job $APP_NAME-$APP_REVISION-deploy-canary-completely added, it has not been started." 
echo "If the single canary instance is to be rolled out completely, replacing the existing" 
echo "deployed and running app, use this job."
echo

dcos job add /tmp/$APP_NAME-$APP_REVISION-rollback-single-canary.json

echo "DC/OS Job $APP_NAME-$APP_REVISION-rollback-single-canary added, it has not been started."
echo "If the single canary instance is to be removed, use this job to rollback."
echo
echo "To see DC/OS Jobs via the CLI, use: dcos job list"
echo
echo "To run one of the jobs from the CLI, such as $APP_NAME-$APP_REVISION-deploy-single-canary," 
echo "via the CLI use: dcos job run $APP_NAME-$APP_REVISION-deploy-single-canary"
echo "or via the GUI: Just go to the Jobs screen and start the job" 
echo "or via the API: see  https://dcos.github.io/metronome/docs/generated/api.html"
echo
echo
