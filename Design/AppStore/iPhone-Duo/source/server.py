import asyncio, asyncssh, pathlib, os, signal, pty, fcntl, termios, struct, subprocess
ROOT=pathlib.Path(__file__).resolve().parent/'remote'
for folder in ['srv/apps/api/current','srv/apps/api/releases','srv/apps/api/shared','srv/apps/api/logs','srv/apps/api/backups']:
 (ROOT/folder).mkdir(parents=True,exist_ok=True)
for name,size in [('README.md',1840),('compose.yaml',2948),('deploy.sh',3260),('api-server',18643200),('release.tar.gz',5242880)]:
 p=ROOT/'srv/apps/api'/name
 with p.open('wb') as f:f.truncate(size)
 os.utime(p,(1792737000,1792737000))
for p in ROOT.rglob('*'):
 os.chmod(p,0o755 if p.is_dir() or p.name in ['deploy.sh','api-server'] else 0o644)
 os.utime(p,(1792737000,1792737000))
class Server(asyncssh.SSHServer):
 def begin_auth(self,username):return True
 def password_auth_supported(self):return True
 def validate_password(self,username,password):return username=='deploy' and password=='screenshot-only'
async def process_factory(process):
 if process.command:
  process.stdout.write(b'Linux\n')
  process.exit(0)
  return
 master,slave=pty.openpty()
 def start():
  os.setsid();fcntl.ioctl(slave,termios.TIOCSCTTY,0)
 child=subprocess.Popen(['/bin/bash','--noprofile','--norc','-i'],stdin=slave,stdout=slave,stderr=slave,cwd=ROOT,
  env={'PATH':'/usr/bin:/bin','TERM':'xterm-256color','PS1':'deploy@api-prod:~$ ','BASH_SILENCE_DEPRECATION_WARNING':'1'},preexec_fn=start)
 os.close(slave)
 def resize(size):
  w,h,pw,ph=size;fcntl.ioctl(master,termios.TIOCSWINSZ,struct.pack('HHHH',h,w,pw,ph))
 resize(process.term_size)
 def read():
  try:
   data=os.read(master,65536)
   if data:process.stdout.write(data)
   else:process.exit(0)
  except OSError:process.exit(0)
 loop=asyncio.get_running_loop();loop.add_reader(master,read)
 try:
  while True:
   try:
    data=await process.stdin.read(65536)
    if not data:break
    os.write(master,data)
   except asyncssh.TerminalSizeChanged as event:resize(event.term_size)
 finally:
  loop.remove_reader(master);os.close(master)
  try:os.killpg(child.pid,signal.SIGTERM)
  except ProcessLookupError:pass
async def socks(reader,writer):
 remote=None
 try:
  version,count=await reader.readexactly(2);await reader.readexactly(count);writer.write(b'\x05\x00');await writer.drain()
  ver,cmd,_,kind=await reader.readexactly(4)
  if kind==1:await reader.readexactly(4)
  elif kind==3:await reader.readexactly((await reader.readexactly(1))[0])
  elif kind==4:await reader.readexactly(16)
  await reader.readexactly(2)
  r,remote=await asyncio.open_connection('127.0.0.1',22222)
  writer.write(b'\x05\x00\x00\x01\x7f\x00\x00\x01\x56\xce');await writer.drain()
  async def pump(src,dst):
   try:
    while data:=await src.read(65536):dst.write(data);await dst.drain()
   finally:dst.close()
  await asyncio.gather(pump(reader,remote),pump(r,writer))
 except (Exception,asyncio.CancelledError):pass
 finally:
  writer.close()
  if remote:remote.close()
async def main():
 await asyncssh.create_server(Server,'127.0.0.1',22222,server_host_keys=[asyncssh.generate_private_key('ssh-ed25519')],
  encoding=None,process_factory=process_factory,line_editor=False,sftp_factory=lambda chan:asyncssh.SFTPServer(chan,chroot=str(ROOT)))
 await asyncio.start_server(socks,'127.0.0.1',22223)
 print('Screenshot fixtures ready (loopback SSH/SFTP + SOCKS)',flush=True)
 await asyncio.Event().wait()
asyncio.run(main())
