# Implementation Notes

## Packaging Changes

- Kept `rtl/vgg16.v`, the input data, the 128 archived BMP outputs, the original report, and the three synthesis reports unchanged.
- Replaced school-server absolute paths in the testbench with repository-relative paths. New simulation output goes to `build/layer1` and `build/layer2`.
- Changed only design/output paths and output-directory creation in the synthesis script. Standard-cell library settings remain environment-specific.
- Added a Python launcher for Icarus Verilog and VCS, an English README, and PNG contact sheets generated from the archived images.
- Excluded simulator binaries, caches, waveform dumps, generated netlists, DDC/SDF files, duplicate editable report files, and teaching slides from the publication package.

## Preserved Behavior

This release packages the coursework implementation without redesigning its numerical or scheduling behavior.

- **Layer 1 padding:** the testbench pads the unsigned image stream with zero; the top module then subtracts 128 from every input, including padding. The padded border therefore becomes -128 in the convolution datapath.
- **Layer 1 output timing:** the testbench samples using the line-buffer `enable` signal, while convolution and ReLU have registered outputs. There is no independent golden-reference comparison checking this alignment.
- **Last Layer 1 batch:** 22 batches cover 64 output channels. The original testbench attempts to read weights and biases for all three lanes in the last batch, even though only one lane is written to an output file. File-read return values are not checked.
- **Layer 2 parameter order:** the testbench reads the parameter file sequentially in output-batch / input-group / output-lane / input-lane order. The parameter-export program is unavailable, so its correspondence to a software checkpoint has not been independently verified.
- **Partial sums:** the Layer 2 accumulation memory is a testbench array, outside the synthesizable top-level design.
- **Datapath selection:** both layer modules are instantiated. `layer_sel` selects the result; this is not a single shared compute array with clock gating.

## Evidence Boundaries

The archived synthesis reports are dated November 27, 2025. No source revision identifier ties those reports to the retained RTL, so the metrics are presented as historical project results rather than fresh measurements of this release.

The original PDF contains screenshots labeled pre-simulation and post-simulation. The separate `layer1` and `layer2` image folders do not carry enough provenance to establish which simulation produced them. No automated pre/post numerical equivalence result is included.

Compilation checks syntax and elaboration. Readable output images establish that the archived files can be displayed. Neither check proves numerical correctness or agreement with a pretrained VGG16 implementation.
