	#!/bin/bash
	# Todo ------------------------------------------------------------
	# Please install awscli, gawk, mysql-client to work this script well.
	# Mysql Table Structure : 
	# Column Name in order - 
	# Server Name | LogTime | Request | RequestType/ErrorCode(5xx,4xx) | HighestRequestTime | NoOfDistinctRequest | SumOfRequestTime | AvgRequestTime  
	# Please update the following credentials.
	# Here s3 bucket path format is "s3://bucket-name-log/AWSLogs/filepath/xxxxx/2015/01/01/". change it, if yours is not like this.
	# todo ends here. Good Luck!.---------------------------------------

	# export S3_ACCESS_KEY_ID="S3_ACCESS_KEY_ID"
	# export S3_SECRET_ACCESS_KEY="S3_SECRET_ACCESS_KEY"

	MYSQL_HOST="hostname.mysql.hos"
	MYSQL_USER_NAME="rootuser"
	MYSQL_PASSWORD="user.password"
	MYSQL_DATABASE="db.elb_info"
	MYSQL_TABLE="elb_tablename"
	S3_BUCKET_NAME="s3://bucket-name-log/AWSLogs/filepath/xxxxx/" 

	echo "INFO:: Initializing temporary variables."
	DATE=`date +%Y/%m/%d`
	SERVERNAME="ELB_TEST"
	RESULT_FILE="ELBTest.csv"
	TEMP_FILE="ELBTest_tempfile"

	s3_bucket=$S3_BUCKET_NAME"/"$DATE"/"
	DIRECTORY="tmp"

	echo "INFO:: Initializing directory structure."
	if [ ! -d "$DIRECTORY" ]; 
		then
		echo "INFO:: Creating directory : " $(pwd)"/"$DIRECTORY
		mkdir $(pwd)"/"$DIRECTORY
		echo "INFO:: Creating temporary files : " $DIRECTORY"/"$TEMP_FILE;
		touch $DIRECTORY"/"$TEMP_FILE;
	fi

	echo "INFO:: Checking awsClient Information."
	awsClient=`aws --version`
	if [[ $awsClient = " " ]] 
		then
		echo "ERROR:: awsClient not found.\n";
		echo "---------------------------------------------------";
		echo "-------------- Installing AWS Client --------------";
		echo "UPDATE:: sudo apt-get update"; sudo apt-get update;
		echo "INSTALL:: sudo apt-get install awscli"; sudo apt-get -y install awscli
		echo "CONFIGURE:: aws configure"; aws configure	
		echo "------------------- completed ---------------------"
	else
		echo "INFO:: awsClient Info : " $awsClient
	fi

	echo "INFO:: Connecting to s3 bucket : " $s3_bucket;
	file_name=`/usr/bin/aws s3 ls $s3_bucket | tail -n 1 | awk '{print $4}'`;

	info=`cat $DIRECTORY"/"$TEMP_FILE`;

	echo "INFO:: Last updated log file : " $info	
	echo "INFO:: Latest available log file : " $file_name

	if [[ "$info" = "$file_name" ]] 
		then
		echo "INFO:: We haven't find new files, Exiting."
		echo "INFO:: Removing temporary files."	
		exit;
	else
		echo "INFO:: Downloading : " $file_name	
		echo $file_name > $DIRECTORY"/"$TEMP_FILE
		/usr/bin/aws s3 cp $s3_bucket$file_name $DIRECTORY"/" 

		awk '
		{
			split($1,T,".")
			gsub("T"," ",T[1]);

			if ($8 ~ /^2.*/) 
			{
				arr[$13]["time"] = T[1]
				arr[$13]["RequestTime"]["sum"] = arr[$13]["RequestTime"]["sum"] + $5
				arr[$13]["BackendReqTime"]["sum"] = arr[$13]["BackendReqTime"]["sum"] + $6
				arr[$13]["ResponseTime"]["sum"] = arr[$13]["ResponseTime"]["sum"] + $7
				arr[$13]["RequestTime"]["count"] = arr[$13]["RequestTime"]["count"] + 1
				arr[$13]["BackendReqTime"]["count"] = arr[$13]["BackendReqTime"]["count"] + 1
				arr[$13]["ResponseTime"]["count"] = arr[$13]["ResponseTime"]["count"] + 1
				arr[$13]["RequestTime"]["avg"] = arr[$13]["RequestTime"]["sum"] / arr[$13]["RequestTime"]["count"]
				arr[$13]["BackendReqTime"]["avg"] = arr[$13]["BackendReqTime"]["sum"] / arr[$13]["BackendReqTime"]["count"]
				arr[$13]["ResponseTime"]["avg"] = arr[$13]["ResponseTime"]["sum"] / arr[$13]["ResponseTime"]["count"]
				if($5 > arr[$13]["RequestTime"]["max"])
				{
					arr[$13]["RequestTime"]["max"] = $5
				}
				if($6 > arr[$13]["BackendReqTime"]["max"])
				{
					arr[$13]["BackendReqTime"]["max"] = $6
				}
				if($7 > arr[$13]["ResponseTime"]["max"])
				{
					arr[$13]["ResponseTime"]["max"] = $7
				}
			}

			if ($8 ~ /^4.*/) 
			{
				arr[$13]["4xxError"]["count"] = arr[$13]["4xxError"]["count"] + 1
				arr[$13]["4xxError"]["error"] = $8
				arr[$13]["time"] = T[1]
			}
			if ($8 ~ /^5.*/) 
			{
				arr[$13]["5xxError"]["count"] = arr[$13]["5xxError"]["count"] + 1
				arr[$13]["5xxError"]["error"] = $8
				arr[$13]["time"] = T[1]
			}
		} 
		END{

			for (i in arr)
			{
				if(i != "")
				{
					if(length(arr[i]["5xxError"]["count"]) != 0)
					{
						print "'"$SERVERNAME"'" ","arr[i]["time"] "," i ",5xxError,"arr[i]["5xxError"]["count"] "," arr[i]["5xxError"]["error"] ",0,0" 
					}
					else if(length(arr[i]["4xxError"]["count"]) != 0)
					{
						print "'"$SERVERNAME"'" ","arr[i]["time"] "," i ",4xxError,"arr[i]["4xxError"]["count"] "," arr[i]["4xxError"]["error"] ",0,0" 
					}
					else
					{
						print "'"$SERVERNAME"'" ","arr[i]["time"] "," i ",RequestTime," arr[i]["RequestTime"]["max"] "," arr[i]["RequestTime"]["count"] "," arr[i]["RequestTime"]["sum"] "," arr[i]["RequestTime"]["avg"]
						print "'"$SERVERNAME"'" ","arr[i]["time"] "," i ",BackendReqTime," arr[i]["BackendReqTime"]["max"] "," arr[i]["BackendReqTime"]["count"] "," arr[i]["BackendReqTime"]["sum"] "," arr[i]["BackendReqTime"]["avg"]
						print "'"$SERVERNAME"'" ","arr[i]["time"] "," i ",ResponseTime," arr[i]["ResponseTime"]["max"] "," arr[i]["ResponseTime"]["count"] "," arr[i]["ResponseTime"]["sum"] "," arr[i]["ResponseTime"]["avg"]
					}
				}
			}
		}' $DIRECTORY"/"$file_name > $DIRECTORY"/"$RESULT_FILE

		

		echo "INFO:: Checking mysqlClient Information."
		mysqlClient=`which mysql`
		if [[ $mysqlClient = "" ]] 
			then
			echo "ERROR:: mysqlClient not found.";
		else
			echo "INFO:: mysqlClient Info : " $mysqlClient
			echo "INFO:: Mysql exicecution started."
			mysql -h $MYSQL_HOST -u $MYSQL_USER_NAME --password=$MYSQL_PASSWORD --local_infile=1 $MYSQL_DATABASE -e "LOAD DATA LOCAL INFILE '"$DIRECTORY"/"$RESULT_FILE"' INTO TABLE "$MYSQL_TABLE" FIELDS TERMINATED BY ','"

			echo "INFO:: Finalizing exicecution."
			echo "INFO:: Removing temporary files."	
			rm $DIRECTORY"/"$file_name; echo $DIRECTORY"/"$file_name;
			rm $DIRECTORY"/"$RESULT_FILE; echo $DIRECTORY"/"$RESULT_FILE;
		fi

	fi