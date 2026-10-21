"""Exercise only 48 MiB inside a disposable, memory-limited local container."""
import json, pathlib, subprocess, time

NAME='m3note-wifi-swap-check'
def command(*args, timeout=45):
    return subprocess.check_output(args, text=True, stderr=subprocess.PIPE, timeout=timeout).strip()
assert command('docker','info','--format','{{.SwapLimit}}')=='true'
assert pathlib.Path('/sys/block/zram0/disksize').read_text().strip()=='4294967296'
assert not command('docker','ps','-aq','--filter','name=^/'+NAME+'$'), 'Existing test container; refusing to replace it'
created=False
try:
    cid=command('docker','run','-d','--name',NAME,'--pull','never','--network','none',
                '--memory','32m','--memory-swap','96m',
                '--mount','type=bind,src=/var/tmp/m3note-wifi-server,dst=/work,readonly',
                '--entrypoint','/work/alloc-probe','m3note-docker-check:local')
    created=True
    pid=int(command('docker','inspect','--format','{{.State.Pid}}',NAME))
    entries={c:p for line in pathlib.Path('/proc/%d/cgroup'%pid).read_text().splitlines()
             for _,cs,p in [line.split(':',2)] for c in cs.split(',')}
    root=pathlib.Path('/sys/fs/cgroup/memory'+entries['memory'])
    assert int((root/'memory.limit_in_bytes').read_text())==32*1024**2
    assert int((root/'memory.memsw.limit_in_bytes').read_text())==96*1024**2
    for _ in range(12):
        stat=dict(line.split() for line in (root/'memory.stat').read_text().splitlines())
        if int(stat.get('swap','0'))>8*1024**2: break
        time.sleep(1)
    else: raise RuntimeError('Swap accounting was not exercised')
    swap=int(stat['swap'])
    assert command('docker','wait',NAME)=='0'
    output=command('docker','logs',NAME)
    assert 'ALLOCATED_48_MIB' in output and 'TOUCHED_AGAIN_OK' in output
    result={'boot_id':pathlib.Path('/proc/sys/kernel/random/boot_id').read_text().strip(),
            'zram_bytes':4294967296,'compression':pathlib.Path('/sys/block/zram0/comp_algorithm').read_text().strip(),
            'allocated_MiB':48,'memory_limit_MiB':32,'memory_swap_limit_MiB':96,
            'observed_swap_bytes':swap,'exit_code':0,'output':output}
finally:
    if created: command('docker','rm','-f',NAME)
OUT=pathlib.Path(__file__).resolve().with_name('swap-verification.json')
OUT.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
print(json.dumps(result,indent=2),flush=True)
