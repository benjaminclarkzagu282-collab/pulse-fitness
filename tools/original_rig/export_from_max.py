"""Run inside 3ds Max after opening the original T-pose MAX.

Skin extraction and full FBX export verified in Max 2027.2 on 2026-09-29.
Writes a new export folder only; does not save/overwrite the MAX scene.
See README.md for native pose review and export validation requirements.
"""
from collections import Counter
from datetime import datetime
import hashlib
import json
import math
from pathlib import Path
import uuid
from pymxs import runtime as rt

HERE=Path(__file__).resolve().parent
MESH_NAMES={'Man','Boxers','Eyelashes_bottom','Eyebrows_root','Iris_L',
    'Eyeball_L','Cornea_L','Lens_R','EyeBall_R','Lens_L','Cornea_R',
    'Tearline','Eyelashes_top','Tearduct','Iris_R','Tongue',
    'UpperGums','UpperTeeth','LowerTeeth','LowerGums'}


def dump_skin(node,skin):
    rt.select(node)
    rt.setCommandPanelTaskMode(rt.Name('modify'))
    rt.modPanel.setCurrentObject(skin)
    count=int(rt.skinOps.GetNumberBones(skin))
    # This source has contiguous Bone IDs. The sorted UI list can be empty in
    # Max 2027 during script execution; it is not the source of vertex Bone IDs.
    # Reject unexpected IDs below rather than silently remapping weights.
    ids=list(range(1,count+1))
    bones={i:str(rt.skinOps.GetBoneName(skin,i,0)) for i in ids}
    weights=[]
    for v in range(1,int(rt.skinOps.GetNumberVertices(skin))+1):
        row=[]
        for influence in range(1,int(rt.skinOps.GetVertexWeightCount(skin,v))+1):
            bone_id=int(rt.skinOps.GetVertexWeightBoneID(skin,v,influence))
            if bone_id not in bones:
                raise RuntimeError('Unexpected sparse source Bone ID '+str(bone_id))
            weight=float(rt.skinOps.GetVertexWeight(skin,v,influence))
            if not math.isfinite(weight) or weight<0:
                raise RuntimeError('Invalid source Skin weight at vertex '+str(v))
            if weight>0:row.append([bone_id,weight])
        if not row or abs(sum(w for _,w in row)-1)>0.002:
            raise RuntimeError('Unbound or non-normalized source vertex '+str(v))
        weights.append(row)
    try:
        dq_weights=[float(rt.skinOps.getVertexDQWeight(skin,v))
                    for v in range(1,len(weights)+1)]
        dq_read_error=None
    except Exception as error:
        dq_weights=None
        dq_read_error=str(error)
    return {'node':str(node.name),'vertex_count':len(weights),
            'bones':bones,'weights_by_vertex_1_based':weights,
            'dq_weights':dq_weights,'dq_read_error':dq_read_error,
            'dq_enabled':bool(skin.enableDQ) if rt.isProperty(skin,'enableDQ') else None}


def main(destination=None):
    source=Path(str(rt.maxFilePath))/str(rt.maxFileName)
    if not source.is_file() or 'tpose' not in source.name.lower():
        raise RuntimeError('Open the original T-pose MAX in 3ds Max first.')
    expected=json.loads((HERE/'expected_source.json').read_text(encoding='utf-8'))
    body=rt.getNodeByName('Man')
    if body is None:raise RuntimeError('Man mesh not found.')
    skins=[m for m in body.modifiers if rt.classOf(m)==rt.Skin]
    if len(skins)!=1:raise RuntimeError('Man must retain exactly one original Skin modifier.')
    if destination is None:
        destination=rt.getSavePath(caption='Choose a folder for the original-rig export')
    if not destination:return
    out=Path(str(destination))/('pulse-original-rig-'+datetime.now().strftime('%Y%m%d-%H%M%S')+'-'+uuid.uuid4().hex[:6])
    out.mkdir()
    before=hashlib.sha256(source.read_bytes()).hexdigest()
    previous_selection=list(rt.selection)
    previous_panel=rt.getCommandPanelTaskMode()
    previous_modifier=rt.modPanel.getCurrentObject()
    pushed=False
    try:
        audits=[]
        for node in list(rt.objects):
            if str(node.name) not in MESH_NAMES:continue
            for modifier in node.modifiers:
                if rt.classOf(modifier)==rt.Skin:audits.append(dump_skin(node,modifier))
        (out/'source-skin-audits.json').write_text(
            json.dumps(audits,ensure_ascii=False),encoding='utf-8')
        body_audit=next(a for a in audits if a['node']=='Man')
        actual=Counter(body_audit['bones'].values())
        if actual!=Counter(expected['expected_skin_bones']):
            raise RuntimeError('Source Skin bones differ from the inspected original rig.')
        # Select actual character meshes and all Skin bone nodes, including duplicates.
        names=set(MESH_NAMES)
        for audit in audits:names.update(audit['bones'].values())
        selected=[n for n in list(rt.objects) if str(n.name) in names]
        selected_handles={int(rt.getHandleByAnim(n)) for n in selected}
        for node in list(selected):
            parent=node.parent
            while parent is not None:
                handle=int(rt.getHandleByAnim(parent))
                if handle not in selected_handles:selected.append(parent);selected_handles.add(handle)
                parent=parent.parent
        rt.pluginManager.loadClass(rt.FBXEXP)
        rt.FBXExporterSetParam('PushSettings');pushed=True
        rt.FBXExporterSetParam('ResetExport')
        settings={'Skin':True,'Shape':True,'Animation':True,
            'BakeAnimation':True,'BakeResampleAnimation':True,
            'BakeFrameStart':int(rt.animationRange.start.frame),
            'BakeFrameEnd':int(rt.animationRange.end.frame),'BakeFrameStep':1,
            'CAT2HIK':False,'Cameras':False,'Lights':False,
            'EmbedTextures':True,'ASCII':False,'SmoothMeshExport':True,
            'ShowWarnings':True,'GenerateLog':True,'UpAxis':'Y'}
        setting_results={}
        for key,value in settings.items():
            status=rt.FBXExporterSetParam(key,value)
            # Max 2027 returns True, despite older docs describing "OK".
            # Verify the resulting value, including False settings.
            actual=rt.FBXExporterGetParam(key)
            matches=(str(actual).lower()==value.lower()) if isinstance(value,str) else actual==value
            setting_results[key]={'requested':value,'status':str(status),
                                  'actual':str(actual),'matches':matches}
            (out/'fbx-settings.json').write_text(json.dumps(setting_results,indent=2))
            if not matches:
                raise RuntimeError('FBX setting verification failed: '+key+' readback='+str(actual))
        rt.select(rt.Array(*selected))
        fbx=out/'original-rig.fbx'
        result=rt.exportFile(str(fbx),rt.Name('noPrompt'),selectedOnly=True,using=rt.FBXEXP)
        if not result or not fbx.is_file() or fbx.stat().st_size==0:
            raise RuntimeError('FBX export failed. Check the native FBX warnings/log.')
        if hashlib.sha256(source.read_bytes()).hexdigest()!=before:
            raise RuntimeError('Original MAX hash changed unexpectedly.')
        manifest={'status':'exported_pending_import_and_pose_review',
            'source_name':source.name,'source_sha256':before,
            'source_disk_unchanged':True,'fbx_sha256':hashlib.sha256(fbx.read_bytes()).hexdigest(),
            'fbx_settings':settings,'fbx_setting_readbacks':setting_results,
            'skin_audits':audits,'ready_for_app':False,
            'native_pose_review_completed':False}
        (out/'max-export-audit.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
        print('Exported for review, NOT approved for app: '+str(out))
    except Exception as error:
        (out/'EXPORT_FAILED.txt').write_text(str(error),encoding='utf-8')
        raise
    finally:
        if pushed:rt.FBXExporterSetParam('PopSettings')
        rt.select(rt.Array(*previous_selection))
        if previous_modifier is not None:
            try:rt.modPanel.setCurrentObject(previous_modifier)
            except Exception:pass
        rt.setCommandPanelTaskMode(previous_panel)

if __name__=='__main__':main()
