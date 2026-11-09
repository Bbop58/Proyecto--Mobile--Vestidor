"""Real system-drawer tap on the OWN Android QA emulator; no push doubles.

Prerequisite: normal QA APK installed and synthetic customer's session/opt-in
active. When using notifications_journey_test first, pass --no-uninstall.
Does not log in or clear data on the Android app.
"""
import argparse,json,os,re,subprocess,time,xml.etree.ElementTree as ET
from pathlib import Path
import httpx

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--company',choices=['urbanstyle','modaexpress'],required=True)
    parser.add_argument('--remote',action='store_true')
    parser.add_argument('--serial',default='emulator-5554');args=parser.parse_args()
    if not args.serial.startswith('emulator-'):raise RuntimeError('Only an owned QA emulator is supported')
    api=('https://proyecto-backend-vestidor-production.up.railway.app/api/v1' if args.remote else 'http://127.0.0.1:58013/api/v1')
    adb=Path(os.environ['LOCALAPPDATA'])/'Android/Sdk/platform-tools/adb.exe'
    fixture=next(f for f in json.loads((Path(os.environ['TEMP'])/'fashionstore-notifications-fixtures.json').read_text()) if f['slug']==args.company)
    if not (fixture['email'].startswith('pushqa-') and fixture['email'].endswith('@example.com')):
        raise RuntimeError('Only the synthetic notification fixtures are supported')
    def command(*parts):return subprocess.check_output([str(adb),'-s',args.serial,*parts],text=True,encoding='utf8',errors='replace',timeout=30)
    if command('emu','avd','name').splitlines()[0] not in {'fashionstore_acceptance_qa','fashionstore_notifications_c2_qa'}:
        raise RuntimeError('The selected emulator is not the owned FashionStore QA AVD')
    def wait(predicate,description,seconds=100):
        deadline=time.monotonic()+seconds
        while time.monotonic()<deadline:
            result=predicate()
            if result:return result
            time.sleep(1)
        raise AssertionError(description)
    def hierarchy():
        target='/data/local/tmp/fashionstore-push-qa.xml'
        command('shell','rm','-f',target)
        try:
            command('shell','uiautomator','dump',target)
            raw=command('shell','cat',target)
            return ET.fromstring(raw[raw.index('<?xml'):])
        except (subprocess.SubprocessError,ValueError,ET.ParseError):
            return ET.Element('hierarchy')
    def tap_notice():
        tree=hierarchy()
        nodes=[n for n in tree.iter('node') if 'Tenés una actualización.' in n.attrib.get('text','')]
        if not nodes:return False
        bounds=[int(v) for v in re.findall(r'\d+',nodes[0].attrib['bounds'])]
        command('shell','input','tap',str((bounds[0]+bounds[2])//2),str((bounds[1]+bounds[3])//2));return True
    sessions=[];reservation=None;customer=None
    with httpx.Client(timeout=30) as client:
        def call(method,path,session=None,**kwargs):
            response=client.request(method,api+path,headers={'Authorization':'Bearer '+session['access_token']} if session else {},**kwargs)
            response.raise_for_status();return response.json()
        try:
            customer=call('POST','/auth/login',json={'tenant_id':fixture['tenant_id'],'email':fixture['email'],'password':'OnlyTest123!'})
            admin=call('POST','/auth/login',json={'tenant_id':fixture['tenant_id'],'email':'admin@'+args.company+'.com','password':'Password123!'})
            sessions=[customer,admin]
            command('shell','input','keyevent','KEYCODE_HOME')
            def backgrounded():
                lines=[line for line in command('shell','dumpsys','activity','activities').splitlines()
                    if 'mResumedActivity=' in line or 'topResumedActivity=' in line]
                return bool(lines) and all('com.si2proyecto.mobile' not in line for line in lines)
            wait(backgrounded,
                'App did not enter background',20)
            from datetime import datetime,timedelta,timezone
            reservation=call('POST','/reservas',customer,json={'sucursal_id':fixture['branch_id'],
                'fecha_hora_esperada':(datetime.now(timezone.utc)+timedelta(hours=3)).isoformat(),
                'items':[{'variante_id':fixture['variant_id'],'cantidad':1}]})
            call('PATCH','/reservas/'+reservation['id']+'/preparar',admin,json={})
            notice=next(n for n in call('GET','/notifications',customer) if n['type']=='RESERVATION_READY' and reservation['codigo'] in n['message'])
            def received():
                dump=command('shell','dumpsys','notification','--noredact')
                return any('com.si2proyecto.mobile' in line and notice['id'] in line for line in dump.splitlines())
            wait(received,'Firebase system notification with matching event ID did not arrive')
            command('shell','cmd','statusbar','expand-notifications')
            wait(tap_notice,'Own FashionStore notification not exposed in system drawer',30)
            # The catalog bell also has the accessible label "Notificaciones".
            # Require the actual screen's unique live-update controls instead.
            def authenticated_panel():
                labels=[n.attrib.get('text','')+' '+n.attrib.get('content-desc','') for n in hierarchy().iter('node')]
                return (any('Actualizaciones en vivo' in text for text in labels)
                    and any(reservation['codigo'] in text for text in labels))
            wait(authenticated_panel,'Tap did not open the authenticated notification history for this event',60)
            image=Path(os.environ['TEMP'])/('notifications-c2-android-'+args.company+'.png')
            command('shell','screencap','-p','/data/local/tmp/fashionstore-push-qa.png')
            command('pull','/data/local/tmp/fashionstore-push-qa.png',str(image))
            result={'company':args.company,'background_system_push':True,'matching_event_id':True,'system_drawer_tap':True,
                'notifications_screen_opened':True,'screenshot':str(image),'reservation_id':reservation['id'],'notification_id':notice['id']}
            (Path(os.environ['TEMP'])/('notifications-c2-android-'+args.company+'.json')).write_text(json.dumps(result,indent=2),encoding='utf8')
            print(json.dumps(result))
        finally:
            if reservation and customer:
                try:call('PATCH','/reservas/'+reservation['id']+'/cancelar',customer,json={})
                except httpx.HTTPError:pass
            for session in sessions:
                try:call('POST','/auth/logout',session,json={'refresh_token':session['refresh_token']})
                except httpx.HTTPError:pass

if __name__=='__main__':main()
