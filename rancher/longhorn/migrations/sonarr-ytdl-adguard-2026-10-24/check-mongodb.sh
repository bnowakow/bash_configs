#!/bin/sh
set -eu
state=/target/youtubedl-material-mongodb-data/data/db
mongod --dbpath "$state" --bind_ip 127.0.0.1 --port 27018 --nounixsocket \
  --noauth --wiredTigerCacheSizeGB 0.25 --logpath /tmp/mongod-check.log --logappend &
mongo_pid=$!
trap 'kill -TERM "$mongo_pid" 2>/dev/null || true; wait "$mongo_pid" 2>/dev/null || true' EXIT INT TERM
uri='mongodb://127.0.0.1:27018/?serverSelectionTimeoutMS=1000&directConnection=true'
ready=0
for attempt in $(seq 1 90); do
  if mongosh "$uri" --quiet --eval 'if(db.adminCommand({ping:1}).ok!==1)quit(1)' >/dev/null 2>&1; then ready=1; break; fi
  if ! kill -0 "$mongo_pid" 2>/dev/null; then
    echo 'Isolated MongoDB exited; startup errors follow' >&2
    tail -15 /tmp/mongod-check.log >&2
    exit 1
  fi
  sleep 1
done
[ "$ready" -eq 1 ] || { echo "MongoDB did not become ready after $attempt attempts" >&2; exit 1; }
mongosh "$uri" --quiet --eval '
const databases=db.adminCommand({listDatabases:1,nameOnly:true}).databases;
if(!databases.some(x=>x.name==="ytdl_material"))throw new Error("Application database missing");
let count=0;
for(const x of databases){
 const d=db.getSiblingDB(x.name);
 for(const c of d.getCollectionInfos({type:"collection"})){
  const result=d.runCommand({validate:c.name,full:true});
  if(result.ok!==1||result.valid!==true)throw new Error("Full collection validation failed");
  count++;
 }
}
if(count===0)throw new Error("No collections validated");
print("MongoDB full validation passed: "+count+" collections across "+databases.length+" databases");'
