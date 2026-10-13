# Brain Explorer

A three-plane viewer (sagittal, coronal, axial) for the MNI152 template with
eight public atlases. Click anywhere and the readout gives the label from
every atlas at that point. You can also add overlays: the template's grey
matter, white matter and CSF probability maps are built in, or you can open
your own NIfTI map.

It is a single `index.html` with no libraries and no build step. The data
lives in `data/`, about 3.5 MB in total.

## Running it

Browsers won't let a `file://` page fetch its data, so serve the folder:

```bash
python3 -m http.server 8000      # from the repo root
# then open http://localhost:8000/brain/
```

On the deployed site it is just another static folder.

## What it does

- **Three linked views.** Click or drag to move the crosshair, scroll to step
  through slices, Ctrl/⌘ + scroll or pinch to zoom, Shift-drag or right-drag
  to pan. Arrow keys nudge the crosshair, PgUp/PgDn change slice, `[` `]`
  switch atlas and `/` opens search. The region under the crosshair is
  outlined in white in all three views, and hovering shows the region under
  the pointer.
- **Readout.** Shows the MNI coordinate (you can type in it to jump), the
  voxel index, the template intensity, the label from each atlas, and the
  value of each overlay. Click an atlas row to show that atlas.
- **Atlas display.** Fill, outline, both, or off, with an opacity slider and
  an option to show only the region at the cursor. Outlines are drawn as
  vectors along voxel edges, so they stay 1 px wide at any zoom.
- **Region list and search.** The side panel lists the current atlas's
  regions with their volumes. The search box looks through every atlas at
  once ("amygdala" finds it in Harvard-Oxford and in aseg). Choosing a region
  jumps to its deepest voxel, the point furthest from its edges, so the
  crosshair always lands inside the region, even one shaped like a C.
- **Overlays.** NIfTI-1 or NIfTI-2, `.nii` or `.nii.gz`, any orientation,
  any grid. The file is read in the browser and never uploaded. It is
  sampled on the fly through its own affine, trilinear for float data and
  nearest-neighbour for integer data, with threshold, max, colour map,
  negative values and opacity settings. Overlays stack. A file whose box
  misses MNI space entirely gets a warning. 4D files show their first
  volume.
- **Links.** The URL hash keeps the coordinate and the atlas
  (`#x=-38&y=4&z=4&atlas=ho_cort`), so a link opens on the same spot.

## The data

Everything is in **MNI152NLin2009cAsym**, the ICBM 2009c nonlinear asymmetric
template that fMRIPrep writes into, and comes from
[TemplateFlow](https://www.templateflow.org/). Note that this is not FSL's
MNI152 (`MNI152NLin6Asym`). The two differ by a few millimetres in places, so
coordinates from FSL-space results land close but not exactly.

| Atlas | Regions | Source | Licence |
| --- | --- | --- | --- |
| Harvard-Oxford cortical (lateralised, max-prob, thr 25%) | 96 | Desikan et al. 2006; Frazier et al. 2005; Makris et al. 2006; Goldstein et al. 2007, via FSL | FSL licence (non-commercial) |
| Harvard-Oxford subcortical (max-prob, thr 25%) | 21 | as above | FSL licence (non-commercial) |
| Schaefer 2018, 400 parcels, 7-network order | 400 | Schaefer et al. 2018, *Cereb Cortex* (CBIG) | MIT |
| Yeo 7 networks, via Schaefer 400 | 7 | Yeo et al. 2011, *J Neurophysiol* | MIT |
| Yeo 17 networks, via Schaefer 400 | 17 | Yeo et al. 2011 | MIT |
| FreeSurfer aseg of the template | 43 | Fischl et al. 2002, *Neuron* | derived with FreeSurfer |
| Desikan-Killiany-Tourville (DKT31), cortical labels | 62 | Klein & Tourville 2012, *Front Neurosci* (Mindboggle) | Mindboggle terms |
| Thalamic nuclei | 14 | Najdenovska et al. 2018, *Sci Data* | CC BY 4.0 |

The template carries this notice: *Copyright (C) 1993–2004 Louis Collins,
McConnell Brain Imaging Centre, Montreal Neurological Institute, McGill
University. Permission to use, copy, modify, and distribute this software and
its documentation for any purpose and without fee is hereby granted, provided
that the above copyright notice appear in all copies.* (Fonov et al. 2011,
*NeuroImage*; Fonov et al. 2009.)

A few notes on how the atlases were prepared:

- The **Yeo network maps** are the Schaefer 400 parcels grouped by the
  network each one is assigned to. That is close to the original Yeo 2011
  maps but not identical, which is why they are labelled "via Schaefer 400".
- **Schaefer parcel colours.** In the source table every parcel in a network
  has almost exactly the same colour, which makes neighbouring parcels
  impossible to tell apart. Each parcel's colour has been shifted slightly
  in hue and lightness, keeping the network's base colour.
- **DKT** exists only at 2 mm in TemplateFlow. It was upsampled to 1 mm by
  interpolating each label's indicator and taking the argmax, which gives
  smoother edges than nearest-neighbour. Only the cortical labels are kept,
  since aseg covers the subcortical ones.
- **Harvard-Oxford names.** TemplateFlow's label tables drop every row whose
  name contains a comma, which is 44 of the 96 cortical labels. The build
  script embeds FSL's full 48-region list and checks it against the rows that
  did survive.
- Every atlas is checked during the build so that each label is non-empty
  and each "Left" or "Right" label sits on the correct side of the midline.

## Files

| File | What it is |
| --- | --- |
| `index.html` | The viewer, including a small NIfTI reader (gzip via the browser's `DecompressionStream`) |
| `data/atlases.json` | Grid, backgrounds, overlays, and every atlas's labels (`v`, `name`, `color`, source name `raw`, voxel count `n`, deepest voxel `at`) |
| `data/t1.webp`, `t2.webp` | T1/T2 templates as a mosaic of axial slices in one lossy WebP |
| `data/brainmask.nii.gz` | Brain mask, for "Hide skull and scalp" |
| `data/<atlas>.nii.gz` | Label volumes on the 1 mm template grid (193 × 229 × 193) |
| `data/gm.nii.gz`, `wm.nii.gz`, `csf.nii.gz` | Tissue probability maps at 2 mm, uint8 scaled 0–1 |
| `tools/build_data.py` | Downloads from TemplateFlow and rebuilds everything in `data/` |

Why WebP for the templates: as 8-bit gzipped NIfTI each one is about 5 MB,
because deflate does badly on smooth gradients. As a WebP mosaic at quality
92 each is under 1 MB, with a mean error below 1.5 grey levels inside the
brain. The label volumes stay as NIfTI, because labels have to be exact.

## Rebuilding the data

```bash
pip install nibabel numpy scipy pillow
python3 brain/tools/build_data.py --cache /tmp/tf --out brain/data
```

It takes about a minute and downloads about 32 MB into the cache.

## Caveats

These are maximum-probability or thresholded atlases on an average brain.
A label at a coordinate is a best guess, and atlases often disagree near
boundaries; the readout shows all eight side by side so you can see where
they do. This is not a clinical tool.
