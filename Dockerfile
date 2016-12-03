FROM ubuntu:16.04
ENV BG-DEPLOY-REVISION=December-2-16

######### 
# Install the environment
# curl, expect, and jq  are mandatory for this container
RUN apt-get update && apt-get install -y --no-install-recommends \
curl \
expect \
"tcl8.6" \
jq \
ca-certificates \
libssl-dev \
gcc \
python3 \
python3-dev \
python3-pip \
python3-setuptools \
make \
vim \
nano \
txt2regex \
git \
dnsutils \
traceroute \
net-tools \
iputils-ping \
tcpdump \
&& pip3 install --upgrade pip 
# && rm -rf /var/lib/apt/lists/* \
# && apt-get purge -y --auto-remove
# nmap, netcat, atop, 

# Fetch txt2regex, a handy script for converting human text to regex. It is not used in this container, but since it takes so little space I keep it around in all my containers
#ADD https://raw.githubusercontent.com/aureliojargas/txt2regex/master/txt2regex.sh /usr/local/sbin/txt2regex.sh
#ADD https://raw.githubusercontent.com/aureliojargas/txt2regex/master/README.md /txt2regex-readme.md

# Needed by some python apps, such as a few DC/OS CLI modules
ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8
ENV LANGUAGE=en_US.UTF-8
ENV TERM=xterm

WORKDIR /

###########
# Install the DC/OS CLI for linux. Note, this is a specific version, new as of 1-1-16, but you should ensure
# it is up to date if you are building your own image from this Dockerfile
# for some reason the ADD command doesn't seem to work, maybe a docker bug? 
# TODO combine this into 1 big line at apt-get
# for some reason curl -o won't work, I suspect a docker bug since I'm using the mac version that is still beta
RUN cd /usr/local/bin && curl -fLk -O https://downloads.dcos.io/binaries/cli/linux/x86-64/dcos-1.8/dcos && chmod u+x /usr/local/bin/dcos && cd / 

###########
# Fetch Brenden M's Zero Downtime Deployment script from his marathon-lb, since this container is essentially just a wrapper around Brenden's script
ADD https://raw.githubusercontent.com/mesosphere/marathon-lb/master/zdd.py /
# This is optional, it provides the ability to add custome exception handling for the Zero Downtime Deployment script
ADD https://raw.githubusercontent.com/mesosphere/marathon-lb/master/zdd_exceptions.py /

# Fetch and install his python requirements for zdd.py
ADD https://raw.githubusercontent.com/mesosphere/marathon-lb/master/requirements.txt /tmp/zdd-requirements.txt
# TODO: move this to initial apt get line
# This will install a lot, such as python's cryptography library
# virtualenv is needed for the DC/OS CLI
RUN echo "alias python='python3'" >> /root/.bashrc && pip3 install --no-cache --upgrade --force-reinstall -r /tmp/zdd-requirements.txt virtualenv

# Fetch Brenden's readme.md, call it zdd-readme.md, even though it's really the documentation for marathon-lb 
# and only the ZDD section of it is relevant here. If you docker exec into the container, and you shouldn't need to, there's the docs
# Note the app definition label of HAPROXY_DEPLOYMENT_GROUP and HAPROXY_DEPLOYMENT_ALT_PORT 
# are mandatory in any app the zdd.py script deploys. Therefore they are mandatory in any app template .json file 
# that deploy-canary.sh takes as an input. The .._GROUP label must be unique for each app, and will therefore be 
# the same for each version of the app. The .._PORT must be unique for every app. Note  
ADD https://raw.githubusercontent.com/mesosphere/marathon-lb/master/README.md /zdd-readme.md
ADD https://raw.githubusercontent.com/mesosphere/marathon-lb/master/Longhelp.md /zdd-longhelp.md

############
# Fetch a script from the DC/OS SDK that automates the login for the DC/OS CLI, which this container uses
ADD https://raw.githubusercontent.com/mesosphere/dcos-commons/master/tools/dcos_login.py /dcos_login.py 

############
# add deploy-canary files, even though they aren't actually executed in this container when this container is used in a DC/OS Job created 
# by deploy-canary.sh. However, this container can be ran outside of the DC/OS cluster too, in which case perhaps the deploy-canary script
# would be ran in this container. Therefore all project files are in this container.  
ADD *.json *.sh /

###########
# Run our commands
# Some DC/OS CLI modules require the language variables because of python
RUN chmod u+x /*.sh 
