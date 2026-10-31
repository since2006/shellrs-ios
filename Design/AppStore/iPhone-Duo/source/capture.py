import pathlib,subprocess,time,sys
language=sys.argv[1]
device='5D221A22-DAA0-4A07-859D-B67B8EED72CE'
container=pathlib.Path(subprocess.check_output(['xcrun','simctl','get_app_container',device,'com.shellrs.ios','data'],text=True).strip())
bridge=container/'Documents/duo-capture'
out=pathlib.Path('Design/AppStore/iPhone-Duo/raw')/language
out.mkdir(parents=True,exist_ok=True)
for page in ['01-terminal','02-hosts','03-files','04-sync']:
 token=language+'/'+page
 deadline=time.time()+180
 while time.time()<deadline:
  container=pathlib.Path(subprocess.check_output(['xcrun','simctl','get_app_container',device,'com.shellrs.ios','data'],text=True).strip())
  bridge=container/'Documents/duo-capture'
  if (bridge/'ready.txt').exists() and (bridge/'ready.txt').read_text()==token:break
  time.sleep(.2)
 else:raise RuntimeError('Screenshot fixture did not reach '+token)
 path=out/(page+'.png')
 subprocess.run(['xcrun','simctl','io',device,'screenshot','--display=3','--mask=ignored',str(path)],check=True,capture_output=True)
 print('Captured '+str(path),flush=True)
 (bridge/'next.txt').write_text(token)
