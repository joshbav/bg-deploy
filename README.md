# AUTOMATING ZERO DOWNTIME DEPLOYMENTS WITH MARATHON-LB
Revision 12-1-16

A utility for DC/OS'S marathon-lb north/south load balancer (mesosphere/marathon-lb & github.com/mesosphere/marathon-lb).

This is bash script (bg-deploy.sh) takes two arguments; a container name (repo/name:label) and an app name (testapp). 
ex: ./deploy-canary.sh nginx testapp

[Here is a video of its use](https://mesosphere-mc.webex.com/mesosphere-mc/ldr.php?RCID=a8bbc9120c09544543719d2416c28a2c) following the directions below.

It then creates 3 DC/OS Jobs that manage the deployment of that app. The app is the app template with the new container specified within it. This script does not affect a running system in any way, but it does create and destroy jobs which are specifically tied to the app name. 

REQUIREMENTS 

These requirements are temporary and will change.

1. The DC/OS enterprise cluster must have an account named bootstrapuser with a password of deleteme. This account needs superuser=full permissions.

2. Marathon-lb must already be installed, and modified to use the :latest container.

3. The service account named dcos_marathon_lb must have a permission added of dcos:superuser=full, this is best done by inserting the permission string (upper right corner of window).

4. For each app a template file must exist, and each template/app must have a unique HAPROXY_DEPLOYMENT_GROUP and HAPROXY_DEPLOYMENT_ALT_PORT. If you just copy testapp's included template, it will have the same labels, so be sure to modify them and the app name when you create a new template file for your own app.

WHAT IT DOES

A new app definition file is created (/tmp/new-app-definition.json) from a template file that is specific to the app (testapp.template.json) and the provided container name.
Three new DC/OS Job definitions are created from the new app definition, using a job template (bg-deploy-job.template.json):

/tmp/appname-revision-deploy-single-canary.json

/tmp/appname-revision-deploy-canary-completely.json

/tmp/appname-revision-rollback-single-canary.json

Any jobs with these names that already exist are stopped and removed. 
Then the three jobs are added.

The appname-revision-deploy-single-canary job is ready to be ran. It will create just one instance of the new container, and scale down by one the existing matching app of the blue green pair. 


The new and existing apps are matched by their app name, not by their revision. This allows for multiple versions of the same apps to be defined as Jobs. For example, if the app-v1-deploy-canary-completely job is ran when v2 is already deployed, it will rollback v2 to v1. Allowing multiple versions of an app's definitions to exist in Jobs which manage their deployment is powerful.   

The canary instance is then tested.

If successful, the rollout-appname-canary job would be ran. It will scale down the existing matching app one instance at a time, while the new canary version is scaled up one instance at a time.

However, if the new canary instance was not successful, the rollback-appname-canary job is utilized, which terminates the canary instance, removes the app definition from DC/OS Services (aka Marathon), and scales up the existing app by one instance, returning it to its original instance count.

During each of the above scaling events, marathon-lb's zero downtime script (zdd.py) is utilized to achieve connection draining. It is documented at: https://github.com/mesosphere/marathon-lb#zero-downtime-deployments

The DC/OS Enterprise Edition CLI is used by this script, you must be logged in already when running deploy-canary.sh

This is the first version of this script.  

# TRY IT OUT

Follow this lab example to try it yourself. If you have not watched the video above, do so now, since you will be repeating those steps here. 

1. Ensure the requirements above are met.

2. Clone this repo, login to your DC/OS Enterprise Edition cluster, and ensure you don't have an app already named testapp. 

3. Create a revision-specific application definition template. This is useful because of more than just the container changes, such as envioroment variables, CPU, etc, then that constitues a new "revision" of the app as far as this bg-deploy method is concerned. Let us assume that is the case here. So copy the generic template file named testapp.template.json to testapp.v1.template.json, creating our first version. 

3. Modify the testapp.v1.template.json file and change the HAPROXY_0_VHOST label to match the DNS entry for this app. This label is how marathon-lb knows what app is associated to what DNS FQDN, and from this marathon-lb automatically configures itself to make the app available via load balancing. Note this testapp template uses the NGINX web server container. 

4. In this example,  assume the new canary version will differ from the existing version only because a different container is used. bg-deploy will be used, and it will generate a new app definition which uses this new container. It will also generate three associated DC/OS jobs, whose names include the app version. These jobs will contain the new app definition and manage its deployment via blue green w/ canary w/ connection draining. In this example, the Apache container will represent the change from the previous version. We will refer to this as version 1.  Run this command: bash bg-deploy.sh httpd testapp v1

5. In the DC/OS GUI go to the Jobs screen and begin the testapp-v1-deploy-single-test-canary. Alternatively, you can use the DC/OS CLI to run the job via:  dcos job run testapp-v1-deploy-single-canary    Or you could use the API. bg-deploy uses a fully enabled python and DC/OS CLI container, based on Ubuntu 16.04, so the container must first download, then the job will begin. Wait for the Job to complete. Note no existing version of this app is will be detected by the Job, because the app is not already running. Thus the deploy single canary job will actually not deploy a single canary this time, this is expected. Instead a full deployment (4 instances) will occur. This is because bg-deploy is designed for existing deployments, this step instead performs the initial deployment so that we have something to upgrade. 

6. Go into the DC/OS GUI and go to the Services screen. Marathon-lb's zero downtime deployment appends -blue or -green to the app name. This app name will not contain bg-deploy's app version/revision in its name, unlike the Jobs that are created and are specific to a particular version of an app.  When the DC/OS Job completes, an app named testapp-blue will be visible in the Services screen. Note this documentation later addresses the use of DC/OS's east/west load balancer & services discovery with bg-deploy, because IP-based VIPs are necessary when an app's name changes, since the DNS-level VIP's are a function of the app name and you likely don't want them suddenly changing.  

7. Test that you can reach testapp using your browser, curl, etc. You should see the default apache web server screen of "It works!"    

8. Since this script is focused on rolling out new versions of apps, we need to first have a version already running. This only needs to be done once, because from then on all operations are rollouts/rollbacks of new versions. The previous step accomplished the need to get an initial app running. Now that we have an existing version of the app runninng, we will generate the next version that uses nginx instead of apache, and we will label this version 2. So rerun bg-deploy, but this time with nginx: bash bg-deploy.sh nginx testapp v2

9. In the DC/OS GUI go to the Jobs screen and begin the job deploy-testapp-canary. This will deploy one instance of the nginx version and name it testapp-green.

10. If you cycle thru the browser or curl, or generate a load test, you should see 1 of 4 responses with the "Welcome to NGINX" default page, and 3 of 4 responses with the "It works!" default apache page.  At this point you are in a hybrid deployment mode; both the old and new versions are running and traffic is split. This mode is temporary, one of the other two jobs must be ran to either complete or rollback this temporary step. 

11a. Let us assume the test canary was successful. You would now run the rollout-testapp-canary job. 

11b. However, if the test canary instance was not successful, you would remove it by running the rollback-testapp-canary job.

HOW IT WORKS

The new and existing apps are matched by their app name, the version is ignored. This allows for multiple versions of the same apps to be defined as Jobs, and for blue green deploys between them (but not while in a traffic split mode - just deployed a single test canary). You can not run the deploy single test canary job twice in a row. Since the version of a running app is ignored by the bg-deploy jobs created in DC/OS, if the app-v1-deploy-canary-completely job is ran when v2 is already deployed, it will rollback v2 to v1. Again, jobs ignore the version of the running app and only match to the app name. The version of a running app is a function of what job deployed it, since the job contains the app definition, thus new jobs are created when new app versions are created. 

Allowing multiple versions of an app's definitions to exist in Jobs (which manage their deployment) is powerful, since what defines an app is more than just the container; it is also ram, cpu, secrets, environment variables, etc, all of which are stored in an app definition. This is why an app definition template is required that is specific to the app version. However you can not run two different versions simultaneously and use these jobs, without ensuring you have changed the [TODO HAPROXY LABEL] to be unique per job, therefore unique per app version.  

What is hybrid mode, how you can get stuck in it. how single must be rolledout or rolled back. how you can rollout completely between versions but you must do the canary to do so, you must be fully deployed already, then rollout another revision's single canary, which puts you in hybrid mode, and then completely rollout that same revision's canary.

The details of the logic is documented in the bg-deploy.sh script. 

USE WITHIN JENKINS

TODO: video and example of use in jenkins

USE WITH CUSTOM DEVELOPMENT TEST CANARIES

Sometimes the single test canary is not intended to be rolled out completely, such as the case of a canary running with debug code enabled, special monitoring, extra development tools within the container, etc. In this case, simply use the deploy single instance canary job, test, then use the rollback canary job. Then create the next container, and app definition template file such as testapp.v2.template.json. Then re-run bg-deploy with the new container and version parameters, which will cause it to use the matching new app template file to create three new DC/OS Jobs. Then deploy a single test canary of that new job, test it, then use the job to complete the rollout.  

USE WITH MINUTEMAN

Since the app name changes because of the -blue and -green names, IP level vips are needed for DC/OS's east/west loadbalancing & services discovery, instead of DNS VIPs. Otherwise the DNS FQDN would change with each deployment. TODO: FILL IN

USE WITH ROLE BASED ACCESS CONTROLS

With Enterprise DC/OS, the user account the script runs under can be restricted to certain folders within the Services screen (aka Marathon), thus isolating the Jobs from each other. By design, the Jobs login with the account credentials provided to bg-deploy.sh when the Jobs were created by it. The account credentials are embedded into the job, along with the new app definition. The Jobs do not login as root. Therefore different teams can use different accounts, with ACL's to different folders, and create different Jobs that are unable to access other folders in the Services/Marathon screen. 

USE OF CONTAINER OUTSIDE OF THE CLUSTER

One of the parameters required by bg-deploy.sh is the cluster's URL. In most cases, you will want to provide master.mesos, because you are creating Jobs that run containers within the cluster, which therefore access the cluster by the internal cluster DNS.

If, however, you have a DNS forward zone for .mesos (and .thisdcos.directory) in your existing DNS system (which resides outside the DC/OS cluster) then the cluster DNS FQDN of master.mesos will still work when running this script / container from outside of the cluster. See [TODO: ADD URL TO DNS DOC]. Otherwise, you need to use a URL that will work outside of your cluster, such as the DNS A record you created for the masters (example: three A records with same name, for three masters).

The joshbav/bg-deploy container is intended to be a full DC/OS CLI and python environment, ideal for managing DC/OS, and the author of bg-deploy uses it as such.   

TO DO LIST

make jenkins, container work within or out of cluster address master.mesos assumption, no fetch of script from within container, make a login script for container to run, pass it the credentials, not superuser, document restricted RBAC and video, detect OS DCOS and skip security, make login account/pw into parameters, add revision as argument, move sterr to stdout, jq instead of sed
