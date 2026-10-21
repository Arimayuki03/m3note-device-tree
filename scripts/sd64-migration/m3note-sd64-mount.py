#!/usr/bin/python3
"""Mount only the enrolled SD card; expose its audited Docker trees, or fail closed."""
import argparse,json,os,subprocess,time

CID='SD_CID_REDACTED'
UUID='SD_UUID_REDACTED'
# 按自己的 SD 卡填写：卡总扇区数、分区起始扇区、分区扇区数
GEOMETRY=['<SD_SIZE_SECTORS>','<SD_PART_START_SECTOR>','<SD_PART_SIZE_SECTORS>']
DEVICE='/dev/block/mmcblk1p1'
MOUNT='/mnt/sd64'
BASE=MOUNT+'/m3note-docker'
PAIRS=[('engine','/var/lib/docker'),
       ('beszel-data','/opt/beszel-agent/beszel_agent_data')]

def run(args):
    return subprocess.check_output(args,stderr=subprocess.STDOUT,text=True).strip()

def identity():
    assert open('/sys/block/mmcblk1/device/cid').read().strip()==CID,'Wrong SD card CID'
    paths=['/sys/block/mmcblk1/size','/sys/block/mmcblk1/mmcblk1p1/start','/sys/block/mmcblk1/mmcblk1p1/size']
    assert [open(p).read().strip() for p in paths]==GEOMETRY,'Wrong SD geometry'
    assert run(['blkid','-p','-s','TYPE','-o','value',DEVICE])=='ext4','SD is not ext4'
    assert run(['blkid','-p','-s','UUID','-o','value',DEVICE])==UUID,'Wrong SD filesystem UUID'
    return os.stat(DEVICE).st_rdev

def mounts():
    with open('/proc/self/mountinfo') as f:return [line.split() for line in f]

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    if not args.check:
        for _ in range(60):
            if os.path.exists(DEVICE) and os.path.exists('/sys/block/mmcblk1/device/cid'):break
            time.sleep(1)
    device=identity();number='%d:%d'%(os.major(device),os.minor(device))
    current=[m for m in mounts() if m[4]==MOUNT]
    if current:
        assert len(current)==1 and current[0][2]==number and 'ext4' in current[0],'Unexpected SD mount'
        assert 'rw' in current[0][5].split(','),'SD is read-only'
    else:
        assert not args.check,'SD is not mounted'
        # The exclusive open also catches references held in other mount namespaces.
        fd=os.open(DEVICE,os.O_RDONLY|os.O_EXCL);os.close(fd)
        check=subprocess.run(['e2fsck','-p',DEVICE],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
        print(check.stdout,flush=True)
        assert check.returncode in (0,1),'SD filesystem requires manual repair; refusing Docker startup'
        identity()
        os.makedirs(MOUNT,exist_ok=True)
        print(run(['mount','-t','ext4','-o','rw,noatime,nosuid,nodev',DEVICE,MOUNT]),flush=True)
    assert os.stat(MOUNT).st_dev==device,'SD backing device mismatch'
    assert os.stat(MOUNT).st_uid==0 and not (os.stat(MOUNT).st_mode & 0o022),'SD root permissions are unsafe'
    assert os.stat(BASE).st_uid==0 and not (os.stat(BASE).st_mode & 0o077),'Docker SD directory permissions are unsafe'
    with open(BASE+'/ready.json') as f:ready=json.load(f)
    assert ready['cid']==CID and ready['uuid']==UUID and ready['offline_checksum_verified'] is True,'SD migration marker invalid'
    for name,target in PAIRS:
        source=BASE+'/'+name
        assert os.path.isdir(source) and os.stat(source).st_dev==device,'Missing SD data tree'
        already=[m for m in mounts() if m[4]==target]
        if already:
            assert len(already)==1 and os.path.samefile(source,target),'Unexpected data bind mount'
        else:
            assert not args.check,'Data bind mount missing: '+target
            assert os.path.isdir(target) and os.stat(target).st_dev!=device,'Internal fallback directory invalid'
            print(run(['mount','--bind',source,target]),flush=True)
        assert os.path.samefile(source,target) and os.stat(target).st_dev==device
    print('SD64_READY: identity, ext4 mount, and all three data bindings verified',flush=True)

if __name__=='__main__':main()
