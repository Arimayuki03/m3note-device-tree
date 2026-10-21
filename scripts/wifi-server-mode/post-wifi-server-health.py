"""Historical verification script (2026-10-16).

AstrBot has since been removed; current services are Beszel, DSHA, DSH and
Magpie. This script still expects the old AstrBot container/baseline and must
not be run as-is. Kept as a record of the SD64 persistence test.
"""
import json,os,pathlib,subprocess,sys,time,urllib.request
phase='final'
WORK='/var/tmp/m3note-sd64-migration'
with open(WORK+'/baseline.json') as f:baseline=json.load(f)
PROOF_MARKER='m3note-sd64-proof-marker'
PROOF='sd64-migration-proof';VOLUME='sd64-migration-proof-volume'
def command(*args,timeout=120):
    return subprocess.check_output(list(args),stderr=subprocess.PIPE,text=True,timeout=timeout).strip()
def docker(*args):return json.loads(command('docker',*args))
def dev(path):
    d=os.stat(path).st_dev;return '%d:%d'%(os.major(d),os.minor(d))
assert open('/sys/block/mmcblk1/device/cid').read().strip()=='SD_CID_REDACTED'
sd=os.stat('/dev/block/mmcblk1p1').st_rdev
pid=int(open('/run/docker.pid').read());engine='/proc/%d/root'%pid
paths=['/var/lib/docker','/srv/astrbot/data','/opt/beszel-agent/beszel_agent_data']
for p in paths:
    assert os.stat(p).st_dev==sd and os.stat(engine+p).st_dev==sd,'Wrong backing device: '+p
images=sorted(set(command('docker','image','ls','--no-trunc','--format','{{.ID}}').splitlines()))
assert images==baseline['image_ids']
apps=[]
for old in baseline['containers']:
    c=docker('inspect',old['id'])[0]
    assert c['Id']==old['id'] and c['Image']==old['image'] and c['State']['Running']
    for prop,key in [('NanoCpus','nano_cpus'),('CpusetCpus','cpuset'),('Memory','memory'),('RestartPolicy','restart_policy')]:
        assert c['HostConfig'][prop]==old[key],prop+' changed'
    r='/proc/%d/root'%c['State']['Pid']
    data='/AstrBot/data' if c['Name']=='/astrbot' else '/var/lib/beszel-agent'
    assert os.stat(r).st_dev==sd and os.stat(r+data).st_dev==sd
    apps.append({'name':c['Name'],'id':c['Id'],'same_image':True,'running':True,'root_device':dev(r),'data_device':dev(r+data),'restart_count':c['RestartCount'],'nano_cpus':c['HostConfig']['NanoCpus'],'cpuset':c['HostConfig']['CpusetCpus'],'memory':c['HostConfig']['Memory']})
for _ in range(90):
    try:
        with urllib.request.urlopen('http://127.0.0.1:6185/',timeout=3) as r:assert r.status==200
        break
    except Exception:time.sleep(1)
else:raise RuntimeError('AstrBot HTTP did not become ready')
proof=None
if phase=='before-reboot':
    command('docker','volume','create',VOLUME)
    command('docker','run','-d','--name',PROOF,'--restart=unless-stopped','--network','none','--pull','never','--mount','type=volume,source='+VOLUME+',target=/work','m3note-docker-check:local','/bin/sleep','86400')
    command('docker','exec',PROOF,'/bin/sh','-c','/bin/echo '+PROOF_MARKER+' > /sd64-proof; /bin/echo '+PROOF_MARKER+' > /work/proof; /bin/sync')
    command('docker','restart','-t','5',PROOF)
if phase!='final':
    c=docker('inspect',PROOF)[0];assert c['State']['Running']
    if phase=='after-reboot':
        with open(WORK+'/before-reboot-verification.json') as f:before=json.load(f)
        assert c['Id']==before['proof']['id'],'Proof container was replaced'
        assert open('/proc/sys/kernel/random/boot_id').read().strip()!=before['boot_id'],'Phone did not reboot'
    root='/proc/%d/root'%c['State']['Pid']
    for p in ['/sd64-proof','/work/proof']:
        assert command('docker','exec',PROOF,'/bin/cat',p)==PROOF_MARKER
        assert os.stat(root+p).st_dev==sd
    volume=docker('volume','inspect',VOLUME)[0]
    assert os.stat(engine+volume['Mountpoint']).st_dev==sd
    proof={'id':c['Id'],'writable_file_persisted':True,'named_volume_persisted':True,'writable_device':dev(root+'/sd64-proof'),'volume_device':dev(root+'/work/proof'),'auto_started':phase=='after-reboot'}
v=os.statvfs('/mnt/sd64')
result={'phase':phase,'boot_id':open('/proc/sys/kernel/random/boot_id').read().strip(),'docker_driver':command('docker','info','--format','{{.Driver}}'),'data_root':'/var/lib/docker','data_root_device':dev('/var/lib/docker'),'sd_device':dev('/mnt/sd64'),'image_count':len(images),'all_original_image_ids_match':True,'apps':apps,'astrbot_http_status':200,'cpu_online':open('/sys/devices/system/cpu/online').read().strip(),'sd_free_GiB':round(v.f_bavail*v.f_frsize/2**30,2),'proof':proof,'sd_mount':next(l.strip() for l in open('/proc/mounts') if l.split()[1]=='/mnt/sd64')}
assert result['cpu_online']=='0-7'
OUT=pathlib.Path(__file__).resolve().with_name('post-wifi-server-health.json')
OUT.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
print(json.dumps(result,indent=2),flush=True)
