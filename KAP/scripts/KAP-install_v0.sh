#! /bin/bash
echo "Starting at "`date +'%Y%m%d%H%M'`
adminuser=$1
adminpassword=$2
metastore=$3
apptype=$4
clusterName=$5
kyaccountToken=$6

BRANCH_NAME=kap237-mp
KAP_TARFILE=kap-2.3.7-GA-hbase1.x.tar.gz
KYANALYZER_TARFILE=KyAnalyzer-2.3.2.tar.gz
KYANALYZER_FOLDER_NAME=kyanalyzer-server-2.3.2
SAMPLE_CUBE_TARFILE=sample_cube.tar.gz
KAP_FOLDER_NAME="${KAP_TARFILE%.tar.gz*}"
KAP_INSTALL_BASE_FOLDER=/usr/local/kap
KAP_TMPFOLDER=/tmp/kap
KAP_SECURITY_TEMPLETE_URI=https://raw.githubusercontent.com/Kyligence/Iaas-Applications/$BRANCH_NAME/KAP/files/kylinSecurity.xml

BACKUP_DIR=/kycloud/backup

newInstall=true

KAP_SAMPLE_CUBE_URL=https://kyhub.blob.core.chinacloudapi.cn/packages/kap/$SAMPLE_CUBE_TARFILE

YARNUI_URL=''
host=`hostname -f`
if [[ "$host" == *chinacloudapp.cn ]]; then
    # download from cn
    echo "On Azure CN"
    KAP_DOWNLOAD_URI=https://kyhub.blob.core.chinacloudapi.cn/packages/kap/$KAP_TARFILE
    KYANALYZER_DOWNLOAD_URI=https://kyhub.blob.core.chinacloudapi.cn/packages/kyanalyzer/$KYANALYZER_TARFILE
    YARNUI_URL=https://${clusterName}.azurehdinsight.cn/yarnui/hn/cluster/app/%s
else
    echo "On Azure global"
    KAP_DOWNLOAD_URI=https://kyligencekeys.blob.core.windows.net/kap-binaries/$KAP_TARFILE
    KYANALYZER_DOWNLOAD_URI=https://kyligencekeys.blob.core.windows.net/kap-binaries/$KYANALYZER_TARFILE
    YARNUI_URL=https://${clusterName}.azurehdinsight.net/yarnui/hn/cluster/app/%s
fi

#import helper module.
wget -O /tmp/HDInsightUtilities-v01.sh -q https://hdiconfigactions.blob.core.windows.net/linuxconfigactionmodulev01/HDInsightUtilities-v01.sh && source /tmp/HDInsightUtilities-v01.sh && rm -f /tmp/HDInsightUtilities-v01.sh

downloadAndUnzipKAP() {
    echo "Removing KAP tmp folder"
    rm -rf $KAP_TMPFOLDER
    mkdir $KAP_TMPFOLDER
    
    echo "Downloading KAP tar file"
    wget $KAP_DOWNLOAD_URI -P $KAP_TMPFOLDER
    wget $KAP_SAMPLE_CUBE_URL -P $KAP_TMPFOLDER
    
    echo "Unzipping KAP"
    mkdir -p $KAP_INSTALL_BASE_FOLDER
    tar -zxvf $KAP_TMPFOLDER/$KAP_TARFILE -C $KAP_INSTALL_BASE_FOLDER

    echo "Updating sample cube"
    tar -zxvf $KAP_TMPFOLDER/$SAMPLE_CUBE_TARFILE -C $KAP_INSTALL_BASE_FOLDER/$KAP_FOLDER_NAME

    echo "Updating KAP admin account"
    if [ "$adminpassword" == "changeItNow" ] || [ "$adminpassword" == "" ]
    then
        adminpassword=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -n 1`
        echo "The initial password for administrator account '$adminuser' is '$adminpassword'. "
    fi

    cd $KAP_INSTALL_BASE_FOLDER/$KAP_FOLDER_NAME/tomcat/webapps/
    # Remove old before unzip
    rm -rf kylin
    unzip kylin.war -d kylin
    wget $KAP_SECURITY_TEMPLETE_URI -P kylin/WEB-INF/classes/
    sed -i "s/KAP-ADMIN/$adminuser/g" kylin/WEB-INF/classes/kylinSecurity.xml
    sed -i "s/KAP-PASSWD/$adminpassword/g" kylin/WEB-INF/classes/kylinSecurity.xml
    sed -i '/<\/head>/i\ <script>\n var _hmt = _hmt || []; \n (function() {\n  var hm = document.createElement("script");\n  hm.src = "https://hm.baidu.com/hm.js?03f3053bd1cc63313b9e532627250a18";\n var s = document.getElementsByTagName("script")[0];\n  s.parentNode.insertBefore(hm, s);\n })();\n </script>\n' kylin/index.html
    echo "Updating KAP metastore to $metastore"
    cd $KAP_INSTALL_BASE_FOLDER/$KAP_FOLDER_NAME/conf
    sed -i "s/kylin_default_instance/$metastore/g" kylin.properties

    #echo "Updating working dir"
    #sed -i "s/kylin.env.hdfs-working-dir=\/kylin/kylin.env.hdfs-working-dir=wasb:\/\/\/kylin/g" kylin.properties


    if [[ ! -z $kyaccountToken ]]
    then
        echo "Updating kap.kyaccount.token"
        echo "kap.kyaccount.token=$kyaccountToken" >> kylin.properties
    fi
    # update YRAN job tracking URL
    echo "kylin.job.tracking-url-pattern=$YARNUI_URL" >> kylin.properties
    echo "kylin.query.max-scan-bytes=20971520000" >> kylin.properties

    rm -rf $KAP_TMPFOLDER
}

startKAP() {
    echo "Adding kylin user"
    useradd -r kylin
    chown -R kylin:kylin $KAP_INSTALL_BASE_FOLDER
    export KYLIN_HOME=$KAP_INSTALL_BASE_FOLDER/$KAP_FOLDER_NAME

    echo "Create default working dir /kylin"
    su kylin -c "hdfs dfs -mkdir -p /kylin" 

    ## Add index page to auto redirect to KAP 
    mkdir -p $KYLIN_HOME/tomcat/webapps/ROOT
    cat > $KYLIN_HOME/tomcat/webapps/ROOT/index.html <<EOL
<html>
  <head>
    <meta http-equiv="refresh" content="1;url=kylin"> 
  </head>
</html>
EOL

    if [ "$newInstall" = true ] ; then
        echo "bypass" > $KYLIN_HOME/bin/check-env-bypass
        echo "Creating sample cube"
        su kylin -c "export SPARK_HOME=$KYLIN_HOME/spark && $KYLIN_HOME/bin/sample.sh"
    fi
    
    echo "Starting KAP with kylin user"
    su kylin -c "export SPARK_HOME=$KYLIN_HOME/spark && $KYLIN_HOME/bin/kylin.sh start"
    sleep 15

    if [ "$newInstall" = true ] ; then
        echo "Trigger a build for sample cube"
        nohup curl -X PUT --user $adminuser:$adminpassword -H "Content-Type: application/json;charset=utf-8" -d '{ "startTime": 1325376000000, "endTime": 1456790400000, "buildType": "BUILD"}' http://localhost:7070/kylin/api/cubes/kylin_sales_cube/rebuild &
        sleep 10
    fi
}

downloadAndUnzipKyAnalyzer() {
    rm -rf $KAP_TMPFOLDER
    mkdir $KAP_TMPFOLDER
    
    echo "Downloading KyAnalyzer tar file"
    wget $KYANALYZER_DOWNLOAD_URI -P $KAP_TMPFOLDER
    
    echo "Unzipping KyAnalyzer"
    mkdir -p $KAP_INSTALL_BASE_FOLDER
    tar -zxvf $KAP_TMPFOLDER/$KYANALYZER_TARFILE -C $KAP_INSTALL_BASE_FOLDER

    rm -rf $KAP_TMPFOLDER
}

startKyAnalyzer() {

    echo "Starting KyAnalyzer with kylin user"
    chown -R kylin $KAP_INSTALL_BASE_FOLDER/$KYANALYZER_FOLDER_NAME
    export KYANALYZER_HOME=$KAP_INSTALL_BASE_FOLDER/$KYANALYZER_FOLDER_NAME
    $KYANALYZER_HOME/start-analyzer.sh
    sleep 10

}

installKAP() {
    downloadAndUnzipKAP
    restoreKAP
    startKAP
}

installKyAnalyzer() {
    downloadAndUnzipKyAnalyzer
    restoreKyAnalyzer
    startKyAnalyzer
}

restoreKAP() {
    hdfs dfs -test -e $BACKUP_DIR/kap
    if [ $? -eq 0 ]; then
        newInstall=false
        echo "restore kap..."
        cd $KAP_INSTALL_BASE_FOLDER/$KAP_FOLDER_NAME
        rm -rf $KAP_INSTALL_BASE_FOLDER/$KAP_FOLDER_NAME/conf
        hdfs dfs -get $BACKUP_DIR/kap/conf $KAP_INSTALL_BASE_FOLDER/$KAP_FOLDER_NAME
    fi
}

restoreKyAnalyzer() {
    hdfs dfs -test -e $BACKUP_DIR/kyanalyzer
    if [ $? -eq 0 ]; then
        echo "restore kyanalyzer..."
        kyanalyzer_dir=$KAP_INSTALL_BASE_FOLDER/$KYANALYZER_FOLDER_NAME
        rm -rf $kyanalyzer_dir/data $kyanalyzer_dir/repository $kyanalyzer_dir/conf
        hdfs dfs -get $BACKUP_DIR/kyanalyzer/data $kyanalyzer_dir
        hdfs dfs -get $BACKUP_DIR/kyanalyzer/repository $kyanalyzer_dir
        hdfs dfs -get $BACKUP_DIR/kyanalyzer/conf $kyanalyzer_dir
    fi
}

main() {
    case "$apptype" in
        KAP+KyAnalyzer)
            installKAP
            installKyAnalyzer
            ;;
        KAP)
            installKAP
            ;;
        *)
            echo "Not Supported APP Type!"
            exit 1
            ;;
    esac
}

##############################
if [ "$(id -u)" != "0" ]; then
    echo "[ERROR] The script has to be run as root."
    exit 1
fi

export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64

if [ -e $KAP_INSTALL_BASE_FOLDER/$KAP_FOLDER_NAME ]; then
    echo "KAP is already installed. Exiting ..."
    exit 0
fi

###############################
main
echo "End at "`date +'%Y%m%d%H%M'`
