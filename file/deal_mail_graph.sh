#!/bin/sh
#######################################################
# Author: xiaochuan
# Date: 2015-06-16
# Describe: 邮箱画像二期
# 前置工作：导入活跃用户ID并挂在f_mail_uid表，导入
#活跃用户注册时间数据并挂在f_mail_uid_regtime。所有
#挂表都需要有分区dt(dt为项目开始的时间，以第一封邮件的时间为准）
#######################################################

source ~/.bash_profile
##自行取到运行跟目录
rootdir=`dirname $0`/..
#source $rootdir/lib/suda_lib.sh
#联系人设置
contact=haifeng7:18612461789
## 判断计算输入日期
if [ "$1" = ""  ]
then
    ts=`date --date "-1 days" +%Y%m%d`
else
    ts=$1
fi
## 生成日期变量 参数1 YYYYMMDD 参数2 HH
gen_date $ts
#如果当前时间2014-08-01 09:30:00
#ts		20140801
#dt		2014-08-01
#dtpath	2014/08/01
#partdt	201408/01
#month	08
#day		01
#hour	09
#ympath	201408

## check variable
## debug用的函数 打印设置的变量
dumpvar ts pathdt
resultpath=$rootdir/data/
#有可能错误输出的加 2>&1 
mkdir -p $resultpath 2>&1 
#$ts 将结果插入到f_mail_user_graph中并增加分区dt='$ts'
sql1="set mapred.job.name='`basename $0`';
insert overwrite table f_mail_user_graph
partition(dt='$ts')
select a.uid,b.gender,b.age,b.prov_id,b.marital_status,b.degree,c.interest,d.salary,d.hy_tag,e.reg_time
from f_mail_uid a
left outer join (
select uid,gender,age,reg_time,prov_id,marital_status,max(degree) degree
from mds_user_info
where dt='$ts'
group by uid,gender,age,reg_time,prov_id,marital_status
) b
on a.uid=b.uid
left outer join (
select uid,collect_set(tname) interest
from f_mr_user_interest_library
where dt='$dt'
group by uid
) c
on a.uid=c.uid
left outer join hue_zhihong4_uid_biaoqian d
on a.uid=d.uid
left outer join f_mail_uid_regTime e
on a.uid=e.uid
"
echo $sql1
#hive  -e "$sql1" > $resultpath/mail_beahvior_all$ts.txt
hive  -e "$sql1" >null
check_result $contact "mail_beahvior_all Ln:${LINENO}"