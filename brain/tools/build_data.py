#!/usr/bin/env python3
"""Build the compact volumes and label tables that brain/index.html loads.

Everything comes from TemplateFlow's MNI152NLin2009cAsym template (the ICBM
2009c nonlinear asymmetric average, the space fMRIPrep writes into), plus the
FreeSurfer colour table for the aseg and DKT labels. Each label volume is
written as gzipped NIfTI on the template's 1 mm grid. The tissue maps stay at
2 mm, so the viewer resamples them the same way it would a dropped-in map.

The T1 and T2 backgrounds are the exception: as 8-bit NIfTI they gzip to about
5 MB each, because deflate does badly on smooth gradients. They ship instead as
a mosaic of axial slices in one lossy WebP (about 0.9 MB, mean error under 1.5
grey levels inside the brain), which the browser decodes natively.

    pip install nibabel numpy scipy pillow
    python3 build_data.py --cache /tmp/tf --out ../data

Files already in the cache are not downloaded again.
"""
import argparse, colorsys, csv, gzip, json, os, re, shutil, urllib.request

import nibabel as nib
import numpy as np
from PIL import Image
from scipy import ndimage

TF = 'https://templateflow.s3.amazonaws.com'
T09 = 'tpl-MNI152NLin2009cAsym/tpl-MNI152NLin2009cAsym_'
T6 = 'tpl-MNI152NLin6Asym/tpl-MNI152NLin6Asym_'
FS_LUT = 'https://raw.githubusercontent.com/freesurfer/freesurfer/dev/distribution/FreeSurferColorLUT.txt'

SOURCES = {
    't1': TF + '/' + T09 + 'res-01_T1w.nii.gz',
    't2': TF + '/' + T09 + 'res-01_T2w.nii.gz',
    'mask': TF + '/' + T09 + 'res-01_desc-brain_mask.nii.gz',
    'hoc': TF + '/' + T09 + 'res-01_atlas-HOCPAL_desc-th25_dseg.nii.gz',
    'hoc_tsv': TF + '/' + T6 + 'atlas-HOCPAL_dseg.tsv',
    'hos': TF + '/' + T09 + 'res-01_atlas-HOSPA_desc-th25_dseg.nii.gz',
    'hos_tsv': TF + '/' + T6 + 'atlas-HOSPA_dseg.tsv',
    'sch7': TF + '/' + T09 + 'res-01_atlas-Schaefer2018_desc-400Parcels7Networks_dseg.nii.gz',
    'sch7_tsv': TF + '/' + T09 + 'atlas-Schaefer2018_desc-400Parcels7Networks_dseg.tsv',
    'sch17': TF + '/' + T09 + 'res-01_atlas-Schaefer2018_desc-400Parcels17Networks_dseg.nii.gz',
    'sch17_tsv': TF + '/' + T09 + 'atlas-Schaefer2018_desc-400Parcels17Networks_dseg.tsv',
    'aseg': TF + '/' + T09 + 'res-01_seg-aseg_dseg.nii.gz',
    'dkt': TF + '/' + T09 + 'res-02_desc-DKT31_dseg.nii.gz',
    'thal': TF + '/' + T09 + 'res-01_atlas-MIAL67ThalamicNuclei_dseg.nii.gz',
    'thal_tsv': TF + '/' + T09 + 'atlas-MIAL67ThalamicNuclei_dseg.tsv',
    'gm': TF + '/' + T09 + 'res-02_label-GM_probseg.nii.gz',
    'wm': TF + '/' + T09 + 'res-02_label-WM_probseg.nii.gz',
    'csf': TF + '/' + T09 + 'res-02_label-CSF_probseg.nii.gz',
    'fslut': FS_LUT,
}


def fetch(cache, key):
    url = SOURCES[key]
    path = os.path.join(cache, os.path.basename(url))
    if not os.path.exists(path):
        print('  downloading', os.path.basename(url))
        with urllib.request.urlopen(url) as r, open(path + '.part', 'wb') as f:
            shutil.copyfileobj(r, f)
        os.replace(path + '.part', path)
    return path


def load(cache, key):
    img = nib.load(fetch(cache, key))
    return img, np.asanyarray(img.dataobj)


def read_tsv(path):
    with open(path, newline='') as f:
        return list(csv.DictReader(f, delimiter='\t'))


def save(out, name, data, affine, slope=None):
    """Write a NIfTI-1 file with sform/qform set to MNI152 and gzip -9."""
    img = nib.Nifti1Image(data, affine)
    img.header.set_data_dtype(data.dtype)
    img.header.set_xyzt_units('mm')
    img.set_sform(affine, code=4)
    img.set_qform(affine, code=4)
    raw = os.path.join(out, name[:-3])
    nib.save(img, raw)
    if slope is not None:
        # nibabel resets scl_slope for integer arrays; patch the header bytes.
        with open(raw, 'r+b') as f:
            f.seek(112)
            f.write(np.array([slope, 0.0], dtype='<f4').tobytes())
    with open(raw, 'rb') as src, open(os.path.join(out, name), 'wb') as f, \
            gzip.GzipFile(fileobj=f, mode='wb', compresslevel=9, mtime=0, filename='') as dst:
        shutil.copyfileobj(src, dst)
    os.remove(raw)
    print(f'  {name:22s} {os.path.getsize(os.path.join(out, name)) / 1024:8.0f} KB')


def save_mosaic(out, name, vol, quality=92):
    """Tile the axial slices of a uint8 volume into one greyscale WebP.

    Slice k sits at tile (k // cols, k % cols); within a tile, image rows run
    along y (row 0 is voxel j = 0) and columns along x.
    """
    X, Y, Z = vol.shape
    cols = int(np.ceil(np.sqrt(Z)))
    rows = int(np.ceil(Z / cols))
    m = np.zeros((rows * Y, cols * X), np.uint8)
    for k in range(Z):
        r, c = divmod(k, cols)
        m[r * Y:(r + 1) * Y, c * X:(c + 1) * X] = vol[:, :, k].T
    Image.fromarray(m).save(os.path.join(out, name), 'WEBP', quality=quality, method=6)
    print(f'  {name:22s} {os.path.getsize(os.path.join(out, name)) / 1024:8.0f} KB')
    return cols


def hexcol(rgb):
    return '#%02x%02x%02x' % tuple(int(round(c)) for c in rgb)


def palette(n, offset=0):
    """Distinct colours: golden-angle hues with alternating lightness."""
    cols = []
    for i in range(n):
        h = ((i + offset) * 0.381966) % 1.0
        l = (0.52, 0.64, 0.44)[i % 3]
        s = (0.70, 0.60, 0.80)[(i // 3) % 3]
        cols.append(hexcol([c * 255 for c in colorsys.hls_to_rgb(h, l, s)]))
    return cols


def jitter(hexc, k):
    """Shift a network colour a little per parcel so neighbours stay apart."""
    r, g, b = (int(hexc[i:i + 2], 16) / 255 for i in (1, 3, 5))
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    h = (h + (((k * 37) % 23) - 11) / 360) % 1.0
    l = min(0.82, max(0.22, l + (((k * 53) % 19) - 9) / 70))
    return hexcol([c * 255 for c in colorsys.hls_to_rgb(h, l, s)])


def side_key(name):
    """'Left Insular Cortex' -> 'Insular Cortex', so homologues share a colour."""
    return re.sub(r'^(left|right)[ -]|^(lh|rh)[ -]|-(lh|rh)-', '', name, flags=re.I).strip()


def compact(vol, codes):
    """Map the label codes in vol to 1..N in the given order."""
    lut = np.zeros(int(vol.max()) + 1, dtype=np.uint16)
    for i, c in enumerate(codes, 1):
        lut[c] = i
    return lut[vol.astype(np.int64)]


def check_sides(vol, labels, affine):
    """Assert that every 'Left' label sits left of the midline, and so on."""
    idx = np.nonzero(vol)
    lab = vol[idx]
    x = affine[0, 0] * idx[0] + affine[0, 3]
    sums = np.bincount(lab, weights=x, minlength=len(labels) + 1)
    counts = np.bincount(lab, minlength=len(labels) + 1)
    for i, name, *_ in labels:
        if counts[i] == 0:
            raise SystemExit(f'label {i} {name!r} is empty')
        mean_x = sums[i] / counts[i]
        n = name.lower()
        if n.startswith('left') and mean_x > 0 or n.startswith('right') and mean_x < 0:
            raise SystemExit(f'label {i} {name!r} has mean x {mean_x:.1f}')


# FSL's HarvardOxford-Cortical.xml order. TemplateFlow's TSVs drop every row
# whose name contains a comma, so the full list lives here and is checked
# against the rows that did survive.
HO_CORTICAL = [
    'Frontal Pole', 'Insular Cortex', 'Superior Frontal Gyrus', 'Middle Frontal Gyrus',
    'Inferior Frontal Gyrus, pars triangularis', 'Inferior Frontal Gyrus, pars opercularis',
    'Precentral Gyrus', 'Temporal Pole', 'Superior Temporal Gyrus, anterior division',
    'Superior Temporal Gyrus, posterior division', 'Middle Temporal Gyrus, anterior division',
    'Middle Temporal Gyrus, posterior division', 'Middle Temporal Gyrus, temporooccipital part',
    'Inferior Temporal Gyrus, anterior division', 'Inferior Temporal Gyrus, posterior division',
    'Inferior Temporal Gyrus, temporooccipital part', 'Postcentral Gyrus', 'Superior Parietal Lobule',
    'Supramarginal Gyrus, anterior division', 'Supramarginal Gyrus, posterior division', 'Angular Gyrus',
    'Lateral Occipital Cortex, superior division', 'Lateral Occipital Cortex, inferior division',
    'Intracalcarine Cortex', 'Frontal Medial Cortex',
    'Juxtapositional Lobule Cortex (formerly Supplementary Motor Cortex)', 'Subcallosal Cortex',
    'Paracingulate Gyrus', 'Cingulate Gyrus, anterior division', 'Cingulate Gyrus, posterior division',
    'Precuneous Cortex', 'Cuneal Cortex', 'Frontal Orbital Cortex', 'Parahippocampal Gyrus, anterior division',
    'Parahippocampal Gyrus, posterior division', 'Lingual Gyrus', 'Temporal Fusiform Cortex, anterior division',
    'Temporal Fusiform Cortex, posterior division', 'Temporal Occipital Fusiform Cortex',
    'Occipital Fusiform Gyrus', 'Frontal Operculum Cortex', 'Central Opercular Cortex',
    'Parietal Operculum Cortex', 'Planum Polare', "Heschl's Gyrus (includes H1 and H2)", 'Planum Temporale',
    'Supracalcarine Cortex', 'Occipital Pole',
]

NET7 = [('Vis', 'Visual'), ('SomMot', 'Somatomotor'), ('DorsAttn', 'Dorsal attention'),
        ('SalVentAttn', 'Salience / ventral attention'), ('Limbic', 'Limbic'),
        ('Cont', 'Frontoparietal control'), ('Default', 'Default mode')]
NET17 = [('VisCent', 'Visual central'), ('VisPeri', 'Visual peripheral'),
         ('SomMotA', 'Somatomotor A'), ('SomMotB', 'Somatomotor B'),
         ('DorsAttnA', 'Dorsal attention A'), ('DorsAttnB', 'Dorsal attention B'),
         ('SalVentAttnA', 'Salience / ventral attention A'), ('SalVentAttnB', 'Salience / ventral attention B'),
         ('LimbicA', 'Limbic A (temporal pole)'), ('LimbicB', 'Limbic B (orbitofrontal)'),
         ('ContA', 'Control A'), ('ContB', 'Control B'), ('ContC', 'Control C'),
         ('DefaultA', 'Default A'), ('DefaultB', 'Default B'), ('DefaultC', 'Default C'),
         ('TempPar', 'Temporal parietal')]
SUBREGION = {
    'PFC': 'prefrontal', 'PFCl': 'lateral prefrontal', 'PFCv': 'ventral prefrontal',
    'PFCm': 'medial prefrontal', 'PFCd': 'dorsal prefrontal', 'PFCmp': 'medial posterior prefrontal',
    'PFCdPFCm': 'dorsal/medial prefrontal', 'Par': 'parietal', 'Temp': 'temporal', 'PCC': 'posterior cingulate',
    'pCun': 'precuneus', 'Cinga': 'anterior cingulate', 'Cing': 'cingulate', 'FEF': 'frontal eye field',
    'PrCv': 'ventral precentral', 'PrCd': 'dorsal precentral', 'PrC': 'precentral', 'PostC': 'postcentral',
    'Ins': 'insula', 'ParOper': 'parietal operculum', 'FrOper': 'frontal operculum',
    'FrOperIns': 'frontal operculum / insula', 'OFC': 'orbitofrontal', 'TempPole': 'temporal pole',
    'Med': 'medial', 'ExStr': 'extrastriate', 'ExStrInf': 'inferior extrastriate',
    'ExStrSup': 'superior extrastriate', 'Striate': 'striate', 'StriCal': 'striate / calcarine',
    'SPL': 'superior parietal lobule', 'IPL': 'inferior parietal lobule', 'IPS': 'intraparietal sulcus',
    'TempOcc': 'temporo-occipital', 'Aud': 'auditory', 'Rsp': 'retrosplenial', 'RSC': 'retrosplenial',
    'PHC': 'parahippocampal', 'Ent': 'entorhinal', 'SomMotA': '', 'Cent': 'central', 'S2': 'secondary somatosensory',
    'Vent': 'ventral', 'ParMed': 'medial parietal', 'FrMed': 'medial frontal', 'Precuneus': 'precuneus',
    'PostTemp': 'posterior temporal', 'AntTemp': 'anterior temporal', 'Precentral': 'precentral',
    'ParOcc': 'parieto-occipital', 'Cingm': 'mid-cingulate', 'Cingp': 'posterior cingulate', 'pCunPCC': 'precuneus / PCC',
    'Post': 'posterior', 'TempOccPar': 'temporo-occipito-parietal', 'PFCld': 'dorsolateral prefrontal',
    'PFClv': 'ventrolateral prefrontal',
}
DK_NAMES = {
    'bankssts': 'Banks of superior temporal sulcus', 'caudalanteriorcingulate': 'Caudal anterior cingulate',
    'caudalmiddlefrontal': 'Caudal middle frontal', 'cuneus': 'Cuneus', 'entorhinal': 'Entorhinal',
    'fusiform': 'Fusiform', 'inferiorparietal': 'Inferior parietal', 'inferiortemporal': 'Inferior temporal',
    'isthmuscingulate': 'Isthmus cingulate', 'lateraloccipital': 'Lateral occipital',
    'lateralorbitofrontal': 'Lateral orbitofrontal', 'lingual': 'Lingual',
    'medialorbitofrontal': 'Medial orbitofrontal', 'middletemporal': 'Middle temporal',
    'parahippocampal': 'Parahippocampal', 'paracentral': 'Paracentral', 'parsopercularis': 'Pars opercularis',
    'parsorbitalis': 'Pars orbitalis', 'parstriangularis': 'Pars triangularis', 'pericalcarine': 'Pericalcarine',
    'postcentral': 'Postcentral', 'posteriorcingulate': 'Posterior cingulate', 'precentral': 'Precentral',
    'precuneus': 'Precuneus', 'rostralanteriorcingulate': 'Rostral anterior cingulate',
    'rostralmiddlefrontal': 'Rostral middle frontal', 'superiorfrontal': 'Superior frontal',
    'superiorparietal': 'Superior parietal', 'superiortemporal': 'Superior temporal',
    'supramarginal': 'Supramarginal', 'frontalpole': 'Frontal pole', 'temporalpole': 'Temporal pole',
    'transversetemporal': 'Transverse temporal', 'insula': 'Insula',
}


def schaefer_name(raw, nets):
    # 7Networks_LH_Default_PFC_1 -> "Left · Default mode · prefrontal 1"
    parts = raw.split('_')
    hemi = 'Left' if parts[1] == 'LH' else 'Right'
    net = dict(nets)[parts[2]]
    rest = parts[3:]
    num = rest.pop() if rest and rest[-1].isdigit() else ''
    sub = ' '.join(SUBREGION.get(p, p) for p in rest if SUBREGION.get(p, p))
    tail = (sub + ' ' + num).strip() if sub else ('parcel ' + num if num else '')
    return f'{hemi} · {net}' + (f' · {tail}' if tail else '')


def aseg_name(fs):
    n = fs.replace('_', ' ').replace('-', ' ')
    n = re.sub(r'\bInf Lat Vent\b', 'Inferior Lateral Ventricle', n)
    n = re.sub(r'\bVentralDC\b', 'Ventral DC', n)
    n = re.sub(r'\bCC\b', 'Corpus Callosum', n)
    n = re.sub(r'\bMid ', 'Mid-', n)
    n = n.replace('Accumbens area', 'Accumbens').replace('vessel', 'Vessel').replace('choroid plexus', 'Choroid Plexus')
    n = n.replace('3rd', 'Third').replace('4th', 'Fourth').replace('Brain Stem', 'Brainstem')
    return n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--cache', required=True)
    ap.add_argument('--out', required=True)
    a = ap.parse_args()
    os.makedirs(a.cache, exist_ok=True)
    os.makedirs(a.out, exist_ok=True)
    nib.openers.Opener.default_compresslevel = 9

    t1img, t1 = load(a.cache, 't1')
    aff = t1img.affine
    assert np.allclose(aff[:3, :3], np.eye(3)), 'expected a 1 mm RAS grid'
    shape = t1.shape
    meta = {'space': 'MNI152NLin2009cAsym', 'backgrounds': [], 'atlases': [], 'overlays': []}

    print('backgrounds')
    _, mask = load(a.cache, 'mask')
    save(a.out, 'brainmask.nii.gz', (mask > 0).astype(np.uint8), aff)
    meta['mask'] = 'brainmask.nii.gz'
    meta['grid'] = {'dims': list(shape), 'origin': aff[:3, 3].tolist(), 'zooms': [1, 1, 1]}
    for key, name in (('t1', 'T1-weighted'), ('t2', 'T2-weighted')):
        img, v = load(a.cache, key)
        assert v.shape == shape and np.allclose(img.affine, aff)
        v = v.astype(np.float32)
        hi = np.percentile(v[mask > 0], 99.5)
        u8 = np.clip(np.round(v / hi * 255), 0, 255).astype(np.uint8)
        # The template sits on a box of ~7% grey noise. Zero everything outside
        # the head; it costs bytes and shows as a grey rectangle.
        head = ndimage.binary_fill_holes(ndimage.gaussian_filter(v, 2) > 0.1 * hi)
        u8[~ndimage.binary_dilation(head, iterations=2)] = 0
        cols = save_mosaic(a.out, f'{key}.webp', u8)
        meta['backgrounds'].append({'id': key, 'name': name, 'file': f'{key}.webp', 'cols': cols})

    atlases = []

    def add(aid, name, short, vol, labels, info):
        """Save an atlas and describe its labels.

        Each label becomes {v, name, color, raw?, n, at}: its value in the
        volume, display name, colour, the source's own name where it differs,
        voxel count (1 voxel = 1 mm^3), and its deepest voxel, the point
        furthest from the region's edge, which is where search jumps to.
        """
        assert vol.shape == shape
        dt = np.uint8 if len(labels) < 256 else np.uint16
        vol = vol.astype(dt)
        check_sides(vol.astype(np.int64), labels, aff)
        boxes = ndimage.find_objects(vol)
        counts = np.bincount(vol.ravel(), minlength=len(boxes) + 1)
        out = []
        for v, lname, col, *raw in labels:
            box = boxes[v - 1]
            edt = ndimage.distance_transform_edt(np.pad(vol[box] == v, 1))[1:-1, 1:-1, 1:-1]
            pos = np.unravel_index(np.argmax(edt), edt.shape)
            o = {'v': v, 'name': lname, 'color': col}
            if raw and raw[0] != lname:
                o['raw'] = raw[0]
            o['n'] = int(counts[v])
            o['at'] = [int(box[d].start + pos[d]) for d in range(3)]
            out.append(o)
        save(a.out, f'{aid}.nii.gz', vol, aff)
        atlases.append(dict(id=aid, name=name, short=short, file=f'{aid}.nii.gz', labels=out, **info))

    HO_INFO = dict(
        source='Harvard Center for Morphometric Analysis, via FSL and TemplateFlow',
        cite='Desikan et al. 2006; Frazier et al. 2005; Makris et al. 2006; Goldstein et al. 2007',
        url='https://fsl.fmrib.ox.ac.uk/fsl/fslwiki/Atlases',
        license='FSL licence (non-commercial)')

    print('atlases')
    # Harvard-Oxford cortical, lateralised. Volume value v is index v-1, and
    # the lateralised indices alternate left, right through the 48 regions.
    _, v = load(a.cache, 'hoc')
    names = [side + ' ' + n for n in HO_CORTICAL for side in ('Left', 'Right')]
    for r in read_tsv(fetch(a.cache, 'hoc_tsv')):
        assert names[int(r['index'])] == r['name'].strip(), r
    keys = list(dict.fromkeys(side_key(n) for n in names))
    pal = dict(zip(keys, palette(len(keys))))
    add('ho_cort', 'Harvard-Oxford cortical', 'HO cortical', v,
        [[i + 1, n, pal[side_key(n)]] for i, n in enumerate(names)],
        dict(group='Anatomical', note='Maximum-probability labels, thresholded at 25%.', **HO_INFO))

    # Harvard-Oxford subcortical. Volume value v is TSV row v (row 0 is background).
    _, v = load(a.cache, 'hos')
    rows = read_tsv(fetch(a.cache, 'hos_tsv'))[1:]
    names = [r['name'].strip().replace('Ventrical', 'Ventricle') for r in rows]
    keys = list(dict.fromkeys(side_key(n) for n in names))
    pal = dict(zip(keys, palette(len(keys), offset=5)))
    add('ho_sub', 'Harvard-Oxford subcortical', 'HO subcortical', v,
        [[int(r['index']), n, pal[side_key(n)]] for r, n in zip(rows, names)],
        dict(group='Anatomical', note='Maximum-probability labels, thresholded at 25%.', **HO_INFO))

    SCH_INFO = dict(source='Thomas Yeo lab (CBIG), via TemplateFlow',
                    url='https://github.com/ThomasYeoLab/CBIG/tree/master/stable_projects/brain_parcellation/Schaefer2018_LocalGlobal',
                    license='MIT')

    # Schaefer 400, 7 networks, plus the network map it implies.
    _, s7 = load(a.cache, 'sch7')
    rows7 = read_tsv(fetch(a.cache, 'sch7_tsv'))
    netcol = {}
    for r in rows7:
        netcol.setdefault(r['name'].split('_')[2], r['color'])
    labels, per_net = [], {}
    for r in rows7:
        net = r['name'].split('_')[2]
        k = per_net[net] = per_net.get(net, 0) + 1
        labels.append([int(r['index']), schaefer_name(r['name'], NET7), jitter(r['color'], k), r['name']])
    add('schaefer400', 'Schaefer 2018, 400 parcels', 'Schaefer 400', s7, labels,
        dict(group='Functional', cite='Schaefer et al. 2018, Cerebral Cortex',
             note='Local-global functional parcellation from resting-state fMRI, ordered by the Yeo 7 networks.',
             **SCH_INFO))

    lut = np.zeros(401, dtype=np.uint8)
    order = [n for n, _ in NET7]
    for r in rows7:
        lut[int(r['index'])] = order.index(r['name'].split('_')[2]) + 1
    add('yeo7', 'Yeo 7 networks (via Schaefer 400)', 'Yeo 7', lut[s7.astype(np.int64)],
        [[i + 1, full, netcol[n]] for i, (n, full) in enumerate(NET7)],
        dict(group='Functional', cite='Yeo et al. 2011, J Neurophysiol; Schaefer et al. 2018',
             note='The Schaefer 400 parcels grouped by the network each is assigned to.', **SCH_INFO))

    _, s17 = load(a.cache, 'sch17')
    rows17 = read_tsv(fetch(a.cache, 'sch17_tsv'))

    def net17(raw):
        # The 17-network table names both limbic networks "Limbic" and tells
        # them apart by subregion: temporal pole is A, orbitofrontal is B.
        p = raw.split('_')
        if p[2] == 'Limbic':
            return 'LimbicA' if p[3] == 'TempPole' else 'LimbicB'
        return p[2]

    netcol17 = {}
    for r in rows17:
        netcol17.setdefault(net17(r['name']), r['color'])
    lut = np.zeros(401, dtype=np.uint8)
    order = [n for n, _ in NET17]
    for r in rows17:
        lut[int(r['index'])] = order.index(net17(r['name'])) + 1
    add('yeo17', 'Yeo 17 networks (via Schaefer 400)', 'Yeo 17', lut[s17.astype(np.int64)],
        [[i + 1, full, netcol17[n]] for i, (n, full) in enumerate(NET17)],
        dict(group='Functional', cite='Yeo et al. 2011, J Neurophysiol; Schaefer et al. 2018',
             note='The 17-network Schaefer 400 parcels grouped by network.', **SCH_INFO))

    # FreeSurfer colour table, for aseg and DKT.
    fslut = {}
    for line in open(fetch(a.cache, 'fslut')):
        p = line.split()
        if len(p) >= 5 and p[0].isdigit():
            fslut[int(p[0])] = (p[1], hexcol([int(p[2]), int(p[3]), int(p[4])]))

    _, v = load(a.cache, 'aseg')
    v = v.astype(np.int64)
    codes = [int(c) for c in np.unique(v) if c]
    add('aseg', 'FreeSurfer aseg', 'aseg', compact(v, codes),
        [[i, aseg_name(fslut[c][0]), fslut[c][1], f'{fslut[c][0]} ({c})'] for i, c in enumerate(codes, 1)],
        dict(group='Anatomical', source='FreeSurfer run on the template, via TemplateFlow',
             cite='Fischl et al. 2002, Neuron', url='https://surfer.nmr.mgh.harvard.edu/',
             license='Derived with FreeSurfer',
             note='Automatic subcortical segmentation of the template itself.'))

    # DKT: 2 mm source. Upsample each cortical label's indicator trilinearly
    # and take the argmax, which gives smoother edges than nearest neighbour.
    dimg, d = load(a.cache, 'dkt')
    d = np.round(d).astype(np.int64)
    m = np.linalg.inv(dimg.affine) @ aff
    assert np.allclose(m[:3, :3], np.diag(np.diag(m[:3, :3])))
    zoom, off = np.diag(m[:3, :3]), m[:3, 3]
    codes = [int(c) for c in np.unique(d) if c >= 1000]
    best = ndimage.affine_transform((d < 1000).astype(np.float32), zoom, off, output_shape=shape, order=1)
    lab = np.zeros(shape, dtype=np.uint8)
    for i, c in enumerate(codes, 1):
        p = ndimage.affine_transform((d == c).astype(np.float32), zoom, off, output_shape=shape, order=1)
        win = p > best
        lab[win], best[win] = i, p[win]
    labels = []
    for i, c in enumerate(codes, 1):
        fs, col = fslut[c]
        hemi = 'Left' if '-lh-' in fs else 'Right'
        labels.append([i, f'{hemi} {DK_NAMES[fs.split("-")[-1]].lower()}', col, f'{fs} ({c})'])
    for l in labels:
        l[1] = l[1][0].upper() + l[1][1:]
    add('dkt', 'Desikan-Killiany-Tourville (DKT31)', 'DKT', lab, labels,
        dict(group='Anatomical', source='Mindboggle DKT protocol, via TemplateFlow',
             cite='Klein & Tourville 2012, Front Neurosci', url='https://mindboggle.info/',
             license='Mindboggle terms (see source)',
             note='Cortical labels only, upsampled from 2 mm.'))

    _, v = load(a.cache, 'thal')
    rows = read_tsv(fetch(a.cache, 'thal_tsv'))
    labels = []
    for r in rows:
        hemi = 'Left' if '-lh-' in r['name'] else 'Right'
        nuc = r['name'].split('-', 2)[2].replace('-', ' ')
        labels.append([int(r['index']), f'{hemi} thalamus · {nuc}', r['color'], r['name']])
    add('thalamus', 'Thalamic nuclei (Najdenovska 2018)', 'Thalamus', v, labels,
        dict(group='Anatomical', source='MIAL, via TemplateFlow',
             cite='Najdenovska et al. 2018, Sci Data', url='https://doi.org/10.1038/sdata.2018.270',
             license='CC BY 4.0', note='Diffusion-based maximum-probability map of 7 nuclei groups per side.'))

    meta['atlases'] = atlases

    print('overlays')
    for key, name, cmap in (('gm', 'Grey matter probability', 'hot'),
                            ('wm', 'White matter probability', 'winter'),
                            ('csf', 'CSF probability', 'cool')):
        img, v = load(a.cache, key)
        u8 = np.clip(np.round(v * 255), 0, 255).astype(np.uint8)
        save(a.out, f'{key}.nii.gz', u8, img.affine, slope=1 / 255)
        meta['overlays'].append({'id': key, 'name': name, 'file': f'{key}.nii.gz', 'cmap': cmap,
                                 'min': 0.3, 'max': 1.0})

    with open(os.path.join(a.out, 'atlases.json'), 'w') as f:
        json.dump(meta, f, separators=(',', ':'), ensure_ascii=False)
    print(f'  atlases.json           {os.path.getsize(os.path.join(a.out, "atlases.json")) / 1024:8.0f} KB')


if __name__ == '__main__':
    main()
