"""Read-only USD checks for archive art, original geometry, and moving clearance."""
from pathlib import Path
import hashlib
import json
import math
import subprocess
import tempfile
import numpy as np
from pxr import Usd, UsdGeom

ROOT=Path(__file__).resolve().parents[2]
ART=ROOT/'Endless Runner/ArtAssets'
KEYS=['emberRun','summitStep','lowCrawl','ghostGlass','stormPass','crystalCave','vectorFoundry','orbitGate']


def geometry(stage):
    result={}
    for prim in stage.Traverse():
        if not prim.IsA(UsdGeom.Mesh):continue
        mesh=UsdGeom.Mesh(prim)
        result[prim.GetName()]=(np.asarray(mesh.GetPointsAttr().Get(),dtype=np.float64),
                               list(mesh.GetFaceVertexCountsAttr().Get()),
                               list(mesh.GetFaceVertexIndicesAttr().Get()))
    return result


def rotation(axis,angle):
    c,s=math.cos(angle),math.sin(angle)
    if axis=='y':return np.array([[c,0,s],[0,1,0],[-s,0,c]])
    return np.array([[c,-s,0],[s,c,0],[0,0,1]])


def check():
    summary={}
    with tempfile.TemporaryDirectory(prefix='slipframe-clue-check-') as directory:
        for key in KEYS:
            name='environment_'+key
            old=Path(directory)/(name+'.usdz')
            old.write_bytes(subprocess.check_output(['git','show','HEAD:Endless Runner/ArtAssets/'+name+'.usdz'],cwd=ROOT))
            baseline=geometry(Usd.Stage.Open(str(old)))
            current=geometry(Usd.Stage.Open(str(ART/(name+'.usdz'))))
            preserved=0
            remaining=dict(current)
            for mesh,(points,counts,indices) in baseline.items():
                if '__story_' in mesh:continue
                matches=[n for n,g in remaining.items() if points.shape==g[0].shape
                         and counts==g[1] and indices==g[2]
                         and np.allclose(points,g[0],atol=1e-6,rtol=0)]
                assert matches,(name,'original geometry missing or changed',mesh)
                remaining.pop(matches[0]);preserved+=1
            clues={n:g for n,g in current.items() if '__story_' in n}
            assert clues,(name,'no exported environment details')
            assert not any('__story_echo' in n or '__story_arm' in n for n in current),(name,'humanoid remains')
            minimum=float('inf')
            for mesh,(points,counts,indices) in clues.items():
                triangles=points[np.asarray(indices).reshape(-1,3),0]
                assert np.all((triangles.min(axis=1)>=1.85-1e-5)|(triangles.max(axis=1)<=-1.85+1e-5)),(name,'face enters course',mesh)
                role=mesh.split('__')[1]
                for progress in np.linspace(0,1,21):
                    transformed=points
                    if role=='story_hatch':
                        pivot=np.array([3.27,.04,-9.51]);r=rotation('y',progress*1.12)
                        transformed=(points-pivot)@r.T+pivot
                    elif role=='story_fan':
                        pivot=np.array([2.7,.05,-9.06]);r=rotation('z',progress*math.tau)
                        transformed=(points-pivot)@r.T+pivot
                    minimum=min(minimum,float(np.min(np.abs(transformed[:,0]))))
                    assert np.all(np.abs(transformed[:,0])>=1.85-1e-5),(name,'animation enters course',mesh,progress)
            summary[key]={'originalMeshesPreserved':preserved,'clueMeshes':len(clues),
                          'minimumMovingClearanceMeters':round(minimum,3)}
    (ROOT/'Art/Previews/story-clue-validation.json').write_text(json.dumps(summary,indent=2)+'\n')
    print('STORY CLUE VALIDATION PASSED\n'+json.dumps(summary,indent=2))


if __name__=='__main__':check()
