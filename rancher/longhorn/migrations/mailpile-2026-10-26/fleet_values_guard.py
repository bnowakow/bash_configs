"""Read Fleet's actual downstream Helm values without logging Secret contents."""
import base64,json

def target_values_ready(get,namespace):
 secret=get(['-n',namespace,'get','secret','mailpile'])
 values=json.loads(base64.b64decode(secret.get('data',{}).get('values','')))
 for key,claim in [('path1','mailpile-path1-longhorn-rwo'),('path2','mailpile-path2-longhorn-rwo')]:
  p=values.get('persistence',{}).get(key,{})
  if p.get('existingClaim')!=claim or p.get('enabled') is not True or p.get('type')!='pvc':return False
 w=values.get('workload',{}).get('main',{})
 return w.get('replicas')==1 and w.get('strategy')=='Recreate'
