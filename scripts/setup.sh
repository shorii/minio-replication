#!/usr/bin/bash

set -xe

access_key=$1;shift;
secret_key=$1;shift;

sample_bucket="mybucket"

function create_versioning_bucket() {
  alias=$1;shift;
  target=$alias/$sample_bucket
  mc mb $target
  mc version enable $target
}

function create_user_with_policy() {
  alias=$1;shift;
  user=$1;shift;
  policy=$1;shift;
  path=$1;shift;
  mc admin policy add $alias $policy $path
  mc admin user add $alias $user $secret_key #reuse secret_key
  mc admin policy set $alias $policy user=$user
}

function create_replication_target() {
  replication_alias=$1;shift;
  replication_remote_user=$1;shift;
  replication_remote_host=$1;shift;
  arn=$(mc admin bucket remote add $replication_alias/$sample_bucket http://$replication_remote_user:$secret_key@$replication_remote_host/$sample_bucket --service "replication")
  echo $(echo $arn | sed -e 's/Remote ARN = `\(.*\)`./\1/g')
}

minio0="minio0"
minio1="minio1"
minio0_server="${minio0}:9000"
minio1_server="${minio1}:9000"
minio0_alias="${minio0}Alias"
minio1_alias="${minio1}Alias"


# set alias
until mc alias s $minio0_alias http://$minio0_server $access_key $secret_key; do
  >&2 echo "minio0 is unavailable - sleeping"
  sleep 1
done

until mc alias s $minio1_alias http://$minio1_server $access_key $secret_key; do
  >&2 echo "minio1 is unavailable - sleeping"
  sleep 1
done

# create versioning bucket
create_versioning_bucket $minio0_alias
create_versioning_bucket $minio1_alias

# create user and set policy(replication admin user)
minio0_replication_admin_user="${minio0}ReplicationAdmin"
create_user_with_policy \
  $minio0_alias \
  $minio0_replication_admin_user \
  ReplicationAdminPolicy \
  /policies/ReplicationAdminPolicy.json

minio1_replication_admin_user="${minio1}ReplicationAdmin"
create_user_with_policy \
  $minio1_alias \
  $minio1_replication_admin_user \
  ReplicationAdminPolicy \
  /policies/ReplicationAdminPolicy.json

# create user and set policy(replication remote user)
minio0_replication_remote_user="${minio0}ReplicationRemoteUser"
create_user_with_policy \
  $minio0_alias \
  $minio0_replication_remote_user \
  ReplicationRemoteUserPolicy \
  /policies/ReplicationRemoteUserPolicy.json

minio1_replication_remote_user="${minio1}ReplicationRemoteUser"
create_user_with_policy \
  $minio1_alias \
  $minio1_replication_remote_user \
  ReplicationRemoteUserPolicy \
  /policies/ReplicationRemoteUserPolicy.json

# set replication alias
minio0_replication_alias="${minio0}ReplicationAlias"
minio1_replication_alias="${minio1}ReplicationAlias"
mc alias s $minio0_replication_alias http://$minio0_server $minio0_replication_admin_user $secret_key
mc alias s $minio1_replication_alias http://$minio1_server $minio1_replication_admin_user $secret_key

# create replication target
arn0=$(create_replication_target $minio0_replication_alias $minio1_replication_remote_user $minio1_server)
arn1=$(create_replication_target $minio1_replication_alias $minio0_replication_remote_user $minio0_server)

# create replication rule
mc replicate add $minio0_replication_alias/$sample_bucket --remote-bucket $sample_bucket --arn $arn0 --replicate "delete,delete-marker"
mc replicate add $minio1_replication_alias/$sample_bucket --remote-bucket $sample_bucket --arn $arn1 --replicate "delete,delete-marker"