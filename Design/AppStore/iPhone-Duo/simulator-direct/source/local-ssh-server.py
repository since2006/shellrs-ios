import asyncio, asyncssh, os, pty, fcntl, termios, struct, signal, subprocess, tempfile
ROOT = '/tmp/shellrs-direct-demo'
os.makedirs(ROOT, exist_ok=True)
class Shell(asyncssh.SSHServerSession):
    def connection_made(self, chan):
        self.chan = chan
        self.master = None
        self.child = None
        self.size = (80, 24, 0, 0)
    def pty_requested(self, term_type, term_size, term_modes):
        self.size = term_size
        return True
    def terminal_size_changed(self, width, height, pixwidth, pixheight):
        self.size = (width, height, pixwidth, pixheight)
        self.resize()
    def resize(self):
        if self.master is not None:
            w,h,pw,ph = self.size
            fcntl.ioctl(self.master, termios.TIOCSWINSZ, struct.pack('HHHH',h,w,pw,ph))
    def shell_requested(self): return True
    def session_started(self):
        self.master, slave = pty.openpty()
        def start():
            os.setsid()
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
        self.child = subprocess.Popen(['/bin/bash','--noprofile','--rcfile','/tmp/shellrs-direct-rc','-i'],
            stdin=slave, stdout=slave, stderr=slave, cwd=ROOT,
            env={'PATH':'/usr/bin:/bin','TERM':'xterm-256color','PS1':'demo$ ','BASH_SILENCE_DEPRECATION_WARNING':'1'}, preexec_fn=start)
        os.close(slave)
        self.resize()
        asyncio.get_running_loop().add_reader(self.master, self.read)
    def read(self):
        try:
            data = os.read(self.master, 65536)
            if data: self.chan.write(data)
            else: self.chan.exit(0)
        except OSError: self.chan.exit(0)
    def data_received(self, data, datatype):
        if self.master is not None: os.write(self.master, data)
    def eof_received(self): return False
    def connection_lost(self, exc):
        if self.master is not None:
            asyncio.get_running_loop().remove_reader(self.master)
            os.close(self.master)
            self.master = None
        if self.child is not None:
            try: os.killpg(self.child.pid, signal.SIGTERM)
            except ProcessLookupError: pass
            self.child = None
class Server(asyncssh.SSHServer):
    def begin_auth(self, username): return True
    def password_auth_supported(self): return True
    def validate_password(self, username, password):
        return username == 'root' and password == 'shellrs-test'
    def public_key_auth_supported(self): return True
    def validate_public_key(self, username, key):
        return username == 'root' and b'AAAAC3NzaC1lZDI1NTE5AAAAIFt1RMfeVGPOwxKiOBQ5XPK+s20chu7Z2S1c7Pj3B8F1' in key.export_public_key()
    def session_requested(self): return Shell()
async def process_factory(process):
    if process.command:
        child = await asyncio.create_subprocess_shell(process.command, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE, cwd=ROOT)
        out, err = await child.communicate()
        process.stdout.write(out); process.stderr.write(err); process.exit(child.returncode)
        return
    master, slave = pty.openpty()
    def start():
        os.setsid()
        fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
    child = subprocess.Popen(['/bin/bash','--noprofile','--rcfile','/tmp/shellrs-direct-rc','-i'],
        stdin=slave, stdout=slave, stderr=slave, cwd=ROOT,
        env={'PATH':'/usr/bin:/bin','TERM':'xterm-256color','PS1':'demo$ ','BASH_SILENCE_DEPRECATION_WARNING':'1'}, preexec_fn=start)
    os.close(slave)
    def resize(size):
        w,h,pw,ph = size
        fcntl.ioctl(master,termios.TIOCSWINSZ,struct.pack('HHHH',h,w,pw,ph))
    resize(process.term_size)
    def read():
        try:
            data=os.read(master,65536)
            if data: process.stdout.write(data)
            else: process.exit(0)
        except OSError: process.exit(0)
    loop=asyncio.get_running_loop()
    loop.add_reader(master,read)
    try:
        while True:
            try:
                data=await process.stdin.read(65536)
                if not data: break
                os.write(master,data)
            except asyncssh.TerminalSizeChanged as event:
                resize(event.term_size)
    finally:
        loop.remove_reader(master)
        os.close(master)
        try: os.killpg(child.pid,signal.SIGTERM)
        except ProcessLookupError: pass
async def main():
    await asyncssh.create_server(Server, '127.0.0.1', 22224,
        server_host_keys=['/tmp/shellrs-direct-hostkey'], encoding=None,
        process_factory=process_factory,line_editor=False,
        sftp_factory=lambda chan: asyncssh.SFTPServer(chan, chroot=ROOT))
    print('SSH test server ready on 127.0.0.1:22224', flush=True)
    await asyncio.Event().wait()
asyncio.run(main())
