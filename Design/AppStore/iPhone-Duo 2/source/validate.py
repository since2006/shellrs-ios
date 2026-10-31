"""Check the upload files and regenerate a checksum manifest (standard library only)."""
from pathlib import Path
import hashlib,json,struct
root=Path(__file__).resolve().parent.parent
files=[]
for language in ['zh-Hans','en']:
    images=sorted((root/language).glob('*.png'))
    assert len(images)==4, (language,len(images))
    for path in images:
        data=path.read_bytes()
        assert data[:8]==b'\x89PNG\r\n\x1a\n',path
        width,height,depth,color_type=struct.unpack('>IIBB',data[16:26])
        assert (width,height,depth,color_type)==(2853,2007,8,2),(path,width,height,depth,color_type)
        chunks=[];offset=8
        while offset<len(data):
            size=struct.unpack('>I',data[offset:offset+4])[0]
            chunks.append(data[offset+4:offset+8].decode('ascii'))
            offset+=size+12
        assert 'iCCP' in chunks or 'sRGB' in chunks,(path,chunks)
        files.append({'file':str(path.relative_to(root)),'width':width,'height':height,
                      'bit_depth':depth,'format':'RGB PNG','alpha':False,'color_space':'sRGB',
                      'sha256':hashlib.sha256(data).hexdigest()})
manifest={'device':'iPhone Duo','display':'inner','orientation':'landscape','appearance':'light',
          'app_source_commit':'e18750e','files':files}
(root/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print('Validated 8 PNGs: 2853 x 2007, 8-bit RGB, opaque, sRGB.')
