"""Compile or run the original HW5 testbench from a portable project root."""
import argparse
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--simulator', choices=['iverilog', 'vcs'], default='iverilog')
    parser.add_argument('--compile-only', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    for folder in ['build/layer1', 'build/layer2']:
        (root / folder).mkdir(parents=True, exist_ok=True)
    required = [args.simulator]
    if args.simulator == 'iverilog' and not args.compile_only:
        required.append('vvp')
    for tool in required:
        if shutil.which(tool) is None:
            parser.error(f'{tool} was not found on PATH')
    sources = ['presim/testbench.v', 'rtl/vgg16.v']
    if args.simulator == 'iverilog':
        command = ['iverilog', '-g2012', '-s', 'HDL_HW5_TB', '-o', 'build/sim.vvp', *sources]
        runner = ['vvp', 'build/sim.vvp']
    else:
        command = ['vcs', '-full64', '-sverilog', '-top', 'HDL_HW5_TB',
                   '-o', 'build/simv', '-Mdir=build/csrc', *sources]
        runner = [str(root / 'build/simv')]
    subprocess.run(command, cwd=root, check=True)
    if not args.compile_only:
        subprocess.run(runner, cwd=root, check=True)


if __name__ == '__main__':
    main()
