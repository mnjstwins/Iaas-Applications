#! /bin/bash

# Providing variables for kylin to restart
export KAP_INSTALL_BASE_FOLDER=/usr/local/kap
cd $KAP_INSTALL_BASE_FOLDER
export KAP_FOLDER_NAME="`ls -d kap-*-GA-hbase*`"
cd -
# export KAP_FOLDER_NAME='kap-2.3.5-GA-hbase1'
export KYLIN_HOME="$KAP_INSTALL_BASE_FOLDER/$KAP_FOLDER_NAME"

export ZOOKEEPERADDRESS=`awk '/hbase.zookeeper.quorum/{getline; print}' /etc/hbase/*/0/hbase-site.xml | grep -oP '<value>\K.*(?=</value>)'`
export KYLINPROPERTIESFILE="`ls /usr/local/kap/kap-*-GA-hbase*/conf/kylin.properties`"

# Setting kylin.server.mode=query
sed -i 's/kylin.server.mode=.*/kylin.server.mode=query/' $KYLINPROPERTIESFILE
# Setting kylin.job.scheduler.default=1
sed -i 's/kylin.job.scheduler.default=.*/kylin.job.scheduler.default=1/' $KYLINPROPERTIESFILE
# Setting kap.job.helix.zookeeper-address
sed -i "s/kap.job.helix.zookeeper-address=.*/kap.job.helix.zookeeper-address=$ZOOKEEPERADDRESS/" $KYLINPROPERTIESFILE


#  Copying hbase-site.xml to hdfs
hadoop fs -put /etc/hbase/*/0/hbase-site.xml /kylin/hbase-site.xml

# Restart of KAP
# su kylin -c "export KYLIN_HOME=\"`ls -d /usr/local/kap/kap-*-GA-hbase*`\";export SPARK_HOME=$KYLIN_HOME/spark && $KYLIN_HOME/bin/kylin.sh stop && $KYLIN_HOME/bin/kylin.sh start"
# su kylin -c "export SPARK_HOME=$KYLIN_HOME/spark && $KYLIN_HOME/bin/kylin.sh start"
# sleep 15
wget https://raw.githubusercontent.com/Kyligence/Iaas-Applications/master/KAP/files/kap.service -O /etc/systemd/system/kap.service
systemctl daemon-reload
systemctl enable kap
systemctl restart kap
