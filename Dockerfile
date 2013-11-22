FROM ubuntu
 
RUN echo 'deb http://archive.ubuntu.com/ubuntu precise main universe' > /etc/apt/sources.list.d/sources.list && \
    echo 'deb http://archive.ubuntu.com/ubuntu precise-updates universe' >> /etc/apt/sources.list.d/sources.list && \
    apt-get update

#Prevent daemon start during install
RUN	echo '#!/bin/sh\nexit 101' > /usr/sbin/policy-rc.d && \
    chmod +x /usr/sbin/policy-rc.d

#Supervisord
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y supervisor && \
	mkdir -p /var/log/supervisor
CMD ["/usr/bin/supervisord", "-n"]

#SSHD
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server && \
	mkdir /var/run/sshd && \
	echo 'root:root' |chpasswd

#Utilities
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y vim less ntp net-tools inetutils-ping curl git telnet bzip2 nmap

#Requirements
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y \
    apache2  libapache2-mod-wsgi python-setuptools memcached build-essential \
    python-dev python-cairo-dev python-django python-ldap python-memcache python-pysqlite2 sqlite3
RUN easy_install django-tagging && \
    easy_install zope.interface && \
    easy_install twisted && \
    easy_install txamqp


#Graphite
RUN wget https://launchpad.net/graphite/0.9/0.9.10/+download/graphite-web-0.9.10.tar.gz && \
    tar -zxvf graphite-web-0.9.10.tar.gz && \
    rm graphite-web-0.9.10.tar.gz && \
    mv graphite-web-0.9.10 /opt/graphite && \
    wget https://launchpad.net/graphite/0.9/0.9.10/+download/carbon-0.9.10.tar.gz && \
    tar -zxvf carbon-0.9.10.tar.gz && \
    mv carbon-0.9.10 carbon && \
    rm carbon-0.9.10.tar.gz && \
    wget https://launchpad.net/graphite/0.9/0.9.10/+download/whisper-0.9.10.tar.gz && \
    tar -zxvf whisper-0.9.10.tar.gz && \
    rm whisper-0.9.10.tar.gz && \
    mv whisper-0.9.10 whisper

#Whisper
RUN cd /whisper && \
    python setup.py install

#Carbon
RUN cd /carbon && \
    python setup.py install

#Graphite
RUN cd /opt/graphite && \
    python check-dependencies.py && \
    python setup.py install && \
    cd /opt/graphite/conf && \
    cp carbon.conf.example carbon.conf && \
    cp storage-schemas.conf.example storage-schemas.conf && \
    cd /opt/graphite/examples && \
    cp example-graphite-vhost.conf /etc/apache2/sites-available/default && \
    sed -i -e "s|WSGISocketPrefix.*run/wsgi||" /etc/apache2/sites-available/default && \
    cp /opt/graphite/conf/graphite.wsgi.example /opt/graphite/conf/graphite.wsgi && \
    cd /opt/graphite/webapp/graphite && \
    cp local_settings.py.example local_settings.py && \
    mkdir /var/run/apache2 && \
    chown -R www-data:www-data /var/run/apache2/

#Graph Explorer
RUN git clone --recursive https://github.com/vimeo/graph-explorer.git

#ElasticSearch
RUN wget https://download.elasticsearch.org/elasticsearch/elasticsearch/elasticsearch-0.90.7.tar.gz && \
    tar xf elasticsearch-*.tar.gz && \
    rm elasticsearch-*.tar.gz && \
    mv elasticsearch-* elasticsearch

#Install Oracle Java 7
RUN echo 'deb http://ppa.launchpad.net/webupd8team/java/ubuntu precise main' > /etc/apt/sources.list.d/java.list && \
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys EEA14886 && \
    apt-get update && \
    echo oracle-java7-installer shared/accepted-oracle-license-v1-1 select true | /usr/bin/debconf-set-selections && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y oracle-java7-installer


#Initialize MySQL
RUN cd /opt/graphite/webapp/graphite/ && \
    python manage.py syncdb --noinput && \
    chown -R www-data:www-data /opt/graphite/storage/

#Configure Apache for CORS
RUN a2enmod headers && \
    sed -i -e 's|</VirtualHost>|Header set Access-Control-Allow-Origin "*"\nHeader set Access-Control-Allow-Methods "GET, OPTIONS, POST"\nHeader set Access-Control-Allow-Headers "origin, authorization, accept"\n</VirtualHost>|' \
        /etc/apache2/sites-enabled/000-default && \
    sed -i -e 's|http://graphite.machine.dns|http://:49185|' \
        /graph-explorer/config.py

RUN apt-get install -y cron && \
    echo "* * * * * /graph-explorer/update_metrics.py &>/dev/null" > /var/spool/cron/crontabs/root


ADD ./ docker-graphite
RUN cd /docker-graphite && \
    cp supervisord.conf /etc/supervisor/conf.d/supervisord.conf

EXPOSE 22 80 2003

