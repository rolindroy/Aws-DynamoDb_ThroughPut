#!/bin/bash

#----------------------------------------------
# Amazon Web Services - Dynamo Db
# @Description Dynamo Db Provisioned through put update.
# @author Rolind Roy <rolind.roy@gmail.com>
#----------------------------------------------

PROVISIONED_READ="ProvisionedReadCapacityUnits"
PROVISIONED_WRITE="ProvisionedWriteCapacityUnits"
CONSUMED_READ="ConsumedReadCapacityUnits"
CONSUMED_WRITE="ConsumedWriteCapacityUnits"

#Todo
DynamoDB="dynamo-table"
To="test@testmail.com"
From="test@testmail.com"
Mailer="mail.txt"

function dataParser 
{
	#Average for Provisioned and Sum for Consumed
	echo `awk '
	{
        if (($1 ~ "Sum"))
        {
        	split($2,T,",")
            printf int(T[1]/900)
        }

        if (($1 ~ "Average"))
        {
        	split($2,T,",")
            printf int(T[1])
        }
	}' json`
}

function _getDyanamoMetric 
{
	#Average for Provisioned and Sum for Consumed
	if [[ $6 != "Provisoned" ]] 
		then
		statistics="Sum"
	else
		statistics="Average"
	fi

	aws cloudwatch get-metric-statistics --metric-name $1 --start-time $2 --end-time $3 --period $4 --namespace AWS/DynamoDB --statistics $statistics --dimensions Name=TableName,Value=$5 > json
	echo $(dataParser)
}

function _updateTime
{
	#05:25:22 => 05:20:00
	echo $1 | awk -F: '{
		print $1":"int($2/5)*5":00" 
	}'
}

function _calculateMetric
{
	# $1 : ProvisionedWriteCapacityUnits
	# $2 : ConsumedWriteCapacityUnits
	# $3 : PreviousConsumedWriteCapacityUnits
	# $4 : LastWeekConsumedWriteCapacityUnits

	ThroughPutIncRatio=`echo "$2 + ( ( $1 * 30 ) / 100 )" | bc` # ConsumedWriteCapacityUnits + 30 % of ProvisionedWriteCapacityUnits
	ThroughPutDecRatio=`echo "( ( $1 * 30 ) / 20 )" | bc`  # 20 % of ProvisionedWriteCapacityUnits

	if [ $2 -gt $3 ] && [ $2 -gt $4 ] && [ $ThroughPutIncRatio -gt $1 ]; then
		#Increase ThroughPut 20 %
		echo `echo "$1 + ( $1 * 20 ) / 100" | bc` 
	elif [ $2 -lt $3 ] && [ $2 -lt $4 ] && [ $ThroughPutDecRatio -lt $2 ]; then
		#Decrease ThroughPut 10 %
		echo `echo "$1 - ( $1 * 10 ) / 100" | bc` 
	else
		#Normal
		echo "0" 
	fi
}

function _updateThroughputData
{
	#updating throughput
	aws dynamodb update-table --table-name $3 --provisioned-throughput $2=$1
	echo $1
}

CurrentEndTime=`date -u +%Y-%m-%d`"T"$(_updateTime `date -u +"%T"`) #2015-08-24T20:23:11 currentTime
ProvisonedStartTime=`date -u +%Y-%m-%d`"T"$(_updateTime `date -u -d '-300 seconds' +"%T"`) #2015-08-24T20:23:11 -60 seconds
CurrentStartTime=`date -u +%Y-%m-%d`"T"$(_updateTime `date -u -d '-900 seconds' +"%T"`) #2015-08-24T20:23:11 -900 seconds

PreviousEndTime=`date -u -d '-1day' +%Y-%m-%d`"T"$(_updateTime `date -u +"%T"`) #2015-08-24T20:23:11 - 1 day 
PreviousStartTime=`date -u -d '-1day' +%Y-%m-%d`"T"$(_updateTime `date -u -d '-900 seconds' +"%T"`) #2015-08-24T20:23:11 -1 day and -900 seconds
LastWeekEndTime=`date -u -d '-7day' +%Y-%m-%d`"T"$(_updateTime `date -u +"%T"`) #2015-08-24T20:23:11 -7 day
LastWeekStartTime=`date -u -d '-7day' +%Y-%m-%d`"T"$(_updateTime `date -u -d '-900 seconds' +"%T"`) #2015-08-24T20:23:11 -7 day and -900 seconds
Provisoned="Provisoned" 
echo "Subject: DynamoDB Through Put Info - `date`" > $Mailer

ProvisionedWriteCapacityUnits=$(_getDyanamoMetric $PROVISIONED_WRITE $ProvisonedStartTime $CurrentEndTime 300 $DynamoDB $Provisoned)
ProvisionedReadCapacityUnits=$(_getDyanamoMetric $PROVISIONED_READ $ProvisonedStartTime $CurrentEndTime 300 $DynamoDB $Provisoned)
Provisoned="Consumed"

if ([ "$ProvisionedWriteCapacityUnits" != "" ] && [ "$ProvisionedReadCapacityUnits" != "" ])
	then
	echo "Provisioned Write Capacity : "$ProvisionedWriteCapacityUnits >> $Mailer
	echo "Provisioned Read Capacity : "$ProvisionedReadCapacityUnits  >> $Mailer
	
	ConsumedWriteCapacityUnits=$(_getDyanamoMetric $CONSUMED_WRITE $CurrentStartTime $CurrentEndTime 900 $DynamoDB $Provisoned)
	ConsumedReadCapacityUnits=$(_getDyanamoMetric $CONSUMED_READ $CurrentStartTime $CurrentEndTime 900 $DynamoDB $Provisoned)

	echo "ConsumedWriteCapacityUnits : "$ConsumedWriteCapacityUnits >> $Mailer
	echo "ConsumedReadCapacityUnits : "$ConsumedReadCapacityUnits >> $Mailer

	PreviousConsumedWriteCapacityUnits=$(_getDyanamoMetric $CONSUMED_WRITE $PreviousStartTime $PreviousEndTime 900 $DynamoDB $Provisoned)
	PreviousConsumedReadCapacityUnits=$(_getDyanamoMetric $CONSUMED_READ $PreviousStartTime $PreviousEndTime 900 $DynamoDB $Provisoned)

	echo "PreviousConsumedWriteCapacityUnits : "$PreviousConsumedWriteCapacityUnits >> $Mailer
	echo "PreviousConsumedReadCapacityUnits : "$PreviousConsumedReadCapacityUnits >> $Mailer


	LastWeekConsumedWriteCapacityUnits=$(_getDyanamoMetric $CONSUMED_WRITE $LastWeekStartTime $LastWeekEndTime 900 $DynamoDB $Provisoned)
	LastWeekConsumedReadCapacityUnits=$(_getDyanamoMetric $CONSUMED_READ $LastWeekStartTime $LastWeekEndTime 900 $DynamoDB $Provisoned)

	echo "LastWeekConsumedWriteCapacityUnits : "$LastWeekConsumedWriteCapacityUnits >> $Mailer
	echo "LastWeekConsumedReadCapacityUnits : "$LastWeekConsumedReadCapacityUnits >> $Mailer

	UpdateWriteThroughputMetric=$(_calculateMetric $ProvisionedWriteCapacityUnits $ConsumedWriteCapacityUnits $PreviousConsumedWriteCapacityUnits $LastWeekConsumedWriteCapacityUnits)
	echo "Metric Data : "$UpdateWriteThroughputMetric >> $Mailer

	ReadCapacityUnits="ReadCapacityUnits" >> $Mailer
	WriteCapacityUnits="WriteCapacityUnits" >> $Mailer

	if [[ "$UpdateWriteThroughputMetric" != "0" ]]; then
		OutPutWrite=$(_updateThroughputData $UpdateWriteThroughputMetric $WriteCapacityUnits $DynamoDB)
		echo "Update Write Through Put : "$ProvisionedWriteCapacityUnits" - "$OutPutWrite  >> $Mailer
	fi

	UpdateReadThroughputMetric=$(_calculateMetric $ProvisionedReadCapacityUnits $ConsumedReadCapacityUnits $PreviousConsumedReadCapacityUnits $LastWeekConsumedReadCapacityUnits)
	echo "Metric Data : "$UpdateReadThroughputMetric >> $Mailer

	if [[ "$UpdateReadThroughputMetric" != "0" ]]; then
		OutPutRead=$(_updateThroughputData $UpdateReadThroughputMetric $ReadCapacityUnits $DynamoDB)
		echo "Update Read Through Put : "$ProvisionedReadCapacityUnits" - "$OutPutRead >> $Mailer
	fi

	sendmail -f "$From" -s "DynamoDB ThroughPut !!" "$To" < $Mailer ##send mail
else
	echo "We haven't find out the Provisioned Write and Read Units."
fi

echo `cat $Mailer`
